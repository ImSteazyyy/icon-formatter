//! Soft (colour blur) icons, like Google Flow: the whole art must survive, with
//! no hard ring and no dark fringe, and its colours and glow position kept.
//! Synthetic icons only (no third-party art in the repo).
use icon_core::lucent::{self, render, LucentParams};
use icon_core::segment::{isolate, SegmentOptions};
use icon_core::imageops;
use image::{Rgba, RgbaImage};

fn rr_inset(n: u32, r: f32, x: u32, y: u32, inset: u32) -> bool {
    let m = (n - 2 * inset) as f32;
    let (fx, fy) = (x as f32 - inset as f32, y as f32 - inset as f32);
    if fx < 0.0 || fy < 0.0 || fx >= m || fy >= m {
        return false;
    }
    let (dx, dy) = ((r - fx).max(fx - (m - r)).max(0.0), (r - fy).max(fy - (m - r)).max(0.0));
    dx * dx + dy * dy <= r * r
}

/// Separable box blur with edge clamp.
fn box_blur(v: &[f32], n: usize, r: usize) -> Vec<f32> {
    let mut tmp = vec![0f32; n * n];
    let mut out = vec![0f32; n * n];
    for y in 0..n {
        for x in 0..n {
            let (lo, hi) = (x.saturating_sub(r), (x + r).min(n - 1));
            tmp[y * n + x] = (lo..=hi).map(|k| v[y * n + k]).sum::<f32>() / (hi - lo + 1) as f32;
        }
    }
    for y in 0..n {
        for x in 0..n {
            let (lo, hi) = (y.saturating_sub(r), (y + r).min(n - 1));
            out[y * n + x] = (lo..=hi).map(|k| tmp[k * n + x]).sum::<f32>() / (hi - lo + 1) as f32;
        }
    }
    out
}

fn mix(a: [f32; 3], b: [f32; 3], t: f32) -> [f32; 3] {
    [0, 1, 2].map(|k| a[k] * (1.0 - t) + b[k] * t)
}

/// Grey rounded tile (4 px translucent edge) with a blurred blue-to-orange glow
/// beside a crisp white glyph: colour blur, like Google Flow.
fn soft_tile(n: u32) -> RgbaImage {
    let nu = n as usize;
    let mut white = vec![0f32; nu * nu];
    let mut band = vec![0f32; nu * nu];
    for y in 0..nu {
        for x in 0..nu {
            let (fx, fy) = (x as f32 / n as f32, y as f32 / n as f32);
            white[y * nu + x] = ((0.22..0.50).contains(&fx) && (0.36..0.64).contains(&fy)) as u8 as f32;
            band[y * nu + x] = ((0.46..0.86).contains(&fx) && (0.18..0.82).contains(&fy)) as u8 as f32;
        }
    }
    let band = box_blur(&band, nu, nu / 10);
    let white = box_blur(&white, nu, 1);
    let mut img = RgbaImage::new(n, n);
    for y in 0..n {
        for x in 0..n {
            let i = (y as usize) * nu + x as usize;
            let a = if rr_inset(n, 0.22 * n as f32, x, y, 4) {
                255
            } else if rr_inset(n, 0.22 * n as f32, x, y, 0) {
                110
            } else {
                continue;
            };
            let fy = y as f32 / n as f32;
            let glow = mix([50.0, 150.0, 255.0], [255.0, 150.0, 60.0], fy);
            let c = mix(mix([70.0, 70.0, 76.0], glow, band[i]), [255.0; 3], white[i]);
            img.put_pixel(x, y, Rgba([c[0] as u8, c[1] as u8, c[2] as u8, a]));
        }
    }
    img
}

/// Blurred orange blob on a transparent background (alpha ramp; rgb is 0 where
/// transparent, as PNG encoders leave it).
fn soft_blob(n: u32) -> RgbaImage {
    let nu = n as usize;
    let mut m = vec![0f32; nu * nu];
    for y in 0..nu {
        for x in 0..nu {
            let (fx, fy) = (x as f32 / n as f32, y as f32 / n as f32);
            m[y * nu + x] = ((0.30..0.70).contains(&fx) && (0.30..0.70).contains(&fy)) as u8 as f32;
        }
    }
    let m = box_blur(&m, nu, nu / 12);
    let mut img = RgbaImage::new(n, n);
    for y in 0..n {
        for x in 0..n {
            let a = m[(y as usize) * nu + x as usize];
            if a > 0.004 {
                img.put_pixel(x, y, Rgba([240, 150, 40, (a * 255.0).round() as u8]));
            }
        }
    }
    img
}

fn render_auto(src: &RgbaImage, p: &LucentParams) -> RgbaImage {
    let res = isolate(src, &SegmentOptions::default());
    render(src, &res.glyph, res.bbox, 256, p).image
}

fn opaque_frac(img: &RgbaImage) -> f32 {
    img.pixels().filter(|q| q[3] >= 200).count() as f32 / img.pixels().len() as f32
}

fn lum(c: [f32; 3]) -> f32 {
    0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
}

/// Mean colour of the pixels with alpha >= 200.
fn opaque_mean(img: &RgbaImage) -> [f32; 3] {
    let (mut s, mut n) = ([0f64; 3], 0f64);
    for q in img.pixels().filter(|q| q[3] >= 200) {
        for k in 0..3 {
            s[k] += q[k] as f64;
        }
        n += 1.0;
    }
    [0, 1, 2].map(|k| (s[k] / n.max(1.0)) as f32)
}

