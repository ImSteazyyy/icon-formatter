//! Glyph / logo isolation.
//!
//! Strategy (no ML model required, deterministic and fast):
//! 1. Initial background:
//!    * transparent surround -> transparent pixels;
//!    * opaque image -> flood fill from the border using colour clusters of
//!      the border (k-means in OKLab + alpha) with a strict tolerance and a
//!      "drift" tolerance that only follows smooth gradients.
//! 2. Plate stripping: if what remains is a large shape whose rim has a
//!    uniform colour (a rounded square / squircle / circle "plate", also
//!    semi-transparent ones like the reference pack), it is flood-filled away
//!    from its rim, once (inner discs that belong to the logo are kept).
//! 3. Enclosed background-coloured regions (holes in "O", "A", ...) are
//!    optionally removed; large removals are flagged as ambiguous.
//! 4. Tiny specks are removed, small pinholes filled.
//! 5. Edge refinement: boundary pixels are un-mixed in premultiplied RGBA
//!    space against the local background so anti-aliasing survives without
//!    colour halos.
//!
//! The flood fill only follows *connected* similar pixels, so glyph parts
//! whose colour is close to the background survive whenever they are
//! separated by an edge; risky cases are reported via `ambiguous`.

use crate::color::{linear_lut, rgba_to_oklab, Lab};
use crate::imageops::{alpha_bbox, components, crop, distance_from};
use image::RgbaImage;
use serde::{Deserialize, Serialize};
use std::collections::VecDeque;

#[derive(Clone, Copy, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub enum SegmentMode {
    /// Detect transparency / plates / opaque backgrounds automatically.
    Auto,
    /// Trust the alpha channel as is (only trims).
    KeepAlpha,
    /// Always remove the background by border flood fill, even with alpha.
    RemoveBackground,
    /// No isolation: the whole image is the glyph.
    None,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct SegmentOptions {
    pub mode: SegmentMode,
    /// Colour tolerance in OKLab units (0.02 .. 0.35). Default 0.10.
    pub tolerance: f32,
    /// Remove enclosed background-coloured regions (holes).
    pub remove_holes: bool,
    /// Components smaller than this fraction of the image are discarded.
    pub min_component: f32,
    /// Un-mix anti-aliased boundary pixels.
    pub refine_edges: bool,
}

impl Default for SegmentOptions {
    fn default() -> Self {
        SegmentOptions {
            mode: SegmentMode::Auto,
            tolerance: 0.10,
            remove_holes: true,
            min_component: 0.0004,
            refine_edges: true,
        }
    }
}

#[derive(Clone, Debug)]
pub struct SegmentResult {
    /// Cropped glyph with real alpha.
    pub glyph: RgbaImage,
    /// Glyph bbox in source coordinates (x0, y0, x1, y1), exclusive end.
    pub bbox: (u32, u32, u32, u32),
    pub source_size: (u32, u32),
    /// 0..1, heuristic quality estimate.
    pub confidence: f32,
    /// True when a manual check is recommended.
    pub ambiguous: bool,
    pub method: String,
    pub notes: Vec<String>,
}

#[derive(Clone, Copy, Debug)]
struct Model {
    lab: Lab,
    alpha: f32, // 0..1
}

#[inline]
fn dist(lab: &[Lab], alpha: &[u8], i: usize, m: &Model) -> f32 {
    let a = alpha[i] as f32 / 255.0;
    if a < 0.06 && m.alpha < 0.06 {
        return 0.0;
    }
    lab[i].dist(&m.lab) + (a - m.alpha).abs() * 0.5
}

#[inline]
fn dist_px(lab: &[Lab], alpha: &[u8], i: usize, j: usize) -> f32 {
    let (ai, aj) = (alpha[i] as f32 / 255.0, alpha[j] as f32 / 255.0);
    if ai < 0.06 && aj < 0.06 {
        return 0.0;
    }
    lab[i].dist(&lab[j]) + (ai - aj).abs() * 0.5
}

fn nearest(lab: &[Lab], alpha: &[u8], i: usize, models: &[Model]) -> f32 {
    models.iter().map(|m| dist(lab, alpha, i, m)).fold(f32::MAX, f32::min)
}

