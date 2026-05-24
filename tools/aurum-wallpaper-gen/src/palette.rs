//! Palette definitions for the six bundled Sequoia-style wallpapers.
//!
//! Each entry is a 3-stop linear gradient (top → middle → bottom) plus a
//! handful of style flags describing the "extras" overlaid on top of the
//! base gradient: light-leak corner, stars (for Night), aurora bands
//! (for Aurora), warm centre radial (for Sunset), and so on.
//!
//! The list is kept in the same order as the file numbering convention
//! used by the install script: `aurum-sequoia-1.png` == Aurum Dawn,
//! `aurum-sequoia-6.png` == Aurum Aurora.

use serde::Serialize;

/// One of the canonical hero treatments overlayed after the base gradient.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
pub enum HeroStyle {
    /// Single large soft radial in the upper-left corner.
    LeakTopLeft,
    /// Single large soft radial in the upper-right corner.
    LeakTopRight,
    /// Horizontal wave-banding (used for Coastal).
    WaveBands,
    /// Bright warm radial in the centre (used for Sunset).
    WarmCenter,
    /// Sparse white-dot starfield in the top half (used for Night).
    Starfield,
    /// Three to five sinusoidal horizontal bands at low alpha (Aurora).
    AuroraBands,
}

/// Self-contained description of a single wallpaper entry.
#[derive(Clone, Debug, Serialize)]
pub struct Theme {
    /// Filename-safe slug, e.g. `aurum-dawn`.
    pub id: &'static str,
    /// Human-readable title, e.g. `"Aurum Dawn"`.
    pub title: &'static str,
    /// File number — 1-based; drives `aurum-sequoia-{n}.png` naming.
    pub number: u32,
    /// 3 stops, each `#RRGGBB`, top to bottom.
    pub palette: [&'static str; 3],
    /// Which hero treatment to overlay on top of the base gradient.
    pub hero: HeroStyle,
}

/// The full bundled set. Index 0 = Aurum Dawn (default).
pub const THEMES: &[Theme] = &[
    Theme {
        id: "aurum-dawn",
        title: "Aurum Dawn",
        number: 1,
        palette: ["#FFB088", "#FF7D8E", "#9F5FFF"],
        hero: HeroStyle::LeakTopLeft,
    },
    Theme {
        id: "aurum-forest",
        title: "Aurum Forest",
        number: 2,
        palette: ["#8FBFA0", "#2D9B8E", "#0A2540"],
        hero: HeroStyle::LeakTopRight,
    },
    Theme {
        id: "aurum-coastal",
        title: "Aurum Coastal",
        number: 3,
        palette: ["#A4D8F7", "#3DA5D9", "#1B4965"],
        hero: HeroStyle::WaveBands,
    },
    Theme {
        id: "aurum-sunset",
        title: "Aurum Sunset",
        number: 4,
        palette: ["#FFB347", "#FF6B6B", "#9B59B6"],
        hero: HeroStyle::WarmCenter,
    },
    Theme {
        id: "aurum-night",
        title: "Aurum Night",
        number: 5,
        palette: ["#0F1729", "#1E2A5E", "#6B5B95"],
        hero: HeroStyle::Starfield,
    },
    Theme {
        id: "aurum-aurora",
        title: "Aurum Aurora",
        number: 6,
        palette: ["#0F4C5C", "#5FB8B2", "#E9C46A"],
        hero: HeroStyle::AuroraBands,
    },
];

/// Parse a `#RRGGBB` literal into `(r, g, b)` with each component 0..=255.
pub fn parse_hex(hex: &str) -> (u8, u8, u8) {
    let h = hex.trim_start_matches('#');
    assert!(h.len() == 6, "palette colour must be #RRGGBB");
    let r = u8::from_str_radix(&h[0..2], 16).expect("bad hex r");
    let g = u8::from_str_radix(&h[2..4], 16).expect("bad hex g");
    let b = u8::from_str_radix(&h[4..6], 16).expect("bad hex b");
    (r, g, b)
}
