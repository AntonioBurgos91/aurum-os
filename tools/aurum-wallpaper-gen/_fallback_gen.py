#!/usr/bin/env python3
"""aurum-wallpaper-gen — Pillow fallback generator.

Reproduces the Rust crate's render pipeline in pure Python so the bundled
PNGs and MANIFEST.json can still be regenerated in environments without a
Rust toolchain (Docker preview, restricted CI, etc.).

The output is not byte-identical to the Rust crate (Pillow's anti-aliasing
and tiny-skia's rasterisation differ in their LSBs) but is visually
indistinguishable and follows the same three-stage pipeline:

    1. 3-stop vertical linear gradient
    2. hero overlay (light leak / wave bands / warm centre /
       starfield / aurora ribbons), composited additively
    3. ~4% per-pixel film-grain noise, deterministic per theme

Usage matches the Rust binary's flags:

    python3 _fallback_gen.py --output-dir distro/seed/wallpapers/
    python3 _fallback_gen.py --output-dir /tmp/wp \\
        --resolutions 2560x1600,5120x3200
    python3 _fallback_gen.py --output-dir distro/seed/wallpapers/ \\
        --only "Aurum Dawn"

Output PNGs are opaque 8-bit/RGB. MANIFEST.json records the renderer
identity in the top-level `generator` field so downstream tooling can
tell which path produced the assets.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import random
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Tuple

from PIL import Image, ImageDraw, ImageFilter

GENERATOR_ID = "aurum-wallpaper-gen 0.1.0 (python-fallback)"

# ---------------------------------------------------------------------------
# Theme catalogue — mirrors src/palette.rs::THEMES exactly.
# ---------------------------------------------------------------------------

HERO_LEAK_TL = "leak_tl"
HERO_LEAK_TR = "leak_tr"
HERO_WAVE = "wave"
HERO_WARM_CENTER = "warm_center"
HERO_STARFIELD = "starfield"
HERO_AURORA = "aurora"


@dataclass(frozen=True)
class Theme:
    id: str
    title: str
    number: int
    palette: Tuple[str, str, str]
    hero: str


THEMES: List[Theme] = [
    Theme("aurum-dawn",    "Aurum Dawn",    1, ("#FFB088", "#FF7D8E", "#9F5FFF"), HERO_LEAK_TL),
    Theme("aurum-forest",  "Aurum Forest",  2, ("#8FBFA0", "#2D9B8E", "#0A2540"), HERO_LEAK_TR),
    Theme("aurum-coastal", "Aurum Coastal", 3, ("#A4D8F7", "#3DA5D9", "#1B4965"), HERO_WAVE),
    Theme("aurum-sunset",  "Aurum Sunset",  4, ("#FFB347", "#FF6B6B", "#9B59B6"), HERO_WARM_CENTER),
    Theme("aurum-night",   "Aurum Night",   5, ("#0F1729", "#1E2A5E", "#6B5B95"), HERO_STARFIELD),
    Theme("aurum-aurora",  "Aurum Aurora",  6, ("#0F4C5C", "#5FB8B2", "#E9C46A"), HERO_AURORA),
]


def hex_to_rgb(hex_str: str) -> Tuple[int, int, int]:
    """Parse `#RRGGBB` to a `(r, g, b)` 0..255 triple."""
    h = hex_str.lstrip("#")
    assert len(h) == 6, f"expected #RRGGBB, got {hex_str!r}"
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))


def brighten(rgb: Tuple[int, int, int], f: float) -> Tuple[int, int, int]:
    """Lift `rgb` toward white by `f` ∈ [0, 1]."""
    lift = lambda c: max(0, min(255, int(c + (255 - c) * f)))
    return (lift(rgb[0]), lift(rgb[1]), lift(rgb[2]))


# ---------------------------------------------------------------------------
# Pipeline stages.
# ---------------------------------------------------------------------------


def paint_base_gradient(theme: Theme, w: int, h: int) -> Image.Image:
    """Render the 3-stop vertical gradient that every theme starts with.

    We render scanline-by-scanline at full canvas height — three colour
    stops interpolated linearly, with the middle stop sitting at y == h/2.
    `putdata` on a single-row image followed by `resize(NEAREST)` would be
    faster but produces visible banding on 5K images; the per-row loop is
    fast enough (under a second for the 5120×3200 case on a 2020 laptop).
    """
    img = Image.new("RGB", (w, h))
    draw = ImageDraw.Draw(img)

    c_top = hex_to_rgb(theme.palette[0])
    c_mid = hex_to_rgb(theme.palette[1])
    c_bot = hex_to_rgb(theme.palette[2])

    for y in range(h):
        t = y / max(1, h - 1)
        if t < 0.5:
            # blend top → middle on the upper half
            f = t * 2.0
            col = tuple(int(c_top[i] * (1 - f) + c_mid[i] * f) for i in range(3))
        else:
            # blend middle → bottom on the lower half
            f = (t - 0.5) * 2.0
            col = tuple(int(c_mid[i] * (1 - f) + c_bot[i] * f) for i in range(3))
        draw.line([(0, y), (w, y)], fill=col)
    return img


def _additive_paste(base: Image.Image, layer: Image.Image) -> None:
    """Composite `layer` (RGBA) onto `base` (RGB) using additive blend.

    Pillow's `ImageChops.add` clamps per channel — that's exactly the
    "Plus" blend mode tiny-skia uses for our light-leak overlays. We honor
    the alpha channel on `layer` by scaling its colour data by alpha/255
    before adding so a translucent layer contributes proportionally.
    """
    from PIL import ImageChops

    if layer.mode != "RGBA":
        layer = layer.convert("RGBA")
    # Pre-multiply colour by alpha so partial-alpha pixels contribute
    # proportionally to the additive sum (matches BlendMode::Plus).
    r, g, b, a = layer.split()
    r = ImageChops.multiply(r, a)
    g = ImageChops.multiply(g, a)
    b = ImageChops.multiply(b, a)
    contrib = Image.merge("RGB", (r, g, b))
    base.paste(ImageChops.add(base, contrib))


def _radial_alpha_layer(
    w: int, h: int, cx: float, cy: float, rx: float, ry: float, color: Tuple[int, int, int], peak_alpha: int
) -> Image.Image:
    """Generate an RGBA layer with a soft elliptical falloff for additive blend.

    We approximate a Gaussian by drawing four stacked ellipses at growing
    radii with falling alpha — same trick `src/lightleaks.rs` uses. A real
    Gaussian blur is too slow at 5K resolution; the stacked-ellipse
    approximation is visually indistinguishable for a wallpaper.
    """
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    # (radius_mul, alpha_mul) — geometric falloff in alpha, linear in radius.
    for rm, am in [(1.00, 1.00), (1.55, 0.55), (2.30, 0.25), (3.20, 0.10)]:
        a = max(0, min(255, int(peak_alpha * am)))
        if a == 0:
            continue
        ex = rx * rm
        ey = ry * rm
        draw.ellipse(
            (cx - ex, cy - ey, cx + ex, cy + ey),
            fill=(color[0], color[1], color[2], a),
        )
    # One light blur softens the discrete ellipse edges into a smooth glow.
    layer = layer.filter(ImageFilter.GaussianBlur(radius=max(2.0, min(rx, ry) * 0.10)))
    return layer


def paint_corner_leak(base: Image.Image, theme: Theme, fx: float, fy: float) -> None:
    """Soft additive radial centred at the given fractional canvas position."""
    w, h = base.size
    bright = brighten(hex_to_rgb(theme.palette[0]), 0.35)
    cx = w * fx
    cy = h * fy
    radius = math.hypot(w, h) * 0.30
    layer = _radial_alpha_layer(w, h, cx, cy, radius, radius * 0.85, bright, 20)
    _additive_paste(base, layer)


def paint_warm_center(base: Image.Image, theme: Theme) -> None:
    """Bright warm radial in the centre — Aurum Sunset's hero treatment."""
    w, h = base.size
    bright = brighten(hex_to_rgb(theme.palette[0]), 0.30)
    cx = w * 0.5
    cy = h * 0.55
    radius = math.hypot(w, h) * 0.45
    layer = _radial_alpha_layer(w, h, cx, cy, radius, radius, bright, 30)
    _additive_paste(base, layer)


