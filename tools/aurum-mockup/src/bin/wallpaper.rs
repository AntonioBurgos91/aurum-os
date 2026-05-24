// aurum-wallpaper — generates the AurumOS default wallpaper PNG.
//
// Look: macOS Sequoia Dark inspired — a deep night-time gradient sky with a
// soft aurora-borealis band, low rolling mountain silhouettes, a high-altitude
// glow, and a sparse starfield. Designed to read well as a backdrop while a
// translucent menubar (top) and dock (bottom) sit on top of it. NO photo
// content; everything is procedural so it stays crisp at any resolution.
//
// Usage:
//   aurum-wallpaper [WIDTH HEIGHT] [OUTPUT.png]
//
// Defaults: 1600 x 1000 → ./aurum-wallpaper.png
//
// Tested at: 1600x1000 (preview), 1920x1200, 2560x1600, 2880x1800 (Retina).
// Each pass is path-based, so it scales without blur.

use aurum_render::*;
use std::path::PathBuf;
use tiny_skia::*;

// ---------- Palette ----------
// Anchored on the mocked hero shot so the desktop reads as one piece.
const SKY_TOP_NIGHT:    Rgba = [0x04, 0x07, 0x16, 0xff];  // deep night
const SKY_MID_BLUE:     Rgba = [0x0d, 0x12, 0x32, 0xff];  // royal night
const SKY_BOT_VIOLET:   Rgba = [0x18, 0x14, 0x38, 0xff];  // dusky purple
const AURORA_GREEN:     Rgba = [0x35, 0xd6, 0xa6, 0xff];  // aurora teal-green
const AURORA_PURPLE:    Rgba = [0xa0, 0x4f, 0xff, 0xff];  // upper aurora violet
const MOON_HALO:        Rgba = [0xff, 0xf2, 0xd8, 0xff];  // warm moon
const HILL_FAR:         Rgba = [0x0f, 0x14, 0x2c, 0xff];
const HILL_MID:         Rgba = [0x07, 0x0a, 0x1c, 0xff];
const HILL_NEAR:        Rgba = [0x02, 0x04, 0x0e, 0xff];

