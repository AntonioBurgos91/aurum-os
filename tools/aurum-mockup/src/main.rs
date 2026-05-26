// AurumOS hero mockup renderer.
//
// Produces a single 2880x1800 (Retina-ish) PNG that shows what the AurumOS
// desktop is supposed to look like once fully polished — a macOS Sequoia Dark
// clone tuned for deep-learning workstations.
//
// Layers, back-to-front in the painter's algorithm:
//   1. Sequoia-style abstract dark wallpaper (gradient sky + glow + hills)
//   2. Floating Finder-style window (rounded glass panel with three columns)
//   3. Centered Spotlight overlay (glass panel + query + results)
//   4. Bottom-center dock (rounded glass shelf with magnified row + GPU badge)
//   5. Top menubar (translucent 28-pt strip with Apple-style left + DL applets)
//   6. A floating notification card in the top-right
//
// All drawing is tiny-skia paths into a single Pixmap. Fonts come from the
// system DejaVuSans family which is always present on Linux build images.

use aurum_render::*;
use fontdue::Font; // re-used in inline type annotations below
use std::path::PathBuf;
use tiny_skia::*;

// ---------- Output geometry ----------
const W: u32 = 2880;
const H: u32 = 1800;

// ---------- Palette (sampled from macOS Sequoia Dark + AurumOS Theme.qml) ----
const SKY_TOP: Rgba = [0x05, 0x0a, 0x1d, 0xff];
const SKY_BOT: Rgba = [0x14, 0x18, 0x33, 0xff];
const HILL_FAR: Rgba = [0x10, 0x18, 0x33, 0xff];
const HILL_NEAR: Rgba = [0x06, 0x0c, 0x1c, 0xff];
const ACCENT: Rgba = [0x55, 0xaa, 0xff, 0xff];
const BORDER: Rgba = [0x3c, 0x3c, 0x42, 0xff];
const TEXT_PRI: Rgba = [0xfa, 0xfa, 0xfa, 0xff];
const TEXT_SEC: Rgba = [0x95, 0x95, 0x9c, 0xff];
const TEXT_DIM: Rgba = [0x70, 0x70, 0x76, 0xff];
const SUCCESS: Rgba = [0x32, 0xd6, 0x5d, 0xff];
const WARNING: Rgba = [0xff, 0xa4, 0x12, 0xff];

// ============================================================================
// Scene draws
// ============================================================================

/// Sequoia-style abstract dark wallpaper.
fn draw_wallpaper(pm: &mut Pixmap) {
    vertical_gradient(pm, 0.0, 0.0, W as f32, H as f32, c(SKY_TOP), c(SKY_BOT));

    // Distant moonrise glow behind the hills, off-centre right.
    let glow_cx = W as f32 * 0.72;
    let glow_cy = H as f32 * 0.36;
    for i in 0..40 {
        let r = 40.0 + i as f32 * 22.0;
        let a = (24u32.saturating_sub((i / 2) as u32)) as u8;
        fill_round_rect(
            pm,
            glow_cx - r,
            glow_cy - r,
            r * 2.0,
            r * 2.0,
            r,
            rgba8(255, 244, 220, a),
        );
    }

    // Subtle starfield above the hill line — pseudo-random points.
    let mut seed: u64 = 0xC0FFEE_BABE;
    for _ in 0..300 {
        seed ^= seed << 13;
        seed ^= seed >> 7;
        seed ^= seed << 17;
        let x = (seed % W as u64) as f32;
        let y = ((seed >> 16) % (H as u64 * 6 / 10)) as f32;
        let brightness = 160 + (seed % 80) as u8;
        let r = if seed % 23 == 0 { 2.0 } else { 1.0 };
        fill_round_rect(
            pm,
            x,
            y,
            r,
            r,
            r * 0.5,
            rgba8(
                brightness,
                brightness,
                (brightness as u32 + 30).min(255) as u8,
                220,
            ),
        );
    }

    // Stacked silhouette ridges (quadratic-bezier rolling hills).
    let draw_hill = |pm: &mut Pixmap, base_y: f32, amp: f32, color: Color| {
        let mut pb = PathBuilder::new();
        pb.move_to(0.0, H as f32);
        pb.line_to(0.0, base_y + amp);
        let segments = 10;
        for i in 0..segments {
            let x0 = (i as f32) * (W as f32 / segments as f32);
            let x1 = ((i + 1) as f32) * (W as f32 / segments as f32);
            let cx = (x0 + x1) * 0.5;
            let cy = base_y + amp * if i % 2 == 0 { -1.0 } else { 0.6 };
            pb.quad_to(cx, cy, x1, base_y + amp);
        }
        pb.line_to(W as f32, H as f32);
        pb.close();
        if let Some(path) = pb.finish() {
            let mut paint = Paint::default();
            paint.set_color(color);
            paint.anti_alias = true;
            pm.fill_path(
                &path,
                &paint,
                FillRule::Winding,
                Transform::identity(),
                None,
            );
        }
    };
    draw_hill(pm, H as f32 * 0.78, 80.0, c(HILL_FAR));
    draw_hill(pm, H as f32 * 0.88, 60.0, c(HILL_NEAR));

    // Vignette around the edges.
    radial_vignette(
        pm,
        W,
        H,
        W as f32 / 2.0,
        H as f32 / 2.0,
        H as f32 * 0.30,
        H as f32 * 1.05,
        rgba8(0, 0, 0, 0),
        rgba8(0, 0, 0, 130),
    );
}

