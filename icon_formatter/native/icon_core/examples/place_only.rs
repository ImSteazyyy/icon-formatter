//! "Solo posizione e dimensione" as compose_glyph_png does it.
use icon_core::{compose, imageops, lucent};
fn main() {
    let a: Vec<String> = std::env::args().skip(1).collect();
    let mut sheet = image::RgbaImage::from_pixel(256 * (a.len() as u32 - 1), 256, image::Rgba([85, 85, 92, 255]));
    for (k, p) in a[1..].iter().enumerate() {
        let g = compose::crop_to_content(&imageops::decode_file(std::path::Path::new(p)).unwrap());
        let lp = lucent::LucentParams { strategy: lucent::GlyphStrategy::Tile, ..lucent::LucentParams::dark() };
        let o = lucent::render(&g, &g, (0, 0, g.width(), g.height()), 256, &lp);
        eprintln!("{p}: {:?}", o.notes);
        imageops::draw_over(&mut sheet, &o.image, k as i32 * 256, 0, 1.0);
    }
    imageops::write_png(&sheet, std::path::Path::new(&a[0])).unwrap();
}
