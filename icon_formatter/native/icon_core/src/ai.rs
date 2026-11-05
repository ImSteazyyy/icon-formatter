//! Local AI background removal (salient-object segmentation, ONNX).
//!
//! Models are optional downloads (rembg releases, Apache-2.0): U²-Net-p,
//! Silueta (U²-Net distilled) and IS-Net general use. Inference runs with
//! `tract` (pure Rust, CPU) on Windows and Android; a loaded model is cached
//! and reused across previews and batches.

use crate::imageops::{alpha_bbox, crop, resize};
use crate::segment::{isolate, SegmentMode, SegmentOptions, SegmentResult};
use image::{Rgba, RgbaImage};
use std::path::Path;
use std::sync::{Arc, Mutex};
use tract_onnx::prelude::*;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum ModelKind {
    U2netp,
    Silueta,
    IsnetGeneral,
}

impl ModelKind {
    pub fn input_size(self) -> usize {
        match self {
            ModelKind::IsnetGeneral => 1024,
            _ => 320,
        }
    }
    fn norm(self) -> ([f32; 3], [f32; 3]) {
        match self {
            ModelKind::IsnetGeneral => ([0.5, 0.5, 0.5], [1.0, 1.0, 1.0]),
            _ => ([0.485, 0.456, 0.406], [0.229, 0.224, 0.225]),
        }
    }
    pub fn id(self) -> &'static str {
        match self {
            ModelKind::U2netp => "u2netp",
            ModelKind::Silueta => "silueta",
            ModelKind::IsnetGeneral => "isnet-general-use",
        }
    }
}

type Plan = std::sync::Arc<TypedRunnableModel>;

pub struct Model {
    pub kind: ModelKind,
    pub path: String,
    plan: Plan,
    /// Large models run one at a time to bound memory.
    gate: Option<Mutex<()>>,
}

impl Model {
    pub fn load(path: &Path, kind: ModelKind) -> Result<Model, String> {
        let n = kind.input_size();
        let plan = tract_onnx::onnx()
            .model_for_path(path)
            .and_then(|m| m.with_input_fact(0, f32::fact([1, 3, n, n]).into()))
            .and_then(|m| m.into_optimized())
            .and_then(|m| m.into_runnable())
            .map_err(|e| format!("modello non valido: {e}"))?;
        Ok(Model {
            kind,
            path: path.to_string_lossy().to_string(),
            plan,
            gate: (kind == ModelKind::IsnetGeneral).then(|| Mutex::new(())),
        })
    }

    /// Raw saliency mask (0..1) at the source resolution.
    pub fn predict(&self, src: &RgbaImage) -> Result<Vec<f32>, String> {
        let _g = self.gate.as_ref().map(|m| m.lock());
        let n = self.kind.input_size();
        // flatten alpha over mid grey (icons often have transparent corners)
        let mut rgb = src.clone();
        for p in rgb.pixels_mut() {
            let a = p[3] as f32 / 255.0;
            for c in 0..3 {
                p[c] = (p[c] as f32 * a + 128.0 * (1.0 - a)).round() as u8;
            }
            p[3] = 255;
        }
        let small = resize(&rgb, n as u32, n as u32);
        let max = small.pixels().flat_map(|p| [p[0], p[1], p[2]]).max().unwrap_or(255).max(1) as f32;
        let (mean, std) = self.kind.norm();
        let input: Tensor = tract_ndarray::Array4::from_shape_fn((1, 3, n, n), |(_, c, y, x)| {
            let v = small.get_pixel(x as u32, y as u32)[c] as f32 / max;
            (v - mean[c]) / std[c]
        })
        .into();
        let out = self.plan.run(tvec!(input.into())).map_err(|e| format!("inferenza fallita: {e}"))?;
        let t = out[0].to_plain_array_view::<f32>().map_err(|e| e.to_string())?;
        let shape = t.shape().to_vec();
        let (h, w) = (shape[shape.len() - 2], shape[shape.len() - 1]);
        let flat: Vec<f32> = t.iter().take(h * w).copied().collect();
        let (mi, ma) = flat.iter().fold((f32::MAX, f32::MIN), |(a, b), &v| (a.min(v), b.max(v)));
        let range = (ma - mi).max(1e-6);
        let mut m = RgbaImage::new(w as u32, h as u32);
        for (i, v) in flat.iter().enumerate() {
            let q = (((v - mi) / range) * 255.0).round() as u8;
            m.put_pixel((i % w) as u32, (i / w) as u32, Rgba([q, q, q, 255]));
        }
        let up = resize(&m, src.width(), src.height());
        Ok(up.pixels().map(|p| p[0] as f32 / 255.0).collect())
    }
}

static CACHE: Mutex<Option<Arc<Model>>> = Mutex::new(None);

/// Loads (or reuses) the cached model.
pub fn model(path: &str, kind: ModelKind) -> Result<Arc<Model>, String> {
    let mut c = CACHE.lock().map_err(|_| "cache bloccata".to_string())?;
    if let Some(m) = c.as_ref() {
        if m.path == path && m.kind == kind {
            return Ok(m.clone());
        }
    }
    *c = None; // free the previous model before loading a new one
    let m = Arc::new(Model::load(Path::new(path), kind)?);
    *c = Some(m.clone());
    Ok(m)
}

