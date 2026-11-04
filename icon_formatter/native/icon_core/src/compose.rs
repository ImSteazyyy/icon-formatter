//! Glyph placement and composition on a base (image or procedural).

use crate::imageops::{clean_transparent, draw_over, resize, trim};
use crate::segment::{isolate, SegmentOptions, SegmentResult};
use crate::translucent::{render, TranslucentParams};
use image::RgbaImage;
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

/// Full pipeline for one icon: isolate -> scale/centre -> compose.
pub fn compose_icon(
    src: &RgbaImage,
    background: &RgbaImage,
    placement: &Placement,
    seg: &SegmentOptions,
) -> (RgbaImage, SegmentResult) {
    let res = isolate(src, seg);
    let mut canvas = background.clone();
    place_glyph(&mut canvas, &res.glyph, placement);
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
}
