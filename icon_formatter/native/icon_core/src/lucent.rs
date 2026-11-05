//! "Lucent" rendering (Nothing OS 5.0 translucent icons).
//!
//! Port of the rendering method of Nothing IconGen
//! (<https://github.com/linuxct/nothing-icongen>, AGPL-3.0-only, © linuxct):
//!
//! * `PortableMonochrome.generate`: the launcher's luminance → ink-alpha
//!   conversion (modal grey shift, quadratic ramp above the darkest opaque
//!   grey, complexity classification, light-ink inverted mask);
//! * `IconArtwork.buildIcon`: frosted backdrop plate (`container_frosted_backdrop`,
//!   `#66000000` dark / `#66FFFFFF` light) with the glyph tinted SRC_IN by the
//!   ink colour (`system_neutral1_50` dark / `system_neutral1_900` light);
//! * `PackIconEncoder`: compensation for Nothing Launcher drawing a pack icon
//!   as source → ShadowGenerator shadows → source again.
//!
//! Differences from IconGen, by design: the input is a raster icon (not an
//! Android `Drawable`), so the glyph comes from `segment::isolate`; the plate
//! follows the original icon silhouette instead of IconGen's fixed circle
//! (circle and squircle stay available), and the glyph can keep its original
//! position and size inside the icon.

use crate::imageops::resize;
use crate::squircle;
use image::{Rgba, RgbaImage};

const FALLBACK_NOTE: &str = "La sorgente non ha un piatto/sfondo: uso il piatto circolare di Nothing";
/// Longest glyph side on the fallback circle for bare logos.
const BARE_LOGO_SCALE: f32 = 0.62;

/// IconGen `PortableMonochrome.GLYPH_SCALE`.
pub const GLYPH_SCALE: f32 = 0.388_888_9;
/// IconGen `IconArtwork.NATIVE_BACKGROUND_SCALE`.
pub const NATIVE_BACKGROUND_SCALE: f32 = 0.93;

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum PlateShape {
    /// Silhouette of the source icon (its alpha channel).
    Original,
    /// IconGen / Nothing Launcher circular plate.
    Circle,
    Squircle(squircle::Shape),
}

#[derive(Clone, Debug, PartialEq)]
pub struct LucentParams {
    /// Ink (foreground) colour, RGB.
    pub ink: [u8; 3],
    /// Frosted backdrop colour; `[3]` is its alpha (0x66 on Nothing OS).
    pub backdrop: [u8; 4],
    pub shape: PlateShape,
    /// Nothing ink conversion (optional). Default false: the glyph keeps its
    /// own colours and only the plate uses the Lucent treatment.
    pub monochrome: bool,
    /// Keep the glyph's original position/size inside the icon; false uses
    /// the Nothing Launcher normalisation (longest side 0.389 / 0.93).
    pub keep_composition: bool,
    /// Manual glyph scale multiplier.
    pub glyph_scale: f32,
    /// Manual glyph offset, fraction of the output size.
    pub offset_x: f32,
    pub offset_y: f32,
    /// Subtle light rim on the plate edge (0 = off, as on Nothing OS).
    pub rim: f32,
    /// Dark plate: lift dark neutral greys of the glyph so they stay visible.
    pub lift_greys: bool,
    /// Bake the launcher's ShadowGenerator shadow into the PNG.
    pub launcher_shadow: bool,
    /// Apply IconGen's PackIconEncoder (only for packs used by Nothing Launcher).
    pub nothing_encode: bool,
}

impl LucentParams {
    pub fn dark() -> Self {
        LucentParams {
            ink: [0xF1, 0xF0, 0xF4],
            backdrop: [0, 0, 0, 0x66],
            // the plate we render (reference squircle) is the clipping edge
            shape: PlateShape::Squircle(squircle::Shape { size_ratio: 0.93, exponent: 4.25 }),
            monochrome: false,
            keep_composition: true,
            glyph_scale: 1.0,
            offset_x: 0.0,
            offset_y: 0.0,
            rim: 0.0,
            lift_greys: true,
            launcher_shadow: false,
            nothing_encode: false,
        }
    }

    pub fn light() -> Self {
        LucentParams { ink: [0x1B, 0x1B, 0x1F], backdrop: [255, 255, 255, 0x66], ..Self::dark() }
    }
}

