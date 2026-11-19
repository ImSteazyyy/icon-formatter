//! Quality contact sheet for the Lucent colour/strategy bug report.
//!
//! cargo run --release --example quality_sheet -- OUT.png in1.png in2.png ...
//!
//! Renders every input through `batch::process_one` (the same path as the
//! app) with `LucentParams::dark()` and `::light()`, and lays out one row per
//! input: original on mid-grey, original on black, dark on grey, dark on black,
//! light on grey, light on black. Also prints the symbol colour metric (mean
//! colour of the opaque pixels, input vs output) and the luminance ratio over
//! mid-grey (output / input) for each dark and light render.
use icon_core::batch::{self, BatchConfig, Job, Source};
use icon_core::compose::Placement;
use icon_core::effects::Effects;
use icon_core::imageops;
use icon_core::lucent::LucentParams;
use icon_core::segment::SegmentOptions;
use image::{Rgba, RgbaImage};
use std::path::PathBuf;
use std::sync::Arc;

const CELL: u32 = 256;

/// Mean RGB of the opaque (alpha >= 200) pixels.
fn opaque_mean(img: &RgbaImage) -> Option<[f32; 3]> {
    let (mut s, mut n) = ([0f64; 3], 0f64);
    for q in img.pixels().filter(|q| q[3] >= 200) {
        for k in 0..3 {
            s[k] += q[k] as f64;
        }
        n += 1.0;
    }
    (n > 0.0).then(|| [0, 1, 2].map(|k| (s[k] / n) as f32))
}

/// Mean luminance of the image composited over mid-grey, over pixels with alpha >= 200 in the input.
fn grey_lum(img: &RgbaImage, grey: f32) -> f32 {
    let (mut s, mut n) = (0f64, 0f64);
    for q in img.pixels().filter(|q| q[3] >= 200) {
        let a = q[3] as f32 / 255.0;
        let c = |v: u8| v as f32 * a + grey * (1.0 - a);
        s += (0.2126 * c(q[0]) + 0.7152 * c(q[1]) + 0.0722 * c(q[2])) as f64;
        n += 1.0;
    }
    (s / n.max(1.0)) as f32
}

fn over(bg: [u8; 3], img: &RgbaImage) -> RgbaImage {
    let mut out = RgbaImage::from_pixel(img.width(), img.height(), Rgba([bg[0], bg[1], bg[2], 255]));
    imageops::draw_over(&mut out, img, 0, 0, 1.0);
    out
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let out = PathBuf::from(&args[0]);
    let inputs = &args[1..];
    let cols = 6u32;
    let mut sheet = RgbaImage::from_pixel(cols * CELL, inputs.len() as u32 * CELL, Rgba([0, 0, 0, 255]));
    for (row, p) in inputs.iter().enumerate() {
        let src = imageops::decode_file(std::path::Path::new(p)).unwrap();
        let cfg = |lp: LucentParams| BatchConfig {
            size: CELL,
            background: Arc::new(RgbaImage::new(CELL, CELL)),
            placement: Placement::default(),
            segment: SegmentOptions::default(),
            threads: 1,
            lucent: Some(lp),
            ai: None,
            effects: Effects::default(),
            cut_cache: None,
        };
        let job = Job {
            id: "q".into(),
            name: p.clone(),
            source: Source::Path(PathBuf::from(p)),
            output: PathBuf::new(),
            segment: None,
            placement: None,
            skip_isolation: false,
            shape: None,
            backdrop: None,
        };
        let dark = batch::process_one(&src, &cfg(LucentParams::dark()), &job);
        let light = batch::process_one(&src, &cfg(LucentParams::light()), &job);
        let src_cell = imageops::resize(&src, CELL - 32, CELL - 32);
        let mut src_pad = RgbaImage::new(CELL, CELL);
        imageops::draw_over(&mut src_pad, &src_cell, 16, 16, 1.0);
        let cells = [
            (over([128, 128, 128], &src_pad), 0u32),
            (over([0, 0, 0], &src_pad), 1),
            (over([128, 128, 128], &dark.0), 2),
            (over([0, 0, 0], &dark.0), 3),
            (over([128, 128, 128], &light.0), 4),
            (over([0, 0, 0], &light.0), 5),
        ];
        for (im, c) in cells.iter() {
            imageops::draw_over(&mut sheet, im, (*c * CELL) as i32, (row as u32 * CELL) as i32, 1.0);
        }
        let stem = std::path::Path::new(p).file_stem().unwrap().to_string_lossy().to_string();
        let fmt = |v: Option<[f32; 3]>| v.map(|c| format!("[{:.0},{:.0},{:.0}]", c[0], c[1], c[2])).unwrap_or("-".into());
        let src_lum = grey_lum(&src_pad, 128.0);
        for (name, r) in [("dark", &dark), ("light", &light)] {
            let o = &r.0;
            // output is resampled on a CELL canvas: compare on the same canvas
            let oin = fmt(opaque_mean(&src_pad));
            let oout = fmt(opaque_mean(o));
            let lum_ratio = grey_lum(o, 128.0) / src_lum.max(1.0);
            println!(
                "{stem}\t{name}\tsym_in={oin}\tsym_out={oout}\tlum_ratio={lum_ratio:.3}\tnotes={:?}",
                r.1.notes
            );
        }
    }
    imageops::write_png(&sheet, &out).unwrap();
    println!("sheet {}", out.display());
}
