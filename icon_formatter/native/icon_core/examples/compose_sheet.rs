//! cargo run --release --example compose_sheet -- base.png out.png in...
use icon_core::{batch::*, compose::*, imageops, segment::SegmentOptions};
use image::{Rgba, RgbaImage};
use std::sync::Arc;
fn main() {
    let a: Vec<String> = std::env::args().skip(1).collect();
    let base = imageops::decode_file(std::path::Path::new(&a[0])).unwrap();
    let size = 160;
    let cfg = BatchConfig { size, background: Arc::new(render_background(&Background::Image(Arc::new(base)), size)), placement: Placement::default(), segment: SegmentOptions::default(), threads: 1, lucent: None, ai: None };
    let ins = &a[2..];
    let mut sheet = RgbaImage::from_pixel(size * 2, size * ins.len() as u32, Rgba([200, 120, 200, 255]));
    for (r, p) in ins.iter().enumerate() {
        let src = imageops::decode_file(std::path::Path::new(p)).unwrap();
        let job = Job { id: p.clone(), name: p.clone(), source: Source::Path(p.into()), output: "x".into(), segment: None, placement: None, skip_isolation: false };
        let (out, res) = process_one(&src, &cfg, &job);
        eprintln!("{p}: edge={} {}", reaches_edges(&src, (0,0,0,0)), res.method);
        imageops::draw_over(&mut sheet, &imageops::resize(&src, size, size), 0, (r as u32 * size) as i32, 1.0);
        imageops::draw_over(&mut sheet, &out, size as i32, (r as u32 * size) as i32, 1.0);
    }
    imageops::write_png(&sheet, std::path::Path::new(&a[1])).unwrap();
}
