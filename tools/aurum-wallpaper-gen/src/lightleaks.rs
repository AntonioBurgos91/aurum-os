// Light-leak overlay — soft, high-intensity ellipses additively blended.
//
// tiny-skia 0.11 does not ship a Gaussian blur primitive, so we fake the
// blur by stacking 3-5 copies of the same radial gradient at progressively
// larger radii and decreasing alpha. The eye reads the union as a single,
// gently feathered glow. This is the same trick the aurum-mockup "drop
// shadow" helper uses, generalised to ellipses and additive blending.
//
// Each leak is parameterised by:
//   center (cx, cy)
//   radii  (rx, ry)        — ellipse dimensions in px
//   color  (r, g, b)        — RGB only; alpha is derived per stack level
//   peak_alpha             — alpha at stack-level 0 (the bright core)

use tiny_skia::*;
use crate::gradients::Rgb;

pub struct Leak {
    pub cx: f32,
    pub cy: f32,
    pub rx: f32,
    pub ry: f32,
    pub color: Rgb,
    pub peak_alpha: u8,
}

/// Paint a single light leak on top of `pm` using additive blending. The
/// ellipse is approximated by a circular RadialGradient drawn into a
/// transformed coordinate system: tiny-skia's gradient is radial-symmetric,
/// so we scale the world non-uniformly with a Transform to get an ellipse.
pub fn draw_leak(pm: &mut Pixmap, leak: &Leak) {
    // Three stacked passes: tight bright core, mid halo, wide soft bloom.
    // Alpha falls off geometrically; radius grows linearly.
    let layers = [
        (1.00_f32, 1.00_f32),  // (radius_mul, alpha_mul)
        (1.55,     0.55),
        (2.30,     0.25),
        (3.20,     0.10),
    ];
    for (rm, am) in layers {
        let alpha = ((leak.peak_alpha as f32) * am).clamp(0.0, 255.0) as u8;
        if alpha == 0 { continue; }
        // Build the radial gradient in a unit-circle space (radius = 1),
        // then transform it to an ellipse of (rx * rm, ry * rm) centred at
        // (cx, cy). The transform applies to the *shader*, not the path,
        // because we fill_rect over the whole canvas masked by the alpha
        // falloff of the gradient itself.
        let rx = leak.rx * rm;
        let ry = leak.ry * rm;
        // Translate so (0,0) of the gradient lands at (cx, cy), then scale
        // x and y independently. Order matters in tiny-skia's premultiplied
        // model: scale first, then translate.
        let tr = Transform::from_scale(rx, ry).post_translate(leak.cx, leak.cy);
        let shader = RadialGradient::new(
            Point::from_xy(0.0, 0.0),
            Point::from_xy(0.0, 0.0),
            1.0,
            vec![
                GradientStop::new(0.0,
                    Color::from_rgba8(leak.color.0, leak.color.1, leak.color.2, alpha)),
                GradientStop::new(0.6,
                    Color::from_rgba8(leak.color.0, leak.color.1, leak.color.2, alpha / 3)),
                GradientStop::new(1.0,
                    Color::from_rgba8(leak.color.0, leak.color.1, leak.color.2, 0)),
            ],
            SpreadMode::Pad,
            tr,
        ).expect("light-leak radial gradient");

        let mut paint = Paint::default();
        paint.shader = shader;
        paint.anti_alias = true;
        paint.blend_mode = BlendMode::Plus;

        // Fill a rect large enough to cover the entire ellipse stack. Using
        // the full canvas would also work but wastes shader evaluation on
        // far-away pixels where the gradient is already 0.
        let pad = (rx.max(ry)) * 1.05;
        let x0 = (leak.cx - pad).max(0.0);
        let y0 = (leak.cy - pad).max(0.0);
        let x1 = (leak.cx + pad).min(pm.width()  as f32);
        let y1 = (leak.cy + pad).min(pm.height() as f32);
        if x1 > x0 && y1 > y0 {
            if let Some(r) = Rect::from_xywh(x0, y0, x1 - x0, y1 - y0) {
                pm.fill_rect(r, &paint, Transform::identity(), None);
            }
        }
    }
}

/// Convenience: draw a batch of leaks in declaration order.
pub fn draw_leaks(pm: &mut Pixmap, leaks: &[Leak]) {
    for l in leaks { draw_leak(pm, l); }
}
