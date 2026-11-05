use icon_core::{imageops, segment::*};
use image::{Rgba, RgbaImage};
fn main() {
    let a: Vec<String> = std::env::args().skip(1).collect();
    let tols = [0.03f32, 0.05, 0.08, 0.12];
    let cell = 160u32;
    let mut sheet = RgbaImage::from_pixel(cell * (tols.len() as u32 + 1), cell * (a.len() as u32 - 1), Rgba([200, 120, 200, 255]));
    for (r, p) in a[1..].iter().enumerate() {
        let src = imageops::decode_file(std::path::Path::new(p)).unwrap();
        let outer = isolate(&src, &SegmentOptions::default());
        let t = &outer.glyph;
        imageops::draw_over(&mut sheet, &imageops::resize(t, cell, cell), 0, (r as u32 * cell) as i32, 1.0);
        for (c, tol) in tols.iter().enumerate() {
            let o = SegmentOptions { tolerance: *tol, remove_holes: false, ..Default::default() };
            let inner = isolate(t, &o);
            let mut canvas = RgbaImage::new(t.width(), t.height());
            imageops::draw_over(&mut canvas, &inner.glyph, inner.bbox.0 as i32, inner.bbox.1 as i32, 1.0);
            imageops::draw_over(&mut sheet, &imageops::resize(&canvas, cell, cell), ((c as u32 + 1) * cell) as i32, (r as u32 * cell) as i32, 1.0);
            eprintln!("{p} tol {tol}: {} {:?}", inner.method, inner.notes);
        }
    }
    imageops::write_png(&sheet, std::path::Path::new(&a[0])).unwrap();
}