def paint_wave_bands(base: Image.Image, theme: Theme) -> None:
    """Thin translucent horizontal stripes with sinusoidal vertical jitter."""
    w, h = base.size
    bright = brighten(hex_to_rgb(theme.palette[0]), 0.40)
    band_count = 14
    band_h = (h / band_count) * 0.35

    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    for i in range(band_count):
        frac = (i + 0.5) / band_count
        y = h * frac
        jitter = math.sin(frac * math.pi * 2.0) * h * 0.02
        yy = y + jitter
        draw.rectangle((0, yy, w, yy + band_h), fill=(bright[0], bright[1], bright[2], 15))
    layer = layer.filter(ImageFilter.GaussianBlur(radius=2.0))
    _additive_paste(base, layer)


def paint_starfield(base: Image.Image, seed: int) -> None:
    """Sparse anti-aliased white dots in the top two-thirds of the canvas."""
    w, h = base.size
    rng = random.Random(seed)
    count = 320  # mid-range of the brief's 200-400 ask

    # Render to RGBA so alpha-blended stars composite onto the gradient.
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    for _ in range(count):
        rx = rng.random()
        ry = rng.random()
        rs = rng.random()
        ra = rng.random()
        # Concentrate ~80% of dots in the top half.
        yfrac = ry * 0.5 if ry < 0.8 else 0.5 + (ry - 0.8) * 2.5
        cx = rx * w
        cy = yfrac * h
        radius = 0.5 + rs * 1.0
        alpha = int(140 + ra * 115)
        # Pillow's ellipse anti-aliases via supersampling when we render at
        # 4x then downscale — for a sub-2-px dot the plain draw is fine.
        draw.ellipse(
            (cx - radius, cy - radius, cx + radius, cy + radius),
            fill=(255, 255, 255, alpha),
        )
    # Composite the stars on top of the gradient (not additive — we want
    # pure white, not white-plus-gradient which would clip to white).
    base.paste(layer, (0, 0), layer)


