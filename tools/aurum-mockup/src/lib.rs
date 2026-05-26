// Shared drawing helpers for the AurumOS image-renderer family
// (mockup, wallpaper, icons). All three binaries paint into a tiny-skia
// Pixmap with the same primitives, so they live here.
//
// Public API kept intentionally small:
//   * Rgba + c() + rgba8()                       palette
//   * rect()                                     short Rect ctor
//   * fill_round_rect / stroke_round_rect        squircle-ish primitives
//   * drop_shadow                                cheap stacked-rect blur
//   * vertical_gradient / radial_vignette        background washes
//   * FontStack + load_fonts                     DejaVu loader (Debian path)
//   * draw_text + text_width                     software glyph blit
//
// Nothing here allocates beyond the input strings / PathBuilders, so call
// these from a `Pixmap::new(W, H)` and a few `draw_*` invocations is all
// you need for a fast scene.

use fontdue::{Font, FontSettings};
use std::path::Path;
use tiny_skia::*;

pub type Rgba = [u8; 4];

#[inline]
pub fn c(rgba: Rgba) -> Color {
    Color::from_rgba8(rgba[0], rgba[1], rgba[2], rgba[3])
}
#[inline]
pub fn rgba8(r: u8, g: u8, b: u8, a: u8) -> Color {
    Color::from_rgba8(r, g, b, a)
}
/// Convenience: build a Color from a palette entry but override its alpha.
/// Used heavily by the wallpaper renderer's stacked halo rings.
#[inline]
pub fn ca(rgba: Rgba, alpha: u8) -> Color {
    Color::from_rgba8(rgba[0], rgba[1], rgba[2], alpha)
}

pub fn rect(x: f32, y: f32, w: f32, h: f32) -> Rect {
    Rect::from_xywh(x, y, w, h).unwrap()
}

/// Fill an axis-aligned rounded rectangle with `color`. Corner radius `r` is
/// clamped to half of the shorter side so the squircle never self-intersects.
pub fn fill_round_rect(pm: &mut Pixmap, x: f32, y: f32, w: f32, h: f32, r: f32, color: Color) {
    let r = r.min(w * 0.5).min(h * 0.5).max(0.0);
    let mut pb = PathBuilder::new();
    pb.move_to(x + r, y);
    pb.line_to(x + w - r, y);
    pb.quad_to(x + w, y, x + w, y + r);
    pb.line_to(x + w, y + h - r);
    pb.quad_to(x + w, y + h, x + w - r, y + h);
    pb.line_to(x + r, y + h);
    pb.quad_to(x, y + h, x, y + h - r);
    pb.line_to(x, y + r);
    pb.quad_to(x, y, x + r, y);
    pb.close();
    if let Some(path) = pb.finish() {
        let mut paint = Paint::default();
        paint.set_color(color);
        paint.anti_alias = true;
        pm.fill_path(
            &path,
            &paint,
            FillRule::Winding,
            Transform::identity(),
            None,
        );
    }
}

/// Stroke the outline of a rounded rectangle with `color` at `width` px.
pub fn stroke_round_rect(
    pm: &mut Pixmap,
    x: f32,
    y: f32,
    w: f32,
    h: f32,
    r: f32,
    color: Color,
    width: f32,
) {
    let r = r.min(w * 0.5).min(h * 0.5).max(0.0);
    let mut pb = PathBuilder::new();
    pb.move_to(x + r, y);
    pb.line_to(x + w - r, y);
    pb.quad_to(x + w, y, x + w, y + r);
    pb.line_to(x + w, y + h - r);
    pb.quad_to(x + w, y + h, x + w - r, y + h);
    pb.line_to(x + r, y + h);
    pb.quad_to(x, y + h, x, y + h - r);
    pb.line_to(x, y + r);
    pb.quad_to(x, y, x + r, y);
    pb.close();
    if let Some(path) = pb.finish() {
        let mut paint = Paint::default();
        paint.set_color(color);
        paint.anti_alias = true;
        let stroke = Stroke {
            width,
            ..Stroke::default()
        };
        pm.stroke_path(&path, &paint, &stroke, Transform::identity(), None);
    }
}

