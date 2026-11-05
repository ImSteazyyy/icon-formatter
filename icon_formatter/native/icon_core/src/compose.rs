//! Glyph placement and composition on a base (image or procedural).

use crate::imageops::{clean_transparent, draw_over, resize, trim};
use crate::segment::{isolate, SegmentOptions, SegmentResult};
use crate::translucent::{render, TranslucentParams};
use image::{Rgba, RgbaImage};
use serde::{Deserialize, Serialize};
use std::sync::Arc;

#[derive(Clone, Copy, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub enum FitMode {
    /// Longest glyph side = glyph_ratio * canvas.
    MaxSide,
    /// sqrt(w*h) = area_ratio * canvas (optical size), capped by MaxSide*1.15.
    Area,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct Placement {
    pub glyph_ratio: f32,
    pub area_ratio: f32,
    pub center_x: f32,
    pub center_y: f32,
    pub fit: FitMode,
    /// Manual corrections.
    pub scale_mul: f32,
    pub offset_x: f32,
    pub offset_y: f32,
}

impl Default for Placement {
    fn default() -> Self {
        // Derived from the reference pack (192 px): glyph long side ~ 124 px,
        // centred at (96, 95.5).
        Placement {
            glyph_ratio: 0.645,
            area_ratio: 0.60,
            center_x: 0.5,
            center_y: 0.497,
            fit: FitMode::MaxSide,
            scale_mul: 1.0,
            offset_x: 0.0,
            offset_y: 0.0,
        }
    }
}

#[derive(Clone)]
pub enum Background {
    Transparent,
    Image(Arc<RgbaImage>),
    Translucent(TranslucentParams),
}

/// Background pre-rendered at the output size (shared across a batch).
pub fn render_background(bg: &Background, size: u32) -> RgbaImage {
    match bg {
        Background::Transparent => RgbaImage::new(size, size),
        Background::Image(img) => resize(img, size, size),
        Background::Translucent(p) => render(size, p),
    }
}

/// Places an already isolated glyph on `canvas`.
pub fn place_glyph(canvas: &mut RgbaImage, glyph: &RgbaImage, pl: &Placement) {
    let size = canvas.width().min(canvas.height()) as f32;
    let Some(g) = trim(glyph) else { return };
    let (gw, gh) = (g.width() as f32, g.height() as f32);
    let max_side = pl.glyph_ratio.clamp(0.05, 1.0) * size;
    let mut scale = match pl.fit {
        FitMode::MaxSide => max_side / gw.max(gh),
        FitMode::Area => (pl.area_ratio.clamp(0.05, 1.0) * size / (gw * gh).sqrt())
            .min(max_side * 1.15 / gw.max(gh)),
    };
    scale *= pl.scale_mul.clamp(0.1, 4.0);
    let tw = (gw * scale).round().max(1.0) as u32;
    let th = (gh * scale).round().max(1.0) as u32;
    let scaled = resize(&g, tw, th);
    let cx = (pl.center_x + pl.offset_x) * canvas.width() as f32;
    let cy = (pl.center_y + pl.offset_y) * canvas.height() as f32;
    let ox = (cx - tw as f32 / 2.0).round() as i32;
    let oy = (cy - th as f32 / 2.0).round() as i32;
    draw_over(canvas, &scaled, ox, oy, 1.0);
}

/// True when the glyph fills its own icon edge to edge (it touches the
/// source's opaque area on at least three sides): such content keeps
/// reaching the plate edge instead of being shrunk to `glyph_ratio`.
pub fn reaches_edges(src: &RgbaImage, bbox: (u32, u32, u32, u32)) -> bool {
    let Some((x0, y0, x1, y1)) = crate::imageops::alpha_bbox(src, 24) else { return false };
    let tol = ((x1 - x0).max(y1 - y0) as f32 * 0.03).max(1.0) as i64;
    let near = |a: u32, b: u32| (a as i64 - b as i64).abs() <= tol;
    [near(bbox.0, x0), near(bbox.1, y0), near(bbox.2, x1), near(bbox.3, y1)].iter().filter(|&&v| v).count() >= 3
}

/// The image cropped to its visible box (alpha > 16), or a copy when it has
/// no transparent margin.
pub fn crop_to_content(img: &RgbaImage) -> RgbaImage {
    match crate::imageops::alpha_bbox(img, 16) {
        Some((x0, y0, x1, y1)) if (x1 - x0, y1 - y0) != img.dimensions() && x1 > x0 + 8 && y1 > y0 + 8 => {
            image::imageops::crop_imm(img, x0, y0, x1 - x0, y1 - y0).to_image()
        }
        _ => img.clone(),
    }
}