def paint_aurora_bands(base: Image.Image, theme: Theme) -> None:
    """Five sinusoidal horizontal aurora ribbons, additively blended."""
    w, h = base.size
    cols = [brighten(hex_to_rgb(hx), 0.25) for hx in theme.palette]
    bands = 5
    segments = 64

    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    for b in range(bands):
        bf = b / max(1, bands - 1)
        band_y = h * (0.15 + bf * 0.60)
        amp = h * 0.04
        freq = 1.5 + bf * 1.0
        phase = bf * math.pi
        thick = h * (0.04 + bf * 0.015)
        col = cols[b % len(cols)]
        for s in range(segments):
            sf = s / segments
            x = sf * w
            sw = w / segments + 1.0
            y = band_y + math.sin((sf * freq * 2.0 * math.pi) + phase) * amp
            draw.rectangle(
                (x, y - thick * 0.5, x + sw, y + thick * 0.5),
                fill=(col[0], col[1], col[2], 60),
            )
    # Heavy blur so the aurora reads as a soft glow, not a stair-step.
    layer = layer.filter(ImageFilter.GaussianBlur(radius=max(4.0, h * 0.008)))
    _additive_paste(base, layer)


def paint_hero(base: Image.Image, theme: Theme) -> None:
    """Dispatch to the per-style hero painter."""
    if theme.hero == HERO_LEAK_TL:
        paint_corner_leak(base, theme, 0.18, 0.18)
    elif theme.hero == HERO_LEAK_TR:
        paint_corner_leak(base, theme, 0.82, 0.18)
    elif theme.hero == HERO_WAVE:
        paint_wave_bands(base, theme)
    elif theme.hero == HERO_WARM_CENTER:
        paint_warm_center(base, theme)
    elif theme.hero == HERO_STARFIELD:
        paint_starfield(base, theme.number * 0xA02026 + 0xDEAD)
    elif theme.hero == HERO_AURORA:
        paint_aurora_bands(base, theme)
    else:
        raise ValueError(f"unknown hero style: {theme.hero!r}")


def apply_grain(base: Image.Image, theme: Theme) -> None:
    """Apply ~4% per-pixel ±10/255 luma noise, deterministic per theme.

    Done at the pixel-byte level for speed: we iterate the entire raw
    RGB byte buffer and perturb each triple by a shared signed delta.
    """
    w, h = base.size
    rng = random.Random(0xA02026 + theme.number * 0xCAFEBABE)
    amplitude = 10  # ≈4% of 255

    data = bytearray(base.tobytes())
    # 3 bytes per pixel (RGB).
    n = w * h
    i = 0
    for _ in range(n):
        delta = rng.randint(-amplitude, amplitude)
        for c in range(3):
            v = data[i + c] + delta
            if v < 0:
                v = 0
            elif v > 255:
                v = 255
            data[i + c] = v
        i += 3
    base.frombytes(bytes(data))