fn border_indices(w: usize, h: usize) -> Vec<usize> {
    let mut v = Vec::with_capacity(2 * (w + h));
    for x in 0..w {
        v.push(x);
        v.push((h - 1) * w + x);
    }
    for y in 1..h.saturating_sub(1) {
        v.push(y * w);
        v.push(y * w + w - 1);
    }
    v
}

/// k-means (k <= 3) over OKLab + alpha of the given pixels.
fn clusters(lab: &[Lab], alpha: &[u8], idx: &[usize], k: usize) -> Vec<(Model, f32)> {
    if idx.is_empty() {
        return vec![];
    }
    let pts: Vec<[f32; 4]> = idx
        .iter()
        .map(|&i| [lab[i].l, lab[i].a, lab[i].b, alpha[i] as f32 / 255.0 * 0.5])
        .collect();
    let d2 = |a: &[f32; 4], b: &[f32; 4]| {
        (0..4).map(|c| (a[c] - b[c]) * (a[c] - b[c])).sum::<f32>()
    };
    // farthest-point init
    let mut cents: Vec<[f32; 4]> = vec![pts[0]];
    while cents.len() < k {
        let far = pts
            .iter()
            .max_by(|a, b| {
                let da = cents.iter().map(|c| d2(a, c)).fold(f32::MAX, f32::min);
                let db = cents.iter().map(|c| d2(b, c)).fold(f32::MAX, f32::min);
                da.partial_cmp(&db).unwrap()
            })
            .copied()
            .unwrap();
        cents.push(far);
    }
    let mut assign = vec![0usize; pts.len()];
    for _ in 0..10 {
        for (pi, p) in pts.iter().enumerate() {
            assign[pi] = (0..cents.len())
                .min_by(|&a, &b| d2(p, &cents[a]).partial_cmp(&d2(p, &cents[b])).unwrap())
                .unwrap();
        }
        let mut sums = vec![[0f32; 5]; cents.len()];
        for (pi, p) in pts.iter().enumerate() {
            let s = &mut sums[assign[pi]];
            for c in 0..4 {
                s[c] += p[c];
            }
            s[4] += 1.0;
        }
        for (ci, s) in sums.iter().enumerate() {
            if s[4] > 0.0 {
                cents[ci] = [s[0] / s[4], s[1] / s[4], s[2] / s[4], s[3] / s[4]];
            }
        }
    }
    let mut counts = vec![0usize; cents.len()];
    for a in &assign {
        counts[*a] += 1;
    }
    cents
        .iter()
        .zip(counts)
        .map(|(c, n)| {
            (
                Model { lab: Lab { l: c[0], a: c[1], b: c[2] }, alpha: (c[3] * 2.0).clamp(0.0, 1.0) },
                n as f32 / pts.len() as f32,
            )
        })
        .collect()
}

/// Median model of the given pixels (robust to a few glyph pixels).
fn median_model(lab: &[Lab], alpha: &[u8], idx: &[usize]) -> Model {
    let med = |mut v: Vec<f32>| {
        v.sort_by(|a, b| a.partial_cmp(b).unwrap());
        v[v.len() / 2]
    };
    Model {
        lab: Lab {
            l: med(idx.iter().map(|&i| lab[i].l).collect()),
            a: med(idx.iter().map(|&i| lab[i].a).collect()),
            b: med(idx.iter().map(|&i| lab[i].b).collect()),
        },
        alpha: med(idx.iter().map(|&i| alpha[i] as f32 / 255.0).collect()),
    }
}

