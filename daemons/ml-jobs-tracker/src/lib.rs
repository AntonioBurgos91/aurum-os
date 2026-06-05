//! Library surface for the AurumOS ML jobs tracker.
//!
//! The daemon binary (`main.rs`) is a thin shell over this crate. Exposing the
//! modules as a library lets the integration tests import them with
//! `use ml_jobs_tracker::mlflow::…` instead of `#[path = "../src/…"]`, which in
//! turn lets coverage tooling (cargo-llvm-cov) attribute test execution back to
//! these source files.

pub mod config;
pub mod mlflow;
