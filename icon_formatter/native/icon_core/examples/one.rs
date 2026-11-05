use icon_core::{imageops, lucent, segment};
fn main() {
    let a: Vec<String> = std::env::args().skip(1).collect();
    let src = imageops::decode_file(std::path::Path::new(&a[0])).unwrap();
    let r = segment::isolate(&src, &Default::default());
    let o = lucent::render(&src, &r.glyph, r.bbox, 512, &lucent::LucentParams::dark()).image;
    let mut bg = image::RgbaImage::from_pixel(512, 512, image::Rgba([120, 90, 150, 255]));
    imageops::draw_over(&mut bg, &o, 0, 0, 1.0);
    imageops::write_png(&bg, std::path::Path::new(&a[1])).unwrap();
}