impl Default for LucentParams {
    fn default() -> Self {
        Self::dark()
    }
}

/// Applies the manual corrections of a `Placement` (scale and offset).
pub fn with_placement(p: &LucentParams, pl: &crate::compose::Placement) -> LucentParams {
    LucentParams {
        glyph_scale: p.glyph_scale * pl.scale_mul,
        offset_x: p.offset_x + pl.offset_x,
        offset_y: p.offset_y + pl.offset_y,
        ..p.clone()
    }
}

pub struct LucentOutput {
    pub image: RgbaImage,
    pub notes: Vec<String>,
}

fn smoothstep(e0: f32, e1: f32, x: f32) -> f32 {
    let t = ((x - e0) / (e1 - e0)).clamp(0.0, 1.0);
    t * t * (3.0 - 2.0 * t)
}

fn luminance(r: u8, g: u8, b: u8) -> i32 {
    (r as f64 * 0.30 + g as f64 * 0.59 + b as f64 * 0.11) as i32
}

/// Source fitted into a `size` square (aspect preserved, centred).
/// Returns the fitted image, scale and offset.
fn fit_square(src: &RgbaImage, size: u32) -> (RgbaImage, f32, f32, f32) {
    let (w, h) = (src.width().max(1) as f32, src.height().max(1) as f32);
    let k = size as f32 / w.max(h);
    let (tw, th) = ((w * k).round().max(1.0) as u32, (h * k).round().max(1.0) as u32);
    let scaled = resize(src, tw, th);
    let (ox, oy) = ((size - tw) / 2, (size - th) / 2);
    let mut out = RgbaImage::new(size, size);
    for y in 0..th {
        for x in 0..tw {
            out.put_pixel(x + ox, y + oy, *scaled.get_pixel(x, y));
        }
    }
    (out, k, ox as f32, oy as f32)
}

/// Plate coverage mask (0..1) at `size`.
fn plate_mask(src: &RgbaImage, glyph: &RgbaImage, size: u32, shape: PlateShape, notes: &mut Vec<String>) -> Vec<f32> {
    let n = (size * size) as usize;
    let circle = |size: u32| -> Vec<f32> {
        let c = size as f32 / 2.0;
        let mut m = vec![0.0; (size * size) as usize];
        for y in 0..size {
            for x in 0..size {
                let d = ((x as f32 + 0.5 - c).powi(2) + (y as f32 + 0.5 - c).powi(2)).sqrt();
                m[(y * size + x) as usize] = (c - d + 0.5).clamp(0.0, 1.0);
            }
        }
        m
    };
    match shape {
        PlateShape::Circle => circle(size),
        PlateShape::Squircle(s) => squircle::mask(size, &s).iter().map(|&v| v as f32 / 255.0).collect(),
        PlateShape::Original => {
            let (fitted, ..) = fit_square(src, size);
            // Soft drop shadows (low alpha) are not part of the silhouette;
            // anti-aliased edges are kept.
            // The plate may itself be semi-transparent (already translucent
            // icons): normalise by its typical alpha level, so a plate at
            // alpha 0.5 still gives a full silhouette while fainter drop
            // shadows stay out.
            // level = median alpha sampled 4% inside the silhouette's edges:
            // the outer plate itself, not an opaque inner tile
            let level = {
                let (x0, y0, x1, y1) = crate::imageops::alpha_bbox(&fitted, 24).unwrap_or((0, 0, size, size));
                let inset = ((x1 - x0).min(y1 - y0) as f32 * 0.04).round().max(1.0) as u32;
                let (ax, ay) = (x0 + inset, y0 + inset);
                let (bx, by) = (x1.saturating_sub(inset + 1).max(ax), y1.saturating_sub(inset + 1).max(ay));
                let mut v: Vec<u8> = Vec::new();
                for k in 1..8u32 {
                    let x = x0 + (x1 - x0) * k / 8;
                    let y = y0 + (y1 - y0) * k / 8;
                    v.extend([fitted.get_pixel(x, ay)[3], fitted.get_pixel(x, by)[3], fitted.get_pixel(ax, y)[3], fitted.get_pixel(bx, y)[3]]);
                }
                v.sort_unstable();
                v[v.len() / 2].max(32) as f32 / 255.0
            };
            let m: Vec<f32> = fitted.pixels().map(|p| smoothstep(0.35 * level, 0.85 * level, p[3] as f32 / 255.0)).collect();
            let coverage = m.iter().sum::<f32>() / n as f32;
            // No plate when the isolated glyph is (almost) the whole opaque
            // area: the source is a bare logo, so there is no silhouette to keep.
            let count = |img: &RgbaImage, t: u8| img.pixels().filter(|p| p[3] > t).count() as f32;
            let bare = count(glyph, 16) >= 0.8 * count(src, 16).max(1.0);
            if coverage < 0.10 || bare {
                notes.push(FALLBACK_NOTE.into());
                circle(size)
            } else {
                m
            }
        }
    }
}

