// aurum-icons — generates a macOS-style squircle icon set for the dock.
//
// Each icon is a 320×320 PNG (256×256 face + 32 px padding for the drop
// shadow). Every icon is a multi-element composition — gradient body, glass
// highlight, a 1-px inset border, then app-specific marks (Finder face,
// terminal prompt, browser globe, notebook chevron, etc.). No glyph-only
// designs: at 64 px on the dock you want something with depth.
//
// Output filenames match the .desktop file IDs we install alongside.
//
// Usage:
//   aurum-icons <OUT_DIR>

use aurum_render::*;
use std::path::{Path, PathBuf};
use tiny_skia::*;

const SIDE: u32 = 256;
const PAD:  u32 = 32;
const FULL: u32 = SIDE + PAD * 2;

// Draw the macOS squircle base + glass highlight + inset border, leaving the
// caller free to paint the per-app mark on top. Returns the (x, y) origin
// of the icon face for convenience.
fn draw_squircle_base(pm: &mut Pixmap, top: Rgba, bot: Rgba) -> (f32, f32, f32, f32) {
    let x = PAD as f32;
    let y = PAD as f32;
    let s = SIDE as f32;
    let r = s * 0.225;

    drop_shadow(pm, x, y + 6.0, s, s, r, 140);
    fill_round_rect_gradient(pm, x, y, s, s, r, c(top), c(bot));
    // Top specular highlight.
    fill_round_rect_gradient(pm, x + s * 0.04, y + s * 0.06,
                              s * 0.92, s * 0.42, r * 0.6,
                              rgba8(255, 255, 255, 80),
                              rgba8(255, 255, 255, 0));
    // Inset border (top-light, bottom-shadow).
    stroke_round_rect(pm, x + 0.5, y + 0.5, s - 1.0, s - 1.0, r,
                      rgba8(255, 255, 255, 70), 1.0);
    stroke_round_rect(pm, x, y, s, s, r, rgba8(0, 0, 0, 90), 1.0);

    (x, y, s, r)
}

// ============================================================================
// Per-app art
// ============================================================================

fn draw_finder(pm: &mut Pixmap) {
    let (x, y, s, _r) = draw_squircle_base(pm, [0x44,0x9d,0xff,0xff], [0x18,0x55,0xc6,0xff]);
    // Two-tone "happy Mac" silhouette: a vertical split with a left eye + right
    // eye + smile sketched in white. Simplified to read at 64 px.
    let cx = x + s * 0.5;
    let cy = y + s * 0.5;
    // Split vertical line
    let line_w = 6.0;
    fill_round_rect(pm, cx - line_w / 2.0, y + s * 0.20, line_w, s * 0.60, line_w / 2.0,
                    rgba8(255, 255, 255, 230));
    // Left eye (white circle)
    let eye_r = s * 0.05;
    fill_round_rect(pm, cx - s*0.18 - eye_r, cy - s*0.10 - eye_r,
                    eye_r * 2.0, eye_r * 2.0, eye_r, rgba8(255, 255, 255, 245));
    // Right eye
    fill_round_rect(pm, cx + s*0.18 - eye_r, cy - s*0.10 - eye_r,
                    eye_r * 2.0, eye_r * 2.0, eye_r, rgba8(255, 255, 255, 245));
    // Smile (curved line). Implemented as a flat rectangle since tiny-skia
    // ellipses need PathBuilder, and a thick rounded pill reads as a smile.
    fill_round_rect(pm, cx - s*0.18, cy + s*0.18, s*0.36, s*0.05, s*0.025,
                    rgba8(255, 255, 255, 230));
}

