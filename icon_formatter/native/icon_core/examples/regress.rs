//! Regression harness for the Lucent pipeline (same calls as the app:
//! `segment::isolate` + `lucent::render` with the default dark params).
//!
//! cargo run --release --example regress -- OUT_DIR in1.png in2.png ...
//!
//! Writes OUT_DIR/<name>.png (256 px), renders every input twice and fails
//! when the two renders differ (determinism), prints one line per icon with
//! the notes and an FNV-1a hash of the output pixels.
use icon_core::{imageops, lucent, segment};

fn fnv(b: &[u8]) -> u64 {
    let mut h: u64 = 0xcbf2_9ce4_8422_2325;
    for &x in b {
        h ^= x as u64;
        h = h.wrapping_mul(0x100_0000_01b3);
    }
    h
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let out = std::path::Path::new(&args[0]);
    std::fs::create_dir_all(out).unwrap();
    let mut bad = 0;
    for p in &args[1..] {
        let src = imageops::decode_file(std::path::Path::new(p)).unwrap();
        let run = || {
            let mut so = segment::SegmentOptions::default();
            if std::env::var("SEG").as_deref() == Ok("remove") {
                so.mode = segment::SegmentMode::RemoveBackground;
                so.tolerance = 0.25;
            }
            let res = segment::isolate(&src, &so);
            let mut o = lucent::render(
                &src,
                &res.glyph,
                res.bbox,
                256,
                &lucent::LucentParams::dark(),
            );
            imageops::clean_transparent(&mut o.image);
            o
        };
        let (a, b) = (run(), run());
        let (ha, hb) = (fnv(a.image.as_raw()), fnv(b.image.as_raw()));
        if ha != hb {
            bad += 1;
        }
        let stem = std::path::Path::new(p)
            .file_stem()
            .unwrap()
            .to_string_lossy()
            .to_string();
        imageops::write_png(&a.image, &out.join(format!("{stem}.png"))).unwrap();
        println!(
            "{stem}\t{ha:016x}\t{}\t{:?}",
            if ha == hb { "det" } else { "NONDET" },
            a.notes
        );
    }
    if bad > 0 {
        eprintln!("{bad} non-deterministic renders");
        std::process::exit(1);
    }
}