fn draw(pm: &mut Pixmap, w: u32, h: u32) {
    let wf = w as f32;
    let hf = h as f32;

    // ── 1. Sky — 3-stop vertical gradient via two stacked rects ──────────────
    // tiny-skia gradient stops are linear, so we approximate a 3-stop sky by
    // drawing two regions: top half = night → mid-blue, bottom half = mid →
    // violet. The seams disappear because adjacent colours are picked to be
    // continuous.
    vertical_gradient(pm, 0.0, 0.0,     wf, hf * 0.55, c(SKY_TOP_NIGHT), c(SKY_MID_BLUE));
    vertical_gradient(pm, 0.0, hf*0.55, wf, hf * 0.45, c(SKY_MID_BLUE),  c(SKY_BOT_VIOLET));

    // ── 2. Aurora borealis band — wide, soft, low-opacity vertical glow ─────
    // Concentric horizontal bands of decreasing alpha, vertical centre about
    // 40% from the top, taller than wide. Diagonal direction faked by drawing
    // each band with a slight x-shift derived from y.
    let aurora_cx = wf * 0.40;
    let aurora_cy = hf * 0.38;
    for i in 0..38 {
        let r        = 60.0 + i as f32 * 28.0;
        let alpha    = ((40 - i).max(0) * 2) as u8;
        let mix_t    = (i as f32) / 38.0;  // 0 = green core, 1 = violet outer
        let mix = |a: Rgba, b: Rgba, t: f32| -> Color {
            rgba8(
                ((a[0] as f32) * (1.0 - t) + (b[0] as f32) * t) as u8,
                ((a[1] as f32) * (1.0 - t) + (b[1] as f32) * t) as u8,
                ((a[2] as f32) * (1.0 - t) + (b[2] as f32) * t) as u8,
                alpha,
            )
        };
        let col = mix(AURORA_GREEN, AURORA_PURPLE, mix_t);
        // Squash vertically so the glow forms a vertical column rather than
        // an evenly round disc — that's what auroras read as visually.
        let stretch_x = 0.55;
        fill_round_rect(pm,
            aurora_cx - r * stretch_x, aurora_cy - r,
            r * 2.0 * stretch_x, r * 2.0,
            r, col);
    }

    // ── 3. Moon halo — small warm disc upper-right ──────────────────────────
    let moon_cx = wf * 0.78;
    let moon_cy = hf * 0.22;
    let moon_r  = (hf * 0.040).max(20.0);
    // halo
    for i in 0..28 {
        let rr = moon_r + i as f32 * 6.0;
        let a  = ((30 - i).max(0) * 2) as u8;
        fill_round_rect(pm, moon_cx - rr, moon_cy - rr, rr * 2.0, rr * 2.0, rr, ca(MOON_HALO, a));
    }
    // moon disc
    fill_round_rect(pm, moon_cx - moon_r, moon_cy - moon_r,
                    moon_r * 2.0, moon_r * 2.0, moon_r, c(MOON_HALO));

    // ── 4. Starfield — small bright dots, denser higher up ──────────────────
    let mut seed: u64 = 0xA17_C0DE_5_BEEF;
    let n_stars = (wf * hf / 6_500.0) as usize;
    for _ in 0..n_stars {
        // xorshift64*
        seed ^= seed << 13;
        seed ^= seed >> 7;
        seed ^= seed << 17;
        let s = seed.wrapping_mul(0x2545F491_4F6CDD1D);

        let xn = ((s         & 0xFFFF) as f32) / 65535.0;
        let yn = ((s >> 16) & 0xFFFF) as f32 / 65535.0;
        let bn = ((s >> 32) & 0xFF)   as f32 / 255.0;

        // Bias y toward the top (square root makes more stars appear high).
        let x = xn * wf;
        let y = yn.sqrt() * hf * 0.78;     // 78% upper band
        let bright = 140 + (bn * 110.0) as u8;

        // Most stars are 1px; ~5% twinkle to 2px and pick up a faint halo.
        if (s >> 60) & 0xF == 0 {
            // big twinkler — tiny cross + halo
            fill_round_rect(pm, x, y, 2.0, 2.0, 1.0, rgba8(bright, bright, 255, 220));
            fill_round_rect(pm, x - 1.0, y, 4.0, 1.0, 0.5, rgba8(bright, bright, 255, 80));
            fill_round_rect(pm, x, y - 1.0, 1.0, 4.0, 0.5, rgba8(bright, bright, 255, 80));
        } else {
            fill_round_rect(pm, x, y, 1.0, 1.0, 0.5, rgba8(bright, bright, (bright as u16 + 30).min(255) as u8, 230));
        }
    }

    // ── 5. Hills — three layered silhouettes for depth ──────────────────────
    let draw_hill = |pm: &mut Pixmap,
                     base_y: f32, amp: f32, segments: usize,
                     color: Color, phase: f32| {
        let mut pb = PathBuilder::new();
        pb.move_to(0.0, hf);
        pb.line_to(0.0, base_y + amp * 0.5);
        for i in 0..segments {
            let t0 = i as f32 / segments as f32;
            let t1 = (i + 1) as f32 / segments as f32;
            let x0 = t0 * wf;
            let x1 = t1 * wf;
            let mid = (x0 + x1) * 0.5;
            // Quasi-random hill heights using sin sums.
            let h_offset = (mid * 0.013 + phase).sin() * amp
                         + (mid * 0.041 + phase).sin() * amp * 0.35;
            let cy = base_y - h_offset;
            pb.quad_to(mid, cy, x1, base_y + (h_offset * 0.4));
        }
        pb.line_to(wf, hf);
        pb.close();
        if let Some(path) = pb.finish() {
            let mut paint = Paint::default();
            paint.set_color(color);
            paint.anti_alias = true;
            pm.fill_path(&path, &paint, FillRule::Winding, Transform::identity(), None);
        }
    };
    draw_hill(pm, hf * 0.74,  70.0, 16, c(HILL_FAR),  0.0);
    draw_hill(pm, hf * 0.84,  90.0, 14, c(HILL_MID),  2.4);
    draw_hill(pm, hf * 0.93, 100.0, 12, c(HILL_NEAR), 5.1);

    // ── 6. Vignette — subtle darkening toward all four edges ────────────────
    radial_vignette(
        pm, w, h,
        wf * 0.5, hf * 0.5,
        hf * 0.30, hf.max(wf) * 0.85,
        rgba8(0, 0, 0, 0),
        rgba8(0, 0, 0, 120),
    );
}

fn main() {
    // Argument parsing: [WIDTH HEIGHT] [OUTPUT].  All optional.  We expect
    // exactly 0, 1, 2, or 3 positional args so users don't get confused.
    let args: Vec<String> = std::env::args().skip(1).collect();
    let (w, h, out): (u32, u32, PathBuf) = match args.len() {
        0 => (1600, 1000, PathBuf::from("aurum-wallpaper.png")),
        1 => (1600, 1000, PathBuf::from(&args[0])),
        2 => (args[0].parse().expect("WIDTH"),
              args[1].parse().expect("HEIGHT"),
              PathBuf::from("aurum-wallpaper.png")),
        3 => (args[0].parse().expect("WIDTH"),
              args[1].parse().expect("HEIGHT"),
              PathBuf::from(&args[2])),
        _ => {
            eprintln!("usage: aurum-wallpaper [WIDTH HEIGHT] [OUTPUT.png]");
            std::process::exit(2);
        }
    };

    let mut pm = Pixmap::new(w, h).expect("pixmap alloc");
    draw(&mut pm, w, h);
    pm.save_png(&out).expect("save png");
    eprintln!("✓ wrote {} ({}x{})", out.display(), w, h);
}