/// True when the glyph is itself a filled tile ("icon inside the icon": a
/// rounded square or circle that fills most of its own box). Such glyphs
/// are stretched to the plate edge and clipped by the plate shape.
pub fn is_tile(glyph: &RgbaImage) -> bool {
    let (w, h) = glyph.dimensions();
    if w < 8 || h < 8 {
        return false;
    }
    let aspect = w.max(h) as f32 / w.min(h) as f32;
    let filled = glyph.pixels().filter(|p| p[3] > 127).count() as f32 / (w * h) as f32;
    aspect < 1.25 && filled > 0.80
}

/// Coloured plate with a neutral glyph (e.g. a dark tag on a yellow disc):
/// the glyph becomes the plate's colour and the plate itself is dropped, so
/// on the Lucent plate the symbol keeps the app's colour; holes inside the
/// glyph that showed the plate become transparent. Returns the recoloured
/// glyph cropped to the plate box, the glyph box inside it and the plate box
/// in `img` coordinates. None when the plate is neutral, not a filled
/// disc/rounded square, or the content is itself coloured.
pub fn recolor_on_colored_plate(img: &RgbaImage, force: bool) -> Option<(RgbaImage, (u32, u32, u32, u32), (u32, u32, u32, u32))> {
    let (x0, y0, x1, y1) = crate::imageops::alpha_bbox(img, 127)?;
    let (w, h) = (x1 - x0, y1 - y0);
    if w < 16 || h < 16 || w.max(h) as f32 / w.min(h) as f32 > 1.2 {
        return None;
    }
    let fw = img.width();
    let raw = img.as_raw();
    let mut inside = 0usize;
    for y in y0..y1 {
        for x in x0..x1 {
            if raw[((y * fw + x) * 4 + 3) as usize] > 127 {
                inside += 1;
            }
        }
    }
    // filled disc (pi/4) .. rounded square (~0.95)
    if (inside as f32) < 0.72 * (w * h) as f32 {
        return None;
    }
    let lut = crate::color::linear_lut();
    let lab = crate::color::rgba_to_oklab(raw, &lut);
    // plate colour: mode on a ring just inside the plate edge
    let (cx, cy) = ((x0 + x1) as f32 / 2.0, (y0 + y1) as f32 / 2.0);
    let r = w.min(h) as f32 / 2.0;
    let mut ring: Vec<crate::color::Lab> = Vec::new();
    for k in 0..720 {
        let t = k as f32 / 720.0 * std::f32::consts::TAU;
        for rr in [0.86f32, 0.90] {
            let (x, y) = ((cx + t.cos() * r * rr) as u32, (cy + t.sin() * r * rr) as u32);
            let i = (y * fw + x) as usize;
            if raw[i * 4 + 3] < 200 {
                continue;
            }
            ring.push(lab[i]);
        }
    }
    if ring.len() < 64 {
        return None;
    }
    // plate colour = per-channel median of the ring (robust to the symbol
    // crossing it and to soft gradients / sheens on the plate)
    let plate = lab_median(&ring);
    // the ring must be (mostly) one colour, and a saturated one
    let near = ring
        .iter()
        .filter(|c| ((c.l - plate.0).powi(2) + (c.a - plate.1).powi(2) + (c.b - plate.2).powi(2)).sqrt() < 0.07)
        .count();
    if (near as f32) < 0.6 * ring.len() as f32 {
        return None;
    }
    if plate.1.hypot(plate.2) < 0.07 {
        return None;
    }
    // glyph = pixels clearly different from the plate colour
    let dist = |c: &crate::color::Lab| ((c.l - plate.0).powi(2) + (c.a - plate.1).powi(2) + (c.b - plate.2).powi(2)).sqrt();
    let mut cover = vec![0f32; (w * h) as usize];
    let (mut cnt, mut chroma_sum, mut l_sum) = (0usize, 0f32, 0f32);
    for y in y0..y1 {
        for x in x0..x1 {
            let i = (y * fw + x) as usize;
            if raw[i * 4 + 3] < 128 {
                continue;
            }
            // edge band of the plate (anti-aliasing, outlines, leftover
            // background): never part of the symbol
            let e = (w.min(h) as f32 * 0.045) as u32;
            let edge = [(x.saturating_sub(e), y), ((x + e).min(fw - 1), y), (x, y.saturating_sub(e)), (x, (y + e).min(img.height() - 1))]
                .iter()
                .any(|&(ex, ey)| raw[((ey * fw + ex) * 4 + 3) as usize] < 128);
            if edge {
                continue;
            }
            let d = dist(&lab[i]);
            let t = ((d - 0.06) / 0.10).clamp(0.0, 1.0);
            cover[((y - y0) * w + (x - x0)) as usize] = t;
            if t > 0.5 {
                cnt += 1;
                chroma_sum += lab[i].a.hypot(lab[i].b);
                l_sum += lab[i].l;
            }
        }
    }
    let frac = cnt as f32 / inside.max(1) as f32;
    // a real symbol, and a neutral one (dark/white): coloured artwork stays as it is
    if !(0.03..0.75).contains(&frac) {
        return None;
    }
    // automatic only for a dark or grey neutral symbol (it would turn into a
    // grey smudge on the dark frosted plate); white symbols on coloured plates
    // stay white. `force` (per-app choice) recolours whatever sits on the plate.
    let mean_l = l_sum / cnt.max(1) as f32;
    if !force && (chroma_sum / cnt.max(1) as f32 > 0.06 || mean_l > 0.80) {
        return None;
    }
    // plate colour in sRGB: median of the ring pixels close to the mode
    let mut rs = Vec::new();
    for y in y0..y1 {
        for x in x0..x1 {
            let i = (y * fw + x) as usize;
            if raw[i * 4 + 3] > 200 && dist(&lab[i]) < 0.05 {
                rs.push([raw[i * 4], raw[i * 4 + 1], raw[i * 4 + 2]]);
            }
        }
    }
    if rs.is_empty() {
        return None;
    }
    let med = |c: usize| {
        let mut v: Vec<u8> = rs.iter().map(|p| p[c]).collect();
        v.sort_unstable();
        v[v.len() / 2]
    };
    let col = [med(0), med(1), med(2)];
    let mut out = RgbaImage::new(w, h);
    for y in 0..h {
        for x in 0..w {
            let t = cover[(y * w + x) as usize];
            if t > 0.0 {
                let a = raw[(((y + y0) * fw + x + x0) * 4 + 3) as usize] as f32 / 255.0;
                out.put_pixel(x, y, image::Rgba([col[0], col[1], col[2], (t * a * 255.0).round() as u8]));
            }
        }
    }
    let gb = crate::imageops::alpha_bbox(&out, 32)?;
    let crop = image::imageops::crop_imm(&out, gb.0, gb.1, gb.2 - gb.0, gb.3 - gb.1).to_image();
    Some((crop, gb, (x0, y0, x1, y1)))
}