/// Cheap stacked-rect drop shadow: 8 concentric rounded rects with fading
/// alpha. Faster than a real Gaussian blur and visually convincing at the
/// thumbnail/mockup sizes we use.
pub fn drop_shadow(pm: &mut Pixmap, x: f32, y: f32, w: f32, h: f32, r: f32, intensity: u8) {
    for i in 0..8 {
        let g = i as f32 * 4.0;
        let alpha = ((intensity as f32) * (1.0 - (i as f32 / 8.0)) / 2.0) as u8;
        fill_round_rect(
            pm,
            x - g,
            y + g,
            w + 2.0 * g,
            h + 2.0 * g,
            r + g,
            rgba8(0, 0, 0, alpha),
        );
    }
}

/// Fill a rectangle with a top→bottom linear gradient between `top` and `bot`.
pub fn vertical_gradient(pm: &mut Pixmap, x: f32, y: f32, w: f32, h: f32, top: Color, bot: Color) {
    let shader = LinearGradient::new(
        Point::from_xy(x, y),
        Point::from_xy(x, y + h),
        vec![GradientStop::new(0.0, top), GradientStop::new(1.0, bot)],
        SpreadMode::Pad,
        Transform::identity(),
    )
    .unwrap();
    let mut paint = Paint::default();
    paint.shader = shader;
    paint.anti_alias = true;
    pm.fill_rect(rect(x, y, w, h), &paint, Transform::identity(), None);
}

/// Fill a rectangle with a linear gradient between arbitrary points `p1` and
/// `p2`, useful for diagonal washes that `vertical_gradient` can't express.
pub fn linear_gradient_2(
    pm: &mut Pixmap,
    x: f32,
    y: f32,
    w: f32,
    h: f32,
    p1: (f32, f32),
    p2: (f32, f32),
    top: Color,
    bot: Color,
) {
    let shader = LinearGradient::new(
        Point::from_xy(p1.0, p1.1),
        Point::from_xy(p2.0, p2.1),
        vec![GradientStop::new(0.0, top), GradientStop::new(1.0, bot)],
        SpreadMode::Pad,
        Transform::identity(),
    )
    .unwrap();
    let mut paint = Paint::default();
    paint.shader = shader;
    paint.anti_alias = true;
    pm.fill_rect(rect(x, y, w, h), &paint, Transform::identity(), None);
}

/// Paint a centred radial gradient (`inner` at `r0` → `outer` at `r1`) across
/// the full pixmap, used as the background vignette behind the wallpaper.
pub fn radial_vignette(
    pm: &mut Pixmap,
    w: u32,
    h: u32,
    cx: f32,
    cy: f32,
    r0: f32,
    r1: f32,
    inner: Color,
    outer: Color,
) {
    let shader = RadialGradient::new(
        Point::from_xy(cx, cy),
        Point::from_xy(cx, cy),
        r1,
        vec![
            GradientStop::new(r0 / r1, inner),
            GradientStop::new(1.0, outer),
        ],
        SpreadMode::Pad,
        Transform::identity(),
    )
    .unwrap();
    let mut paint = Paint::default();
    paint.shader = shader;
    paint.anti_alias = true;
    pm.fill_rect(
        rect(0.0, 0.0, w as f32, h as f32),
        &paint,
        Transform::identity(),
        None,
    );
}

/// A filled rounded rectangle whose color is a vertical gradient. tiny-skia's
/// stroke/fill path doesn't accept a shader, so we draw the gradient first
/// then mask it manually by re-filling the corners with the background color.
/// In practice we just draw the gradient inside the squircle bounds — the
/// corners are filled but invisible because callers draw on top.
pub fn fill_round_rect_gradient(
    pm: &mut Pixmap,
    x: f32,
    y: f32,
    w: f32,
    h: f32,
    r: f32,
    top: Color,
    bot: Color,
) {
    let r = r.min(w * 0.5).min(h * 0.5).max(0.0);
    let mut pb = PathBuilder::new();
    pb.move_to(x + r, y);
    pb.line_to(x + w - r, y);
    pb.quad_to(x + w, y, x + w, y + r);
    pb.line_to(x + w, y + h - r);
    pb.quad_to(x + w, y + h, x + w - r, y + h);
    pb.line_to(x + r, y + h);
    pb.quad_to(x, y + h, x, y + h - r);
    pb.line_to(x, y + r);
    pb.quad_to(x, y, x + r, y);
    pb.close();
    if let Some(path) = pb.finish() {
        let shader = LinearGradient::new(
            Point::from_xy(x, y),
            Point::from_xy(x, y + h),
            vec![GradientStop::new(0.0, top), GradientStop::new(1.0, bot)],
            SpreadMode::Pad,
            Transform::identity(),
        )
        .unwrap();
        let mut paint = Paint::default();
        paint.shader = shader;
        paint.anti_alias = true;
        pm.fill_path(
            &path,
            &paint,
            FillRule::Winding,
            Transform::identity(),
            None,
        );
    }
}