/// Port of `PortableMonochrome.classifySource` on a 50 px sample.
fn is_complex(glyph: &RgbaImage) -> bool {
    const S: u32 = 50;
    let (w, h) = (glyph.width().max(1), glyph.height().max(1));
    let k = S as f32 / w.max(h) as f32;
    let (tw, th) = (((w as f32 * k).round() as u32).clamp(1, S), ((h as f32 * k).round() as u32).clamp(1, S));
    let small = resize(glyph, tw, th);
    let mut sample = RgbaImage::new(S, S);
    let (ox, oy) = ((S - tw) / 2, (S - th) / 2);
    for y in 0..th {
        for x in 0..tw {
            sample.put_pixel(x + ox, y + oy, *small.get_pixel(x, y));
        }
    }
    let mut bins = [false; 512];
    let mut colors = 0;
    let mut edges = 0;
    let dist = |a: &Rgba<u8>, b: &Rgba<u8>| -> i32 {
        (a[0] as i32 - b[0] as i32).abs() + (a[1] as i32 - b[1] as i32).abs() + (a[2] as i32 - b[2] as i32).abs()
    };
    for y in 0..S {
        for x in 0..S {
            let p = sample.get_pixel(x, y);
            let bin = (p[0] / 32) as usize * 64 + (p[1] / 32) as usize * 8 + (p[2] / 32) as usize;
            if !bins[bin] {
                bins[bin] = true;
                colors += 1;
            }
            if x + 1 < S && y + 1 < S && dist(p, sample.get_pixel(x + 1, y)) + dist(p, sample.get_pixel(x, y + 1)) > 10 {
                edges += 1;
            }
        }
    }
    colors > 34 || edges as f32 > (S * S) as f32 * 0.3
}

/// Port of `PortableMonochrome.generate` (pixel conversion) on an isolated
/// glyph: returns the ink alpha mask (same size as `glyph`) and complexity.
pub fn monochrome_mask(glyph: &RgbaImage) -> (Vec<u8>, bool) {
    let complex = is_complex(glyph);
    // modal grey of opaque pixels (32 bins of 8)
    let mut bins = [0u32; 32];
    for p in glyph.pixels() {
        if p[3] > 110 {
            bins[(luminance(p[0], p[1], p[2]) / 8).clamp(0, 31) as usize] += 1;
        }
    }
    let mut mode = 0;
    for i in 1..32 {
        if bins[i] > bins[mode] {
            mode = i;
        }
    }
    let modal = (mode as i32 + 1) * 8 - 1;
    let mut offset = 255 - modal;
    if complex && offset > 80 {
        offset = 0;
    }
    let mut gray = vec![0i32; (glyph.width() * glyph.height()) as usize];
    let mut minimum = 255;
    for (i, p) in glyph.pixels().enumerate() {
        if p[3] == 0 {
            continue;
        }
        let shifted = luminance(p[0], p[1], p[2]) + offset;
        let v = if shifted > 255 { 510 - shifted } else { shifted };
        gray[i] = v;
        if p[3] > 110 {
            minimum = minimum.min(v);
        }
    }
    let factor = if minimum < 248 { 210.0f32 / (248 * 248 - minimum * minimum) as f32 } else { 0.0 };
    let mask = glyph
        .pixels()
        .enumerate()
        .map(|(i, p)| {
            if p[3] > 110 && minimum < 248 {
                (((gray[i] * gray[i] - 248 * 248) as f32 * factor) as i32 + 255).clamp(0, 255) as u8
            } else {
                p[3]
            }
        })
        .collect();
    (mask, complex)
}