/// Top menubar: translucent 56-pt strip (28 logical × 2 DPI).
fn draw_menubar(pm: &mut Pixmap, fonts: &FontStack) {
    let bar_h = 56.0;
    // Translucent dark strip.
    let mut paint = Paint::default();
    paint.set_color(rgba8(8, 8, 12, 200));
    paint.anti_alias = true;
    pm.fill_rect(
        rect(0.0, 0.0, W as f32, bar_h),
        &paint,
        Transform::identity(),
        None,
    );

    // Bottom hairline.
    let mut hair = Paint::default();
    hair.set_color(rgba8(255, 255, 255, 25));
    pm.fill_rect(
        rect(0.0, bar_h - 1.0, W as f32, 1.0),
        &hair,
        Transform::identity(),
        None,
    );

    // --- Left: Aurum diamond + app name + menu items ---
    let mut pen = 36.0;
    let mark_cx = pen + 8.0;
    let mark_cy = bar_h / 2.0;
    let mut diamond = PathBuilder::new();
    diamond.move_to(mark_cx, mark_cy - 11.0);
    diamond.line_to(mark_cx + 9.0, mark_cy);
    diamond.line_to(mark_cx, mark_cy + 11.0);
    diamond.line_to(mark_cx - 9.0, mark_cy);
    diamond.close();
    if let Some(d) = diamond.finish() {
        let mut p = Paint::default();
        p.set_color(c(TEXT_PRI));
        p.anti_alias = true;
        pm.fill_path(&d, &p, FillRule::Winding, Transform::identity(), None);
    }
    pen += 38.0;

    let app_name = "Finder";
    draw_text(
        pm,
        &fonts.sans_bold,
        app_name,
        pen,
        bar_h / 2.0 + 9.0,
        26.0,
        c(TEXT_PRI),
    );
    pen += text_width(&fonts.sans_bold, app_name, 26.0) + 30.0;

    for label in ["File", "Edit", "View", "Go", "Window", "Help"] {
        draw_text(
            pm,
            &fonts.sans,
            label,
            pen,
            bar_h / 2.0 + 9.0,
            24.0,
            c(TEXT_PRI),
        );
        pen += text_width(&fonts.sans, label, 24.0) + 28.0;
    }

    // --- Right: DL telemetry + clock ---
    struct Stat<'a> {
        label: &'a str,
        value: &'a str,
        tone: Rgba,
    }
    let stats = [
        Stat {
            label: "GPU",
            value: "78%",
            tone: WARNING,
        },
        Stat {
            label: "VRAM",
            value: "21.6/24G",
            tone: TEXT_PRI,
        },
        Stat {
            label: "°C",
            value: "72",
            tone: WARNING,
        },
        Stat {
            label: "NET",
            value: "1.2 GB/s",
            tone: TEXT_PRI,
        },
        Stat {
            label: "JOBS",
            value: "3",
            tone: ACCENT,
        },
    ];

    let stat_size = 24.0;
    let label_size = 18.0;
    let stat_gap = 22.0;
    let clock = "Tue 26 May  10:42";

    let mut total = 0.0;
    for s in &stats {
        total += text_width(&fonts.sans_bold, s.label, label_size)
            + 8.0
            + text_width(&fonts.sans, s.value, stat_size)
            + stat_gap;
    }
    total += text_width(&fonts.sans, clock, stat_size) + 40.0;

    let mut rx = W as f32 - total - 36.0;
    for s in &stats {
        draw_text(
            pm,
            &fonts.sans_bold,
            s.label,
            rx,
            bar_h / 2.0 + 7.0,
            label_size,
            c(TEXT_SEC),
        );
        rx += text_width(&fonts.sans_bold, s.label, label_size) + 8.0;
        draw_text(
            pm,
            &fonts.sans,
            s.value,
            rx,
            bar_h / 2.0 + 9.0,
            stat_size,
            c(s.tone),
        );
        rx += text_width(&fonts.sans, s.value, stat_size) + stat_gap;
    }
    draw_text(
        pm,
        &fonts.sans,
        clock,
        rx + 16.0,
        bar_h / 2.0 + 9.0,
        stat_size,
        c(TEXT_PRI),
    );
}