/// Per-channel median of OKLab samples.
fn lab_median(v: &[crate::color::Lab]) -> (f32, f32, f32) {
    let med = |f: &dyn Fn(&crate::color::Lab) -> f32| {
        let mut c: Vec<f32> = v.iter().map(f).collect();
        c.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
        c[c.len() / 2]
    };
    (med(&|c| c.l), med(&|c| c.a), med(&|c| c.b))
}

/// A tile with a neutral background (e.g. a coloured disc on a dark rounded
/// square): the background connected to the tile border is made transparent,
/// enclosed regions of the same colour (a dark symbol on the disc) are kept.
/// None when the border colour is not neutral or almost nothing is removed.
pub fn strip_border_background(img: &RgbaImage) -> Option<RgbaImage> {
    let (w, h) = img.dimensions();
    if w < 16 || h < 16 {
        return None;
    }
    let lut = crate::color::linear_lut();
    let lab = crate::color::rgba_to_oklab(img.as_raw(), &lut);
    let raw = img.as_raw();
    let band = ((w.min(h) as f32) * 0.08).round().max(2.0) as u32;
    let inset = ((w.min(h) as f32) * 0.06).round() as u32;
    // background colour: median along the ring 6% inside the edge
    let mut ring = Vec::new();
    for y in inset..h - inset {
        for x in inset..w - inset {
            let on = x == inset || y == inset || x + 1 == w - inset || y + 1 == h - inset;
            let i = (y * w + x) as usize;
            if on && raw[i * 4 + 3] > 200 {
                ring.push(lab[i]);
            }
        }
    }
    if ring.len() < 16 {
        return None;
    }
    let bg = lab_median(&ring);
    if bg.1.hypot(bg.2) > 0.04 {
        return None;
    }
    let dist = |c: &crate::color::Lab| ((c.l - bg.0).powi(2) + (c.a - bg.1).powi(2) + (c.b - bg.2).powi(2)).sqrt();
    let n = (w * h) as usize;
    let mut gone = vec![false; n];
    let mut q = std::collections::VecDeque::new();
    for y in 0..h {
        for x in 0..w {
            let near_edge = x < band || y < band || x >= w - band || y >= h - band;
            let i = (y * w + x) as usize;
            if near_edge && (raw[i * 4 + 3] < 128 || dist(&lab[i]) < 0.06) {
                gone[i] = true;
                q.push_back(i);
            }
        }
    }
    while let Some(i) = q.pop_front() {
        let (x, y) = ((i as u32) % w, (i as u32) / w);
        for (dx, dy) in [(-1i32, 0i32), (1, 0), (0, -1), (0, 1)] {
            let (nx, ny) = (x as i32 + dx, y as i32 + dy);
            if nx < 0 || ny < 0 || nx >= w as i32 || ny >= h as i32 {
                continue;
            }
            let j = (ny as u32 * w + nx as u32) as usize;
            if !gone[j] && raw[j * 4 + 3] > 0 && dist(&lab[j]) < 0.06 {
                gone[j] = true;
                q.push_back(j);
            }
        }
    }
    let removed = (0..n).filter(|&i| gone[i] && raw[i * 4 + 3] > 127).count();
    if removed < n / 20 {
        return None;
    }
    let mut out = img.clone();
    for (i, p) in out.pixels_mut().enumerate() {
        if gone[i] {
            p[3] = 0;
        }
    }
    Some(out)
}

