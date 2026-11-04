//! Per-base calibration from correctly composed example icons.
//!
//! Each sample is compared with the base icon (resized to the sample size):
//! pixels that differ inside the base plate (minus a rim band) are the glyph.
//! When the sample does not match the base (different background style) the
//! glyph is found by segmentation instead. Measurements are aggregated with
//! median / MAD and outliers are excluded, so a few bad samples do not skew
//! the result. Only the glyph is analysed, never the background style.

use crate::compose::{FitMode, Placement};
use crate::imageops::{components, distance_from, resize};
use crate::segment::{isolate, SegmentOptions};
use image::RgbaImage;
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct SampleMeasure {
    pub name: String,
    /// Glyph bbox as canvas fractions (x0, y0, x1, y1).
    pub bbox: [f32; 4],
    pub max_side_ratio: f32,
    pub area_ratio: f32,
    pub width_ratio: f32,
    pub height_ratio: f32,
    pub center_x: f32,
    pub center_y: f32,
    pub method: String,
    pub outlier: bool,
    pub error: Option<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Calibration {
    pub placement: Placement,
    pub max_side_mad: f32,
    pub center_mad: f32,
    /// Median margins (canvas fractions).
    pub margin_left: f32,
    pub margin_top: f32,
    pub margin_right: f32,
    pub margin_bottom: f32,
    /// Robust envelope (10th/90th percentile) of the glyph boxes = useful area.
    pub useful_area: [f32; 4],
    pub median_aspect: f32,
    pub inliers: u32,
    pub samples: Vec<SampleMeasure>,
}

fn diff_mask(base: &RgbaImage, sample: &RgbaImage) -> Option<(Vec<bool>, usize)> {
    let (w, h) = sample.dimensions();
    let b = resize(base, w, h);
    let (wu, hu) = (w as usize, h as usize);
    let n = wu * hu;
    let bb = b.as_raw();
    let sb = sample.as_raw();
    let base_opaque_frac = bb.chunks_exact(4).filter(|p| p[3] > 10).count() as f32 / n as f32;
    let outside: Vec<bool> = if base_opaque_frac > 0.98 {
        // full-bleed base: treat the canvas border as the plate edge
        (0..n).map(|i| i % wu == 0 || i / wu == 0 || i % wu == wu - 1 || i / wu == hu - 1).collect()
    } else {
        bb.chunks_exact(4).map(|p| p[3] <= 10).collect()
    };
    let d = distance_from(&outside, wu, hu);
    let band = w.min(h) as f32 * 0.045;
    let mut mask = vec![false; n];
    let mut inner = 0usize;
    for i in 0..n {
        if outside[i] || d[i] < band {
            continue;
        }
        inner += 1;
        let (ba, sa) = (bb[i * 4 + 3] as f32 / 255.0, sb[i * 4 + 3] as f32 / 255.0);
        let mut m = ((ba - sa).abs() * 255.0) as i32;
        for c in 0..3 {
            let pb = bb[i * 4 + c] as f32 * ba;
            let ps = sb[i * 4 + c] as f32 * sa;
            m = m.max((pb - ps).abs() as i32);
        }
        mask[i] = m > 36;
    }
    // drop specks
    let (labels, sizes) = components(&mask, wu, hu);
    let min = ((n as f32 * 0.0005) as usize).max(4);
    for i in 0..n {
        if mask[i] && sizes[labels[i] as usize] < min {
            mask[i] = false;
        }
    }
    Some((mask, inner))
}

fn bbox_of(mask: &[bool], w: usize, h: usize) -> Option<(usize, usize, usize, usize, usize)> {
    let (mut x0, mut y0, mut x1, mut y1, mut c) = (w, h, 0, 0, 0);
    for (i, &m) in mask.iter().enumerate() {
        if m {
            let (x, y) = (i % w, i / w);
            x0 = x0.min(x);
            y0 = y0.min(y);
            x1 = x1.max(x + 1);
            y1 = y1.max(y + 1);
            c += 1;
        }
    }
    if c == 0 {
        None
    } else {
        Some((x0, y0, x1, y1, c))
    }
}

pub fn measure_sample(name: &str, base: Option<&RgbaImage>, sample: &RgbaImage) -> SampleMeasure {
    let (w, h) = sample.dimensions();
    let (wu, hu) = (w as usize, h as usize);
    let mut method = "segmentation".to_string();
    let mut bbox: Option<(f32, f32, f32, f32)> = None;
    if let Some(base) = base {
        if let Some((mask, inner)) = diff_mask(base, sample) {
            if let Some((x0, y0, x1, y1, count)) = bbox_of(&mask, wu, hu) {
                let cover = count as f32 / inner.max(1) as f32;
                let span = ((x1 - x0) as f32 / w as f32).max((y1 - y0) as f32 / h as f32);
                // whole plate differs -> sample has a different background style
                if cover < 0.85 && span < 0.88 {
                    bbox = Some((x0 as f32, y0 as f32, x1 as f32, y1 as f32));
                    method = "base-difference".into();
                }
            }
        }
    }
    if bbox.is_none() {
        let r = isolate(sample, &SegmentOptions::default());
        let b = r.bbox;
        bbox = Some((b.0 as f32, b.1 as f32, b.2 as f32, b.3 as f32));
        if r.ambiguous {
            method.push_str(" (ambiguous)");
        }
    }
    let (x0, y0, x1, y1) = bbox.unwrap();
    let (fw, fh) = (w as f32, h as f32);
    let size = fw.min(fh);
    let (gw, gh) = (x1 - x0, y1 - y0);
    SampleMeasure {
        name: name.into(),
        bbox: [x0 / fw, y0 / fh, x1 / fw, y1 / fh],
        max_side_ratio: gw.max(gh) / size,
        area_ratio: (gw * gh).sqrt() / size,
        width_ratio: gw / fw,
        height_ratio: gh / fh,
        center_x: (x0 + x1) / 2.0 / fw,
        center_y: (y0 + y1) / 2.0 / fh,
        method,
        outlier: false,
        error: None,
    }
}

fn median(v: &[f32]) -> f32 {
    if v.is_empty() {
        return 0.0;
    }
    let mut s = v.to_vec();
    s.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let m = s.len() / 2;
    if s.len() % 2 == 0 {
        (s[m - 1] + s[m]) / 2.0
    } else {
        s[m]
    }
}

fn percentile(v: &[f32], p: f32) -> f32 {
    if v.is_empty() {
        return 0.0;
    }
    let mut s = v.to_vec();
    s.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let idx = ((s.len() - 1) as f32 * p).round() as usize;
    s[idx]
}

fn mad(v: &[f32], med: f32) -> f32 {
    let d: Vec<f32> = v.iter().map(|x| (x - med).abs()).collect();
    median(&d) * 1.4826
}

pub fn calibrate(base: Option<&RgbaImage>, samples: &[(String, RgbaImage)]) -> Calibration {
    use rayon::prelude::*;
    let mut ms: Vec<SampleMeasure> = samples
        .par_iter()
        .map(|(name, img)| measure_sample(name, base, img))
        .collect();
    aggregate(&mut ms)
}

pub fn aggregate(ms: &mut [SampleMeasure]) -> Calibration {
    let valid: Vec<usize> = (0..ms.len()).filter(|&i| ms[i].error.is_none()).collect();
    let sides: Vec<f32> = valid.iter().map(|&i| ms[i].max_side_ratio).collect();
    let cxs: Vec<f32> = valid.iter().map(|&i| ms[i].center_x).collect();
    let cys: Vec<f32> = valid.iter().map(|&i| ms[i].center_y).collect();
    let (ms_med, cx_med, cy_med) = (median(&sides), median(&cxs), median(&cys));
    let side_mad = mad(&sides, ms_med).max(0.012);
    let c_mad = mad(&cxs, cx_med).max(mad(&cys, cy_med)).max(0.01);
    for &i in &valid {
        let m = &mut ms[i];
        m.outlier = (m.max_side_ratio - ms_med).abs() > 3.0 * side_mad
            || (m.center_x - cx_med).abs() > 3.0 * c_mad + 0.02
            || (m.center_y - cy_med).abs() > 3.0 * c_mad + 0.02
            || m.max_side_ratio > 0.97;
    }
    let inl: Vec<&SampleMeasure> = valid.iter().map(|&i| &ms[i]).filter(|m| !m.outlier).collect();
    let pick = |f: &dyn Fn(&SampleMeasure) -> f32| -> Vec<f32> { inl.iter().map(|m| f(m)).collect() };
    let mut placement = Placement::default();
    if !inl.is_empty() {
        placement = Placement {
            glyph_ratio: median(&pick(&|m| m.max_side_ratio)),
            area_ratio: median(&pick(&|m| m.area_ratio)),
            center_x: median(&pick(&|m| m.center_x)),
            center_y: median(&pick(&|m| m.center_y)),
            fit: FitMode::MaxSide,
            scale_mul: 1.0,
            offset_x: 0.0,
            offset_y: 0.0,
        };
    }
    let x0s = pick(&|m| m.bbox[0]);
    let y0s = pick(&|m| m.bbox[1]);
    let x1s = pick(&|m| m.bbox[2]);
    let y1s = pick(&|m| m.bbox[3]);
    Calibration {
        max_side_mad: side_mad,
        center_mad: c_mad,
        margin_left: median(&x0s),
        margin_top: median(&y0s),
        margin_right: 1.0 - median(&x1s),
        margin_bottom: 1.0 - median(&y1s),
        useful_area: [
            percentile(&x0s, 0.1),
            percentile(&y0s, 0.1),
            percentile(&x1s, 0.9),
            percentile(&y1s, 0.9),
        ],
        median_aspect: median(&pick(&|m| m.width_ratio / m.height_ratio.max(1e-4))),
        inliers: inl.len() as u32,
        placement,
        samples: ms.to_vec(),
    }
}
