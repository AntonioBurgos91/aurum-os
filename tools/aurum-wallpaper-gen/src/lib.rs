//! AurumOS Sequoia-style wallpaper generator (Wave 10 spec).
//!
//! Public entry points:
//!   * [`THEMES`] / [`palette::THEMES`] — the canonical six wallpapers.
//!   * [`render_theme`] — paint one theme into a `tiny_skia::Pixmap`.
//!   * [`encode_png`]   — RGBA pixmap → 8-bit RGB PNG bytes (no alpha out).
//!   * [`sha256_hex`]   — convenience for manifest hash columns.
//!
//! The Wave 10 brief asks for a different visual register than the original
//! "amber / aqua / obsidian / dawn / aurora / void" set rendered by the
//! older modules in `wallpapers/*` (those modules are retained as reference
//! primitives but are no longer wired into the public API). The new set is
//! driven entirely from [`palette::THEMES`] — adding a wallpaper is a one-
//! struct edit there plus a `match` arm in [`paint_hero`].
//!
//! ## Pipeline
//!
//! Every theme follows the same three-stage composition:
//!
//!   1. Base linear gradient (top → middle → bottom) filling the canvas.
//!   2. Hero overlay determined by [`palette::HeroStyle`]:
//!        * `LeakTopLeft` / `LeakTopRight` — soft additive radial.
//!        * `WaveBands`   — horizontal sine bands at low alpha.
//!        * `WarmCenter`  — large bright additive radial in the middle.
//!        * `Starfield`   — sparse anti-aliased white dots in the top half.
//!        * `AuroraBands` — 3-5 wavy horizontal bands.
//!   3. Film-grain noise (deterministic, 3-5% amplitude).
//!
//! Output is always opaque (alpha = 255 everywhere); [`encode_png`] drops
//! the alpha channel and writes 8-bit/channel RGB so the on-disk PNG looks
//! the way macOS users expect (no surprise transparency in screenshots).

pub mod gradients;
pub mod lightleaks;
pub mod noise;
pub mod palette;

// The legacy per-wallpaper renderers from the previous wave. They are not
// part of the Wave 10 API but are kept compiled because they exercise the
// same primitives this lib still uses, and removing them would cause merge
// pain with anyone holding open branches against the older spec.
pub mod wallpapers;

use sha2::{Digest, Sha256};
use tiny_skia::{BlendMode, Color, Paint, Pixmap, Rect, Transform};

pub use palette::{HeroStyle, Theme, THEMES};

/// Render `theme` into a fresh `Pixmap` of `(width, height)` pixels.
///
/// `seed` is the per-theme noise seed; pass `theme.number as u64 * 0xA02026`
/// (or anything stable) so the resulting PNG is bit-reproducible run to run.
///
/// The returned Pixmap is in premultiplied RGBA — convert with
/// [`encode_png`] to get an opaque RGB PNG suitable for shipping.
pub fn render_theme(theme: &Theme, width: u32, height: u32) -> Pixmap {
    let mut pm = Pixmap::new(width, height).expect("allocate pixmap");

    paint_base_gradient(&mut pm, theme, width, height);
    paint_hero(&mut pm, theme, width, height);
    apply_grain(&mut pm, theme);

    pm
}

/// Paint the 3-stop vertical (top→bottom) gradient that every theme uses
/// as its base layer.
fn paint_base_gradient(pm: &mut Pixmap, theme: &Theme, w: u32, h: u32) {
    let stops: Vec<(f32, gradients::Rgb)> = theme
        .palette
        .iter()
        .enumerate()
        .map(|(i, hex)| {
            let offset = i as f32 / (theme.palette.len() - 1) as f32;
            (offset, palette::parse_hex(hex))
        })
        .collect();

    gradients::linear(
        pm,
        w,
        h,
        (w as f32 * 0.5, 0.0),         // top centre
        (w as f32 * 0.5, h as f32),    // bottom centre
        &stops,
    );
}

