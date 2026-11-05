//! Segmentation debug: method, notes and bbox for each input, plus a sheet
//! with source | isolated glyph | Lucent render.
//!
//! cargo run --release --example seg_dbg -- OUT.png in1.png in2.png ...
use icon_core::{imageops, lucent, segment};
use image::{Rgba, RgbaImage};

fn main() {
    let a: Vec<String> = std::env::args().skip(1).collect();
    let cell = 256u32;
    let n = (a.len() - 1) as u32;
    let mut sheet = RgbaImage::from_pixel(cell * 4, cell * n, Rgba([120, 90, 150, 255]));
    for (r, p) in a[1..].iter().enumerate() {
        let src = imageops::decode_file(std::path::Path::new(p)).unwrap();
        let res = segment::isolate(&src, &segment::SegmentOptions::default());
        let o = lucent::render(&src, &res.glyph, res.bbox, cell, &lucent::LucentParams::dark());
        eprintln!("{p}\n  {}x{} method={} bbox={:?} notes={:?}\n  lucent notes={:?}", src.width(), src.height(), res.method, res.bbox, res.notes, o.notes);
        let y = (r as u32 * cell) as i32;
        imageops::draw_over(&mut sheet, &imageops::resize(&src, cell, cell), 0, y, 1.0);
        let mut canvas = RgbaImage::new(src.width(), src.height());
        imageops::draw_over(&mut canvas, &res.glyph, res.bbox.0 as i32, res.bbox.1 as i32, 1.0);
        imageops::draw_over(&mut sheet, &imageops::resize(&canvas, cell, cell), cell as i32, y, 1.0);
        imageops::draw_over(&mut sheet, &o.image, 2 * cell as i32, y, 1.0);
        let st = icon_core::compose::crop_to_content(&src);
        let alphas: Vec<u8> = st.pixels().map(|q| q[3]).collect();
        let mut s2 = alphas.clone();
        s2.sort_unstable();
        eprintln!("  src_tile {:?} is_tile={} glyph is_tile={} alpha p25={} p50={} p75={} filled>127={:.2}", st.dimensions(), icon_core::compose::is_tile(&st), icon_core::compose::is_tile(&res.glyph), s2[s2.len()/4], s2[s2.len()/2], s2[s2.len()*3/4], alphas.iter().filter(|&&a| a > 127).count() as f32 / alphas.len() as f32);
        {
            let g = &res.glyph;
            let tot = (g.width() * g.height()) as f32;
            let f = |t: u8| g.pixels().filter(|q| q[3] > t).count() as f32 / tot;
            let fs = |t: u8| st.pixels().filter(|q| q[3] > t).count() as f32 / (st.width() * st.height()) as f32;
            eprintln!("  glyph {:?} fill>0={:.2} >24={:.2} >127={:.2} | src_tile fill>24={:.2} >48={:.2}", g.dimensions(), f(0), f(24), f(127), fs(24), fs(48));
        }
        if let Some((u, b)) = icon_core::compose::unwrap_tile(&st) {
            eprintln!("  unwrap(src_tile) box={:?}", b);
            imageops::draw_over(&mut sheet, &imageops::resize(&u, cell, cell), 3 * cell as i32, y, 1.0);
        } else if let Some((u, b)) = icon_core::compose::unwrap_tile(&res.glyph) {
            eprintln!("  unwrap(glyph) box={:?}", b);
            imageops::draw_over(&mut sheet, &imageops::resize(&u, cell, cell), 3 * cell as i32, y, 1.0);
        }
    }
    imageops::write_png(&sheet, std::path::Path::new(&a[0])).unwrap();
}
