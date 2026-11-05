//! Icon Formatter core.
//!
//! Pure Rust, platform independent. The Flutter bridge crate (`rust/`) exposes a
//! thin FFI layer over these modules; everything here can be unit-tested with
//! `cargo test` without Flutter.

pub mod ai;
pub mod batch;
pub mod calibrate;
pub mod color;
pub mod compose;
pub mod error;
pub mod iconpack;
pub mod lucent;
pub mod matching;
pub mod imageops;
pub mod pack;
pub mod segment;
pub mod squircle;
pub mod translucent;

pub use error::{CoreError, Result};