// ---------- Font / text ----------

pub struct FontStack {
    pub sans: Font,
    pub sans_bold: Font,
    pub mono: Font,
}

/// Load DejaVu Sans / Sans-Bold / Sans-Mono from their well-known Debian
/// install paths into a `FontStack` used by every renderer in this crate.
///
/// Returns `Err` if any of the three font files is missing. The error string
/// names the package the user should install (`fonts-dejavu-core` on
/// Debian/Ubuntu) so the binary front-ends can exit with an actionable hint.
pub fn load_fonts() -> Result<FontStack, String> {
    fn try_load(paths: &[&str]) -> Result<Font, String> {
        for p in paths {
            if Path::new(p).exists() {
                let bytes = std::fs::read(p)
                    .map_err(|e| format!("read font {p}: {e} — install fonts-dejavu-core"))?;
                return Font::from_bytes(bytes, FontSettings::default())
                    .map_err(|e| format!("parse font {p}: {e} — install fonts-dejavu-core"));
            }
        }
        Err(format!(
            "none of these font paths existed: {paths:?} — install fonts-dejavu-core \
             (Debian/Ubuntu: `sudo apt install fonts-dejavu-core`)"
        ))
    }
    let sans = try_load(&[
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/TTF/DejaVuSans.ttf",
    ])?;
    let sans_bold = try_load(&[
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "/usr/share/fonts/TTF/DejaVuSans-Bold.ttf",
    ])?;
    let mono = try_load(&[
        "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
    ])?;
    Ok(FontStack {
        sans,
        sans_bold,
        mono,
    })
}

/// Blit `text` with `font` at (x, y) where y is the BASELINE. Returns the
/// width consumed so callers can chain glyphs.
pub fn draw_text(
    pm: &mut Pixmap,
    font: &Font,
    text: &str,
    x: f32,
    y: f32,
    size: f32,
    color: Color,
) -> f32 {
    let mut pen_x = x;
    for ch in text.chars() {
        let (metrics, bitmap) = font.rasterize(ch, size);
        if metrics.width == 0 || metrics.height == 0 {
            pen_x += metrics.advance_width;
            continue;
        }
        let gx = pen_x + metrics.xmin as f32;
        let gy = y - metrics.height as f32 - metrics.ymin as f32;
        let rgba = color.to_color_u8();
        let (cr, cg, cb, ca) = (
            rgba.red() as u32,
            rgba.green() as u32,
            rgba.blue() as u32,
            rgba.alpha() as u32,
        );
        let pmw = pm.width() as usize;
        let pmh = pm.height() as usize;
        let data = pm.data_mut();
        for (i, &cov) in bitmap.iter().enumerate() {
            if cov == 0 {
                continue;
            }
            let dx = (gx as i32) + (i as i32) % (metrics.width as i32);
            let dy = (gy as i32) + (i as i32) / (metrics.width as i32);
            if dx < 0 || dy < 0 || dx >= pmw as i32 || dy >= pmh as i32 {
                continue;
            }
            let idx = ((dy as usize) * pmw + dx as usize) * 4;
            let a = (cov as u32) * ca / 255;
            let inv = 255 - a;
            data[idx] = ((cr * a + (data[idx] as u32) * inv) / 255) as u8;
            data[idx + 1] = ((cg * a + (data[idx + 1] as u32) * inv) / 255) as u8;
            data[idx + 2] = ((cb * a + (data[idx + 2] as u32) * inv) / 255) as u8;
            data[idx + 3] = 255;
        }
        pen_x += metrics.advance_width;
    }
    pen_x - x
}

pub fn text_width(font: &Font, text: &str, size: f32) -> f32 {
    text.chars()
        .map(|ch| font.metrics(ch, size).advance_width)
        .sum()
}

/// Single-glyph centred convenience: blit one char centred horizontally in a
/// box of width `box_w` starting at `box_x`, with baseline at `baseline_y`.
pub fn draw_glyph_centered(
    pm: &mut Pixmap,
    font: &Font,
    ch: char,
    box_x: f32,
    box_w: f32,
    baseline_y: f32,
    size: f32,
    color: Color,
) {
    let m = font.metrics(ch, size);
    let glyph_w = m.advance_width;
    let pen = box_x + (box_w - glyph_w) / 2.0;
    draw_text(pm, font, &ch.to_string(), pen, baseline_y, size, color);
}
