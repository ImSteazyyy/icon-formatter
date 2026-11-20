//! The four built-in looks (lib/app/models.dart `builtInPresets`) rendered
//! through the Lucent plate: squircle or circle, colour or monochrome glyph.
//! The params below mirror what LucentConfig.toSettings() sends for each
//! preset (dark plate, backdrop 0x66, monochrome ink F1F0F4).
//!
//! Contact sheet: set ICON_PRESET_SHEET to an output PNG path and run
//! `cargo test --test lucent_presets preset_contact_sheet -- --nocapture`.

use icon_core::imageops::decode_file;
use icon_core::lucent::{render, LucentParams, PlateShape};
use icon_core::segment::{isolate, SegmentOptions};
use icon_core::squircle;
use image::{Rgba, RgbaImage};
use std::path::{Path, PathBuf};

/// (id, shape, monochrome) of the four built-ins, in their list order.
const PRESETS: [(&str, bool, bool); 4] = [
    ("sqColour", true, false),
    ("sqMono", true, true),
    ("ciColour", false, false),
    ("ciMono", false, true),
];

fn params(squircle_shape: bool, mono: bool) -> LucentParams {
    let shape = if squircle_shape { PlateShape::Squircle(squircle::Shape::default()) } else { PlateShape::Circle };
    // LucentConfig defaults: dark plate, backdrop 0x66, ink F1F0F4, adapt neutrals
    LucentParams { shape, monochrome: mono, ..LucentParams::dark() }
}

/// Blue rounded plate with a green disc glyph, transparent corners.
fn synthetic_icon() -> RgbaImage {
    let mut img = RgbaImage::new(120, 120);
    for y in 0..120u32 {
        for x in 0..120u32 {
            let (dx, dy) = ((x as f32 - 59.5).abs(), (y as f32 - 59.5).abs());
            let inside = dx.max(dy) < 50.0 && !(dx > 35.0 && dy > 35.0 && (dx - 35.0).hypot(dy - 35.0) > 15.0);
            if inside {
                let glyph = dx.hypot(dy) < 24.0;
                img.put_pixel(x, y, if glyph { Rgba([40, 200, 80, 255]) } else { Rgba([30, 80, 220, 255]) });
            }
        }
    }
    img
}

fn render_preset(src: &RgbaImage, squircle_shape: bool, mono: bool, size: u32) -> RgbaImage {
    let res = isolate(src, &SegmentOptions::default());
    render(src, &res.glyph, res.bbox, size, &params(squircle_shape, mono)).image
}

/// Pixel on the plate's diagonal, 0.8 of the plate half-size from the centre.
fn corner_point(size: u32) -> (u32, u32) {
    let c = size as f32 / 2.0;
    let h = 0.93 * size as f32 / 2.0;
    ((c - 0.8 * h) as u32, (c - 0.8 * h) as u32)
}

/// Opaque glyph pixels (alpha above 200).
fn glyph_pixels(img: &RgbaImage) -> Vec<[u8; 4]> {
    img.pixels().map(|p| p.0).filter(|p| p[3] > 200).collect()
}

fn chroma(p: [u8; 4]) -> i32 {
    let mx = p[0].max(p[1]).max(p[2]) as i32;
    let mn = p[0].min(p[1]).min(p[2]) as i32;
    mx - mn
}

#[test]
fn squircle_and_circle_plates_differ_at_the_corner() {
    let size = 256;
    let src = synthetic_icon();
    let (x, y) = corner_point(size);
    let sq = render_preset(&src, true, false, size);
    let ci = render_preset(&src, false, false, size);
    // the squircle is fuller than the circle: its corner region is still plate
    assert!(sq.get_pixel(x, y)[3] > 0x40, "squircle corner alpha {}", sq.get_pixel(x, y)[3]);
    assert_eq!(ci.get_pixel(x, y)[3], 0, "circle corner must be outside the plate");
}