/// "Icon inside the icon": when the glyph is a filled tile, its own
/// background is removed too. Returns the inner content and its box inside
/// the tile, or None when there is no inner plate to strip.
pub fn unwrap_tile(glyph: &RgbaImage) -> Option<(RgbaImage, (u32, u32, u32, u32))> {
    if !is_tile(glyph) {
        return None;
    }
    let (w, h) = glyph.dimensions();
    let lut = crate::color::linear_lut();
    let lab: Vec<crate::color::Lab> = crate::color::rgba_to_oklab(glyph.as_raw(), &lut);
    // the tile may itself be translucent: normalise its alpha
    let mut al: Vec<u8> = glyph.pixels().map(|p| p[3]).filter(|&a| a > 8).collect();
    al.sort_unstable();
    let level = al.get(al.len() * 3 / 4).copied().unwrap_or(255).max(32) as f32;
    // background = most frequent colour on a ring 6% inside the tile edge
    let inset = ((w.min(h) as f32) * 0.06).round() as u32;
    let mut bins: std::collections::HashMap<(i32, i32, i32), (u32, f32, f32, f32)> = Default::default();
    for y in inset..h.saturating_sub(inset) {
        for x in inset..w.saturating_sub(inset) {
            let on_ring = x == inset || y == inset || x + 1 == w - inset || y + 1 == h - inset;
            let i = (y * w + x) as usize;
            if !on_ring || (glyph.as_raw()[i * 4 + 3] as f32) < level * 0.5 {
                continue;
            }
            let c = lab[i];
            let k = ((c.l * 40.0) as i32, (c.a * 40.0) as i32, (c.b * 40.0) as i32);
            let e = bins.entry(k).or_insert((0, 0.0, 0.0, 0.0));
            e.0 += 1;
            e.1 += c.l;
            e.2 += c.a;
            e.3 += c.b;
        }
    }
    let (n, sl, sa, sb) = bins.values().max_by_key(|v| v.0).copied()?;
    let bg = (sl / n as f32, sa / n as f32, sb / n as f32);
    // only a neutral (grey/black) inner plate is treated as background:
    // coloured full-bleed artwork is kept as it is
    if bg.1.hypot(bg.2) > 0.04 {
        return None;
    }
    // glossy rim of the tile: drop a thin band along its edge (the inner box
    // is the tile shrunk by `rim`, so edge content still reaches the plate)
    let rim = ((w.min(h) as f32) * 0.035).round() as u32;
    // background region of the old tile: grown from pixels matching the
    // background colour, following smooth gradients (shadows, vignettes)
    // and stopping at object edges, so every object (key, disc, road) is
    // kept or removed as a whole
    let n = (w * h) as usize;
    let mut bgm = vec![false; n];
    let mut queue = std::collections::VecDeque::new();
    let dist = |c: &crate::color::Lab, d: (f32, f32, f32)| ((c.l - d.0).powi(2) + (c.a - d.1).powi(2) + (c.b - d.2).powi(2)).sqrt();
    for y in rim..h.saturating_sub(rim) {
        for x in rim..w.saturating_sub(rim) {
            let i = (y * w + x) as usize;
            // seeds: background colour, or anything darker and neutral (seams, shadows)
            if dist(&lab[i], bg) < 0.05 || (lab[i].l <= bg.0 + 0.02 && lab[i].a.hypot(lab[i].b) < 0.06) {
                bgm[i] = true;
                queue.push_back(i);
            }
        }
    }
    while let Some(i) = queue.pop_front() {
        let (x, y) = ((i as u32) % w, (i as u32) / w);
        let c = lab[i];
        for (dx, dy) in [(-1i32, 0i32), (1, 0), (0, -1), (0, 1)] {
            let (nx, ny) = (x as i32 + dx, y as i32 + dy);
            if nx < rim as i32 || ny < rim as i32 || nx >= (w - rim) as i32 || ny >= (h - rim) as i32 {
                continue;
            }
            let j = (ny as u32 * w + nx as u32) as usize;
            if bgm[j] {
                continue;
            }
            let cn = lab[j];
            // smooth step from the current pixel, and not too far from the background
            if dist(&cn, (c.l, c.a, c.b)) < 0.012 && cn.l < bg.0 + 0.22 {
                bgm[j] = true;
                queue.push_back(j);
            }
        }
    }
    // drop isolated specks (tiny kept components)
    let fg: Vec<bool> = bgm.iter().map(|&b| !b).collect();
    let (labels, sizes) = crate::imageops::components(&fg, w as usize, h as usize);
    let min_size = (n as f32 * 0.0006) as usize;
    let key: Vec<f32> = (0..n)
        .map(|i| if !fg[i] { 0.0 } else if labels[i] > 0 && sizes[labels[i] as usize] < min_size { 0.0 } else { 1.0 })
        .collect();
    // background in sRGB (for edge un-mixing): OKLab L of a neutral -> sRGB
    let bg_rgb = {
        let lin = bg.0.powi(3);
        let v = if lin <= 0.003_130_8 { lin * 12.92 } else { 1.055 * lin.powf(1.0 / 2.4) - 0.055 };
        v * 255.0
    };
    let sigma = (w.min(h) as f32 * 0.004).max(1.0);
    // reference lightness of neutral objects (roads, keys): 90th percentile
    let mut nl: Vec<f32> = (0..n).filter(|&i| key[i] > 0.5 && lab[i].a.hypot(lab[i].b) < 0.03).map(|i| lab[i].l).collect();
    nl.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
    let obj_l = nl.get(nl.len() * 9 / 10).copied().unwrap_or(1.0).max(bg.0 + 0.05);
    let zone = crate::lucent::gaussian_blur(&key, w as usize, h as usize, (w.min(h) as f32 * 0.012).max(2.0));
    let core = key.clone();
    let fg_keep = |i: usize| core[i] > 0.5;
    let key = crate::lucent::gaussian_blur(&key, w as usize, h as usize, sigma);
    let mut out = RgbaImage::new(w, h);
    let mut kept = 0u32;
    for y in rim..h.saturating_sub(rim) {
        for x in rim..w.saturating_sub(rim) {
            let i = (y * w + x) as usize;
            let p = glyph.get_pixel(x, y);
            // edge moved slightly inwards: drops the dark fringe objects had
            // against the old tile
            let t = ((key[i] - 0.55) / 0.3).clamp(0.0, 1.0);
            let k = t * t * (3.0 - 2.0 * t);
            let base_a = (p[3] as f32 / level).min(1.0);
            let a = (base_a * k * 255.0).round() as u8;
            if a > 127 {
                kept += 1;
            }
            // soft (blurry) edge of a neutral object: alpha follows its own
            // lightness ramp over the dark tile, colour un-mixed from it
            let c = lab[i];
            if !bgm[i] && fg_keep(i) {
                // object core: untouched
                // anti-aliased rim from the blurred mask (no stair-steps)
                let t = ((key[i] - 0.25) / 0.5).clamp(0.0, 1.0);
                let ka = t * t * (3.0 - 2.0 * t);
                out.put_pixel(x, y, Rgba([p[0], p[1], p[2], (base_a * ka * 255.0).round() as u8]));
                continue;
            }
            if bgm[i] && zone[i] > 0.02 && c.a.hypot(c.b) < 0.03 {
                let la = ((c.l - bg.0) / (obj_l - bg.0)).clamp(0.0, 1.0);
                let la = la * la * (3.0 - 2.0 * la);
                if la > 0.02 {
                    let un = |v: u8| ((v as f32 - bg_rgb * (1.0 - la)) / la).clamp(0.0, 255.0) as u8;
                    let aa = (base_a * la * 255.0).round() as u8;
                    out.put_pixel(x, y, Rgba([un(p[0]), un(p[1]), un(p[2]), aa]));
                } else {
                    out.put_pixel(x, y, Rgba([0, 0, 0, 0]));
                }
                continue;
            }
            if k > 0.02 && k < 0.98 {
                // edge pixel mixed with the old dark tile: un-mix it from the
                // background colour so the edge is not "burnt"
                let un = |v: u8| ((v as f32 - bg_rgb * (1.0 - k)) / k).clamp(0.0, 255.0) as u8;
                out.put_pixel(x, y, Rgba([un(p[0]), un(p[1]), un(p[2]), a]));
                continue;
            }
            out.put_pixel(x, y, Rgba([p[0], p[1], p[2], a]));
        }
    }
    let inner_area = ((w - 2 * rim) * (h - 2 * rim)) as f32;
    if (kept as f32) < 0.01 * inner_area || (kept as f32) > 0.92 * inner_area {
        return None;
    }
    // content box = the tile minus the rim (keeps edge content on the edge)
    let content = crate::imageops::crop(&out, rim, rim, w - rim, h - rim);
    Some((content, (rim, rim, w - rim, h - rim)))
}

