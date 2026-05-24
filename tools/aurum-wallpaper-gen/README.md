# aurum-wallpaper-gen

Procedural generator for the six default AurumOS wallpapers. Renders the
PNG files in [`distro/seed/wallpapers/`](../../distro/seed/wallpapers/) at
two resolutions each (standard 2560×1600 and retina 5120×3200), then
writes a `MANIFEST.json` indexing every file by id, palette, and sha256.

This is a **build-time tool**, not a runtime component. Release engineering
runs it once per release; the ISO image ships the resulting PNGs, never
the Rust binary.

## The six wallpapers (Wave 10)

| #  | id              | Title          | Palette (top → middle → bottom)              | Hero overlay       |
|----|-----------------|----------------|----------------------------------------------|--------------------|
| 1  | `aurum-dawn`    | Aurum Dawn     | `#FFB088` → `#FF7D8E` → `#9F5FFF`            | Soft leak, top-left  |
| 2  | `aurum-forest`  | Aurum Forest   | `#8FBFA0` → `#2D9B8E` → `#0A2540`            | Soft leak, top-right |
| 3  | `aurum-coastal` | Aurum Coastal  | `#A4D8F7` → `#3DA5D9` → `#1B4965`            | Horizontal wave bands |
| 4  | `aurum-sunset`  | Aurum Sunset   | `#FFB347` → `#FF6B6B` → `#9B59B6`            | Warm centre radial  |
| 5  | `aurum-night`   | Aurum Night    | `#0F1729` → `#1E2A5E` → `#6B5B95`            | Sparse star specks  |
| 6  | `aurum-aurora`  | Aurum Aurora   | `#0F4C5C` → `#5FB8B2` → `#E9C46A`            | Aurora ribbons      |

`aurum-sequoia-1.png` (Aurum Dawn) is the default ISO wallpaper.

## Rendering pipeline

Every theme is composited in three passes (`src/lib.rs::render_theme`):

1. **Base gradient** — a 3-stop linear gradient, top → bottom, filling the
   canvas. Stops are taken from the palette as-is.
2. **Hero overlay** — one of six effects (`HeroStyle` in `src/palette.rs`):
   light leak, wave bands, warm centre, starfield, or aurora bands. All are
   composited with `BlendMode::Plus` (additive) so the underlying gradient
   stays the dominant tone.
3. **Film-grain noise** — deterministic per-pixel ±10/255 (≈4%) jitter,
   seeded per theme so PNGs are bit-reproducible run to run.

Output is opaque 8-bit/RGB PNG (no alpha channel) — Sequoia wallpapers
have to look identical between the lock screen, the desktop, and any
screenshot the user takes.

## Usage

```bash
# Build (release).
cargo build --release --manifest-path tools/aurum-wallpaper-gen/Cargo.toml

# Render all six wallpapers at both production resolutions.
./tools/aurum-wallpaper-gen/target/release/aurum-wallpaper-gen \
    --output-dir distro/seed/wallpapers/

# Override resolutions (first entry is "1x", second is "@2x", etc.).
./aurum-wallpaper-gen \
    --output-dir /tmp/wp \
    --resolutions 1920x1200,3840x2400

# Regenerate a single wallpaper (manifest is merged, not rewritten).
./aurum-wallpaper-gen \
    --output-dir distro/seed/wallpapers/ \
    --only "Aurum Dawn"
```

CLI flags:

| Flag             | Default                  | Description                          |
|------------------|--------------------------|--------------------------------------|
| `--output-dir`   | (required)               | Where to write PNGs + MANIFEST.json  |
| `--resolutions`  | `2560x1600,5120x3200`    | Comma-separated `WxH` list           |
| `--only NAME`    | (render all)             | Title or id of a single theme        |
| `--no-manifest`  | off                      | Skip MANIFEST.json write             |

## MANIFEST.json shape

```json
{
  "generator": "aurum-wallpaper-gen 0.1.0",
  "wallpapers": [
    {
      "id": "aurum-dawn",
      "title": "Aurum Dawn",
      "palette": ["#FFB088", "#FF7D8E", "#9F5FFF"],
      "files":  { "1x": "aurum-sequoia-1.png", "2x": "aurum-sequoia-1@2x.png" },
      "sha256": { "1x": "…", "2x": "…" }
    },
    ...
  ]
}
```

## Python fallback (`_fallback_gen.py`)

If a Rust toolchain isn't available (Docker-only preview, restricted CI),
`_fallback_gen.py` reproduces the entire pipeline using Pillow. It takes
the same CLI flags as the Rust binary and emits byte-comparable PNGs
(within ±1 LSB per channel — Pillow's anti-aliasing and the Rust crate's
tiny-skia rasterisation aren't bit-identical, but the visual result is
indistinguishable).

```bash
python3 tools/aurum-wallpaper-gen/_fallback_gen.py \
    --output-dir distro/seed/wallpapers/
```

The fallback is the source of truth whenever the committed PNGs in
`distro/seed/wallpapers/` were not produced by `cargo run`; the
`generator` field in `MANIFEST.json` records which one ran.

## Reproducibility

Every render is deterministic: noise is a SmallRng-style LCG seeded from
the theme's ordinal, the starfield uses an inline 64-bit LCG with a
constant seed offset, and tiny-skia's gradient rasteriser is itself
deterministic. Two clean runs of the generator produce byte-identical
PNGs — which means `git diff` after a regen is either empty or shows an
intentional change.

## Legacy module set

The previous wave shipped six different wallpapers (amber, aqua,
obsidian, dawn, aurora, void). Their per-wallpaper modules live in
`src/wallpapers/` and are still compiled, but are no longer driven by
the public API. They are kept around as a reference for the gradient
primitives they exercise; they will be deleted in a future cleanup pass
once nothing else in the tree imports them.