#[test]
fn plate_alpha_matches_the_widget_value() {
    // mean alpha of the plate (glyph pixels excluded) inside 0.6 of the radius
    let size = 256;
    let src = synthetic_icon();
    let img = render_preset(&src, true, false, size);
    let c = size as f32 / 2.0;
    let r = 0.6 * 0.93 * size as f32 / 2.0;
    let (mut sum, mut n) = (0f64, 0u32);
    for y in 0..size {
        for x in 0..size {
            let d = ((x as f32 + 0.5 - c).powi(2) + (y as f32 + 0.5 - c).powi(2)).sqrt();
            let a = img.get_pixel(x, y)[3];
            if d < r && a < 200 {
                sum += a as f64;
                n += 1;
            }
        }
    }
    assert!(n > 1000, "plate pixels {n}");
    let mean = (sum / n as f64) / 255.0;
    assert!((mean - 0x66 as f64 / 255.0).abs() < 0.02, "mean plate alpha {mean:.3}, expected ~0.40");
}

#[test]
fn mono_presets_give_a_single_neutral_glyph_colour() {
    let size = 256;
    let src = synthetic_icon();
    for (squircle_shape, mono) in [(true, true), (false, true)] {
        let img = render_preset(&src, squircle_shape, mono, size);
        let px = glyph_pixels(&img);
        assert!(px.len() > 500, "glyph pixels {}", px.len());
        let worst = px.iter().map(|p| chroma(*p)).max().unwrap_or(0);
        assert!(worst < 24, "mono glyph keeps chroma {worst}");
    }
}

#[test]
fn colour_presets_keep_the_source_hue() {
    let size = 256;
    let src = synthetic_icon();
    for squircle_shape in [true, false] {
        let img = render_preset(&src, squircle_shape, false, size);
        let px = glyph_pixels(&img);
        assert!(px.len() > 500, "glyph pixels {}", px.len());
        let n = px.len() as f64;
        let (r, g, b) = px.iter().fold((0f64, 0f64, 0f64), |a, p| (a.0 + p[0] as f64, a.1 + p[1] as f64, a.2 + p[2] as f64));
        let (r, g, b) = (r / n, g / n, b / n);
        assert!(g > r + 40.0 && g > b + 40.0, "glyph mean ({r:.0},{g:.0},{b:.0}) is not green");
    }
}

#[test]
fn preset_contact_sheet() {
    let Some(out) = std::env::var_os("ICON_PRESET_SHEET") else { return };
    let dir = Path::new("D:/Claude/cleanroom-lucent/shared/inputs");
    let mut files: Vec<PathBuf> = match std::fs::read_dir(dir) {
        Ok(rd) => rd.flatten().map(|e| e.path()).filter(|p| p.extension().map(|x| x == "png").unwrap_or(false)).collect(),
        Err(_) => return,
    };
    files.sort();
    let icons: Vec<RgbaImage> = files.iter().take(8).filter_map(|p| decode_file(p).ok()).collect();
    if icons.is_empty() {
        return;
    }
    let cell = 128u32;
    let gap = 8u32;
    let cols = icons.len() as u32;
    let rows = PRESETS.len() as u32;
    let w = cols * cell + (cols + 1) * gap;
    let h = rows * cell + (rows + 1) * gap;
    // colourful wallpaper: diagonal gradient through orange, violet and teal
    let mut sheet = RgbaImage::from_fn(w, h, |x, y| {
        let t = (x as f32 / w as f32 + y as f32 / h as f32) / 2.0;
        let (r, g, b) = if t < 0.5 {
            let k = t * 2.0;
            (255.0 * (1.0 - k) + 120.0 * k, 130.0 * (1.0 - k) + 60.0 * k, 60.0 * (1.0 - k) + 200.0 * k)
        } else {
            let k = (t - 0.5) * 2.0;
            (120.0 * (1.0 - k) + 40.0 * k, 60.0 * (1.0 - k) + 190.0 * k, 200.0 * (1.0 - k) + 170.0 * k)
        };
        Rgba([r as u8, g as u8, b as u8, 255])
    });
    for (ri, &(_, squircle_shape, mono)) in PRESETS.iter().enumerate() {
        for (ci, src) in icons.iter().enumerate() {
            let img = render_preset(src, squircle_shape, mono, cell);
            let x = gap + ci as u32 * (cell + gap);
            let y = gap + ri as u32 * (cell + gap);
            image::imageops::overlay(&mut sheet, &img, x as i64, y as i64);
        }
    }
    sheet.save(PathBuf::from(out)).expect("write contact sheet");
}