/// Places the glyph and clips it to the background silhouette: whatever
/// exceeds the plate below is cut away. Edge-to-edge content is mapped with
/// the source's own proportions so it still reaches the plate edge.
pub fn place_on_plate(canvas: &mut RgbaImage, src: &RgbaImage, res: &SegmentResult, pl: &Placement) {
    let size = canvas.width();
    // plate coverage (0..255), normalised by the plate's own alpha level so a
    // semi-transparent base clips by shape without fading the glyph
    let mut levels: Vec<u8> = canvas.pixels().map(|p| p[3]).filter(|&a| a > 8).collect();
    levels.sort_unstable();
    let level = levels.get(levels.len() * 3 / 4).copied().unwrap_or(255).max(32) as f32;
    let plate: Vec<u8> = canvas
        .pixels()
        .map(|p| ((p[3] as f32 - 0.35 * level) / (0.5 * level)).clamp(0.0, 1.0))
        .map(|t| (t * t * (3.0 - 2.0 * t) * 255.0).round() as u8)
        .collect();
    let covered = plate.iter().filter(|&&a| a > 127).count() as f32 / plate.len().max(1) as f32;
    let mut layer = RgbaImage::new(size, canvas.height());
    let tile = is_tile(&res.glyph);
    // a full-tile source (launcher icon) is unwrapped as a whole
    let src_c = crop_to_content(src);
    let src_tile = covered > 0.2 && is_tile(&src_c);
    let recolored = if covered > 0.2 && !src_tile { recolor_on_colored_plate(src, false) } else { None };
    let recolored_dims = recolored.as_ref().map(|r| (r.2 .2 - r.2 .0, r.2 .3 - r.2 .1));
    let unwrapped = if !(covered > 0.2) {
        None
    } else if let Some((g, gb, _)) = recolored {
        Some((g, gb))
    } else if src_tile {
        unwrap_tile(&src_c)
    } else {
        unwrap_tile(&res.glyph)
    };
    let tile_img = if src_tile && unwrapped.is_some() { &src_c } else { &res.glyph };
    if let Some((inner, ib)) = &unwrapped {
        // tile box -> plate box (cover); inner content keeps its position in the tile
        let (px0, py0, px1, py1) = crate::imageops::alpha_bbox(canvas, (level * 0.6) as u8).unwrap_or((0, 0, size, canvas.height()));
        let (tw0, th0) = match recolored_dims {
            Some((a, b)) => (a as f32, b as f32),
            None => (tile_img.width() as f32, tile_img.height() as f32),
        };
        // the content box (tile minus its glossy rim) covers the plate box
        let (bw, bh) = ((ib.2 - ib.0).max(1) as f32, (ib.3 - ib.1).max(1) as f32);
        let k = ((px1 - px0) as f32 / bw).max((py1 - py0) as f32 / bh) * pl.scale_mul.clamp(0.1, 4.0);
        let (iw, ih) = (inner.width() as f32, inner.height() as f32);
        let (tw, th) = ((iw * k).round().max(1.0) as u32, (ih * k).round().max(1.0) as u32);
        let scaled = resize(inner, tw, th);
        let icx = (ib.0 + ib.2) as f32 / 2.0 - tw0 / 2.0;
        let icy = (ib.1 + ib.3) as f32 / 2.0 - th0 / 2.0;
        let cx = (px0 + px1) as f32 / 2.0 + icx * k + pl.offset_x * size as f32;
        let cy = (py0 + py1) as f32 / 2.0 + icy * k + pl.offset_y * size as f32;
        draw_over(&mut layer, &scaled, (cx - tw as f32 / 2.0).round() as i32, (cy - th as f32 / 2.0).round() as i32, 1.0);
    } else if (tile || reaches_edges(src, res.bbox)) && covered > 0.2 {
        // map the source's opaque box onto the plate's box
        let (sx0, sy0, sx1, sy1) = crate::imageops::alpha_bbox(src, 24).unwrap_or((0, 0, src.width(), src.height()));
        let (px0, py0, px1, py1) = crate::imageops::alpha_bbox(canvas, (level * 0.6) as u8).unwrap_or((0, 0, size, canvas.height()));
        // a tile fills the plate box itself (cover); edge-to-edge art keeps
        // the source's proportions relative to its own opaque box
        let (sx0, sy0, sx1, sy1) = if tile { res.bbox } else { (sx0, sy0, sx1, sy1) };
        let (rx, ry) = ((px1 - px0) as f32 / (sx1 - sx0).max(1) as f32, (py1 - py0) as f32 / (sy1 - sy0).max(1) as f32);
        let k = if tile { rx.max(ry) } else { rx.min(ry) } * pl.scale_mul.clamp(0.1, 4.0);
        let (gw, gh) = (res.glyph.width() as f32, res.glyph.height() as f32);
        let (tw, th) = ((gw * k).round().max(1.0) as u32, (gh * k).round().max(1.0) as u32);
        let scaled = resize(&res.glyph, tw, th);
        let scx = (sx0 + sx1) as f32 / 2.0;
        let scy = (sy0 + sy1) as f32 / 2.0;
        let gcx = (res.bbox.0 + res.bbox.2) as f32 / 2.0;
        let gcy = (res.bbox.1 + res.bbox.3) as f32 / 2.0;
        let cx = (px0 + px1) as f32 / 2.0 + (gcx - scx) * k + pl.offset_x * size as f32;
        let cy = (py0 + py1) as f32 / 2.0 + (gcy - scy) * k + pl.offset_y * size as f32;
        draw_over(&mut layer, &scaled, (cx - tw as f32 / 2.0).round() as i32, (cy - th as f32 / 2.0).round() as i32, 1.0);
    } else {
        place_glyph(&mut layer, &res.glyph, pl);
    }
    if covered > 0.2 {
        for (q, &a) in layer.pixels_mut().zip(plate.iter()) {
            q[3] = (q[3] as u32 * a as u32 / 255) as u8;
        }
    }
    draw_over(canvas, &layer, 0, 0, 1.0);
}