/// Port of `PortableMonochrome.lightMask` (used with dark ink on complex art):
/// alpha inverted inside the glyph's inscribed circle.
fn light_mask(mask: &[u8], w: u32, h: u32) -> Vec<u8> {
    let (cx, cy) = (w as f32 / 2.0, h as f32 / 2.0);
    let r = w.max(h) as f32 / 2.0;
    let mut out = vec![0u8; mask.len()];
    let (mut count, mut opaque) = (0u32, 0u32);
    for y in 0..h {
        for x in 0..w {
            let i = (y * w + x) as usize;
            if (x as f32 + 0.5 - cx).powi(2) + (y as f32 + 0.5 - cy).powi(2) <= r * r {
                count += 1;
                let a = 255 - mask[i];
                if a == 0 {
                    opaque += 1;
                }
                out[i] = a;
            }
        }
    }
    if count > 0 && opaque as f32 / count as f32 >= 0.1 {
        for v in out.iter_mut() {
            if *v > 0 {
                *v = v.saturating_add(10);
            }
        }
    }
    out
}

/// Gaussian blur (three box passes) of a single-channel f32 buffer.
pub fn gaussian_blur(buf: &[f32], w: usize, h: usize, sigma: f32) -> Vec<f32> {
    if sigma < 0.3 {
        return buf.to_vec();
    }
    // box sizes for 3 passes (Kovesi)
    let n = 3.0f32;
    let wi = ((12.0 * sigma * sigma / n) + 1.0).sqrt().floor();
    let wl = if (wi as i32) % 2 == 0 { wi - 1.0 } else { wi };
    let wu = wl + 2.0;
    let m = ((12.0 * sigma * sigma - n * wl * wl - 4.0 * n * wl - 3.0 * n) / (-4.0 * wl - 4.0)).round();
    let sizes: Vec<usize> = (0..3).map(|i| if (i as f32) < m { wl as usize } else { wu as usize }).collect();
    let mut a = buf.to_vec();
    let mut b = vec![0.0f32; buf.len()];
    for s in sizes {
        let r = (s.max(1) - 1) / 2;
        box_h(&a, &mut b, w, h, r);
        box_v(&b, &mut a, w, h, r);
    }
    a
}

fn box_h(src: &[f32], dst: &mut [f32], w: usize, h: usize, r: usize) {
    let norm = 1.0 / (2 * r + 1) as f32;
    for y in 0..h {
        let row = &src[y * w..(y + 1) * w];
        let mut acc = 0.0f32;
        for x in 0..=r.min(w - 1) {
            acc += row[x];
        }
        for x in 0..w {
            dst[y * w + x] = acc * norm;
            let add = x + r + 1;
            if add < w {
                acc += row[add];
            }
            if x >= r {
                acc -= row[x - r];
            }
        }
    }
}

fn box_v(src: &[f32], dst: &mut [f32], w: usize, h: usize, r: usize) {
    let norm = 1.0 / (2 * r + 1) as f32;
    for x in 0..w {
        let mut acc = 0.0f32;
        for y in 0..=r.min(h - 1) {
            acc += src[y * w + x];
        }
        for y in 0..h {
            dst[y * w + x] = acc * norm;
            let add = y + r + 1;
            if add < h {
                acc += src[add * w + x];
            }
            if y >= r {
                acc -= src[(y - r) * w + x];
            }
        }
    }
}

/// Nothing Launcher `ShadowGenerator` shadow alpha (0..1) for an alpha buffer:
/// blurred mask at 25/255, plus the key shadow offset by size/48 at 7/255.
pub fn launcher_shadow(alpha: &[f32], size: usize) -> Vec<f32> {
    let host = (size as f32 - 2.0 * (size as f32 * (1.0 - 0.92) / 2.0).round()) / size as f32;
    let radius = size as f32 * 0.035 / host;
    let sigma = 0.577_35 * radius + 0.5; // Skia BlurMaskFilter radius -> sigma
    let blurred = gaussian_blur(alpha, size, size, sigma);
    let dy = (size as f32 / 48.0 / host).round() as usize;
    let mut out = vec![0.0f32; alpha.len()];
    for y in 0..size {
        for x in 0..size {
            let i = y * size + x;
            let a1 = blurred[i] * 25.0 / 255.0;
            let a2 = if y >= dy { blurred[(y - dy) * size + x] * 7.0 / 255.0 } else { 0.0 };
            out[i] = a2 + a1 * (1.0 - a2);
        }
    }
    out
}

