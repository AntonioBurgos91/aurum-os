// aurum-obsidian — the AurumOS dark-mode default.
//
// Mood: near-black field with a subtle purple→blue radial glow drifting in
// the upper-centre, evoking deep-space starlight without the kitsch of an
// actual starfield. Designed to disappear when you focus on a window — the
// wallpaper exists, but doesn't compete for attention.
//
// Palette (per agent brief):
//   #0A0A1F → #1A1142 → #281553
// Brightest stop kept around 25% luminance so HDR-incapable panels don't
// crush the highlight to mid-grey.

use tiny_skia::Pixmap;
use crate::gradients::{self, Rgb};
use crate::lightleaks::{Leak, draw_leaks};
use crate::noise;

const NEAR_BLACK: Rgb = (0x05, 0x05, 0x10);  // canvas edges
const VIOLET:     Rgb = (0x1A, 0x11, 0x42);  // mid radius
const ROYAL:      Rgb = (0x28, 0x15, 0x53);  // glow centre fallback

pub fn render(w: u32, h: u32) -> Pixmap {
    let mut pm = Pixmap::new(w, h).expect("pixmap alloc");
    let wf = w as f32;
    let hf = h as f32;

    // Base: large radial centred upper-third, glowing toward violet.
    gradients::radial(&mut pm, w, h,
        wf * 0.50, hf * 0.32,
        wf.max(hf) * 0.90,
        &[
            (0.00, ROYAL),
            (0.25, VIOLET),
            (0.70, (0x0A, 0x0A, 0x1F)),
            (1.00, NEAR_BLACK),
        ]);

    // Subtle additive purple-blue highlight to lift the gradient peak.
    draw_leaks(&mut pm, &[
        Leak {
            cx: wf * 0.50, cy: hf * 0.30,
            rx: wf * 0.40, ry: hf * 0.30,
            color: (0x60, 0x40, 0xC0),
            peak_alpha: 60,
        },
    ]);

    noise::apply(&mut pm, 0xA0_2026_0003, 2, 0.05);
    pm
}