/// Full pipeline for one icon: isolate -> scale/centre -> compose.
pub fn compose_icon(
    src: &RgbaImage,
    background: &RgbaImage,
    placement: &Placement,
    seg: &SegmentOptions,
) -> (RgbaImage, SegmentResult) {
    let res = isolate(src, seg);
    let mut canvas = background.clone();
    place_on_plate(&mut canvas, src, &res, placement);
    clean_transparent(&mut canvas);
    (canvas, res)
}

#[cfg(test)]
mod tests {
    use super::*;
    use image::Rgba;

    #[test]
    fn glyph_is_scaled_and_centred() {
        let mut src = RgbaImage::from_pixel(300, 300, Rgba([255, 255, 255, 255]));
        for y in 100..200 {
            for x in 50..250 {
                src.put_pixel(x, y, Rgba([0, 0, 255, 255]));
            }
        }
        let bg = render_background(&Background::Transparent, 200);
        let (out, res) = compose_icon(&src, &bg, &Placement::default(), &SegmentOptions::default());
        assert_eq!(res.bbox, (50, 100, 250, 200));
        let bb = crate::imageops::alpha_bbox(&out, 128).unwrap();
        let w = bb.2 - bb.0;
        assert!((128..=130).contains(&w), "width {}", w);
        let cx = (bb.0 + bb.2) as f32 / 2.0;
        assert!((cx - 100.0).abs() <= 1.0);
        assert_eq!(out.get_pixel(100, 99).0, [0, 0, 255, 255]);
    }

