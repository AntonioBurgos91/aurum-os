// aurum-aurora — northern-lights conic gradient.
//
// Mood: an iridescent green→teal→purple sweep evoking the Sept-Iqaluit-at-
// midnight aurora. We use the multi-stop conic gradient helper from
// gradients.rs to sweep the hue around the canvas, then composite a heavy
// soft glow on top to hide the segment seams and add depth.
//
// Palette (per agent brief):
//   #1A3D2E → #3DA68F → #B36EFF
// Additional stops are interpolated to make the conic loop smoothly back
// to the start without a hard seam.

use std::f32::consts::PI;
use tiny_skia::Pixmap;
use crate::gradients::{self, Rgb};
use crate::lightleaks::{Leak, draw_leaks};
use crate::noise;

const FOREST: Rgb = (0x1A, 0x3D, 0x2E);
const TEAL:   Rgb = (0x3D, 0xA6, 0x8F);
const VIOLET: Rgb = (0xB3, 0x6E, 0xFF);
const NIGHT:  Rgb = (0x12, 0x1A, 0x3D);  // deep blue between violet and forest

pub fn render(w: u32, h: u32) -> Pixmap {
    let mut pm = Pixmap::new(w, h).expect("pixmap alloc");
    let wf = w as f32;
    let hf = h as f32;

    // Base: dark night layer so areas outside the conic radius read as
    // deep blue rather than transparent black after the noise step.
    gradients::linear(&mut pm, w, h,
        (wf * 0.5, 0.0), (wf * 0.5, hf),
        &[
            (0.0, (0x08, 0x0E, 0x22)),
            (1.0, (0x02, 0x05, 0x12)),
        ]);

    // Conic sweep around the centre. Angles ordered so the loop closes.
    gradients::conic(&mut pm, w, h, wf * 0.5, hf * 0.55, &[
        (0.0 * PI,         FOREST),
        (0.5 * PI,         TEAL),
        (1.0 * PI,         VIOLET),
        (1.5 * PI,         NIGHT),
    ]);

    // Heavy soft glow across the centre to blur the conic's polygonal seams
    // — three big additive leaks tinted by the conic's local colour.
    draw_leaks(&mut pm, &[
        Leak {
            cx: wf * 0.50, cy: hf * 0.50,
            rx: wf * 0.48, ry: hf * 0.55,
            color: TEAL,
            peak_alpha: 80,
        },
        Leak {
            cx: wf * 0.65, cy: hf * 0.35,
            rx: wf * 0.30, ry: hf * 0.28,
            color: VIOLET,
            peak_alpha: 100,
        },
        Leak {
            cx: wf * 0.32, cy: hf * 0.62,
            rx: wf * 0.30, ry: hf * 0.28,
            color: FOREST,
            peak_alpha: 70,
        },
    ]);

    noise::apply(&mut pm, 0xA0_2026_0005, 3, 0.04);
    pm
}
