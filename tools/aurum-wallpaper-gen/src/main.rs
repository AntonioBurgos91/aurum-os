//! aurum-wallpaper-gen — CLI (Wave 10 spec).
//!
//! Renders the six bundled Sequoia-style wallpapers at one or more
//! resolutions and emits a MANIFEST.json beside them so downstream tooling
//! (ISO builder, GTK schema, dconf override) can pick the right file by id.
//!
//! Usage:
//!     # Render everything at the two production resolutions and refresh the
//!     # manifest in-place.
//!     aurum-wallpaper-gen \
//!         --output-dir distro/seed/wallpapers/ \
//!         --resolutions 2560x1600,5120x3200
//!
//!     # Regenerate a single wallpaper (manifest still updated for that one).
//!     aurum-wallpaper-gen \
//!         --output-dir distro/seed/wallpapers/ \
//!         --only "Aurum Dawn"
//!
//! Default resolutions are the Apple-style "standard retina" 2560×1600 plus
//! the @2x retina 5120×3200, matching the file naming `aurum-sequoia-N.png`
//! and `aurum-sequoia-N@2x.png`.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::time::Instant;

use clap::Parser;
use serde::Serialize;

use aurum_wallpaper_gen::{encode_png, render_theme, sha256_hex, Theme, THEMES};

#[derive(Parser, Debug)]
#[command(
    name = "aurum-wallpaper-gen",
    about = "Generate the six AurumOS Sequoia-style wallpapers (1x + 2x)."
)]
struct Cli {
    /// Directory to write PNGs and MANIFEST.json into.
    #[arg(long, value_name = "DIR")]
    output_dir: PathBuf,

    /// Comma-separated list of WxH resolutions to render. Order is preserved
    /// and the first resolution is treated as the "1x" file (no @2x suffix);
    /// any remaining resolutions are emitted with `@2x`, `@3x`, ... suffixes
    /// in order of declaration.
    #[arg(long, default_value = "2560x1600,5120x3200")]
    resolutions: String,

    /// Render only the named theme (case-insensitive match on title OR id).
    /// Example: `--only "Aurum Dawn"` or `--only aurum-dawn`.
    #[arg(long, value_name = "NAME")]
    only: Option<String>,

    /// Skip the MANIFEST.json write. Useful when iterating on a single
    /// wallpaper and you don't want to clobber existing hashes.
    #[arg(long)]
    no_manifest: bool,
}

/// One row in the emitted MANIFEST.json.
#[derive(Serialize, Debug)]
struct ManifestEntry {
    id: String,
    title: String,
    palette: Vec<String>,
    /// Map from resolution-tier label (`"1x"`, `"2x"`) to filename.
    files: BTreeMap<String, String>,
    /// Same keys as `files`, values are 64-char lowercase hex digests.
    sha256: BTreeMap<String, String>,
}

#[derive(Serialize, Debug)]
struct Manifest {
    /// Renderer crate version — matches the `Cargo.toml`.
    generator: String,
    wallpapers: Vec<ManifestEntry>,
}

fn parse_resolutions(s: &str) -> Result<Vec<(u32, u32)>, String> {
    let mut out = Vec::new();
    for tok in s.split(',') {
        let tok = tok.trim();
        if tok.is_empty() {
            continue;
        }
        let (w, h) = tok
            .split_once('x')
            .ok_or_else(|| format!("bad resolution `{tok}` (expected WxH)"))?;
        let w: u32 = w.trim().parse().map_err(|e| format!("bad width in `{tok}`: {e}"))?;
        let h: u32 = h.trim().parse().map_err(|e| format!("bad height in `{tok}`: {e}"))?;
        if w == 0 || h == 0 {
            return Err(format!("zero dimension in `{tok}`"));
        }
        out.push((w, h));
    }
    if out.is_empty() {
        return Err("--resolutions produced no usable entries".into());
    }
    Ok(out)
}

/// "1x", "2x", "3x", ... for the n-th resolution (0-indexed).
fn tier_label(idx: usize) -> String {
    format!("{}x", idx + 1)
}

/// File name for a theme + resolution-tier — `aurum-sequoia-1.png` for the
/// first tier of theme #1, `aurum-sequoia-1@2x.png` for the second, etc.
fn file_name(theme: &Theme, tier_idx: usize) -> String {
    if tier_idx == 0 {
        format!("aurum-sequoia-{}.png", theme.number)
    } else {
        format!("aurum-sequoia-{}@{}x.png", theme.number, tier_idx + 1)
    }
}