/// Centroid of the saturated pixels (chroma >= 60, alpha >= 200), relative to
/// the box of the opaque pixels.
fn colour_centroid(img: &RgbaImage) -> (f32, f32) {
    let (w, h) = img.dimensions();
    let (mut bx0, mut by0, mut bx1, mut by1) = (w, h, 0, 0);
    for (x, y, q) in img.enumerate_pixels() {
        if q[3] >= 200 {
            bx0 = bx0.min(x);
            by0 = by0.min(y);
            bx1 = bx1.max(x + 1);
            by1 = by1.max(y + 1);
        }
    }
    let (mut sx, mut sy, mut n) = (0f64, 0f64, 0f64);
    for (x, y, q) in img.enumerate_pixels() {
        let (mx, mn) = (q[0].max(q[1]).max(q[2]), q[0].min(q[1]).min(q[2]));
        if q[3] >= 200 && mx - mn >= 60 {
            sx += (x - bx0) as f64 / (bx1 - bx0).max(1) as f64;
            sy += (y - by0) as f64 / (by1 - by0).max(1) as f64;
            n += 1.0;
        }
    }
    ((sx / n.max(1.0)) as f32, (sy / n.max(1.0)) as f32)
}

#[test]
fn soft_tile_is_named_in_the_result_notes() {
    let src = soft_tile(192);
    let res = isolate(&src, &SegmentOptions::default());
    let out = render(&src, &res.glyph, res.bbox, 256, &LucentParams::dark());
    assert!(out.notes.iter().any(|n| n == lucent::SOFT_COLOUR_NOTE), "notes: {:?}", out.notes);
    // a plain solid glyph must not get the soft note
    let plain = RgbaImage::from_fn(192, 192, |x, y| if (40..150).contains(&x) && (40..150).contains(&y) { Rgba([250, 250, 250, 255]) } else { Rgba([30, 30, 34, 255]) });
    let res = isolate(&plain, &SegmentOptions::default());
    let out = render(&plain, &res.glyph, res.bbox, 256, &LucentParams::dark());
    assert!(!out.notes.iter().any(|n| n == lucent::SOFT_COLOUR_NOTE), "notes: {:?}", out.notes);
}

#[test]
fn soft_tile_keeps_every_pixel_and_colour() {
    let src = soft_tile(192);
    let mut full = LucentParams::dark();
    full.backdrop[3] = 255;
    let out = render_auto(&src, &full);
    let (src_frac, out_frac) = (opaque_frac(&src), opaque_frac(&out));
    assert!(out_frac >= 0.9 * src_frac, "kept {out_frac:.3} of the tile vs source {src_frac:.3}");
    let sm = opaque_mean(&imageops::resize(&src, 256, 256));
    let om = opaque_mean(&out);
    for k in 0..3 {
        assert!((sm[k] - om[k]).abs() <= 16.0, "channel {k}: source {:.1} output {:.1}", sm[k], om[k]);
    }
}

#[test]
fn soft_tile_has_no_hard_ring_on_either_plate() {
    let src = soft_tile(192);
    // light plate only: a dark translucent plate is itself dark, so it cannot
    // be told from a dark cut-out ring by colour alone
    // compared with the source's own translucent edge (grey, alpha ~110): the
    // output must not gain dark translucent pixels of its own
    let dark_translucent = |img: &RgbaImage| {
        img.pixels()
            .filter(|q| q[3] > 60 && q[3] < 200 && lum([q[0] as f32, q[1] as f32, q[2] as f32]) < 110.0)
            .count()
    };
    let out = render_auto(&src, &LucentParams::light());
    let (src_n, out_n) = (dark_translucent(&src), dark_translucent(&out));
    assert!(out_n <= src_n + 256 * 256 / 500, "dark translucent pixels: source {src_n}, output {out_n}");
}

#[test]
fn soft_tile_glow_keeps_its_position() {
    let src = soft_tile(192);
    let mut full = LucentParams::dark();
    full.backdrop[3] = 255;
    let out = render_auto(&src, &full);
    let (sx, sy) = colour_centroid(&src);
    let (ox, oy) = colour_centroid(&out);
    assert!((sx - ox).abs() <= 0.06 && (sy - oy).abs() <= 0.06, "centroid src ({sx:.3},{sy:.3}) out ({ox:.3},{oy:.3})");
}

#[test]
fn soft_blob_alpha_ramp_has_no_dark_fringe() {
    let src = soft_blob(192);
    let mut no_plate = LucentParams::dark();
    no_plate.backdrop[3] = 0;
    let out = render_auto(&src, &no_plate);
    let want = lum([240.0, 150.0, 40.0]);
    let (mut ramp, mut dark) = (0usize, 0usize);
    for q in out.pixels().filter(|q| q[3] > 30 && q[3] < 225) {
        ramp += 1;
        if lum([q[0] as f32, q[1] as f32, q[2] as f32]) < 0.6 * want {
            dark += 1;
        }
    }
    assert!(ramp > 200, "expected a soft edge, got {ramp} ramp pixels");
    assert!(dark * 10 <= ramp, "dark fringe on {dark} of {ramp} soft-edge pixels");
}