/// Bottom-center dock with magnified icons + GPU badge.
fn draw_dock(pm: &mut Pixmap, fonts: &FontStack) {
    let icons = ["▶", "F", "C", "S", "P", "J", "★", "⚙", "📁"];
    let n = icons.len() as f32;
    let icon_size = 100.0;
    let icon_gap = 18.0;

    let peak = 1.6;
    let sigma_idx = 1.5;
    let scales: Vec<f32> = (0..icons.len())
        .map(|i| {
            let d = i as f32 - 3.5;
            1.0 + (peak - 1.0) * (-(d * d) / (sigma_idx * sigma_idx)).exp()
        })
        .collect();

    let total_w: f32 = scales.iter().map(|s| s * icon_size).sum::<f32>() + (n - 1.0) * icon_gap;
    let badge_w = 230.0;
    let divider_w = 1.0;
    let shelf_pad_x = 36.0;
    let shelf_w = total_w + 24.0 + divider_w + 16.0 + badge_w + shelf_pad_x * 2.0;
    let shelf_h = icon_size * peak + 32.0;
    let shelf_x = (W as f32 - shelf_w) / 2.0;
    let shelf_y = H as f32 - shelf_h - 36.0;

    drop_shadow(pm, shelf_x, shelf_y, shelf_w, shelf_h, 26.0, 80);
    fill_round_rect(
        pm,
        shelf_x,
        shelf_y,
        shelf_w,
        shelf_h,
        26.0,
        rgba8(28, 28, 32, 230),
    );
    stroke_round_rect(
        pm,
        shelf_x,
        shelf_y,
        shelf_w,
        shelf_h,
        26.0,
        rgba8(255, 255, 255, 38),
        1.0,
    );
    let mut highlight = Paint::default();
    highlight.set_color(rgba8(255, 255, 255, 14));
    pm.fill_rect(
        rect(shelf_x + 18.0, shelf_y + 6.0, shelf_w - 36.0, 14.0),
        &highlight,
        Transform::identity(),
        None,
    );

    let palette = [
        rgba8(0x4d, 0x99, 0xff, 0xff),
        rgba8(0x32, 0xd6, 0x5d, 0xff),
        rgba8(0xff, 0xb1, 0x3a, 0xff),
        rgba8(0xff, 0x55, 0x8f, 0xff),
        rgba8(0x6e, 0xc1, 0x97, 0xff),
        rgba8(0xff, 0x9f, 0x44, 0xff),
        rgba8(0xb0, 0x83, 0xff, 0xff),
        rgba8(0x95, 0x95, 0x9c, 0xff),
        rgba8(0x4d, 0xb8, 0xff, 0xff),
    ];

    let mut x = shelf_x + shelf_pad_x;
    let bottom = shelf_y + shelf_h - 22.0;
    for (i, ch) in icons.iter().enumerate() {
        let sz = icon_size * scales[i];
        let iy = bottom - sz;
        let r = sz * 0.22;
        fill_round_rect(pm, x, iy, sz, sz, r, palette[i]);
        let mut hp = Paint::default();
        hp.set_color(rgba8(255, 255, 255, 50));
        pm.fill_rect(
            rect(x + sz * 0.10, iy + sz * 0.08, sz * 0.80, sz * 0.18),
            &hp,
            Transform::identity(),
            None,
        );
        let glyph_size = sz * 0.55;
        let gw = text_width(&fonts.sans_bold, ch, glyph_size);
        draw_text(
            pm,
            &fonts.sans_bold,
            ch,
            x + (sz - gw) / 2.0,
            iy + sz * 0.7,
            glyph_size,
            rgba8(0, 0, 0, 220),
        );
        if matches!(i, 0 | 3 | 4) {
            let dx = x + sz / 2.0 - 3.0;
            let dy = bottom + 8.0;
            fill_round_rect(pm, dx, dy, 6.0, 6.0, 3.0, c(TEXT_PRI));
        }
        x += sz + icon_gap;
    }

    // Divider.
    let div_x = x + 6.0;
    let mut dp = Paint::default();
    dp.set_color(rgba8(255, 255, 255, 50));
    pm.fill_rect(
        rect(div_x, shelf_y + 22.0, divider_w, shelf_h - 44.0),
        &dp,
        Transform::identity(),
        None,
    );

    // GPU badge.
    let bx = div_x + 18.0;
    let by = shelf_y + 24.0;
    let bw = badge_w - 12.0;
    let bh = shelf_h - 44.0;
    fill_round_rect(pm, bx, by, bw, bh, 18.0, rgba8(40, 40, 46, 240));
    stroke_round_rect(pm, bx, by, bw, bh, 18.0, c(BORDER), 1.0);
    draw_text(
        pm,
        &fonts.sans_bold,
        "GPU",
        bx + 22.0,
        by + 38.0,
        26.0,
        c(TEXT_SEC),
    );
    draw_text(
        pm,
        &fonts.sans_bold,
        "78%",
        bx + 22.0,
        by + 96.0,
        56.0,
        c(WARNING),
    );

    // Spark line.
    let mut sp = PathBuilder::new();
    let sx = bx + 22.0;
    let sy = by + bh - 20.0;
    let pts = [
        0.25f32, 0.35, 0.30, 0.45, 0.55, 0.40, 0.60, 0.78, 0.65, 0.72, 0.78,
    ];
    sp.move_to(sx, sy - pts[0] * 60.0);
    for (i, v) in pts.iter().enumerate().skip(1) {
        let sx2 = sx + i as f32 * 16.0;
        sp.line_to(sx2, sy - v * 60.0);
    }
    if let Some(path) = sp.finish() {
        let mut sp_paint = Paint::default();
        sp_paint.set_color(c(ACCENT));
        sp_paint.anti_alias = true;
        pm.stroke_path(
            &path,
            &sp_paint,
            &Stroke {
                width: 3.0,
                line_cap: LineCap::Round,
                line_join: LineJoin::Round,
                ..Default::default()
            },
            Transform::identity(),
            None,
        );
    }
}