    #[test]
    fn edge_to_edge_glyph_fills_plate_and_is_clipped() {
        // full-bleed artwork (stripes to every edge) on a semi-transparent squircle base
        let mut src = RgbaImage::new(100, 100);
        for (x, _, p) in src.enumerate_pixels_mut() {
            *p = if (x / 10) % 2 == 0 { Rgba([220, 30, 30, 255]) } else { Rgba([30, 30, 220, 255]) };
        }
        let mask = crate::squircle::mask(120, &crate::squircle::Shape::default());
        let mut bg = RgbaImage::new(120, 120);
        for (p, &m) in bg.pixels_mut().zip(mask.iter()) {
            *p = Rgba([0, 0, 0, (m as u32 * 140 / 255) as u8]);
        }
        let (out, res) = compose_icon(&src, &bg, &Placement::default(), &SegmentOptions::default());
        assert!(reaches_edges(&src, res.bbox));
        assert_eq!(out.get_pixel(1, 1)[3], 0, "corner outside the plate is clipped");
        let edge = out.get_pixel(60, 7);
        assert!(edge[3] > 200 && (edge[0] > 150 || edge[2] > 150), "content reaches the plate edge: {:?}", edge);
    }

    fn disc_with_bar(bar: [u8; 3]) -> RgbaImage {
        let mut img = RgbaImage::new(100, 100);
        for y in 0..100u32 {
            for x in 0..100u32 {
                let (dx, dy) = (x as f32 - 49.5, y as f32 - 49.5);
                if dx.hypot(dy) < 46.0 {
                    let on_bar = dx.abs() < 24.0 && dy.abs() < 9.0 && !(dx.abs() < 5.0 && dy.abs() < 4.0);
                    img.put_pixel(x, y, if on_bar { Rgba([bar[0], bar[1], bar[2], 255]) } else { Rgba([248, 186, 28, 255]) });
                }
            }
        }
        img
    }

