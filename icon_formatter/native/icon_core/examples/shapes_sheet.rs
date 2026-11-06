//! Visual check of the plate shapes: one row per input, columns =
//! source | Squircle | Original | Circle (Lucent, dark), on a mid checker so
//! faint edges and stray light lines show.
//!
//! cargo run --release --example shapes_sheet -- OUT.png in1.png in2.png ...
use icon_core::{imageops, lucent, segment, squircle};
use image::{Rgba, RgbaImage};

fn main() {
    let a: Vec<String> = std::env::args().skip(1).collect();
    let cell = 200u32;
    let n = (a.len() - 1) as u32;
    let mut sheet = RgbaImage::new(cell * 4, cell * n);
    for y in 0..sheet.height() {
        for x in 0..sheet.width() {
            let c = if (x / 10 + y / 10) % 2 == 0 { 0x55 } else { 0x3E };
            sheet.put_pixel(x, y, Rgba([c, c, c + 6, 255]));
        }
    }
    let shapes = [
        ("squircle", lucent::PlateShape::Squircle(squircle::Shape::default())),
        ("original", lucent::PlateShape::Original),
        ("circle", lucent::PlateShape::Circle),
    ];
    for (r, p) in a[1..].iter().enumerate() {
        let src = imageops::decode_file(std::path::Path::new(p)).unwrap();
        let res = segment::isolate(&src, &segment::SegmentOptions::default());
        let y = (r as u32 * cell) as i32;
        imageops::draw_over(&mut sheet, &imageops::resize(&src, cell - 16, cell - 16), 8, y + 8, 1.0);
        for (k, (name, shape)) in shapes.iter().enumerate() {
            let lp = lucent::LucentParams { shape: *shape, ..lucent::LucentParams::dark() };
            let o = lucent::render(&src, &res.glyph, res.bbox, cell - 16, &lp);
            eprintln!("{p} [{name}] notes={:?}", o.notes);
            imageops::draw_over(&mut sheet, &o.image, (k as u32 + 1) as i32 * cell as i32 + 8, y + 8, 1.0);
        }
    }
    imageops::write_png(&sheet, std::path::Path::new(&a[0])).unwrap();
}