/// Paint the per-theme hero overlay on top of the base gradient.
fn paint_hero(pm: &mut Pixmap, theme: &Theme, w: u32, h: u32) {
    match theme.hero {
        HeroStyle::LeakTopLeft => paint_corner_leak(pm, theme, w, h, 0.18, 0.18),
        HeroStyle::LeakTopRight => paint_corner_leak(pm, theme, w, h, 0.82, 0.18),
        HeroStyle::WaveBands => paint_wave_bands(pm, theme, w, h),
        HeroStyle::WarmCenter => paint_warm_center(pm, theme, w, h),
        HeroStyle::Starfield => paint_starfield(pm, w, h, theme.number as u64),
        HeroStyle::AuroraBands => paint_aurora_bands(pm, theme, w, h),
    }
}

/// Soft additive radial centred at the given fractional canvas position.
///
/// The colour is a brightened version of the top palette stop (sRGB lift by
/// ~25% toward white) so the leak reads as "sunlight" against the gradient.
fn paint_corner_leak(pm: &mut Pixmap, theme: &Theme, w: u32, h: u32, fx: f32, fy: f32) {
    let base = palette::parse_hex(theme.palette[0]);
    let bright = brighten(base, 0.35);
    let cx = w as f32 * fx;
    let cy = h as f32 * fy;
    // Radius ≈ 30% of the canvas diagonal so the leak feathers gently into
    // about a third of the visible area.
    let radius = (w as f32).hypot(h as f32) * 0.30;

    let leak = lightleaks::Leak {
        cx,
        cy,
        rx: radius,
        ry: radius * 0.85,
        color: bright,
        // 8% of 255 ≈ 20. Anything brighter starts to look like a blown-out
        // headlight rather than a soft Sequoia leak.
        peak_alpha: 20,
    };
    lightleaks::draw_leak(pm, &leak);
}

/// Soft additive radial in the centre of the canvas — used by "Aurum
/// Sunset" to give the warm radial bloom the spec calls for.
fn paint_warm_center(pm: &mut Pixmap, theme: &Theme, w: u32, h: u32) {
    let base = palette::parse_hex(theme.palette[0]);
    let bright = brighten(base, 0.30);
    let cx = w as f32 * 0.5;
    let cy = h as f32 * 0.55; // slightly below the optical centre
    let radius = (w as f32).hypot(h as f32) * 0.45;

    let leak = lightleaks::Leak {
        cx,
        cy,
        rx: radius,
        ry: radius,
        color: bright,
        peak_alpha: 30,
    };
    lightleaks::draw_leak(pm, &leak);
}

/// Horizontal wave-like banding: ten thin translucent stripes of the
/// brightened top stop, each offset by a sine of x to suggest a calm sea.
///
/// Each band is a thin rectangle filled with a colour at ~6% alpha; the
/// vertical positions are jittered along a low-frequency sine so the bands
/// don't look like a CRT raster.
fn paint_wave_bands(pm: &mut Pixmap, theme: &Theme, w: u32, h: u32) {
    let bright = brighten(palette::parse_hex(theme.palette[0]), 0.40);
    let band_count = 14_u32;
    let band_height = (h as f32 / band_count as f32) * 0.35;

    for i in 0..band_count {
        let frac = (i as f32 + 0.5) / band_count as f32;
        let y = h as f32 * frac;
        // Sinusoidal vertical jitter — amplitude ≈ 2% of canvas height.
        let jitter = (frac * std::f32::consts::PI * 2.0).sin() * h as f32 * 0.02;
        let yy = y + jitter;

        let mut paint = Paint::default();
        paint.set_color(Color::from_rgba8(bright.0, bright.1, bright.2, 15));
        paint.anti_alias = true;
        paint.blend_mode = BlendMode::Plus;

        if let Some(rect) = Rect::from_xywh(0.0, yy, w as f32, band_height) {
            pm.fill_rect(rect, &paint, Transform::identity(), None);
        }
    }
}

