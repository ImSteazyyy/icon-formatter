//! cargo run --release --example regress_tr -- OUT_DIR in1.png ...
//! "Nothing Translucent" path (translucent plate + place_on_plate), 256 px.
use icon_core::{compose, imageops, segment, translucent};
use std::sync::Arc;

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let out = std::path::Path::new(&args[0]);
    std::fs::create_dir_all(out).unwrap();
    let bg = compose::render_background(&compose::Background::Translucent(translucent::TranslucentParams::default()), 256);
    let _ = Arc::new(0);
    for p in &args[1..] {
        let src = imageops::decode_file(std::path::Path::new(p)).unwrap();
        let (img, res) = compose::compose_icon(&src, &bg, &compose::Placement::default(), &segment::SegmentOptions::default());
        let stem = std::path::Path::new(p).file_stem().unwrap().to_string_lossy().to_string();
        imageops::write_png(&img, &out.join(format!("{stem}.png"))).unwrap();
        println!("{stem}\t{}\t{:?}", res.method, res.notes);
    }
}
