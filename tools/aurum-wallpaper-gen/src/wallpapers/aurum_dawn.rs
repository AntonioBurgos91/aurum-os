// aurum-dawn — pink→peach→cream morning palette.
//
// Mood: the first three minutes after sunrise, when everything has a soft
// rose cast and the world still feels asleep. Diagonal gradient mirrors
// aurum-amber's composition but with cooler highlights and a peach midtone.
// One soft cream leak top-centre stands in for the sun just over the horizon.
//
// Palette (per agent brief):
//   #FFE6F0 → #FFD2A8 → #FFA88B

use tiny_skia::Pixmap;
use crate::gradients::{self, Rgb};
use crate::lightleaks::{Leak, draw_leaks};
use crate::noise;

const PINK:   Rgb = (0xFF, 0xE6, 0xF0);  // top-left highlight
const PEACH:  Rgb = (0xFF, 0xD2, 0xA8);  // midtone
const CORAL:  Rgb = (0xFF, 0xA8, 0x8B);  // bottom-right shadow
const ROSE:   Rgb = (0xE0, 0x78, 0x72);  // deepest corner

pub fn render(w: u32, h: u32) -> Pixmap {
    let mut pm = Pixmap::new(w, h).expect("pixmap alloc");
    let wf = w as f32;
    let hf = h as f32;

    gradients::linear(&mut pm, w, h,
        (wf * 0.05, hf * 0.05),
        (wf * 0.95, hf * 0.95),
        &[
            (0.00, PINK),
            (0.45, PEACH),
            (0.85, CORAL),
            (1.00, ROSE),
        ]);

    // Soft cream leak top-centre — the rising sun.
    draw_leaks(&mut pm, &[
        Leak {
            cx: wf * 0.50, cy: hf * 0.10,
            rx: wf * 0.36, ry: hf * 0.18,
            color: (0xFF, 0xF4, 0xE0),
            peak_alpha: 150,
        },
    ]);

    noise::apply(&mut pm, 0xA0_2026_0004, 3, 0.04);
    pm
}