/// Sparse white starfield in the top two-thirds of the canvas.
///
/// We use a deterministic LCG (rolled inline so the helper doesn't pull in
/// `rand`) so every render of "Aurum Night" produces an identical layout.
fn paint_starfield(pm: &mut Pixmap, w: u32, h: u32, seed: u64) {
    let count = 320_u32; // mid-range of the brief's 200-400 ask
    let mut state: u64 = seed.wrapping_mul(0xA0_2026_0005).wrapping_add(0xDEADBEEF);

    for _ in 0..count {
        // 64-bit LCG — Knuth's MMIX constants.
        state = state.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
        let rx = (state >> 33) as f32 / (1u64 << 31) as f32; // 0..1
        state = state.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
        let ry = (state >> 33) as f32 / (1u64 << 31) as f32; // 0..1
        state = state.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
        let rs = (state >> 33) as f32 / (1u64 << 31) as f32; // size jitter
        state = state.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
        let ra = (state >> 33) as f32 / (1u64 << 31) as f32; // alpha jitter

        // Concentrate ~80% of dots in the top half, mirroring the spec.
        let yfrac = if ry < 0.8 { ry * 0.5 } else { 0.5 + (ry - 0.8) * 2.5 };
        let cx = rx * w as f32;
        let cy = yfrac * h as f32;
        let radius = 0.5 + rs * 1.0; // 0.5..1.5 px
        let alpha = (140.0 + ra * 115.0) as u8; // 140..255

        // Draw the star as a small filled rect — at 1 px scale it's
        // indistinguishable from a circle and a lot cheaper than fill_path.
        let mut paint = Paint::default();
        paint.set_color(Color::from_rgba8(255, 255, 255, alpha));
        paint.anti_alias = true;

        if let Some(rect) =
            Rect::from_xywh(cx - radius, cy - radius, radius * 2.0, radius * 2.0)
        {
            pm.fill_rect(rect, &paint, Transform::identity(), None);
        }
    }
}

/// Four sinusoidal horizontal aurora bands — translucent thin ribbons that
/// undulate across the canvas, painted Plus so they brighten the underlying
/// gradient without overpowering it.
fn paint_aurora_bands(pm: &mut Pixmap, theme: &Theme, w: u32, h: u32) {
    use std::f32::consts::PI;
    // The bands cycle through the palette so the eye reads a colour shift
    // from horizon to top, matching real-world aurora photography.
    let cols: Vec<gradients::Rgb> = theme
        .palette
        .iter()
        .map(|hex| brighten(palette::parse_hex(hex), 0.25))
        .collect();
    let bands = 5_u32;
    let segments = 64_u32; // horizontal resolution of each band's sine curve

    for b in 0..bands {
        let bf = b as f32 / (bands - 1) as f32;
        // Each band sits at a vertical fraction from 0.15 to 0.75.
        let band_y = h as f32 * (0.15 + bf * 0.60);
        let amp = h as f32 * 0.04;          // sine amplitude
        let freq = 1.5 + bf * 1.0;          // cycles across the canvas
        let phase = bf * PI;                // staggered phases per band
        let thick = h as f32 * (0.04 + bf * 0.015);
        let col = cols[b as usize % cols.len()];

        let mut paint = Paint::default();
        paint.set_color(Color::from_rgba8(col.0, col.1, col.2, 60));
        paint.anti_alias = true;
        paint.blend_mode = BlendMode::Plus;

        for s in 0..segments {
            let sf = s as f32 / segments as f32;
            let x = sf * w as f32;
            let sw = w as f32 / segments as f32 + 1.0;
            let y = band_y + ((sf * freq * 2.0 * PI) + phase).sin() * amp;
            if let Some(rect) = Rect::from_xywh(x, y - thick * 0.5, sw, thick) {
                pm.fill_rect(rect, &paint, Transform::identity(), None);
            }
        }
    }
}

