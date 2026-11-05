//! cargo run --release --example lucent_sheet -- out.png in1.png in2.png ...
//! Columns: original | Lucent dark (original shape) | Lucent light | IconGen circle,
//! each over a colourful "wallpaper" so the translucency is visible.
use icon_core::{imageops, lucent, segment};
use image::{Rgba, RgbaImage};
fn wall(x: u32, y: u32, s: u32) -> [f32; 3] {
    let u = x as f32 / s as f32;
    let v = y as f32 / s as f32;
    [0.85 - 0.5 * v, 0.35 + 0.45 * u, 0.55 + 0.35 * (1.0 - u)]
}
fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let out = &args[0];
    let inputs = &args[1..];
    let cell: u32 = std::env::var("CELL").ok().and_then(|v| v.parse().ok()).unwrap_or(160);
    let cols = 4u32;
    let mut sheet = RgbaImage::new(cols * cell, inputs.len() as u32 * cell);
    for (row, p) in inputs.iter().enumerate() {
        let src = imageops::decode_file(std::path::Path::new(p)).unwrap();
        let res = segment::isolate(&src, &segment::SegmentOptions::default());
        let size = cell - 32;
        let light = lucent::LucentParams::light();
        let circ = lucent::LucentParams { monochrome: true, shape: lucent::PlateShape::Circle, keep_composition: false, ..Default::default() };
        let imgs = [
            imageops::resize(&src, size, size),
            lucent::render(&src, &res.glyph, res.bbox, size, &lucent::LucentParams::dark()).image,
            lucent::render(&src, &res.glyph, res.bbox, size, &light).image,
            lucent::render(&src, &res.glyph, res.bbox, size, &circ).image,
        ];
        for (c, im) in imgs.iter().enumerate() {
            let (x0, y0) = (c as u32 * cell, row as u32 * cell);
            for y in 0..cell { for x in 0..cell {
                let w = wall(x0 + x, y0 + y, sheet.width().max(sheet.height()));
                let (ix, iy) = (x as i32 - 16, y as i32 - 16);
                let mut col = w;
                if ix >= 0 && iy >= 0 && (ix as u32) < size && (iy as u32) < size {
                    let q = im.get_pixel(ix as u32, iy as u32);
                    let a = q[3] as f32 / 255.0;
                    for k in 0..3 { col[k] = q[k] as f32 / 255.0 * a + col[k] * (1.0 - a); }
                }
                sheet.put_pixel(x0 + x, y0 + y, Rgba([(col[0]*255.0) as u8, (col[1]*255.0) as u8, (col[2]*255.0) as u8, 255]));
            }}
        }
        eprintln!("{}: {} notes={:?}", p, res.method, res.notes);
    }
    imageops::write_png(&sheet, std::path::Path::new(out)).unwrap();
}
