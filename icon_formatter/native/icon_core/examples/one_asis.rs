use icon_core::{imageops, lucent, segment};
fn main() {
    let a: Vec<String> = std::env::args().skip(1).collect();
    let src = imageops::decode_file(std::path::Path::new(&a[0])).unwrap();
    let so = segment::SegmentOptions { mode: segment::SegmentMode::KeepAlpha, ..Default::default() };
    let r = segment::isolate(&src, &so);
    let lp = lucent::LucentParams { strategy: lucent::GlyphStrategy::Tile, ..lucent::LucentParams::dark() };
    let o = lucent::render(&src, &r.glyph, r.bbox, 256, &lp);
    eprintln!("{:?} {:?}", r.notes, o.notes);
    imageops::write_png(&o.image, std::path::Path::new(&a[1])).unwrap();
}
