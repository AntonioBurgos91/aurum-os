//! Library surface for the AurumOS Spotlight indexer.
//!
//! The daemon binary (`main.rs`) is a thin shell over this crate. Exposing the
//! modules as a library lets the integration tests import them with
//! `use spotlight_indexer::index::…` instead of `#[path = "../src/…"]`, which
//! lets coverage tooling (cargo-llvm-cov) attribute test execution back to
//! these source files.

pub mod index;
pub mod watch;