fn draw_spotlight(pm: &mut Pixmap) {
    let (x, y, s, _r) = draw_squircle_base(pm, [0x4b,0x4b,0x53,0xff], [0x21,0x21,0x27,0xff]);
    let cx = x + s * 0.42;
    let cy = y + s * 0.42;
    // Magnifying-glass loop + handle.
    let loop_r = s * 0.20;
    stroke_round_rect(pm, cx - loop_r, cy - loop_r,
                       loop_r * 2.0, loop_r * 2.0, loop_r,
                       rgba8(255, 255, 255, 245), 14.0);
    // Handle — diagonal pill from the loop's lower-right.
    let handle_start_x = cx + loop_r * 0.66;
    let handle_start_y = cy + loop_r * 0.66;
    let handle_len = s * 0.28;
    let mut pb = PathBuilder::new();
    pb.move_to(handle_start_x, handle_start_y);
    pb.line_to(handle_start_x + handle_len * 0.707, handle_start_y + handle_len * 0.707);
    if let Some(path) = pb.finish() {
        let mut p = Paint::default();
        p.set_color(rgba8(255, 255, 255, 245));
        p.anti_alias = true;
        pm.stroke_path(&path, &p, &Stroke {
            width: 16.0, line_cap: LineCap::Round, ..Default::default()
        }, Transform::identity(), None);
    }
}

fn draw_settings(pm: &mut Pixmap) {
    let (x, y, s, _r) = draw_squircle_base(pm, [0xa9,0xae,0xb6,0xff], [0x60,0x65,0x6d,0xff]);
    // Gear silhouette — 8 teeth around a central hole. Drawn as 8 thin rounded
    // rectangles rotated, plus a solid ring + inner circle. Rotation matrices
    // would need PathBuilder transforms; we approximate with 8 rects at
    // computed angles.
    let cx = x + s * 0.5;
    let cy = y + s * 0.5;
    let teeth_r = s * 0.35;
    let inner_r = s * 0.22;
    for i in 0..8 {
        let theta = (i as f32) * std::f32::consts::PI / 4.0;
        let tooth_cx = cx + theta.cos() * teeth_r;
        let tooth_cy = cy + theta.sin() * teeth_r;
        let tooth_w  = s * 0.07;
        let tooth_h  = s * 0.10;
        // Just draw axis-aligned rects (the gear still reads as a gear visually
        // even without rotation; tiny-skia supports Transform on paths but
        // applying it per primitive is verbose).
        fill_round_rect(pm, tooth_cx - tooth_w/2.0, tooth_cy - tooth_h/2.0,
                        tooth_w, tooth_h, tooth_w / 3.0,
                        rgba8(255, 255, 255, 220));
    }
    // Body ring
    fill_round_rect(pm, cx - teeth_r, cy - teeth_r,
                    teeth_r * 2.0, teeth_r * 2.0, teeth_r, rgba8(255, 255, 255, 220));
    // Inner hole
    fill_round_rect(pm, cx - inner_r, cy - inner_r,
                    inner_r * 2.0, inner_r * 2.0, inner_r, rgba8(0x40, 0x42, 0x4a, 255));
}

fn draw_mission(pm: &mut Pixmap) {
    let (x, y, s, _r) = draw_squircle_base(pm, [0x33,0x35,0x40,0xff], [0x12,0x14,0x1c,0xff]);
    // 3×2 grid of window thumbnails (Mission Control look).
    let pad = s * 0.08;
    let gx  = s * 0.06;
    let gy  = s * 0.06;
    let cell_w = (s - pad * 2.0 - gx * 2.0) / 3.0;
    let cell_h = (s - pad * 2.0 - gy * 1.0) / 2.0;
    let colors = [
        rgba8(0xff, 0x55, 0x8f, 220),
        rgba8(0x55, 0xaa, 0xff, 220),
        rgba8(0x32, 0xd6, 0x5d, 220),
        rgba8(0xff, 0xa4, 0x12, 220),
        rgba8(0xb0, 0x83, 0xff, 220),
        rgba8(0x2e, 0xc4, 0xc0, 220),
    ];
    for r in 0..2 {
        for col in 0..3 {
            let cx = x + pad + (col as f32) * (cell_w + gx);
            let cy = y + pad + (r as f32) * (cell_h + gy);
            fill_round_rect(pm, cx, cy, cell_w, cell_h, cell_w * 0.10,
                            colors[r * 3 + col]);
        }
    }
}