/// Three-pane Finder window in the middle-left of the canvas.
fn draw_finder(pm: &mut Pixmap, fonts: &FontStack) {
    let w = 1700.0;
    let h = 1080.0;
    let x = 140.0;
    let y = 230.0;
    let r = 22.0;

    drop_shadow(pm, x, y, w, h, r, 110);
    fill_round_rect(pm, x, y, w, h, r, rgba8(24, 24, 28, 248));
    stroke_round_rect(pm, x, y, w, h, r, rgba8(255, 255, 255, 30), 1.0);

    // Title bar.
    let tb_h = 64.0;
    fill_round_rect(pm, x, y, w, tb_h, r, rgba8(36, 36, 40, 240));
    // Patch over the bottom-rounded part of the title-bar rect so it doesn't
    // create a double-curve at the join with the body.
    fill_round_rect(pm, x, y + tb_h - r, w, r, 0.0, rgba8(36, 36, 40, 240));
    let mut hairp = Paint::default();
    hairp.set_color(rgba8(255, 255, 255, 20));
    pm.fill_rect(
        rect(x, y + tb_h - 1.0, w, 1.0),
        &hairp,
        Transform::identity(),
        None,
    );

    // Traffic lights.
    let tl_y = y + tb_h / 2.0 - 9.0;
    let mut light = |pm: &mut Pixmap, cx: f32, color: Color| {
        let r = 9.0;
        fill_round_rect(pm, cx - r, tl_y, r * 2.0, r * 2.0, r, color);
    };
    light(pm, x + 30.0, rgba8(255, 95, 87, 255));
    light(pm, x + 58.0, rgba8(255, 189, 46, 255));
    light(pm, x + 86.0, rgba8(40, 201, 64, 255));

    // Toolbar buttons + breadcrumb + search.
    draw_text(
        pm,
        &fonts.sans_bold,
        "<",
        x + 130.0,
        y + tb_h / 2.0 + 10.0,
        26.0,
        c(TEXT_PRI),
    );
    draw_text(
        pm,
        &fonts.sans_bold,
        ">",
        x + 170.0,
        y + tb_h / 2.0 + 10.0,
        26.0,
        c(TEXT_DIM),
    );
    draw_text(
        pm,
        &fonts.sans_bold,
        "/home/abb/projects/llm-finetune/",
        x + 230.0,
        y + tb_h / 2.0 + 8.0,
        22.0,
        c(TEXT_PRI),
    );

    let sf_w = 320.0;
    let sf_x = x + w - sf_w - 24.0;
    fill_round_rect(
        pm,
        sf_x,
        y + 16.0,
        sf_w,
        tb_h - 32.0,
        8.0,
        rgba8(48, 48, 54, 230),
    );
    draw_text(
        pm,
        &fonts.sans,
        "Search...",
        sf_x + 14.0,
        y + tb_h / 2.0 + 7.0,
        20.0,
        c(TEXT_DIM),
    );

    // --- Three columns: sidebar / file list / preview ---
    let body_y = y + tb_h;
    let body_h = h - tb_h;
    let side_w = 320.0;
    let prev_w = 520.0;
    let list_w = w - side_w - prev_w;

    // Sidebar.
    let mut sb_paint = Paint::default();
    sb_paint.set_color(rgba8(28, 28, 32, 230));
    pm.fill_rect(
        rect(x, body_y, side_w, body_h),
        &sb_paint,
        Transform::identity(),
        None,
    );

    draw_text(
        pm,
        &fonts.sans_bold,
        "FAVORITES",
        x + 26.0,
        body_y + 40.0,
        16.0,
        c(TEXT_SEC),
    );
    let sb_items = [
        ("Recents", false),
        ("Home", false),
        ("Projects", true),
        ("Downloads", false),
        ("Notebooks", false),
        ("Models", false),
        ("Datasets", false),
    ];
    let mut iy = body_y + 80.0;
    for (txt, selected) in &sb_items {
        if *selected {
            fill_round_rect(
                pm,
                x + 14.0,
                iy - 22.0,
                side_w - 28.0,
                32.0,
                8.0,
                rgba8(76, 134, 215, 220),
            );
        }
        // Tiny chip in front of label.
        let chip_col = if *selected {
            rgba8(255, 255, 255, 220)
        } else {
            rgba8(160, 160, 170, 200)
        };
        fill_round_rect(pm, x + 28.0, iy - 16.0, 18.0, 18.0, 4.0, chip_col);
        draw_text(pm, &fonts.sans, txt, x + 56.0, iy, 22.0, c(TEXT_PRI));
        iy += 44.0;
    }
    draw_text(
        pm,
        &fonts.sans_bold,
        "ML PROJECTS",
        x + 26.0,
        body_y + 460.0,
        16.0,
        c(TEXT_SEC),
    );
    let mlp = [
        "llm-finetune",
        "vision-transformer",
        "timeseries-mlp",
        "diffusion-toy",
    ];
    iy = body_y + 500.0;
    for txt in &mlp {
        fill_round_rect(
            pm,
            x + 28.0,
            iy - 16.0,
            18.0,
            18.0,
            4.0,
            rgba8(160, 160, 170, 200),
        );
        draw_text(pm, &fonts.sans, txt, x + 56.0, iy, 22.0, c(TEXT_PRI));
        iy += 40.0;
    }

    let mut div = Paint::default();
    div.set_color(rgba8(255, 255, 255, 18));
    pm.fill_rect(
        rect(x + side_w, body_y, 1.0, body_h),
        &div,
        Transform::identity(),
        None,
    );

    // File list header.
    let lx = x + side_w;
    draw_text(
        pm,
        &fonts.sans_bold,
        "Name",
        lx + 24.0,
        body_y + 40.0,
        18.0,
        c(TEXT_SEC),
    );
    draw_text(
        pm,
        &fonts.sans_bold,
        "Modified",
        lx + list_w - 360.0,
        body_y + 40.0,
        18.0,
        c(TEXT_SEC),
    );
    draw_text(
        pm,
        &fonts.sans_bold,
        "Size",
        lx + list_w - 110.0,
        body_y + 40.0,
        18.0,
        c(TEXT_SEC),
    );
    pm.fill_rect(
        rect(lx + 14.0, body_y + 56.0, list_w - 28.0, 1.0),
        &div,
        Transform::identity(),
        None,
    );

    struct Row<'a> {
        kind: char,
        name: &'a str,
        modified: &'a str,
        size: &'a str,
        selected: bool,
    }
    let rows = [
        Row {
            kind: 'N',
            name: "01_data_exploration.ipynb",
            modified: "Today  09:14",
            size: "412 KB",
            selected: false,
        },
        Row {
            kind: 'N',
            name: "02_tokenizer_choice.ipynb",
            modified: "Today  09:51",
            size: "188 KB",
            selected: false,
        },
        Row {
            kind: 'N',
            name: "03_finetune_lora.ipynb",
            modified: "Today  10:02",
            size: "612 KB",
            selected: true,
        },
        Row {
            kind: 'M',
            name: "checkpoint-step-2400.safetensors",
            modified: "Today  10:14",
            size: "13.2 GB",
            selected: false,
        },
        Row {
            kind: 'M',
            name: "checkpoint-step-2000.safetensors",
            modified: "Today  09:38",
            size: "13.2 GB",
            selected: false,
        },
        Row {
            kind: 'D',
            name: "train_split.parquet",
            modified: "Yesterday 16:22",
            size: "1.8 GB",
            selected: false,
        },
        Row {
            kind: 'D',
            name: "val_split.parquet",
            modified: "Yesterday 16:22",
            size: "204 MB",
            selected: false,
        },
        Row {
            kind: 'C',
            name: "config.yaml",
            modified: "Mon  21:08",
            size: "2.4 KB",
            selected: false,
        },
        Row {
            kind: 'P',
            name: "train.py",
            modified: "Mon  21:08",
            size: "8.7 KB",
            selected: false,
        },
        Row {
            kind: 'P',
            name: "evaluate.py",
            modified: "Mon  21:08",
            size: "4.3 KB",
            selected: false,
        },
        Row {
            kind: 'C',
            name: "requirements.txt",
            modified: "Mon  21:08",
            size: "612 B",
            selected: false,
        },
        Row {
            kind: 'F',
            name: "logs/",
            modified: "Today  10:14",
            size: "—",
            selected: false,
        },
    ];
    let mut ry = body_y + 90.0;
    for r in &rows {
        if r.selected {
            fill_round_rect(
                pm,
                lx + 12.0,
                ry - 24.0,
                list_w - 24.0,
                38.0,
                8.0,
                rgba8(76, 134, 215, 220),
            );
        }
        // Type chip — colour-coded by file kind.
        let (col, lbl) = match r.kind {
            'N' => (rgba8(0xff, 0xa4, 0x12, 255), "NB"),
            'M' => (rgba8(0xb0, 0x83, 0xff, 255), "M "),
            'D' => (rgba8(0x32, 0xd6, 0x5d, 255), "DS"),
            'C' => (rgba8(0x95, 0x95, 0x9c, 255), "C "),
            'P' => (rgba8(0x55, 0xaa, 0xff, 255), "PY"),
            'F' => (rgba8(0xff, 0xb1, 0x3a, 255), "F "),
            _ => (rgba8(0x70, 0x70, 0x76, 255), "? "),
        };
        fill_round_rect(pm, lx + 22.0, ry - 18.0, 30.0, 22.0, 5.0, col);
        draw_text(
            pm,
            &fonts.sans_bold,
            lbl,
            lx + 27.0,
            ry - 1.0,
            14.0,
            rgba8(0, 0, 0, 220),
        );
        draw_text(pm, &fonts.sans, r.name, lx + 62.0, ry, 22.0, c(TEXT_PRI));
        let c2 = if r.selected { c(TEXT_PRI) } else { c(TEXT_SEC) };
        draw_text(
            pm,
            &fonts.sans,
            r.modified,
            lx + list_w - 360.0,
            ry,
            21.0,
            c2,
        );
        draw_text(pm, &fonts.sans, r.size, lx + list_w - 110.0, ry, 21.0, c2);
        ry += 46.0;
    }

    pm.fill_rect(
        rect(x + side_w + list_w, body_y, 1.0, body_h),
        &div,
        Transform::identity(),
        None,
    );

    // Preview pane.
    let px = x + side_w + list_w;
    draw_text(
        pm,
        &fonts.sans_bold,
        "QUICK LOOK",
        px + 24.0,
        body_y + 22.0,
        16.0,
        c(TEXT_SEC),
    );

    fill_round_rect(
        pm,
        px + 24.0,
        body_y + 40.0,
        prev_w - 48.0,
        240.0,
        14.0,
        rgba8(38, 38, 44, 240),
    );
    draw_text(
        pm,
        &fonts.sans_bold,
        "03_finetune_lora.ipynb",
        px + 38.0,
        body_y + 76.0,
        20.0,
        c(TEXT_PRI),
    );
    draw_text(
        pm,
        &fonts.sans,
        "Jupyter  ·  28 cells  ·  Python 3.11",
        px + 38.0,
        body_y + 104.0,
        18.0,
        c(TEXT_SEC),
    );
    draw_text(
        pm,
        &fonts.sans_bold,
        "In [12]:",
        px + 38.0,
        body_y + 148.0,
        18.0,
        c(ACCENT),
    );
    draw_text(
        pm,
        &fonts.sans,
        "trainer = SFTTrainer(",
        px + 130.0,
        body_y + 148.0,
        18.0,
        c(TEXT_PRI),
    );
    draw_text(
        pm,
        &fonts.sans,
        "    model=model,",
        px + 130.0,
        body_y + 172.0,
        18.0,
        c(TEXT_PRI),
    );
    draw_text(
        pm,
        &fonts.sans,
        "    args=TrainingArguments(...),",
        px + 130.0,
        body_y + 196.0,
        18.0,
        c(TEXT_PRI),
    );
    draw_text(
        pm,
        &fonts.sans,
        ")",
        px + 130.0,
        body_y + 220.0,
        18.0,
        c(TEXT_PRI),
    );
    draw_text(
        pm,
        &fonts.sans,
        "trainer.train()",
        px + 130.0,
        body_y + 244.0,
        18.0,
        c(TEXT_PRI),
    );

    // Metadata box.
    let mb_y = body_y + 310.0;
    fill_round_rect(
        pm,
        px + 24.0,
        mb_y,
        prev_w - 48.0,
        200.0,
        14.0,
        rgba8(38, 38, 44, 240),
    );
    let labels = [
        ("Size", "612 KB"),
        ("Created", "Today  09:48"),
        ("Mods", "Today  10:02"),
        ("Kernel", "python3.11"),
        ("Outputs", "12 cells, 4.3 MB"),
    ];
    let mut ly = mb_y + 36.0;
    for (k, v) in labels {
        draw_text(pm, &fonts.sans, k, px + 40.0, ly, 18.0, c(TEXT_SEC));
        draw_text(pm, &fonts.sans, v, px + 200.0, ly, 18.0, c(TEXT_PRI));
        ly += 32.0;
    }

    // Live training mini-chart.
    let cb_y = body_y + 530.0;
    fill_round_rect(
        pm,
        px + 24.0,
        cb_y,
        prev_w - 48.0,
        280.0,
        14.0,
        rgba8(38, 38, 44, 240),
    );
    draw_text(
        pm,
        &fonts.sans_bold,
        "LIVE TRAINING",
        px + 40.0,
        cb_y + 30.0,
        16.0,
        c(TEXT_SEC),
    );
    draw_text(
        pm,
        &fonts.sans_bold,
        "loss",
        px + 40.0,
        cb_y + 64.0,
        22.0,
        c(TEXT_PRI),
    );
    draw_text(
        pm,
        &fonts.sans,
        "1.342 -> 0.418",
        px + 40.0,
        cb_y + 92.0,
        20.0,
        c(SUCCESS),
    );

    let mut chart = PathBuilder::new();
    let cx = px + 40.0;
    let cy = cb_y + 240.0;
    let cw = prev_w - 116.0;
    let ch = 120.0;
    let mut frame_paint = Paint::default();
    frame_paint.set_color(rgba8(80, 80, 86, 200));
    pm.fill_rect(
        rect(cx, cy - ch, cw, 1.0),
        &frame_paint,
        Transform::identity(),
        None,
    );
    pm.fill_rect(
        rect(cx, cy, cw, 1.0),
        &frame_paint,
        Transform::identity(),
        None,
    );
    let pts: Vec<f32> = (0..60)
        .map(|i| {
            let t = i as f32 / 59.0;
            let base = (-3.5 * t).exp() * 0.9 + 0.1;
            let noise = ((i as f32 * 0.7).sin() * 0.04).abs();
            base + noise
        })
        .collect();
    chart.move_to(cx, cy - pts[0] * ch);
    for (i, v) in pts.iter().enumerate().skip(1) {
        let xx = cx + (i as f32) / 59.0 * cw;
        chart.line_to(xx, cy - v * ch);
    }
    if let Some(chart_path) = chart.finish() {
        let mut cp = Paint::default();
        cp.set_color(c(ACCENT));
        cp.anti_alias = true;
        pm.stroke_path(
            &chart_path,
            &cp,
            &Stroke {
                width: 2.5,
                line_cap: LineCap::Round,
                line_join: LineJoin::Round,
                ..Default::default()
            },
            Transform::identity(),
            None,
        );
    }
}

