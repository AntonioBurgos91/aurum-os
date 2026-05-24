// Film-grain noise overlay.
//
// Sequoia's wallpapers carry a barely-perceptible texture — about 1-2% of
// peak luminance — that prevents the smooth gradients from looking like
// banded vector art on modern OLED panels. We replicate that by perturbing
// each RGB channel by a small signed delta drawn from a SmallRng seeded
// per-wallpaper, so the same wallpaper always produces the same noise
// pattern (bit-reproducible PNGs).
//
// We deliberately do NOT use a Perlin / OpenSimplex texture: real film
// grain is essentially white noise, and a real LCD/OLED's own dithering
// hides any structured pattern. White noise is also ~free to compute.

use rand::{Rng, SeedableRng};
use rand::rngs::SmallRng;
use tiny_skia::Pixmap;

/// Apply additive noise directly to the pixmap's premultiplied-RGBA buffer.
///
/// Parameters:
///   * `seed`      — deterministic per-wallpaper seed (e.g. 0xAU2026_AMBER)
///   * `amplitude` — max absolute pixel delta per channel, in 0..255 units.
///                   2 ≈ "barely visible", 4 ≈ "grain you can see at 100%".
///   * `weight`    — overall opacity of the effect, 0.0..1.0. The spec calls
///                   for ~0.04 which means 4% of the noise is applied; this
///                   lets the caller dial the grain down without changing
///                   amplitude (and the resulting clipping characteristics).
pub fn apply(pm: &mut Pixmap, seed: u64, amplitude: i16, weight: f32) {
    let mut rng = SmallRng::seed_from_u64(seed);
    let weight = weight.clamp(0.0, 1.0);
    let amp = amplitude.max(0);
    if amp == 0 || weight == 0.0 { return; }

    let data = pm.data_mut();
    // RGBA, premultiplied. We perturb R, G, B equally (luma noise — same
    // delta on all three channels reads as brightness jitter rather than
    // chroma noise, matching real silver-halide grain).
    let mut i = 0;
    while i < data.len() {
        // One delta per pixel, shared across R/G/B. Range [-amp, +amp].
        let delta_raw: i16 = rng.gen_range(-amp..=amp);
        let delta = ((delta_raw as f32) * weight) as i16;
        for c in 0..3 {
            let v = data[i + c] as i16 + delta;
            data[i + c] = v.clamp(0, 255) as u8;
        }
        // Alpha left untouched. Pixmap stays premultiplied because alpha
        // is 255 everywhere after a full-canvas base gradient.
        i += 4;
    }
}
