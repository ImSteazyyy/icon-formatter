//! Tests against the reference icons placed in the project root folder
//! (read-only: originals are never written). Skipped if the folder is absent.

use icon_core::calibrate::calibrate;
use icon_core::compose::{place_glyph, render_background, Background, Placement};
use icon_core::imageops::{decode_file, write_png};
use icon_core::segment::{isolate, SegmentOptions};
use icon_core::translucent::TranslucentParams;
use std::path::PathBuf;

fn reference_icons() -> Vec<(String, PathBuf)> {
    let dir = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../..");
    let mut v: Vec<(String, PathBuf)> = std::fs::read_dir(&dir)
        .map(|rd| {
            rd.flatten()
                .filter(|e| e.path().extension().map(|x| x == "png").unwrap_or(false))
                .map(|e| (e.file_name().to_string_lossy().to_string(), e.path()))
                .collect()
        })
        .unwrap_or_default();
    v.sort();
    v
}

fn out_dir() -> PathBuf {
    let d = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("target/ref_out");
    std::fs::create_dir_all(&d).unwrap();
    d
}

#[test]
fn reference_glyphs_are_isolated() {
    let icons = reference_icons();
    if icons.is_empty() {
        eprintln!("no reference icons, skipping");
        return;
    }
    let bg = render_background(&Background::Translucent(TranslucentParams::default()), 512);
    let mut ambiguous = 0;
    for (name, p) in &icons {
        let img = decode_file(p).unwrap();
        let r = isolate(&img, &SegmentOptions::default());
        assert!(r.method.contains("plate"), "{name}: {}", r.method);
        let (x0, y0, x1, y1) = r.bbox;
        let side = (x1 - x0).max(y1 - y0) as f32 / img.width() as f32;
        assert!(side > 0.25 && side < 0.85, "{name}: glyph side ratio {side} bbox {:?}", r.bbox);
        if r.ambiguous {
            ambiguous += 1;
            eprintln!("{name}: ambiguous {:?}", r.notes);
        }
        let mut canvas = bg.clone();
        place_glyph(&mut canvas, &r.glyph, &Placement::default());
        write_png(&canvas, &out_dir().join(name)).unwrap();
    }
    eprintln!("{} icons, {} ambiguous", icons.len(), ambiguous);
}

#[test]
fn calibration_from_reference_samples() {
    let icons = reference_icons();
    if icons.len() < 5 {
        return;
    }
    let samples: Vec<(String, image::RgbaImage)> =
        icons.iter().map(|(n, p)| (n.clone(), decode_file(p).unwrap())).collect();
    // no base: glyphs found by segmentation of the composed samples
    let cal = calibrate(None, &samples);
    eprintln!(
        "glyph_ratio={:.3} area={:.3} center=({:.3},{:.3}) inliers={} mad={:.3}",
        cal.placement.glyph_ratio,
        cal.placement.area_ratio,
        cal.placement.center_x,
        cal.placement.center_y,
        cal.inliers,
        cal.max_side_mad
    );
    for s in &cal.samples {
        eprintln!("  {:28} side={:.3} c=({:.3},{:.3}) {} {}", s.name, s.max_side_ratio, s.center_x, s.center_y, s.method, if s.outlier { "OUTLIER" } else { "" });
    }
    assert!(cal.inliers as usize >= samples.len() * 2 / 3);
    assert!((cal.placement.glyph_ratio - 0.645).abs() < 0.06);
    assert!((cal.placement.center_x - 0.5).abs() < 0.02);
    assert!((cal.placement.center_y - 0.5).abs() < 0.03);
}
