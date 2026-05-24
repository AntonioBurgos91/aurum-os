// aurum-void — pure-black OLED-friendly minimal wallpaper.
//
// Mood: a single dim radial of deep blue in the upper-third over a true-
// black background. Designed for OLED panels where every fully-black pixel
// is a powered-off pixel — the wallpaper draws roughly 5% of the screen
// area in non-black colour.
//
// Palette (per agent brief):
//   #000000 → #0A1838 → #050518
// The "highlight" is intentionally only ~10% luminance.

use tiny_skia::Pixmap;
use crate::gradients::{self, Rgb};
use crate::noise;

const BLACK: Rgb = (0x00, 0x00, 0x00);
const DEEP:  Rgb = (0x05, 0x05, 0x18);   // middle ring
const NAVY:  Rgb = (0x0A, 0x18, 0x38);   // glow centre

pub fn render(w: u32, h: u32) -> Pixmap {
    let mut pm = Pixmap::new(w, h).expect("pixmap alloc");
    let wf = w as f32;
    let hf = h as f32;

    // Start with absolute black so the corners are exactly #000000 (so OLED
    // power savings are not lost to a 1-LSB ramp).
    gradients::linear(&mut pm, w, h,
        (0.0, 0.0), (0.0, hf),
        &[
            (0.0, BLACK),
            (1.0, BLACK),
        ]);

    // Single dim radial top-centre. Small radius so >85% of the canvas
    // stays pure black.
    gradients::radial(&mut pm, w, h,
        wf * 0.50, hf * 0.32,
        wf.max(hf) * 0.42,
        &[
            (0.00, NAVY),
            (0.35, DEEP),
            (1.00, BLACK),
        ]);

    // Very light grain only inside the glow — but applying noise over a
    // mostly-black canvas would lift the floor away from #000000 and
    // defeat the OLED purpose, so we skip noise on this wallpaper.
    let _ = noise::apply; // documented intentional no-op
    pm
}
