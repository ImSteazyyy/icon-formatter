//! remove_holes on/off for one icon: cargo run --release --example holes_dbg -- OUT.png IN.png
use icon_core::{imageops, lucent, segment};
fn main() {
    let a: Vec<String> = std::env::args().skip(1).collect();
    let src = imageops::decode_file(std::path::Path::new(&a[1])).unwrap();
    let mut sheet = image::RgbaImage::from_pixel(512, 256, image::Rgba([85, 85, 92, 255]));
    for (k, holes) in [true, false].iter().enumerate() {
        let so = segment::SegmentOptions { remove_holes: *holes, ..Default::default() };
        let r = segment::isolate(&src, &so);
        let o = lucent::render(&src, &r.glyph, r.bbox, 256, &lucent::LucentParams::dark());
        eprintln!("holes={holes} notes={:?}", r.notes);
        imageops::draw_over(&mut sheet, &o.image, k as i32 * 256, 0, 1.0);
    }
    imageops::write_png(&sheet, std::path::Path::new(&a[0])).unwrap();
}