fn inverse_alpha(target: u8, shadow: u8) -> u8 {
    match target {
        0 => 0,
        255 => 255,
        t => {
            let remaining = ((255.0 - t as f64) / (255.0 - shadow as f64)).min(1.0);
            ((1.0 - remaining.sqrt()) * 255.0).round().clamp(0.0, 255.0) as u8
        }
    }
}

/// Port of IconGen `PackIconEncoder.encode`: the returned PNG, drawn by
/// Nothing Launcher as source → shadows → source, reproduces `target`.
pub fn nothing_encode(target: &RgbaImage) -> RgbaImage {
    let size = target.width() as usize;
    assert_eq!(target.width(), target.height());
    let ta: Vec<u8> = target.pixels().map(|p| p[3]).collect();
    let mut a: Vec<u8> = ta.iter().map(|&t| inverse_alpha(t, 0)).collect();
    let shadow_of = |a: &[u8]| -> Vec<u8> {
        let f: Vec<f32> = a.iter().map(|&v| v as f32 / 255.0).collect();
        launcher_shadow(&f, size).iter().map(|&v| (v * 255.0).round().clamp(0.0, 255.0) as u8).collect()
    };
    let mut s = shadow_of(&a);
    for _ in 0..6 {
        let mut changed = false;
        for i in 0..a.len() {
            let v = inverse_alpha(ta[i], s[i]);
            if v != a[i] {
                a[i] = v;
                changed = true;
            }
        }
        if !changed {
            break;
        }
        s = shadow_of(&a);
    }
    let mut out = RgbaImage::new(target.width(), target.height());
    for (i, (o, t)) in out.pixels_mut().zip(target.pixels()).enumerate() {
        let av = a[i] as f64 / 255.0;
        if av == 0.0 {
            continue;
        }
        let sv = s[i] as f64 / 255.0;
        let weight = av * (1.0 + (1.0 - av) * (1.0 - sv));
        let gain = (t[3] as f64 / 255.0) / weight;
        let ch = |v: u8| (v as f64 * gain).round().clamp(0.0, 255.0) as u8;
        *o = Rgba([ch(t[0]), ch(t[1]), ch(t[2]), a[i]]);
    }
    out
}

/// Simulates Nothing Launcher drawing a pack PNG (source, shadows, source)
/// over a transparent surface; used by tests and the "launcher" preview.
pub fn simulate_launcher(png: &RgbaImage) -> RgbaImage {
    let size = png.width() as usize;
    let a: Vec<f32> = png.pixels().map(|p| p[3] as f32 / 255.0).collect();
    let s = launcher_shadow(&a, size);
    let mut out = RgbaImage::new(png.width(), png.height());
    for (i, (o, p)) in out.pixels_mut().zip(png.pixels()).enumerate() {
        let av = a[i];
        // premultiplied: src, then black shadow, then src again
        let c = |v: u8| v as f32 / 255.0 * av;
        let (mut r, mut g, mut b, mut al) = (c(p[0]), c(p[1]), c(p[2]), av);
        let sv = s[i];
        r *= 1.0 - sv;
        g *= 1.0 - sv;
        b *= 1.0 - sv;
        al = sv + al * (1.0 - sv);
        r = c(p[0]) + r * (1.0 - av);
        g = c(p[1]) + g * (1.0 - av);
        b = c(p[2]) + b * (1.0 - av);
        al = av + al * (1.0 - av);
        if al > 0.0 {
            let un = |v: f32| (v / al * 255.0).round().clamp(0.0, 255.0) as u8;
            *o = Rgba([un(r), un(g), un(b), (al * 255.0).round() as u8]);
        }
    }
    out
}

