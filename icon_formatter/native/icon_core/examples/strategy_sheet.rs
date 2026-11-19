//! Strategy contact sheet: one input, every GlyphStrategy, dark and light.
//!
//! cargo run --release --example strategy_sheet -- OUT.png input.png
//! Rows: Auto, FullBleed, AsIs, Tile. Columns: original (grey), dark on grey,
//! dark on black, light on grey, light on black. Prints the opaque-pixel mean
//! colour (input vs output) for each render.
use icon_core::batch::{self, BatchConfig, Job, Source};
use icon_core::compose::Placement;
use icon_core::effects::Effects;
use icon_core::imageops;
use icon_core::lucent::{GlyphStrategy, LucentParams};
use icon_core::segment::SegmentOptions;
use image::{Rgba, RgbaImage};
use std::path::PathBuf;
use std::sync::Arc;

const CELL: u32 = 256;

fn opaque_mean(img: &RgbaImage) -> String {
    let (mut s, mut n) = ([0f64; 3], 0f64);
    for q in img.pixels().filter(|q| q[3] >= 200) {
        for k in 0..3 {
            s[k] += q[k] as f64;
        }
        n += 1.0;
    }
    if n == 0.0 {
        return "-".into();
    }
    format!("[{:.0},{:.0},{:.0}]", s[0] / n, s[1] / n, s[2] / n)
}

fn over(bg: [u8; 3], img: &RgbaImage) -> RgbaImage {
    let mut out = RgbaImage::from_pixel(img.width(), img.height(), Rgba([bg[0], bg[1], bg[2], 255]));
    imageops::draw_over(&mut out, img, 0, 0, 1.0);
    out
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let out = PathBuf::from(&args[0]);
    let p = &args[1];
    let src = imageops::decode_file(std::path::Path::new(p)).unwrap();
    let strategies = [
        ("Auto", GlyphStrategy::Auto),
        ("FullBleed", GlyphStrategy::FullBleed),
        ("AsIs", GlyphStrategy::AsIs),
        ("Tile", GlyphStrategy::Tile),
    ];
    let mut sheet = RgbaImage::from_pixel(5 * CELL, strategies.len() as u32 * 2 * CELL, Rgba([0, 0, 0, 255]));
    let src_cell = imageops::resize(&src, CELL - 32, CELL - 32);
    let mut src_pad = RgbaImage::new(CELL, CELL);
    imageops::draw_over(&mut src_pad, &src_cell, 16, 16, 1.0);
    let src_mean = opaque_mean(&src_pad);
    println!("input mean {src_mean}");
    for (row, (name, st)) in strategies.iter().enumerate() {
        for (side, (sname, base)) in [("dark", LucentParams::dark()), ("light", LucentParams::light())].into_iter().enumerate() {
            let lp = LucentParams { strategy: *st, ..base };
            let cfg = BatchConfig {
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
                id: "s".into(),
                name: p.clone(),
                source: Source::Path(PathBuf::from(p)),
                output: PathBuf::new(),
                segment: None,
                placement: None,
                skip_isolation: false,
                shape: None,
                backdrop: None,
            };
            let (o, r) = batch::process_one(&src, &cfg, &job);
            println!("{name}	{sname}	sym_out={}	notes={:?}", opaque_mean(&o), r.notes);
            let y = (row * 2 + side) as u32 * CELL;
            let cells = [over([128, 128, 128], &o), over([0, 0, 0], &o)];
            for (c, im) in cells.iter().enumerate() {
                imageops::draw_over(&mut sheet, im, ((c + 1) as u32 * CELL) as i32, y as i32, 1.0);
            }
            if side == 0 {
                imageops::draw_over(&mut sheet, &over([128, 128, 128], &src_pad), 0, y as i32, 1.0);
            }
        }
    }
    imageops::write_png(&sheet, &out).unwrap();
    println!("sheet {}", out.display());
}