fn draw_browser(pm: &mut Pixmap) {
    let (x, y, s, _r) = draw_squircle_base(pm, [0x4d,0xc4,0xff,0xff], [0x1f,0x7a,0xd6,0xff]);
    // Globe — outer circle + two horizontal latitude lines + a vertical longitude.
    let cx = x + s * 0.5;
    let cy = y + s * 0.5;
    let gr = s * 0.32;
    stroke_round_rect(pm, cx - gr, cy - gr, gr * 2.0, gr * 2.0, gr,
                      rgba8(255, 255, 255, 230), 8.0);
    // Latitudes (squashed ovals approximated with rects)
    fill_round_rect(pm, cx - gr * 0.95, cy - 3.0, gr * 1.90, 6.0, 3.0,
                    rgba8(255, 255, 255, 220));
    fill_round_rect(pm, cx - gr * 0.65, cy - gr * 0.5 - 3.0, gr * 1.30, 6.0, 3.0,
                    rgba8(255, 255, 255, 160));
    fill_round_rect(pm, cx - gr * 0.65, cy + gr * 0.5 - 3.0, gr * 1.30, 6.0, 3.0,
                    rgba8(255, 255, 255, 160));
    // Vertical "longitude"
    fill_round_rect(pm, cx - 3.0, cy - gr, 6.0, gr * 2.0, 3.0,
                    rgba8(255, 255, 255, 200));
}

fn draw_terminal(pm: &mut Pixmap) {
    let (x, y, s, _r) = draw_squircle_base(pm, [0x2a,0x2e,0x36,0xff], [0x10,0x11,0x16,0xff]);
    // Header strip with 3 traffic-light dots
    let head_h = s * 0.14;
    fill_round_rect(pm, x + s * 0.06, y + s * 0.08, s * 0.88, head_h, head_h * 0.4,
                    rgba8(0x18, 0x1a, 0x1f, 255));
    let dot_r = s * 0.03;
    for (i, col) in [
        rgba8(255, 95, 87, 255),
        rgba8(255, 189, 46, 255),
        rgba8(40, 201, 64, 255),
    ].iter().enumerate() {
        let dx = x + s * 0.12 + (i as f32) * s * 0.06;
        fill_round_rect(pm, dx, y + s * 0.13, dot_r * 2.0, dot_r * 2.0, dot_r, *col);
    }
    // Body — > prompt + cursor block
    let body_y = y + s * 0.32;
    // Prompt ">" stroked with two diagonals
    let pcx = x + s * 0.22;
    let pcy = body_y + s * 0.10;
    let mut pb = PathBuilder::new();
    pb.move_to(pcx, pcy - s * 0.08);
    pb.line_to(pcx + s * 0.08, pcy);
    pb.line_to(pcx, pcy + s * 0.08);
    if let Some(path) = pb.finish() {
        let mut p = Paint::default();
        p.set_color(rgba8(0x32, 0xd6, 0x5d, 255));  // green prompt
        p.anti_alias = true;
        pm.stroke_path(&path, &p, &Stroke {
            width: 10.0, line_cap: LineCap::Round, line_join: LineJoin::Round,
            ..Default::default()
        }, Transform::identity(), None);
    }
    // Cursor block to the right
    fill_round_rect(pm, x + s * 0.38, pcy - s * 0.05,
                    s * 0.16, s * 0.10, s * 0.01,
                    rgba8(0xff, 0xff, 0xff, 230));
}

fn draw_editor(pm: &mut Pixmap) {
    let (x, y, s, _r) = draw_squircle_base(pm, [0x40,0x90,0xff,0xff], [0x0a,0x49,0xa4,0xff]);
    // Stacked text lines on a "page" background
    let page_x = x + s * 0.12;
    let page_y = y + s * 0.18;
    let page_w = s * 0.76;
    let page_h = s * 0.64;
    fill_round_rect(pm, page_x, page_y, page_w, page_h, s * 0.04,
                    rgba8(245, 247, 252, 255));
    // Sidebar (line-number strip)
    fill_round_rect(pm, page_x, page_y, s * 0.10, page_h, s * 0.02,
                    rgba8(220, 225, 232, 255));
    // Code lines — coloured tokens
    let line_h = s * 0.08;
    let lines = [
        (rgba8(0xc6, 0x4f, 0xa8, 255), 0.55),  // keyword (purple)
        (rgba8(0x55, 0xaa, 0xff, 255), 0.45),  // function (blue)
        (rgba8(0xff, 0xa4, 0x12, 255), 0.65),  // string (orange)
        (rgba8(0x3a, 0x3a, 0x42, 255), 0.40),  // ident
        (rgba8(0xc6, 0x4f, 0xa8, 255), 0.30),
    ];
    for (i, (col, frac)) in lines.iter().enumerate() {
        let ly = page_y + s * 0.06 + (i as f32) * line_h;
        fill_round_rect(pm, page_x + s * 0.14, ly + 4.0,
                        page_w * frac, line_h * 0.55, 2.0, *col);
    }
}