fn matches_filter(theme: &Theme, filter: &str) -> bool {
    let f = filter.trim().to_ascii_lowercase();
    theme.id.to_ascii_lowercase() == f || theme.title.to_ascii_lowercase() == f
}

fn run(cli: Cli) -> Result<(), String> {
    let resolutions = parse_resolutions(&cli.resolutions)?;
    std::fs::create_dir_all(&cli.output_dir)
        .map_err(|e| format!("mkdir -p {}: {e}", cli.output_dir.display()))?;

    let mut entries: Vec<ManifestEntry> = Vec::new();

    for theme in THEMES {
        if let Some(ref filter) = cli.only {
            if !matches_filter(theme, filter) {
                continue;
            }
        }
        let mut files = BTreeMap::new();
        let mut hashes = BTreeMap::new();

        for (idx, &(w, h)) in resolutions.iter().enumerate() {
            let t = Instant::now();
            let pm = render_theme(theme, w, h);
            let bytes = encode_png(&pm);
            let name = file_name(theme, idx);
            let path = cli.output_dir.join(&name);
            std::fs::write(&path, &bytes)
                .map_err(|e| format!("write {}: {e}", path.display()))?;
            let hash = sha256_hex(&bytes);
            let dt = t.elapsed();
            eprintln!(
                "[wallpaper-gen] {:<14} {}x{}  {:>7} KiB  {:>5.2}s  {}",
                theme.id,
                w,
                h,
                bytes.len() / 1024,
                dt.as_secs_f32(),
                path.display(),
            );

            let tier = tier_label(idx);
            files.insert(tier.clone(), name);
            hashes.insert(tier, hash);
        }

        entries.push(ManifestEntry {
            id: theme.id.to_string(),
            title: theme.title.to_string(),
            palette: theme.palette.iter().map(|s| s.to_string()).collect(),
            files,
            sha256: hashes,
        });
    }

    if entries.is_empty() {
        return Err("no themes matched the --only filter".into());
    }

    if !cli.no_manifest {
        write_manifest(&cli.output_dir, &entries)?;
    }
    Ok(())
}

/// Write or update MANIFEST.json. If the file exists and `--only` reduced
/// the entry set, we merge new entries on top of the existing list so we
/// don't lose hashes for themes that weren't regenerated this run.
fn write_manifest(dir: &Path, new_entries: &[ManifestEntry]) -> Result<(), String> {
    let path = dir.join("MANIFEST.json");

    // Try to load existing manifest first so single-theme reruns don't
    // wipe other themes' hashes.
    let mut merged: Vec<ManifestEntry> = match std::fs::read_to_string(&path) {
        Ok(s) => match serde_json::from_str::<serde_json::Value>(&s) {
            Ok(v) => v
                .get("wallpapers")
                .and_then(|w| w.as_array())
                .map(|arr| {
                    arr.iter()
                        .filter_map(|e| serde_json::from_value(e.clone()).ok())
                        .collect()
                })
                .unwrap_or_default(),
            Err(_) => Vec::new(),
        },
        Err(_) => Vec::new(),
    };

    for new_e in new_entries {
        if let Some(slot) = merged.iter_mut().find(|e| e.id == new_e.id) {
            *slot = ManifestEntry {
                id: new_e.id.clone(),
                title: new_e.title.clone(),
                palette: new_e.palette.clone(),
                files: new_e.files.clone(),
                sha256: new_e.sha256.clone(),
            };
        } else {
            merged.push(ManifestEntry {
                id: new_e.id.clone(),
                title: new_e.title.clone(),
                palette: new_e.palette.clone(),
                files: new_e.files.clone(),
                sha256: new_e.sha256.clone(),
            });
        }
    }

    // Preserve canonical theme ordering even after merges.
    merged.sort_by_key(|e| {
        THEMES
            .iter()
            .position(|t| t.id == e.id)
            .unwrap_or(usize::MAX)
    });

    let manifest = Manifest {
        generator: format!("aurum-wallpaper-gen {}", env!("CARGO_PKG_VERSION")),
        wallpapers: merged,
    };
    let json = serde_json::to_string_pretty(&manifest)
        .map_err(|e| format!("serialise manifest: {e}"))?;
    std::fs::write(&path, json + "\n")
        .map_err(|e| format!("write {}: {e}", path.display()))?;
    eprintln!("[wallpaper-gen] wrote {}", path.display());
    Ok(())
}

fn main() {
    let cli = Cli::parse();
    if let Err(e) = run(cli) {
        eprintln!("aurum-wallpaper-gen: error: {e}");
        std::process::exit(1);
    }
}