/// Flood fill from `seeds`, restricted to `allowed`, marking `bg`.
#[allow(clippy::too_many_arguments)]
fn flood(
    lab: &[Lab],
    alpha: &[u8],
    w: usize,
    h: usize,
    seeds: &[usize],
    allowed: &dyn Fn(usize) -> bool,
    models: &[Model],
    tol: f32,
    bg: &mut [bool],
) {
    let strict = tol;
    let drift = tol * 2.5;
    let step = tol * 0.35;
    let mut q: VecDeque<usize> = VecDeque::new();
    for &s in seeds {
        if !bg[s] && allowed(s) && nearest(lab, alpha, s, models) <= strict {
            bg[s] = true;
            q.push_back(s);
        }
    }
    while let Some(i) = q.pop_front() {
        let (x, y) = (i % w, i / w);
        let mut nb = [usize::MAX; 4];
        if x > 0 {
            nb[0] = i - 1;
        }
        if x + 1 < w {
            nb[1] = i + 1;
        }
        if y > 0 {
            nb[2] = i - w;
        }
        if y + 1 < h {
            nb[3] = i + w;
        }
        for &j in nb.iter() {
            if j == usize::MAX || bg[j] || !allowed(j) {
                continue;
            }
            let dm = nearest(lab, alpha, j, models);
            // drift follows shading (lightness) of a background, never into
            // another hue: a light colour next to white (Google's yellow)
            // is reached through the soft edge in small steps otherwise
            let same_hue = || {
                models.iter().any(|m| {
                    let (da, db) = (lab[j].a - m.lab.a, lab[j].b - m.lab.b);
                    (da * da + db * db).sqrt() <= strict
                })
            };
            if dm <= strict || (dm <= drift && dist_px(lab, alpha, i, j) <= step && same_hue()) {
                bg[j] = true;
                q.push_back(j);
            }
        }
    }
}

