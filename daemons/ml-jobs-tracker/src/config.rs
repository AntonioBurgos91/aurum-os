//! Reads ~/.config/aurum/mlops.toml (written by aurum-settings).
//!
//! Schema kept deliberately small — extending it should require updating both
//! ends in lockstep.

use std::path::PathBuf;

use serde::Deserialize;

#[derive(Debug, Default, Deserialize)]
pub struct Config {
    #[serde(default)]
    pub mlflow: MlflowSection,
    #[serde(default)]
    pub wandb: WandbSection,
}

#[derive(Debug, Deserialize)]
pub struct MlflowSection {
    #[serde(default = "default_mlflow_uri")]
    pub tracking_uri: String,
    #[serde(default = "default_experiment")]
    pub experiment: String,
}

impl Default for MlflowSection {
    fn default() -> Self {
        Self {
            tracking_uri: default_mlflow_uri(),
            experiment: default_experiment(),
        }
    }
}

#[derive(Debug, Default, Deserialize)]
pub struct WandbSection {
    // Fields are read from TOML via serde even though not referenced directly
    // in Rust code — they are part of the public config schema consumed by the
    // Python-side wandb integration via env vars set elsewhere.
    #[allow(dead_code)]
    #[serde(default)]
    pub api_key: String,
    #[allow(dead_code)]
    #[serde(default)]
    pub entity: String,
}

fn default_mlflow_uri() -> String {
    "http://localhost:5000".into()
}
fn default_experiment() -> String {
    "Default".into()
}

pub fn config_path() -> PathBuf {
    let base = dirs::config_dir()
        .unwrap_or_else(|| PathBuf::from(std::env::var("HOME").unwrap_or_default()));
    base.join("aurum/mlops.toml")
}

pub fn load() -> Config {
    let path = config_path();
    match std::fs::read_to_string(&path) {
        Ok(text) => toml::from_str(&text).unwrap_or_else(|e| {
            log::warn!("mlops.toml parse error ({e}); using defaults");
            Config::default()
        }),
        Err(_) => {
            log::info!("no mlops.toml at {} — using defaults", path.display());
            Config::default()
        }
    }
}
