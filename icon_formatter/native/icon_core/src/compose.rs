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
    let key = crate::lucent::gaussian_blur(&key, w as usize, h as usize, sigma);
    let mut out = RgbaImage::new(w, h);
    let mut kept = 0u32;
    for y in rim..h.saturating_sub(rim) {
        for x in rim..w.saturating_sub(rim) {
            let i = (y * w + x) as usize;
            let p = glyph.get_pixel(x, y);
            let t = ((key[i] - 0.35) / 0.3).clamp(0.0, 1.0);
            let k = t * t * (3.0 - 2.0 * t);
            let base_a = (p[3] as f32 / level).min(1.0);
            let a = (base_a * k * 255.0).round() as u8;
            if a > 127 {
                kept += 1;
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
    let unwrapped = if covered > 0.2 { unwrap_tile(&res.glyph) } else { None };
    if let Some((inner, ib)) = &unwrapped {
        // tile box -> plate box (cover); inner content keeps its position in the tile
        let (px0, py0, px1, py1) = crate::imageops::alpha_bbox(canvas, (level * 0.6) as u8).unwrap_or((0, 0, size, canvas.height()));
        let (tw0, th0) = (res.glyph.width() as f32, res.glyph.height() as f32);
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
}