pub fn unload() {
    if let Ok(mut c) = CACHE.lock() {
        *c = None;
    }
}

#[derive(Clone, Copy, Debug)]
pub struct AiOptions {
    /// Mask remap: below `low` → transparent, above `high` → opaque.
    pub low: f32,
    pub high: f32,
}

impl Default for AiOptions {
    fn default() -> Self {
        AiOptions { low: 0.15, high: 0.85 }
    }
}

pub struct AiResult {
    pub seg: SegmentResult,
    /// Final alpha mask (source resolution), for the preview.
    pub mask: RgbaImage,
    /// False when the source already has a transparent background.
    pub needed: bool,
    pub uncertain: bool,
}

/// True when the source already is a cut-out glyph (transparent border and
/// the deterministic isolation keeps alpha as is).
pub fn removal_needed(src: &RgbaImage) -> bool {
    let (w, h) = src.dimensions();
    let mut border = 0u32;
    let mut clear = 0u32;
    for x in 0..w {
        for y in [0, h - 1] {
            border += 1;
            clear += (src.get_pixel(x, y)[3] < 16) as u32;
        }
    }
    for y in 0..h {
        for x in [0, w - 1] {
            border += 1;
            clear += (src.get_pixel(x, y)[3] < 16) as u32;
        }
    }
    if (clear as f32) < border as f32 * 0.9 {
        return true;
    }
    // transparent border: needed only if there is an opaque plate inside
    let det = isolate(src, &SegmentOptions::default());
    det.method.contains("plate")
}

pub fn isolate_ai(src: &RgbaImage, model: &Model, opt: AiOptions) -> Result<AiResult, String> {
    if !removal_needed(src) {
        let seg = isolate(src, &SegmentOptions { mode: SegmentMode::KeepAlpha, ..Default::default() });
        let mut mask = RgbaImage::new(src.width(), src.height());
        for (m, p) in mask.pixels_mut().zip(src.pixels()) {
            *m = Rgba([p[3], p[3], p[3], 255]);
        }
        return Ok(AiResult { seg, mask, needed: false, uncertain: false });
    }
    let raw = model.predict(src)?;
    let (lo, hi) = (opt.low.clamp(0.0, 0.98), opt.high.clamp(0.02, 1.0).max(opt.low + 0.02));
    let mut cut = src.clone();
    let mut mask = RgbaImage::new(src.width(), src.height());
    let (mut soft, mut fg) = (0u32, 0u32);
    for (i, (p, m)) in cut.pixels_mut().zip(mask.pixels_mut()).enumerate() {
        let r = raw[i];
        if r > 0.15 && r < 0.85 {
            soft += 1;
        }
        let a = ((r - lo) / (hi - lo)).clamp(0.0, 1.0);
        if a > 0.5 {
            fg += 1;
        }
        let na = (p[3] as f32 * a).round() as u8;
        p[3] = na;
        *m = Rgba([na, na, na, 255]);
    }
    let total = (src.width() * src.height()).max(1) as f32;
    let fg_ratio = fg as f32 / total;
    let soft_ratio = soft as f32 / total;
    // compare with the deterministic segmentation
    let det = isolate(src, &SegmentOptions::default());
    let iou = {
        let (x0, y0, x1, y1) = det.bbox;
        let (mut inter, mut uni) = (0u32, 0u32);
        for y in 0..src.height() {
            for x in 0..src.width() {
                let a = cut.get_pixel(x, y)[3] > 127;
                let b = x >= x0 && x < x1 && y >= y0 && y < y1 && det.glyph.get_pixel(x - x0, y - y0)[3] > 127;
                inter += (a && b) as u32;
                uni += (a || b) as u32;
            }
        }
        if uni == 0 { 0.0 } else { inter as f32 / uni as f32 }
    };
    let mut notes = vec![format!("AI {}: primo piano {:.0}%, accordo con segmentazione classica {:.0}%", model.kind.id(), fg_ratio * 100.0, iou * 100.0)];
    let uncertain = fg_ratio < 0.02 || fg_ratio > 0.95 || soft_ratio > 0.10 || iou < 0.6;
    if uncertain {
        notes.push("Risultato AI incerto: controlla la maschera prima di esportare".into());
    }
    let bbox = alpha_bbox(&cut, 8).unwrap_or((0, 0, src.width(), src.height()));
    let glyph = crop(&cut, bbox.0, bbox.1, bbox.2, bbox.3);
    let confidence = (1.0 - soft_ratio * 4.0).clamp(0.0, 1.0) * (0.5 + 0.5 * iou);
    Ok(AiResult {
        seg: SegmentResult {
            glyph,
            bbox,
            source_size: src.dimensions(),
            confidence,
            ambiguous: uncertain,
            method: format!("ai:{}", model.kind.id()),
            notes,
        },
        mask,
        needed: true,
        uncertain,
    })
}