    #[test]
    fn dark_symbol_on_coloured_disc_takes_the_plate_colour() {
        let (g, gb, pb) = recolor_on_colored_plate(&disc_with_bar([40, 40, 46]), false).expect("recoloured");
        assert!(pb.2 - pb.0 >= 90);
        // the bar is now yellow, the hole in it is transparent
        let c = g.get_pixel(3, g.height() / 2);
        assert!(c[3] > 200 && c[0] > 230 && c[1] > 160 && c[2] < 60, "{:?}", c);
        let hole = g.get_pixel(g.width() / 2, g.height() / 2);
        assert!(hole[3] < 40, "hole {:?}", hole);
        assert!(gb.2 - gb.0 > 40);
        // a white symbol is left white in automatic mode, recoloured when forced
        assert!(recolor_on_colored_plate(&disc_with_bar([255, 255, 255]), false).is_none());
        assert!(recolor_on_colored_plate(&disc_with_bar([255, 255, 255]), true).is_some());
    }

    #[test]
    fn mid_grey_symbol_and_soft_sheen_are_recoloured() {
        // a mid-grey symbol (an Android robot style) on a disc with a sheen
        let mut img = disc_with_bar([104, 104, 104]);
        for (y, row) in img.enumerate_rows_mut() {
            for (_, _, p) in row {
                if p[3] > 0 && p[2] < 60 {
                    let k = 1.0 + 0.12 * (0.5 - y as f32 / 100.0);
                    for c in 0..2 {
                        p[c] = (p[c] as f32 * k).min(255.0) as u8;
                    }
                }
            }
        }
        let (g, _, _) = recolor_on_colored_plate(&img, false).expect("recoloured");
        let c = g.get_pixel(3, g.height() / 2);
        assert!(c[0] > 200 && c[2] < 80, "{:?}", c);
    }

    #[test]
    fn coloured_disc_on_a_dark_tile_is_found() {
        // dark tile, yellow disc, dark bar on the disc
        let d = disc_with_bar([40, 40, 46]);
        let (w, h) = d.dimensions();
        let mut tile = RgbaImage::from_pixel(w + 40, h + 40, Rgba([30, 30, 30, 255]));
        image::imageops::overlay(&mut tile, &d, 20, 20);
        assert!(recolor_on_colored_plate(&tile, false).is_none());
        let stripped = strip_border_background(&tile).expect("background stripped");
        // the dark bar enclosed by the disc is kept
        assert!(stripped.get_pixel(w / 2 + 20 - 15, h / 2 + 20)[3] > 200);
        assert!(recolor_on_colored_plate(&stripped, false).is_some());
    }

    #[test]
    fn tile_with_transparent_margin_is_still_a_tile() {
        // launcher-style full tile drawn at 70% of a transparent canvas
        let mut img = RgbaImage::new(200, 200);
        for y in 30..170u32 {
            for x in 30..170u32 {
                img.put_pixel(x, y, Rgba([90, 90, 96, 255]));
            }
        }
        assert!(!is_tile(&img));
        let c = crop_to_content(&img);
        assert_eq!(c.dimensions(), (140, 140));
        assert!(is_tile(&c));
    }
}
