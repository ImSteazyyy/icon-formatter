//! cargo run --release --example ai_check -- model.onnx kind out.png in...
use icon_core::{ai, imageops};
use image::{Rgba, RgbaImage};
fn main() {
    let a: Vec<String> = std::env::args().skip(1).collect();
    let kind = match a[1].as_str() { "silueta" => ai::ModelKind::Silueta, "isnet" => ai::ModelKind::IsnetGeneral, _ => ai::ModelKind::U2netp };
    let t = std::time::Instant::now();
    let m = ai::model(&a[0], kind).unwrap();
    eprintln!("load {:?}", t.elapsed());
    let cell = 128u32;
    let ins = &a[3..];
    let mut sheet = RgbaImage::from_pixel(cell * 3, cell * ins.len() as u32, Rgba([60, 60, 70, 255]));
    for (r, p) in ins.iter().enumerate() {
        let src = imageops::decode_file(std::path::Path::new(p)).unwrap();
        let t = std::time::Instant::now();
        let res = ai::isolate_ai(&src, &m, Default::default()).unwrap();
        eprintln!("{p}: {:?} needed={} uncertain={} {:?}", t.elapsed(), res.needed, res.uncertain, res.seg.notes);
        let imgs = [imageops::resize(&src, cell, cell), imageops::resize(&res.mask, cell, cell), {
            let mut c = RgbaImage::new(cell, cell);
            let g = &res.seg.glyph; let k = cell as f32 * 0.9 / g.width().max(g.height()) as f32;
            let gs = imageops::resize(g, ((g.width() as f32*k) as u32).max(1), ((g.height() as f32*k) as u32).max(1));
            imageops::draw_over(&mut c, &gs, ((cell - gs.width())/2) as i32, ((cell - gs.height())/2) as i32, 1.0); c }];
        for (c, im) in imgs.iter().enumerate() { imageops::draw_over(&mut sheet, im, (c as u32 * cell) as i32, (r as u32 * cell) as i32, 1.0); }
    }
    imageops::write_png(&sheet, std::path::Path::new(&a[2])).unwrap();
}
