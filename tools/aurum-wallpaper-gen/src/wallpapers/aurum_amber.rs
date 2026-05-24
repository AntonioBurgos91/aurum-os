// aurum-amber — the AurumOS signature wallpaper for tier "pro".
//
// Mood: a warm sunrise read at f/1.4 through a vintage lens. The base is a
// diagonal amber→gold gradient; two slightly-offset light leaks sit in the
// upper-right where you'd expect a flare from a strong off-frame source.
// A subtle vignette darkens the lower-left to anchor the composition and
// give the menubar/dock something darker to sit against.
//
// Palette (per agent brief):
//   #FFAA3D → #FFD25C → #FFE9A8
// All three are extended slightly toward the deep-amber end at the bottom
// so the lower 20% of the canvas isn't burnt-out cream.

use tiny_skia::Pixmap;
use crate::gradients::{self, Rgb};
use crate::lightleaks::{Leak, draw_leaks};
use crate::noise;

const DEEP_AMBER: Rgb = (0xC8, 0x6C, 0x1F);  // shadow corner, off-palette
const AMBER:      Rgb = (0xFF, 0xAA, 0x3D);  // main midtone
const GOLD:       Rgb = (0xFF, 0xD2, 0x5C);  // highlight midtone
const CREAM:      Rgb = (0xFF, 0xE9, 0xA8);  // brightest stop

pub fn render(w: u32, h: u32) -> Pixmap {
    let mut pm = Pixmap::new(w, h).expect("pixmap alloc");
    let wf = w as f32;
    let hf = h as f32;

    // 1. Base diagonal gradient bottom-left (dark) → top-right (bright).
    gradients::linear(&mut pm, w, h,
        (wf * 0.05, hf * 0.95),       // bottom-left
        (wf * 0.95, hf * 0.05),       // top-right
        &[
            (0.00, DEEP_AMBER),
            (0.40, AMBER),
            (0.80, GOLD),
            (1.00, CREAM),
        ]);

    // 2. Two amber light leaks anchored top-right. The first is a tight
    //    bright core; the second is a wider, dimmer halo offset slightly
    //    down and left — together they read as a single anamorphic flare.
    draw_leaks(&mut pm, &[
        Leak {
            cx: wf * 0.82, cy: hf * 0.18,
            rx: wf * 0.18, ry: hf * 0.22,
            color: (0xFF, 0xC8, 0x78),
            peak_alpha: 180,
        },
        Leak {
            cx: wf * 0.68, cy: hf * 0.34,
            rx: wf * 0.30, ry: hf * 0.32,
            color: (0xFF, 0xB4, 0x50),
            peak_alpha: 110,
        },
    ]);

    // 3. Soft radial vignette darkening the lower-left so the dock area
    //    has contrast against light icons. Drawn as a wide radial with
    //    Plus-blend NEGATIVE values would be ideal, but tiny-skia can't
    //    subtract; we instead lay down a dim brown halo at very low alpha.
    crate::gradients::radial_plus(&mut pm, w, h,
        wf * 0.10, hf * 0.90, wf.max(hf) * 0.55,
        &[
            (0.00, (0x30, 0x18, 0x05), 0),
            (1.00, (0x40, 0x18, 0x00), 28),
        ]);

    // 4. Film grain. Seed is a tag-anchored constant so the PNG is byte-
    //    reproducible across machines and Rust versions.
    // Per-wallpaper seed (derived from AurumOS 2026 tag). The literal must
    // be valid hex, so the "U" in the brief's 0xAU2026 becomes 0; we then
    // suffix a per-wallpaper id so the six PNGs never share a grain pattern.
    noise::apply(&mut pm, 0xA0_2026_0001, 3, 0.04);
    pm
}