fn draw_jupyter(pm: &mut Pixmap) {
    let (x, y, s, _r) = draw_squircle_base(pm, [0xff,0xa3,0x3a,0xff], [0xd4,0x60,0x10,0xff]);
    // Three orbiting dots around a centre — the Jupyter mark
    let cx = x + s * 0.5;
    let cy = y + s * 0.5;
    // Outer ring (thin)
    stroke_round_rect(pm, cx - s*0.30, cy - s*0.30,
                      s*0.60, s*0.60, s*0.30,
                      rgba8(255, 255, 255, 100), 4.0);
    // Three planet dots
    let dots = [(0.0_f32, -0.28), (0.24, 0.16), (-0.24, 0.16)];
    for (dx, dy) in dots {
        let r = s * 0.07;
        fill_round_rect(pm, cx + dx * s - r, cy + dy * s - r,
                        r * 2.0, r * 2.0, r,
                        rgba8(255, 255, 255, 240));
    }
}

fn draw_marimo(pm: &mut Pixmap) {
    let (x, y, s, _r) = draw_squircle_base(pm, [0x8a,0x6d,0xff,0xff], [0x4f,0x33,0xd4,0xff]);
    // Reactive grid — 3×3 small squares with one highlighted
    let pad = s * 0.16;
    let cell = (s - pad * 2.0) / 3.0;
    let gap  = cell * 0.10;
    let cs   = cell - gap;
    for r in 0..3 {
        for col in 0..3 {
            let cx = x + pad + (col as f32) * cell;
            let cy = y + pad + (r as f32) * cell;
            let on = matches!((r, col), (1, 1) | (0, 1) | (1, 0) | (1, 2) | (2, 1));
            let color = if on { rgba8(255, 255, 255, 240) } else { rgba8(255, 255, 255, 90) };
            fill_round_rect(pm, cx, cy, cs, cs, cs * 0.18, color);
        }
    }
}

fn draw_ollama(pm: &mut Pixmap) {
    let (x, y, s, _r) = draw_squircle_base(pm, [0x60,0x67,0x6f,0xff], [0x2a,0x2e,0x36,0xff]);
    // Llama-ish silhouette — body + head + neck. Stylised silhouette using
    // rounded rects.
    let cx = x + s * 0.5;
    let body_y = y + s * 0.50;
    // Body
    fill_round_rect(pm, cx - s*0.22, body_y, s*0.44, s*0.28, s*0.06,
                    rgba8(255, 255, 255, 235));
    // Neck
    fill_round_rect(pm, cx + s*0.04, body_y - s*0.18, s*0.10, s*0.22, s*0.04,
                    rgba8(255, 255, 255, 235));
    // Head
    fill_round_rect(pm, cx + s*0.00, body_y - s*0.30, s*0.18, s*0.14, s*0.04,
                    rgba8(255, 255, 255, 235));
    // Ear
    fill_round_rect(pm, cx + s*0.05, body_y - s*0.36, s*0.04, s*0.10, s*0.02,
                    rgba8(255, 255, 255, 235));
    // Legs — 4 short pillars
    for dx in [-0.18, -0.05, 0.08, 0.20] {
        fill_round_rect(pm, cx + dx * s, body_y + s*0.25,
                        s*0.06, s*0.10, s*0.02,
                        rgba8(255, 255, 255, 235));
    }
}

