// Gradient helpers for the wallpaper renderer.
//
// tiny-skia ships LinearGradient / RadialGradient / Shader directly; this
// module is a thin convenience layer that (a) takes RGB tuples instead of
// fully-qualified Color values and (b) covers the whole pixmap with a single
// fill_rect call, which is what every base layer of every wallpaper wants.
//
// Conic gradients aren't a native tiny-skia primitive (as of 0.11), so we
// fake one with a fan of triangular linear gradients — adequate for the
// aurora wallpaper where the conic effect is intentionally soft.

use tiny_skia::*;

pub type Rgb = (u8, u8, u8);

#[inline]
pub fn color(rgb: Rgb, alpha: u8) -> Color {
    Color::from_rgba8(rgb.0, rgb.1, rgb.2, alpha)
}

#[inline]
fn rect(w: u32, h: u32) -> Rect {
    Rect::from_xywh(0.0, 0.0, w as f32, h as f32).unwrap()
}

/// Fill the whole pixmap with a linear gradient from `p1` to `p2`, sampling
/// `stops` (offset 0..1, color) in order.
pub fn linear(pm: &mut Pixmap, w: u32, h: u32,
              p1: (f32, f32), p2: (f32, f32),
              stops: &[(f32, Rgb)]) {
    let gs: Vec<GradientStop> = stops.iter()
        .map(|(o, c)| GradientStop::new(*o, color(*c, 255)))
        .collect();
    let shader = LinearGradient::new(
        Point::from_xy(p1.0, p1.1),
        Point::from_xy(p2.0, p2.1),
        gs,
        SpreadMode::Pad,
        Transform::identity(),
    ).expect("linear gradient");
    let mut paint = Paint::default();
    paint.shader = shader;
    paint.anti_alias = true;
    pm.fill_rect(rect(w, h), &paint, Transform::identity(), None);
}

/// Fill the whole pixmap with a radial gradient centred at (cx, cy) of
/// `radius` px, sampling `stops` (offset 0..1, color).
pub fn radial(pm: &mut Pixmap, w: u32, h: u32,
              cx: f32, cy: f32, radius: f32,
              stops: &[(f32, Rgb)]) {
    let gs: Vec<GradientStop> = stops.iter()
        .map(|(o, c)| GradientStop::new(*o, color(*c, 255)))
        .collect();
    let shader = RadialGradient::new(
        Point::from_xy(cx, cy),
        Point::from_xy(cx, cy),
        radius,
        gs,
        SpreadMode::Pad,
        Transform::identity(),
    ).expect("radial gradient");
    let mut paint = Paint::default();
    paint.shader = shader;
    paint.anti_alias = true;
    pm.fill_rect(rect(w, h), &paint, Transform::identity(), None);
}

/// Same as `radial` but additive: stops carry their own alpha and the result
/// is composited Plus on top of whatever is already in `pm`. Used to paint a
/// soft glow over an existing gradient without clobbering the base.
pub fn radial_plus(pm: &mut Pixmap, w: u32, h: u32,
                   cx: f32, cy: f32, radius: f32,
                   stops: &[(f32, Rgb, u8)]) {
    let gs: Vec<GradientStop> = stops.iter()
        .map(|(o, c, a)| GradientStop::new(*o, color(*c, *a)))
        .collect();
    let shader = RadialGradient::new(
        Point::from_xy(cx, cy),
        Point::from_xy(cx, cy),
        radius,
        gs,
        SpreadMode::Pad,
        Transform::identity(),
    ).expect("radial gradient");
    let mut paint = Paint::default();
    paint.shader = shader;
    paint.anti_alias = true;
    paint.blend_mode = BlendMode::Plus;
    pm.fill_rect(rect(w, h), &paint, Transform::identity(), None);
}

/// Fake conic gradient: sweep `segments` triangular linear gradients around
/// (cx, cy). Each segment is a thin pie slice whose two endpoints take the
/// interpolated colors at the start and end angle. With ~64 segments the
/// seams blend visually; with 128+ they are invisible on a 4K display.
///
/// `stops` is (angle_radians, color); the function wraps around 2π.
pub fn conic(pm: &mut Pixmap, w: u32, h: u32,
             cx: f32, cy: f32,
             stops: &[(f32, Rgb)]) {
    use std::f32::consts::PI;
    let segments = 192_usize;
    let radius = ((w as f32).powi(2) + (h as f32).powi(2)).sqrt();
    let sample = |theta: f32| -> Rgb {
        // Normalise to [0, 2π).
        let t = ((theta % (2.0 * PI)) + 2.0 * PI) % (2.0 * PI);
        // Find surrounding stops.
        let mut lo = stops.last().copied().unwrap();
        let mut hi = stops[0];
        let mut found = false;
        for w in stops.windows(2) {
            if t >= w[0].0 && t <= w[1].0 {
                lo = w[0]; hi = w[1]; found = true; break;
            }
        }
        if !found {
            // Between last stop and (first stop + 2π).
            lo = *stops.last().unwrap();
            hi = (stops[0].0 + 2.0 * PI, stops[0].1);
        }
        let span = (hi.0 - lo.0).max(1e-4);
        let f = ((t - lo.0) / span).clamp(0.0, 1.0);
        let lc = lo.1; let hc = hi.1;
        (
            (lc.0 as f32 * (1.0 - f) + hc.0 as f32 * f) as u8,
            (lc.1 as f32 * (1.0 - f) + hc.1 as f32 * f) as u8,
            (lc.2 as f32 * (1.0 - f) + hc.2 as f32 * f) as u8,
        )
    };
    for i in 0..segments {
        let a0 = (i     as f32 / segments as f32) * 2.0 * PI;
        let a1 = ((i+1) as f32 / segments as f32) * 2.0 * PI;
        // Sample one color per slice (midpoint) and fill the slice with a
        // solid color. The aurora wallpaper composites a heavy blur on top
        // afterwards so the discrete steps are not visible.
        let mid = (a0 + a1) * 0.5;
        let col = sample(mid);
        let mut pb = PathBuilder::new();
        pb.move_to(cx, cy);
        pb.line_to(cx + a0.cos() * radius, cy + a0.sin() * radius);
        pb.line_to(cx + a1.cos() * radius, cy + a1.sin() * radius);
        pb.close();
        if let Some(path) = pb.finish() {
            let mut paint = Paint::default();
            paint.set_color(color(col, 255));
            paint.anti_alias = true;
            pm.fill_path(&path, &paint, FillRule::Winding, Transform::identity(), None);
        }
    }
    let _ = (w, h); // suppress unused-warning when callers ignore size
}