/// Spotlight overlay near the top-centre.
fn draw_spotlight(pm: &mut Pixmap, fonts: &FontStack) {
    let w = 1080.0;
    let h = 560.0;
    let x = (W as f32 - w) / 2.0;
    let y = 320.0;
    let r = 26.0;

    drop_shadow(pm, x, y, w, h, r, 140);
    fill_round_rect(pm, x, y, w, h, r, rgba8(28, 28, 32, 248));
    stroke_round_rect(pm, x, y, w, h, r, rgba8(255, 255, 255, 50), 1.0);
    let mut hl = Paint::default();
    hl.set_color(rgba8(255, 255, 255, 18));
    pm.fill_rect(
        rect(x + 20.0, y + 8.0, w - 40.0, 14.0),
        &hl,
        Transform::identity(),
        None,
    );

    let inp_x = x + 36.0;
    let inp_y = y + 36.0;
    let inp_w = w - 72.0;
    let inp_h = 88.0;
    fill_round_rect(pm, inp_x, inp_y, inp_w, inp_h, 16.0, rgba8(40, 40, 46, 220));
    draw_text(
        pm,
        &fonts.sans_bold,
        "Q",
        inp_x + 28.0,
        inp_y + inp_h / 2.0 + 16.0,
        38.0,
        c(TEXT_DIM),
    );
    draw_text(
        pm,
        &fonts.sans,
        "stable diffusion xl",
        inp_x + 88.0,
        inp_y + inp_h / 2.0 + 17.0,
        42.0,
        c(TEXT_PRI),
    );
    let caret_x = inp_x + 88.0 + text_width(&fonts.sans, "stable diffusion xl", 42.0) + 4.0;
    fill_round_rect(pm, caret_x, inp_y + 22.0, 2.0, inp_h - 44.0, 1.0, c(ACCENT));

    // Result groups.
    struct Group<'a> {
        title: &'a str,
        rows: &'a [(&'a str, &'a str)],
        selected_idx: Option<usize>,
    }
    let groups = [
        Group {
            title: "HUGGING FACE",
            rows: &[
                (
                    "stabilityai/stable-diffusion-xl-base-1.0",
                    "Text-to-Image  ·  9.4k stars",
                ),
                ("stabilityai/sdxl-turbo", "Real-time text-to-image  ·  2.1k"),
            ],
            selected_idx: Some(0),
        },
        Group {
            title: "MODELS ON DISK",
            rows: &[("sdxl-base-1.0.safetensors", "6.94 GB  ·  ~/models/sdxl")],
            selected_idx: None,
        },
        Group {
            title: "ARXIV",
            rows: &[(
                "SDXL: Improving Latent Diffusion Models for High-Resolution Synthesis",
                "2307.01952  ·  Podell et al.",
            )],
            selected_idx: None,
        },
    ];

    let mut ry = inp_y + inp_h + 36.0;
    for g in &groups {
        draw_text(
            pm,
            &fonts.sans_bold,
            g.title,
            x + 50.0,
            ry,
            16.0,
            c(TEXT_SEC),
        );
        ry += 32.0;
        for (j, (a, b)) in g.rows.iter().enumerate() {
            let selected = g.selected_idx == Some(j);
            if selected {
                fill_round_rect(
                    pm,
                    x + 28.0,
                    ry - 24.0,
                    w - 56.0,
                    60.0,
                    10.0,
                    rgba8(76, 134, 215, 230),
                );
            }
            fill_round_rect(
                pm,
                x + 44.0,
                ry - 18.0,
                44.0,
                44.0,
                10.0,
                rgba8(55, 55, 62, 240),
            );
            draw_text(
                pm,
                &fonts.sans_bold,
                "H",
                x + 58.0,
                ry + 14.0,
                30.0,
                c(ACCENT),
            );
            draw_text(pm, &fonts.sans, a, x + 108.0, ry + 4.0, 24.0, c(TEXT_PRI));
            draw_text(pm, &fonts.sans, b, x + 108.0, ry + 30.0, 18.0, c(TEXT_SEC));
            ry += 64.0;
        }
        ry += 14.0;
    }
}