def render_theme(theme: Theme, w: int, h: int) -> Image.Image:
    """Run the full three-stage pipeline and return an RGB Image."""
    img = paint_base_gradient(theme, w, h)
    paint_hero(img, theme)
    apply_grain(img, theme)
    return img


# ---------------------------------------------------------------------------
# CLI driver.
# ---------------------------------------------------------------------------


def parse_resolutions(s: str) -> List[Tuple[int, int]]:
    out: List[Tuple[int, int]] = []
    for tok in s.split(","):
        tok = tok.strip()
        if not tok:
            continue
        if "x" not in tok:
            raise ValueError(f"bad resolution {tok!r} (expected WxH)")
        w_s, h_s = tok.split("x", 1)
        w, h = int(w_s), int(h_s)
        if w <= 0 or h <= 0:
            raise ValueError(f"non-positive dimension in {tok!r}")
        out.append((w, h))
    if not out:
        raise ValueError("--resolutions produced no usable entries")
    return out


def tier_label(idx: int) -> str:
    return f"{idx + 1}x"


def file_name(theme: Theme, tier_idx: int) -> str:
    if tier_idx == 0:
        return f"aurum-sequoia-{theme.number}.png"
    return f"aurum-sequoia-{theme.number}@{tier_idx + 1}x.png"


def matches_filter(theme: Theme, filt: str) -> bool:
    f = filt.strip().lower()
    return theme.id.lower() == f or theme.title.lower() == f


def write_manifest(out_dir: Path, new_entries: List[Dict]) -> None:
    """Merge new entries into MANIFEST.json so single-theme reruns don't
    drop existing hashes for un-rendered themes."""
    path = out_dir / "MANIFEST.json"
    merged: List[Dict] = []
    if path.exists():
        try:
            existing = json.loads(path.read_text())
            merged = list(existing.get("wallpapers", []))
        except (json.JSONDecodeError, OSError):
            merged = []

    by_id = {e["id"]: e for e in merged}
    for new in new_entries:
        by_id[new["id"]] = new

    # Preserve canonical order.
    canonical = [t.id for t in THEMES]
    ordered = [by_id[i] for i in canonical if i in by_id]
    # Append anything we didn't recognise (forward-compat).
    ordered += [e for i, e in by_id.items() if i not in canonical]

    manifest = {
        "generator": GENERATOR_ID,
        "wallpapers": ordered,
    }
    path.write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"[wallpaper-gen] wrote {path}", file=sys.stderr)


def main(argv: List[str]) -> int:
    ap = argparse.ArgumentParser(
        prog="aurum-wallpaper-gen (python fallback)",
        description="Generate AurumOS Sequoia-style wallpapers.",
    )
    ap.add_argument("--output-dir", required=True, type=Path)
    ap.add_argument("--resolutions", default="2560x1600,5120x3200")
    ap.add_argument("--only")
    ap.add_argument("--no-manifest", action="store_true")
    args = ap.parse_args(argv)

    try:
        resolutions = parse_resolutions(args.resolutions)
    except ValueError as e:
        print(f"aurum-wallpaper-gen: error: {e}", file=sys.stderr)
        return 2

    args.output_dir.mkdir(parents=True, exist_ok=True)

    new_entries: List[Dict] = []
    for theme in THEMES:
        if args.only and not matches_filter(theme, args.only):
            continue

        files: Dict[str, str] = {}
        hashes: Dict[str, str] = {}

        for idx, (w, h) in enumerate(resolutions):
            t0 = time.time()
            img = render_theme(theme, w, h)
            name = file_name(theme, idx)
            path = args.output_dir / name
            img.save(path, format="PNG", optimize=True)
            data = path.read_bytes()
            digest = hashlib.sha256(data).hexdigest()
            dt = time.time() - t0
            kib = len(data) // 1024
            print(
                f"[wallpaper-gen] {theme.id:<14} {w}x{h}  {kib:>7} KiB  {dt:>5.2f}s  {path}",
                file=sys.stderr,
            )
            tier = tier_label(idx)
            files[tier] = name
            hashes[tier] = digest

        new_entries.append({
            "id": theme.id,
            "title": theme.title,
            "palette": list(theme.palette),
            "files": files,
            "sha256": hashes,
        })

    if not new_entries:
        print("aurum-wallpaper-gen: error: no themes matched --only", file=sys.stderr)
        return 1

    if not args.no_manifest:
        write_manifest(args.output_dir, new_entries)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
