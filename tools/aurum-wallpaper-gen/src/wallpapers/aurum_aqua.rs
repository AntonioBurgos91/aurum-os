// aurum-aqua — cool tropical-lagoon-at-dusk gradient.
//
// Mood: looking up through clear water at a deep evening sky. The base is a
// vertical teal→cyan→indigo gradient (lighter at the top where the "sun"
// just set, darkest at the very bottom). A single cyan light-leak sits in
// the bottom-left, suggesting bioluminescence or a distant lighthouse.
//
// Palette (per agent brief):
//   #00C9D7 → #0066CC → #2E1A6B

use tiny_skia::Pixmap;
use crate::gradients::{self, Rgb};
use crate::lightleaks::{Leak, draw_leaks};
use crate::noise;

const TEAL:   Rgb = (0x00, 0xC9, 0xD7);
const AZURE:  Rgb = (0x00, 0x66, 0xCC);
const INDIGO: Rgb = (0x2E, 0x1A, 0x6B);
const ABYSS:  Rgb = (0x14, 0x0C, 0x38);  // extra-dark stop at the very bottom

pub fn render(w: u32, h: u32) -> Pixmap {
    let mut pm = Pixmap::new(w, h).expect("pixmap alloc");
    let wf = w as f32;
    let hf = h as f32;

    gradients::linear(&mut pm, w, h,
        (wf * 0.5, 0.0),
        (wf * 0.5, hf),
        &[
            (0.00, TEAL),
            (0.45, AZURE),
            (0.85, INDIGO),
            (1.00, ABYSS),
        ]);

    // Single cyan leak bottom-left.
    draw_leaks(&mut pm, &[
        Leak {
            cx: wf * 0.18, cy: hf * 0.82,
            rx: wf * 0.32, ry: hf * 0.30,
            color: (0x80, 0xF0, 0xFF),
            peak_alpha: 140,
        },
    ]);

    noise::apply(&mut pm, 0xA0_2026_0002, 3, 0.04);
    pm
}