/// Renders a Lucent icon at `size` from the source icon and its isolated glyph
/// (`glyph_bbox` in source coordinates, as returned by `segment::isolate`).
pub fn render(src: &RgbaImage, glyph: &RgbaImage, glyph_bbox: (u32, u32, u32, u32), size: u32, p: &LucentParams) -> LucentOutput {
    let mut notes = Vec::new();
    let n = size as usize;
    let plate = plate_mask(src, glyph, size, p.shape, &mut notes);
    let icon_gen_mode = p.shape == PlateShape::Circle && !p.keep_composition;

    // bare logo (no plate in the source): centred at BARE_LOGO_SCALE on any plate
    let count = |img: &RgbaImage, t: u8| img.pixels().filter(|q| q[3] > t).count() as f32;
    let bare = count(glyph, 16) >= 0.8 * count(src, 16).max(1.0);
    let fallback = bare || notes.iter().any(|n| n == FALLBACK_NOTE);
    // "icon inside the icon": strip the inner tile's own background too and
    // map the tile onto the plate box (cover), clipped by the plate below
    let tile_dims = glyph.dimensions();
    let unwrapped = if fallback { None } else { crate::compose::unwrap_tile(glyph) };
    let inner_box = unwrapped.as_ref().map(|u| u.1);
    let glyph: &RgbaImage = match &unwrapped {
        Some((g, _)) => g,
        None => glyph,
    };

    // ---- glyph layer (straight RGBA at glyph resolution)
    let mut layer = glyph.clone();
    let dark_plate = (p.backdrop[0] as u32 + p.backdrop[1] as u32 + p.backdrop[2] as u32) < 384;
    if p.lift_greys && dark_plate && !p.monochrome {
        // neutral greys get a gamma lift (v^0.6): dark details (roads, keys)
        // become visible on the dark frosted plate while the tonal steps
        // between greys (e.g. a figure on a grey disc) are kept
        let lut: Vec<u8> = (0..256).map(|v| ((v as f32 / 255.0).powf(0.45) * 255.0).round() as u8).collect();
        for px in layer.pixels_mut() {
            let mx = px[0].max(px[1]).max(px[2]);
            let mn = px[0].min(px[1]).min(px[2]);
            if mx - mn < 24 {
                *px = Rgba([lut[px[0] as usize], lut[px[1] as usize], lut[px[2] as usize], px[3]]);
            }
        }
    }
    let mostly_light = {
        let opaque: Vec<_> = layer.pixels().filter(|q| q[3] > 127).collect();
        let light = opaque.iter().filter(|q| q[0].min(q[1]).min(q[2]) > 150).count();
        !opaque.is_empty() && light as f32 > 0.5 * opaque.len() as f32
    };
    if p.monochrome && glyph.width() > 0 && glyph.height() > 0 {
        let (mut mask, complex) = monochrome_mask(glyph);
        let ink_dark = 0.2126 * p.ink[0] as f32 + 0.7152 * p.ink[1] as f32 + 0.0722 * p.ink[2] as f32 <= 128.0;
        // IconGen's inverted mask is defined on its circular plate only
        if complex && ink_dark && icon_gen_mode {
            mask = light_mask(&mask, glyph.width(), glyph.height());
        }
        for (px, &m) in layer.pixels_mut().zip(mask.iter()) {
            *px = Rgba([p.ink[0], p.ink[1], p.ink[2], m]);
        }
    }

    // ---- glyph placement
    let (gw, gh) = (glyph.width().max(1) as f32, glyph.height().max(1) as f32);
    let plate_box = {
        let (mut x0, mut y0, mut x1, mut y1) = (size, size, 0u32, 0u32);
        for y in 0..size {
            for x in 0..size {
                if plate[(y * size + x) as usize] > 0.5 {
                    x0 = x0.min(x);
                    y0 = y0.min(y);
                    x1 = x1.max(x + 1);
                    y1 = y1.max(y + 1);
                }
            }
        }
        (x1 > x0 && y1 > y0).then_some((x0, y0, x1, y1))
    };
    let (cx, cy, scale) = if let (Some(ib), Some((x0, y0, x1, y1))) = (inner_box, plate_box) {
        let (tw0, th0) = (tile_dims.0.max(1) as f32, tile_dims.1.max(1) as f32);
        let (bw, bh) = ((ib.2 - ib.0).max(1) as f32, (ib.3 - ib.1).max(1) as f32);
        let k = ((x1 - x0) as f32 / bw).max((y1 - y0) as f32 / bh);
        let icx = (ib.0 + ib.2) as f32 / 2.0 - tw0 / 2.0;
        let icy = (ib.1 + ib.3) as f32 / 2.0 - th0 / 2.0;
        ((x0 + x1) as f32 / 2.0 + icx * k, (y0 + y1) as f32 / 2.0 + icy * k, k)
    } else if fallback {
        (size as f32 / 2.0, size as f32 / 2.0, size as f32 * BARE_LOGO_SCALE / gw.max(gh))
    } else if p.keep_composition {
        let (sw, sh) = (src.width().max(1) as f32, src.height().max(1) as f32);
        let k = size as f32 / sw.max(sh);
        let (ox, oy) = ((size as f32 - sw * k) / 2.0, (size as f32 - sh * k) / 2.0);
        let bx = (glyph_bbox.0 + glyph_bbox.2) as f32 / 2.0;
        let by = (glyph_bbox.1 + glyph_bbox.3) as f32 / 2.0;
        (ox + bx * k, oy + by * k, k)
    } else {
        let longest = size as f32 * GLYPH_SCALE / NATIVE_BACKGROUND_SCALE;
        (size as f32 / 2.0, size as f32 / 2.0, longest / gw.max(gh))
    };
    let scale = scale * p.glyph_scale.clamp(0.2, 3.0);
    let (tw, th) = ((gw * scale).round().max(1.0) as u32, (gh * scale).round().max(1.0) as u32);
    let scaled = resize(&layer, tw, th);
    let cx = cx + p.offset_x * size as f32;
    let cy = cy + p.offset_y * size as f32;
    let ox = (cx - tw as f32 / 2.0).round() as i64;
    let oy = (cy - th as f32 / 2.0).round() as i64;

    // light plate + mostly light glyph: soft dark shadow under the glyph so a
    // white figure stays readable (the glyph keeps its own colours)
    let glyph_shadow: Option<Vec<f32>> = if p.lift_greys && !dark_plate && !p.monochrome && mostly_light {
        let mut a = vec![0.0f32; n * n];
        for y in 0..th {
            for x in 0..tw {
                let (gx, gy) = (ox + x as i64, oy + y as i64 + (size as f32 * 0.012) as i64);
                if gx >= 0 && gy >= 0 && (gx as u32) < size && (gy as u32) < size {
                    a[(gy as u32 * size + gx as u32) as usize] = scaled.get_pixel(x, y)[3] as f32 / 255.0;
                }
            }
        }
        Some(gaussian_blur(&a, n, n, size as f32 * 0.022))
    } else {
        None
    };

    // ---- composite: plate (backdrop tint) then glyph clipped to the plate
    let bd = p.backdrop;
    let mut out = RgbaImage::new(size, size);
    let rim = p.rim.clamp(0.0, 1.0);
    let edge = if rim > 0.0 {
        let blurred = gaussian_blur(&plate, n, n, size as f32 * 0.012);
        Some(blurred)
    } else {
        None
    };
    for y in 0..size {
        for x in 0..size {
            let i = (y * size + x) as usize;
            let m = plate[i];
            if m <= 0.0 {
                continue;
            }
            // premultiplied accumulation
            let pa = bd[3] as f32 / 255.0 * m;
            let mut r = bd[0] as f32 / 255.0 * pa;
            let mut g = bd[1] as f32 / 255.0 * pa;
            let mut b = bd[2] as f32 / 255.0 * pa;
            let mut a = pa;
            if let Some(e) = &edge {
                // inner edge band, brighter towards the top
                let band = (m - e[i]).max(0.0) * 2.0;
                let light = 0.55 + 0.45 * (1.0 - y as f32 / size as f32);
                let ra = (band * light * rim * 0.6).clamp(0.0, 1.0) * m;
                r = ra + r * (1.0 - ra);
                g = ra + g * (1.0 - ra);
                b = ra + b * (1.0 - ra);
                a = ra + a * (1.0 - ra);
            }
            if let Some(sh) = &glyph_shadow {
                let sa = (sh[i] * 0.45).min(1.0) * m;
                r *= 1.0 - sa;
                g *= 1.0 - sa;
                b *= 1.0 - sa;
                a = sa + a * (1.0 - sa);
            }
            let gx = x as i64 - ox;
            let gy = y as i64 - oy;
            if gx >= 0 && gy >= 0 && (gx as u32) < tw && (gy as u32) < th {
                let q = scaled.get_pixel(gx as u32, gy as u32);
                let qa = q[3] as f32 / 255.0 * m;
                r = q[0] as f32 / 255.0 * qa + r * (1.0 - qa);
                g = q[1] as f32 / 255.0 * qa + g * (1.0 - qa);
                b = q[2] as f32 / 255.0 * qa + b * (1.0 - qa);
                a = qa + a * (1.0 - qa);
            }
            if a > 0.0 {
                let un = |v: f32| (v / a * 255.0).round().clamp(0.0, 255.0) as u8;
                out.put_pixel(x, y, Rgba([un(r), un(g), un(b), (a * 255.0).round() as u8]));
            }
        }
    }

    if p.nothing_encode {
        out = nothing_encode(&out);
        notes.push("Codificata per Nothing Launcher (compensazione IconGen)".into());
    } else if p.launcher_shadow {
        let a: Vec<f32> = out.pixels().map(|q| q[3] as f32 / 255.0).collect();
        let s = launcher_shadow(&a, n);
        for (i, px) in out.pixels_mut().enumerate() {
            let av = a[i];
            let sa = s[i] * (1.0 - av);
            let total = av + sa;
            if total > 0.0 {
                let k = av / total;
                *px = Rgba([
                    (px[0] as f32 * k).round() as u8,
                    (px[1] as f32 * k).round() as u8,
                    (px[2] as f32 * k).round() as u8,
                    (total * 255.0).round() as u8,
                ]);
            }
        }
    }
    LucentOutput { image: out, notes }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn icon() -> RgbaImage {
        // rounded square plate (blue) with a white bar glyph; transparent corners
        let mut img = RgbaImage::new(120, 120);
        for y in 0..120u32 {
            for x in 0..120u32 {
                let (dx, dy) = ((x as f32 - 59.5).abs(), (y as f32 - 59.5).abs());
                let inside = dx.max(dy) < 50.0 && !(dx > 35.0 && dy > 35.0 && (dx - 35.0).hypot(dy - 35.0) > 15.0);
                if inside {
                    let glyph = dx < 25.0 && dy < 8.0;
                    img.put_pixel(x, y, if glyph { Rgba([255, 255, 255, 255]) } else { Rgba([30, 80, 220, 255]) });
                }
            }
        }
        img
    }

    #[test]
    fn plate_follows_original_silhouette_and_glyph_is_inked() {
        let src = icon();
        let res = crate::segment::isolate(&src, &crate::segment::SegmentOptions::default());
        let lp = LucentParams { shape: PlateShape::Original, ..LucentParams::dark() };
        let out = render(&src, &res.glyph, res.bbox, 120, &lp);
        // transparent corner of the source stays transparent
        assert_eq!(out.image.get_pixel(12, 12)[3], 0);
        // plate interior: Nothing frosted backdrop alpha 0x66
        let p = out.image.get_pixel(60, 20);
        assert!((p[3] as i32 - 0x66).abs() <= 2, "plate alpha {}", p[3]);
        assert!(p[0] < 5);
        // glyph centre: ink colour, opaque
        let g = out.image.get_pixel(60, 60);
        assert!(g[3] > 240 && g[0] > 230, "glyph {:?}", g);
    }

    #[test]
    fn monochrome_ramp_matches_icongen_formula() {
        // two-tone glyph: modal grey -> 255 alpha; darker tone gets the 45 floor
        let mut g = RgbaImage::new(10, 10);
        for (i, p) in g.pixels_mut().enumerate() {
            *p = if i < 70 { Rgba([200, 200, 200, 255]) } else { Rgba([60, 60, 60, 255]) };
        }
        let (m, complex) = monochrome_mask(&g);
        assert!(!complex);
        assert_eq!(m[0], 255);
        assert_eq!(m[99], 45);
    }

    #[test]
    fn encoder_round_trips_through_launcher_draw() {
        let src = icon();
        let res = crate::segment::isolate(&src, &crate::segment::SegmentOptions::default());
        let target = render(&src, &res.glyph, res.bbox, 96, &LucentParams::dark()).image;
        let encoded = nothing_encode(&target);
        let shown = simulate_launcher(&encoded);
        let mut worst = 0i32;
        for (a, b) in shown.pixels().zip(target.pixels()).filter(|(_, b)| b[3] > 0) {
            worst = worst.max((a[3] as i32 - b[3] as i32).abs());
        }
        assert!(worst <= 3, "alpha error {}", worst);
    }
}