/// Notification card top-right.
fn draw_notification(pm: &mut Pixmap, fonts: &FontStack) {
    let w = 440.0;
    let h = 110.0;
    let x = W as f32 - w - 40.0;
    let y = 80.0;
    drop_shadow(pm, x, y, w, h, 18.0, 100);
    fill_round_rect(pm, x, y, w, h, 18.0, rgba8(32, 32, 36, 248));
    stroke_round_rect(pm, x, y, w, h, 18.0, rgba8(255, 255, 255, 35), 1.0);
    fill_round_rect(pm, x + 18.0, y + 18.0, 60.0, 60.0, 12.0, c(SUCCESS));
    draw_text(
        pm,
        &fonts.sans_bold,
        "✓",
        x + 36.0,
        y + 60.0,
        38.0,
        rgba8(0, 0, 0, 220),
    );
    draw_text(
        pm,
        &fonts.sans_bold,
        "Training complete",
        x + 96.0,
        y + 42.0,
        22.0,
        c(TEXT_PRI),
    );
    draw_text(
        pm,
        &fonts.sans,
        "llm-finetune  ·  step 3000  ·  loss 0.39",
        x + 96.0,
        y + 72.0,
        18.0,
        c(TEXT_SEC),
    );
    draw_text(
        pm,
        &fonts.sans,
        "now",
        x + w - 56.0,
        y + 42.0,
        16.0,
        c(TEXT_DIM),
    );
}

fn main() {
    let mut pm = Pixmap::new(W, H).expect("pixmap alloc");
    let fonts = match load_fonts() {
        Ok(f) => f,
        Err(e) => {
            eprintln!("aurum-mockup: {e}");
            std::process::exit(1);
        }
    };

    // Back-to-front draws.
    draw_wallpaper(&mut pm);
    draw_finder(&mut pm, &fonts);
    draw_spotlight(&mut pm, &fonts);
    draw_dock(&mut pm, &fonts);
    draw_menubar(&mut pm, &fonts);
    draw_notification(&mut pm, &fonts);

    let out: PathBuf = std::env::args()
        .nth(1)
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("aurum-mockup.png"));
    pm.save_png(&out).expect("save png");
    eprintln!("✓ wrote {} ({}x{})", out.display(), W, H);
}