/// Apply the per-theme grain noise pass. Amplitude is ~4% of full scale,
/// which works out to ±10 / 255 — enough to break up banding on flat
/// gradient sections but not enough to be noticed at arm's length.
fn apply_grain(pm: &mut Pixmap, theme: &Theme) {
    let seed: u64 = 0xA0_2026_0000u64.wrapping_add(theme.number as u64 * 0xCAFEBABE);
    let amplitude: i16 = 10; // ~4% of 255
    let weight: f32 = 1.0;   // full strength — amplitude already small
    noise::apply(pm, seed, amplitude, weight);
}

/// Brighten an RGB triple toward white by `f` ∈ [0, 1]. `0.0` is unchanged,
/// `1.0` returns pure white. Used to derive light-leak colours from the
/// theme's top palette stop.
fn brighten(rgb: gradients::Rgb, f: f32) -> gradients::Rgb {
    let lift = |c: u8| -> u8 {
        let v = c as f32 + (255.0 - c as f32) * f;
        v.clamp(0.0, 255.0) as u8
    };
    (lift(rgb.0), lift(rgb.1), lift(rgb.2))
}

/// Encode a tiny-skia Pixmap as an 8-bit-per-channel **opaque RGB** PNG.
///
/// The brief explicitly asks for "no alpha (full opaque background)", so we
/// drop the alpha channel here even though the pixmap stores it. Pixmap
/// data is premultiplied RGBA; with alpha=255 throughout (which all themes
/// guarantee by filling the canvas with a base gradient) the unpremultiply
/// reduces to a pass-through, but we keep the safe form in case a future
/// hero overlay leaves a sub-1.0 alpha somewhere.
pub fn encode_png(pm: &Pixmap) -> Vec<u8> {
    let w = pm.width();
    let h = pm.height();
    let src = pm.data();
    let mut rgb = Vec::with_capacity((src.len() / 4) * 3);

    let mut i = 0;
    while i < src.len() {
        let r = src[i];
        let g = src[i + 1];
        let b = src[i + 2];
        let a = src[i + 3];
        let (rr, gg, bb) = if a == 0 || a == 255 {
            (r, g, b)
        } else {
            let unpremul = |c: u8| ((c as u32) * 255 / a as u32).min(255) as u8;
            (unpremul(r), unpremul(g), unpremul(b))
        };
        rgb.extend_from_slice(&[rr, gg, bb]);
        i += 4;
    }

    let mut out: Vec<u8> = Vec::with_capacity(src.len() / 4);
    {
        let mut enc = png::Encoder::new(&mut out, w, h);
        enc.set_color(png::ColorType::Rgb);
        enc.set_depth(png::BitDepth::Eight);
        let mut writer = enc.write_header().expect("png header");
        writer.write_image_data(&rgb).expect("png data");
    }
    out
}

/// Hex-encoded SHA-256 of an arbitrary byte slice — used to populate
/// MANIFEST.json hash columns.
pub fn sha256_hex(bytes: &[u8]) -> String {
    let mut h = Sha256::new();
    h.update(bytes);
    let digest = h.finalize();
    let mut s = String::with_capacity(64);
    for b in digest.iter() {
        use std::fmt::Write;
        let _ = write!(&mut s, "{:02x}", b);
    }
    s
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Every theme renders at a tiny resolution without panicking and
    /// produces an opaque PNG with the expected magic bytes.
    #[test]
    fn renders_every_theme() {
        for theme in THEMES {
            let pm = render_theme(theme, 80, 50);
            let bytes = encode_png(&pm);
            assert!(bytes.len() > 100, "{}: png too small", theme.id);
            assert_eq!(&bytes[..8], b"\x89PNG\r\n\x1a\n", "{}: bad header", theme.id);
        }
    }

    #[test]
    fn sha256_hex_is_64_chars() {
        let h = sha256_hex(b"hello");
        assert_eq!(h.len(), 64);
        // sha256("hello") = 2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824
        assert_eq!(&h[..8], "2cf24dba");
    }
}