fn draw_mlflow(pm: &mut Pixmap) {
    let (x, y, s, _r) = draw_squircle_base(pm, [0x2e,0xc4,0xc0,0xff], [0x0b,0x6f,0x86,0xff]);
    // Stack of three layers — a layered cake suggesting model artifacts.
    let cx = x + s * 0.5;
    for (i, frac) in [0.55_f32, 0.65, 0.75].iter().enumerate() {
        let layer_w = s * frac;
        let layer_h = s * 0.12;
        let ly = y + s * 0.24 + (i as f32) * (layer_h + s * 0.04);
        fill_round_rect(pm, cx - layer_w / 2.0, ly, layer_w, layer_h, layer_h * 0.25,
                        rgba8(255, 255, 255, 240));
    }
}

fn draw_tensorboard(pm: &mut Pixmap) {
    let (x, y, s, _r) = draw_squircle_base(pm, [0xff,0x6b,0x4a,0xff], [0xb4,0x2a,0x14,0xff]);
    // Loss curve — descending sigmoid-ish polyline
    let pad = s * 0.16;
    let cx = x + pad;
    let cy = y + s - pad;
    let cw = s - pad * 2.0;
    let ch = s * 0.55;
    // Axes
    fill_round_rect(pm, cx, cy - ch, 4.0, ch, 2.0, rgba8(255, 255, 255, 180));
    fill_round_rect(pm, cx, cy, cw, 4.0, 2.0, rgba8(255, 255, 255, 180));
    // Curve
    let mut pb = PathBuilder::new();
    let pts = 24;
    for i in 0..pts {
        let t = i as f32 / (pts - 1) as f32;
        let xx = cx + t * cw;
        let yy = cy - ch * ((-3.0 * t).exp() * 0.9 + 0.05);
        if i == 0 { pb.move_to(xx, yy); } else { pb.line_to(xx, yy); }
    }
    if let Some(path) = pb.finish() {
        let mut p = Paint::default();
        p.set_color(rgba8(255, 255, 255, 240));
        p.anti_alias = true;
        pm.stroke_path(&path, &p, &Stroke {
            width: 8.0, line_cap: LineCap::Round, line_join: LineJoin::Round,
            ..Default::default()
        }, Transform::identity(), None);
    }
}

// ============================================================================
// Registry + driver
// ============================================================================

struct IconSpec {
    filename: &'static str,
    paint:    fn(&mut Pixmap),
}

const ICONS: &[IconSpec] = &[
    IconSpec { filename: "aurum-finder",      paint: draw_finder      },
    IconSpec { filename: "aurum-spotlight",   paint: draw_spotlight   },
    IconSpec { filename: "aurum-settings",    paint: draw_settings    },
    IconSpec { filename: "aurum-mission",     paint: draw_mission     },
    IconSpec { filename: "aurum-browser",     paint: draw_browser     },
    IconSpec { filename: "aurum-terminal",    paint: draw_terminal    },
    IconSpec { filename: "aurum-editor",      paint: draw_editor      },
    IconSpec { filename: "aurum-jupyterlab",  paint: draw_jupyter     },
    IconSpec { filename: "aurum-marimo",      paint: draw_marimo      },
    IconSpec { filename: "aurum-ollama",      paint: draw_ollama      },
    IconSpec { filename: "aurum-mlflow",      paint: draw_mlflow      },
    IconSpec { filename: "aurum-tensorboard", paint: draw_tensorboard },
];

fn write_icon(out_dir: &Path, spec: &IconSpec) {
    let mut pm = Pixmap::new(FULL, FULL).expect("pixmap alloc");
    (spec.paint)(&mut pm);
    let path = out_dir.join(format!("{}.png", spec.filename));
    pm.save_png(&path).expect("save png");
    eprintln!("  ✓ {} ({}x{})", path.display(), FULL, FULL);
}

fn main() {
    let out_dir = std::env::args().nth(1)
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("./icons"));
    std::fs::create_dir_all(&out_dir).expect("mkdir out_dir");
    eprintln!("Generating {} icons → {}", ICONS.len(), out_dir.display());
    for spec in ICONS { write_icon(&out_dir, spec); }
    eprintln!("✓ done");
}
