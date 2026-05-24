// One module per wallpaper. Each exposes `pub fn render(w, h) -> Pixmap`
// returning a fully-composited canvas. The lib.rs dispatcher matches on
// `name: &str` and forwards to the appropriate module's render().

pub mod aurum_amber;
pub mod aurum_aqua;
pub mod aurum_obsidian;
pub mod aurum_dawn;
pub mod aurum_aurora;
pub mod aurum_void;

/// Canonical list of every wallpaper this crate ships. The CLI iterates
/// this when --name is not given, and the README is auto-generated from it.
/// Order is the order they appear in Settings → Wallpapers.
pub const ALL: &[&str] = &[
    "aurum-amber",
    "aurum-aqua",
    "aurum-obsidian",
    "aurum-dawn",
    "aurum-aurora",
    "aurum-void",
];
