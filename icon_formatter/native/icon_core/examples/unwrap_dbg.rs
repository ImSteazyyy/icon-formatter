use icon_core::{compose, imageops, segment::*};
fn main() {
    for p in std::env::args().skip(1) {
        let src = imageops::decode_file(std::path::Path::new(&p)).unwrap();
        let r = isolate(&src, &SegmentOptions::default());
        let u = compose::unwrap_tile(&r.glyph);
        println!("src {:?} outer bbox {:?} glyph {:?} tile={} unwrap={:?} srcalpha_bbox={:?}", src.dimensions(), r.bbox, r.glyph.dimensions(), compose::is_tile(&r.glyph), u.as_ref().map(|x| (x.0.dimensions(), x.1, imageops::alpha_bbox(&x.0, 127))), imageops::alpha_bbox(&src, 24));
    }
}