pub fn isolate(img: &RgbaImage, opt: &SegmentOptions) -> SegmentResult {
    let (w32, h32) = img.dimensions();
    let (w, h) = (w32 as usize, h32 as usize);
    let n = w * h;
    let mut notes = Vec::new();
    let tol = opt.tolerance.clamp(0.02, 0.35);

    let passthrough = |method: &str, notes: Vec<String>| -> SegmentResult {
        let bbox = alpha_bbox(img, 8).unwrap_or((0, 0, w32, h32));
        SegmentResult {
            glyph: crop(img, bbox.0, bbox.1, bbox.2, bbox.3),
            bbox,
            source_size: (w32, h32),
            confidence: 1.0,
            ambiguous: false,
            method: method.into(),
            notes,
        }
    };

    if w < 3 || h < 3 {
        return passthrough("none", vec!["image too small to segment".into()]);
    }
    match opt.mode {
        SegmentMode::None => return passthrough("none", notes),
        SegmentMode::KeepAlpha => return passthrough("alpha", notes),
        _ => {}
    }

    let buf = img.as_raw();
    let lut = linear_lut();
    let lab = rgba_to_oklab(buf, &lut);
    let alpha: Vec<u8> = buf.chunks_exact(4).map(|p| p[3]).collect();
    let border = border_indices(w, h);
    let transparent_border =
        border.iter().filter(|&&i| alpha[i] < 16).count() as f32 / border.len() as f32;

    let mut bg = vec![false; n];
    let mut models: Vec<Model> = Vec::new();
    let mut border_uniform = 1.0f32;
    let mut method = String::new();

    // already cut out (transparent surroundings): there is no background to
    // remove, also with "always remove background" — removing colours similar
    // to a guessed background would erase white/coloured glyphs (Camera, Chrome)
    if transparent_border > 0.6 {
        if opt.mode == SegmentMode::RemoveBackground {
            notes.push("sfondo già trasparente: rimozione saltata".into());
        }
        for i in 0..n {
            bg[i] = alpha[i] < 16;
        }
        models.push(Model { lab: Lab::default(), alpha: 0.0 });
        method.push_str("alpha");
    } else {
        let cl = clusters(&lab, &alpha, &border, 3);
        models = cl.iter().filter(|(_, share)| *share >= 0.08).map(|(m, _)| *m).collect();
        if models.is_empty() {
            models = cl.iter().map(|(m, _)| *m).collect();
        }
        border_uniform = border
            .iter()
            .filter(|&&i| nearest(&lab, &alpha, i, &models) <= tol)
            .count() as f32
            / border.len() as f32;
        flood(&lab, &alpha, w, h, &border, &|_| true, &models, tol, &mut bg);
        method.push_str("background");
        if border_uniform < 0.7 {
            notes.push(format!(
                "busy background: only {:.0}% of the border matches the background colours",
                border_uniform * 100.0
            ));
        }
    }

    // Plate stripping: a single plate. Outer margins of opaque images are
    // already removed by the border flood above; stripping a second plate
    // would eat inner logo parts (e.g. a clock face inside a coloured disc).
    let mut plate_removed = false;
    for _ in 0..1 {
        let fg_count = bg.iter().filter(|b| !**b).count();
        if (fg_count as f32) < 0.40 * n as f32 {
            break;
        }
        let d = distance_from(&bg, w, h);
        let ring_w = (w.min(h) as f32 * 0.04).max(2.0);
        // sample past the rim (highlights / borders of the plate)
        let ring_start = (w.min(h) as f32 * 0.03).max(1.5);
        let ring: Vec<usize> = (0..n)
            .filter(|&i| !bg[i] && d[i] >= ring_start && d[i] <= ring_start + ring_w)
            .collect();
        if ring.len() < 16 {
            break;
        }
        let model = median_model(&lab, &alpha, &ring);
        // a plate is one flat colour: judged with a strict tolerance, not the
        // (possibly high) background sensitivity, or a multicolour logo ring
        // (Chrome) passes as "uniform" and the whole logo is erased
        let ptol = tol.min(0.10);
        let uniform = ring.iter().filter(|&&i| dist(&lab, &alpha, i, &model) <= ptol).count() as f32
            / ring.len() as f32;
        // The plate must span most of the canvas, otherwise it is a big glyph.
        let fg_mask: Vec<bool> = bg.iter().map(|b| !b).collect();
        let (mut x0, mut y0, mut x1, mut y1) = (w, h, 0usize, 0usize);
        for i in 0..n {
            if fg_mask[i] {
                let (x, y) = (i % w, i / w);
                x0 = x0.min(x);
                y0 = y0.min(y);
                x1 = x1.max(x + 1);
                y1 = y1.max(y + 1);
            }
        }
        let span = ((x1 - x0) as f32 / w as f32).min((y1 - y0) as f32 / h as f32);
        if uniform < 0.65 || span < 0.75 {
            break;
        }
        let band = (w.min(h) as f32 * 0.035).max(1.5);
        let before = bg.clone();
        let seeds: Vec<usize> = ring
            .iter()
            .copied()
            .filter(|&i| dist(&lab, &alpha, i, &model) <= ptol)
            .collect();
        let pm = [model];
        flood(&lab, &alpha, w, h, &seeds, &|i| !before[i], &pm, ptol, &mut bg);
        // the plate rim (highlights, borders) is never part of the glyph
        for i in 0..n {
            if !before[i] && d[i] < band {
                bg[i] = true;
            }
        }
        // what is left of the rim lighting just past the band (a thin light
        // line along the top of frosted icons): pieces that never get deeper
        // than twice the band into the plate are rim, not symbol
        {
            let fgm: Vec<bool> = bg.iter().map(|b| !b).collect();
            let (labels, sizes) = components(&fgm, w, h);
            let mut deepest = vec![0f32; sizes.len()];
            for i in 0..n {
                let l = labels[i] as usize;
                if l != 0 {
                    deepest[l] = deepest[l].max(d[i]);
                }
            }
            for i in 0..n {
                let l = labels[i] as usize;
                if l != 0 && deepest[l] < band * 2.2 {
                    bg[i] = true;
                }
            }
        }
        // safety net: a "plate" that took almost everything was the logo
        let left = bg.iter().filter(|b| !**b).count();
        if (left as f32) < 0.03 * fg_count as f32 {
            bg = before;
            notes.push("piatto non rimosso: avrebbe cancellato il simbolo".into());
            break;
        }
        models.push(model);
        plate_removed = true;
        method.push_str("+plate");
    }
    if plate_removed {
        notes.push("background plate removed".into());
    }

    // Enclosed background-coloured regions.
    let mut hole_area = 0usize;
    let mut hole_dist = 0f32;
    let mut glyph_area = bg.iter().filter(|b| !**b).count();
    if opt.remove_holes && !models.is_empty() {
        let cand: Vec<bool> = (0..n)
            .map(|i| !bg[i] && alpha[i] >= 16 && nearest(&lab, &alpha, i, &models) <= tol * 0.8)
            .collect();
        let (labels, sizes) = components(&cand, w, h);
        let min_hole = ((n as f32 * 0.0005) as usize).max(12);
        for i in 0..n {
            let l = labels[i] as usize;
            if l != 0 && sizes[l] >= min_hole {
                bg[i] = true;
                hole_area += 1;
                hole_dist += nearest(&lab, &alpha, i, &models);
            }
        }
        if hole_area > 0 {
            hole_dist /= hole_area as f32;
            notes.push(format!("{} enclosed background pixels removed", hole_area));
        }
    }

    // Remove specks, fill pinholes.
    {
        let fg: Vec<bool> = bg.iter().map(|b| !b).collect();
        let (labels, sizes) = components(&fg, w, h);
        let min = ((n as f32 * opt.min_component.clamp(0.0, 0.05)) as usize).max(4);
        let largest = sizes.iter().skip(1).copied().max().unwrap_or(0);
        for i in 0..n {
            let l = labels[i] as usize;
            if l != 0 && sizes[l] < min && sizes[l] != largest {
                bg[i] = true;
            }
        }
        let (blabels, bsizes) = components(&bg, w, h);
        let border_lab: std::collections::HashSet<u32> =
            border.iter().map(|&i| blabels[i]).filter(|&l| l != 0).collect();
        let pin = ((n as f32 * 0.00015) as usize).max(3);
        for i in 0..n {
            let l = blabels[i];
            if l != 0 && !border_lab.contains(&l) && bsizes[l as usize] <= pin && alpha[i] >= 16 {
                bg[i] = false;
            }
        }
    }
    let new_glyph_area = bg.iter().filter(|b| !**b).count();
    // Holes that match the background exactly are safe; loose matches covering
    // a visible part of the glyph need a manual check.
    if hole_area > 0
        && glyph_area > 0
        && hole_area as f32 > glyph_area as f32 * 0.02
        && hole_dist > tol * 0.3
    {
        notes.push("large enclosed regions matched the background colour: check the glyph".into());
    }
    glyph_area = new_glyph_area;

    if glyph_area == 0 {
        let mut r = passthrough(&format!("{method}->fallback"), notes);
        r.ambiguous = true;
        r.confidence = 0.1;
        r.notes.push("no glyph found after background removal; using the whole image".into());
        return r;
    }

    // Build output with refined edges.
    let mut out = RgbaImage::new(w32, h32);
    {
        let o: &mut [u8] = &mut out;
        let pm = |i: usize| -> [f32; 4] {
            let a = buf[i * 4 + 3] as f32 / 255.0;
            [
                buf[i * 4] as f32 / 255.0 * a,
                buf[i * 4 + 1] as f32 / 255.0 * a,
                buf[i * 4 + 2] as f32 / 255.0 * a,
                a,
            ]
        };
        for i in 0..n {
            let (x, y) = (i % w, i / w);
            let mut bnb: Vec<usize> = Vec::new();
            let mut fnb: Vec<usize> = Vec::new();
            if opt.refine_edges {
                for dy in -1i32..=1 {
                    for dx in -1i32..=1 {
                        if dx == 0 && dy == 0 {
                            continue;
                        }
                        let (nx, ny) = (x as i32 + dx, y as i32 + dy);
                        if nx < 0 || ny < 0 || nx >= w as i32 || ny >= h as i32 {
                            continue;
                        }
                        let j = ny as usize * w + nx as usize;
                        if bg[j] {
                            bnb.push(j)
                        } else {
                            fnb.push(j)
                        }
                    }
                }
            }
            let boundary = opt.refine_edges && ((!bg[i] && !bnb.is_empty()) || (bg[i] && !fnb.is_empty()));
            if !boundary {
                if !bg[i] {
                    o[i * 4..i * 4 + 4].copy_from_slice(&buf[i * 4..i * 4 + 4]);
                }
                continue;
            }
            // local background (premultiplied) = mean of bg neighbours (or itself)
            let bsrc: Vec<usize> = if bg[i] { vec![i] } else { bnb.clone() };
            let mut b = [0f32; 4];
            for &j in &bsrc {
                let p = pm(j);
                for c in 0..4 {
                    b[c] += p[c] / bsrc.len() as f32;
                }
            }
            let v = pm(i);
            // foreground reference: glyph neighbour farthest from B
            let fsrc: Vec<usize> = if bg[i] { fnb.clone() } else { std::iter::once(i).chain(fnb.iter().copied()).collect() };
            let mut f = v;
            let mut best = -1.0f32;
            for &j in &fsrc {
                let p = pm(j);
                let d: f32 = (0..4).map(|c| (p[c] - b[c]) * (p[c] - b[c])).sum();
                if d > best {
                    best = d;
                    f = p;
                }
            }
            let fb: [f32; 4] = [f[0] - b[0], f[1] - b[1], f[2] - b[2], f[3] - b[3]];
            let fb2: f32 = fb.iter().map(|c| c * c).sum();
            let mix = if fb2 < 0.004 {
                if bg[i] { 0.0 } else { 1.0 }
            } else {
                let dot: f32 = (0..4).map(|c| (v[c] - b[c]) * fb[c]).sum();
                (dot / fb2).clamp(0.0, 1.0)
            };
            if bg[i] && mix < 0.2 {
                continue;
            }
            // remove background contribution
            let mut r = [0f32; 4];
            for c in 0..4 {
                r[c] = (v[c] - (1.0 - mix) * b[c]).max(0.0);
            }
            let a = r[3].min(v[3]).max(0.0);
            if a <= 0.004 {
                continue;
            }
            // colour: un-premultiply, fall back to F colour when unstable
            let fa = f[3].max(1e-4);
            for c in 0..3 {
                let col = if a > 0.05 { r[c] / a } else { f[c] / fa };
                o[i * 4 + c] = (col * 255.0).round().clamp(0.0, 255.0) as u8;
            }
            o[i * 4 + 3] = (a * 255.0).round().clamp(0.0, 255.0) as u8;
        }
    }

    // Quality metrics.
    let glyph_frac = glyph_area as f32 / n as f32;
    let low_contrast = if models.iter().all(|m| m.alpha < 0.06) {
        0.0
    } else {
        let close = (0..n)
            .filter(|&i| !bg[i] && nearest(&lab, &alpha, i, &models) <= tol * 2.0)
            .count();
        close as f32 / glyph_area as f32
    };
    let size_factor = if (0.003..=0.92).contains(&glyph_frac) { 1.0 } else { 0.4 };
    let confidence = (border_uniform * size_factor * (1.0 - low_contrast * 0.8)).clamp(0.0, 1.0);
    if low_contrast > 0.3 {
        notes.push(format!(
            "{:.0}% of the glyph is close to the background colour",
            low_contrast * 100.0
        ));
    }
    if size_factor < 1.0 {
        notes.push(format!("unusual glyph coverage ({:.1}% of the image)", glyph_frac * 100.0));
    }
    let ambiguous = confidence < 0.6
        || notes.iter().any(|n| n.starts_with("large enclosed"))
        || (plate_removed && glyph_frac > 0.6);

    let bbox = alpha_bbox(&out, 8).unwrap_or((0, 0, w32, h32));
    let glyph = crop(&out, bbox.0, bbox.1, bbox.2, bbox.3);
    SegmentResult {
        glyph,
        bbox,
        source_size: (w32, h32),
        confidence,
        ambiguous,
        method,
        notes,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use image::Rgba;

    /// Frosted icons light the top edge of their plate: that light line is
    /// rim, never part of the symbol (no white bar on top of the result).
    #[test]
    fn plate_top_highlight_is_not_glyph() {
        let n = 192u32;
        let shape = crate::squircle::Shape { size_ratio: 0.93, exponent: 4.25 };
        let mask = crate::squircle::mask(n, &shape);
        let mut img = RgbaImage::new(n, n);
        let top = (0..n).find(|&y| mask[(y * n + n / 2) as usize] > 0).unwrap();
        for y in 0..n {
            for x in 0..n {
                let a = mask[(y * n + x) as usize];
                if a == 0 {
                    continue;
                }
                // dark plate, a light band fading out over the first 9 rows
                let t = y.saturating_sub(top);
                let l = if t < 9 { 170 - t * 18 } else { 14 };
                img.put_pixel(x, y, Rgba([l as u8, l as u8, l as u8, (a as u32 * 150 / 255) as u8]));
            }
        }
        disc(&mut img, 96.0, 104.0, 40.0, [240, 70, 70, 255]);
        let r = isolate(&img, &SegmentOptions::default());
        assert!(r.bbox.1 >= 60, "glyph starts at y={} (rim kept): {:?}", r.bbox.1, r.notes);
    }

    fn disc(img: &mut RgbaImage, cx: f32, cy: f32, r: f32, c: [u8; 4]) {
        for y in 0..img.height() {
            for x in 0..img.width() {
                let d = ((x as f32 + 0.5 - cx).powi(2) + (y as f32 + 0.5 - cy).powi(2)).sqrt();
                if d <= r {
                    img.put_pixel(x, y, Rgba(c));
                }
            }
        }
    }

    #[test]
    fn opaque_background_removed() {
        let mut img = RgbaImage::from_pixel(100, 100, Rgba([30, 90, 200, 255]));
        disc(&mut img, 50.0, 50.0, 20.0, [255, 255, 255, 255]);
        let r = isolate(&img, &SegmentOptions::default());
        assert!(r.method.starts_with("background"));
        let (x0, y0, x1, y1) = r.bbox;
        assert!((29..=31).contains(&x0) && (69..=71).contains(&x1), "{:?}", r.bbox);
        assert!((29..=31).contains(&y0) && (69..=71).contains(&y1));
        assert_eq!(r.glyph.get_pixel(20, 20).0[3], 255);
        assert_eq!(r.glyph.get_pixel(0, 0).0[3], 0);
    }

    #[test]
    fn similar_colour_glyph_part_survives_when_separated_by_edge() {
        // blue bg, white ring, inside the ring a slightly different blue disc
        let mut img = RgbaImage::from_pixel(120, 120, Rgba([30, 90, 200, 255]));
        disc(&mut img, 60.0, 60.0, 30.0, [255, 255, 255, 255]);
        disc(&mut img, 60.0, 60.0, 18.0, [40, 110, 235, 255]);
        let opts = SegmentOptions { remove_holes: false, ..Default::default() };
        let r = isolate(&img, &opts);
        let c = r.glyph.get_pixel(r.glyph.width() / 2, r.glyph.height() / 2).0;
        assert_eq!(c[3], 255, "inner part removed: {:?}", c);
    }

    #[test]
    fn hole_of_background_colour_removed() {
        let mut img = RgbaImage::from_pixel(120, 120, Rgba([250, 250, 250, 255]));
        disc(&mut img, 60.0, 60.0, 35.0, [200, 20, 20, 255]);
        disc(&mut img, 60.0, 60.0, 15.0, [250, 250, 250, 255]);
        let r = isolate(&img, &SegmentOptions::default());
        let c = r.glyph.get_pixel(r.glyph.width() / 2, r.glyph.height() / 2).0;
        assert_eq!(c[3], 0);
    }

    #[test]
    fn transparent_logo_kept() {
        let mut img = RgbaImage::new(100, 100);
        disc(&mut img, 50.0, 50.0, 25.0, [10, 200, 10, 255]);
        let r = isolate(&img, &SegmentOptions::default());
        assert!(r.method.starts_with("alpha"));
        assert!(!r.method.contains("plate"));
        assert_eq!(r.glyph.width(), 50);
    }

    #[test]
    fn plate_on_transparent_removed() {
        // white rounded plate filling the canvas with a red glyph
        let mut img = RgbaImage::new(100, 100);
        for y in 4..96 {
            for x in 4..96 {
                img.put_pixel(x, y, Rgba([245, 245, 245, 255]));
            }
        }
        disc(&mut img, 50.0, 50.0, 20.0, [220, 30, 30, 255]);
        let r = isolate(&img, &SegmentOptions::default());
        assert!(r.method.contains("plate"), "{}", r.method);
        assert!(r.glyph.width() <= 42 && r.glyph.width() >= 38, "{}", r.glyph.width());
    }
}

#[cfg(test)]
mod transparent_source_tests {
    use super::*;
    use image::Rgba;

    #[test]
    fn remove_background_keeps_an_already_cut_out_white_glyph() {
        // white rounded glyph on a transparent canvas (an adaptive foreground)
        let mut img = RgbaImage::new(100, 100);
        for y in 25..75u32 {
            for x in 20..80u32 {
                img.put_pixel(x, y, Rgba([250, 250, 250, 255]));
            }
        }
        let opt = SegmentOptions { mode: SegmentMode::RemoveBackground, tolerance: 0.25, ..Default::default() };
        let r = isolate(&img, &opt);
        let kept = r.glyph.pixels().filter(|p| p[3] > 200).count();
        assert!(kept > 2500, "glyph erased: {kept} px left");
    }
}
