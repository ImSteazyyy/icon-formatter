//! Decoding, encoding, resizing and alpha compositing primitives.

use crate::error::{CoreError, Result};
use fast_image_resize as fr;
use image::{ImageEncoder, RgbaImage};
use std::path::Path;

/// Inputs bigger than this (longest side) are downscaled before processing:
/// icons never need more and it bounds memory use in large batches.
pub const MAX_INPUT_SIDE: u32 = 2048;

pub fn decode(bytes: &[u8]) -> Result<RgbaImage> {
    let img = image::load_from_memory(bytes).map_err(|e| CoreError::Decode(e.to_string()))?;
    let rgba = img.to_rgba8();
    Ok(limit_size(rgba))
}

pub fn decode_file(path: &Path) -> Result<RgbaImage> {
    let bytes = std::fs::read(path)?;
    decode(&bytes).map_err(|e| CoreError::Decode(format!("{}: {}", path.display(), e)))
}

fn limit_size(img: RgbaImage) -> RgbaImage {
    let (w, h) = img.dimensions();
    let m = w.max(h);
    if m <= MAX_INPUT_SIDE {
        return img;
    }
    let s = MAX_INPUT_SIDE as f32 / m as f32;
    resize(&img, ((w as f32 * s).round() as u32).max(1), ((h as f32 * s).round() as u32).max(1))
}

pub fn encode_png(img: &RgbaImage) -> Result<Vec<u8>> {
    let mut out = Vec::with_capacity((img.width() * img.height()) as usize);
    let enc = image::codecs::png::PngEncoder::new_with_quality(
        &mut out,
        image::codecs::png::CompressionType::Default,
        image::codecs::png::FilterType::Adaptive,
    );
    enc.write_image(img.as_raw(), img.width(), img.height(), image::ExtendedColorType::Rgba8)
        .map_err(|e| CoreError::Encode(e.to_string()))?;
    Ok(out)
}

pub fn write_png(img: &RgbaImage, path: &Path) -> Result<()> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let bytes = encode_png(img)?;
    std::fs::write(path, bytes)?;
    Ok(())
}

/// High quality, alpha-correct (premultiplied) resize.
pub fn resize(img: &RgbaImage, w: u32, h: u32) -> RgbaImage {
    let (sw, sh) = img.dimensions();
    if sw == w && sh == h {
        return img.clone();
    }
    if sw == 0 || sh == 0 || w == 0 || h == 0 {
        return RgbaImage::new(w.max(1), h.max(1));
    }
    let src = fr::images::Image::from_vec_u8(sw, sh, img.as_raw().clone(), fr::PixelType::U8x4)
        .expect("valid source buffer");
    let mut dst = fr::images::Image::new(w, h, fr::PixelType::U8x4);
    let mut resizer = fr::Resizer::new();
    let filter = if w < sw || h < sh {
        fr::FilterType::Lanczos3
    } else {
        fr::FilterType::CatmullRom
    };
    let opts = fr::ResizeOptions::new()
        .resize_alg(fr::ResizeAlg::Convolution(filter))
        .use_alpha(true);
    resizer.resize(&src, &mut dst, &opts).expect("resize with matching pixel types");
    RgbaImage::from_raw(w, h, dst.into_vec()).expect("buffer size matches")
}

/// Source-over compositing of `src` onto `dst` at integer offset, with an
/// extra global opacity. Straight (non premultiplied) alpha in and out.
pub fn draw_over(dst: &mut RgbaImage, src: &RgbaImage, ox: i32, oy: i32, opacity: f32) {
    let (dw, dh) = (dst.width() as i32, dst.height() as i32);
    let (sw, sh) = (src.width() as i32, src.height() as i32);
    let x0 = ox.max(0);
    let y0 = oy.max(0);
    let x1 = (ox + sw).min(dw);
    let y1 = (oy + sh).min(dh);
    if x0 >= x1 || y0 >= y1 {
        return;
    }
    let dbuf: &mut [u8] = dst;
    let sbuf = src.as_raw();
    for y in y0..y1 {
        for x in x0..x1 {
            let si = (((y - oy) * sw + (x - ox)) * 4) as usize;
            let di = ((y * dw + x) * 4) as usize;
            let sa = sbuf[si + 3] as f32 / 255.0 * opacity;
            if sa <= 0.0 {
                continue;
            }
            let da = dbuf[di + 3] as f32 / 255.0;
            let oa = sa + da * (1.0 - sa);
            if oa <= 0.0 {
                continue;
            }
            for c in 0..3 {
                let sc = sbuf[si + c] as f32;
                let dc = dbuf[di + c] as f32;
                let v = (sc * sa + dc * da * (1.0 - sa)) / oa;
                dbuf[di + c] = v.round().clamp(0.0, 255.0) as u8;
            }
            dbuf[di + 3] = (oa * 255.0).round().clamp(0.0, 255.0) as u8;
        }
    }
}

/// Bounding box (x0, y0, x1 exclusive, y1 exclusive) of pixels with alpha > threshold.
pub fn alpha_bbox(img: &RgbaImage, threshold: u8) -> Option<(u32, u32, u32, u32)> {
    let (w, h) = img.dimensions();
    let buf = img.as_raw();
    let (mut x0, mut y0, mut x1, mut y1) = (u32::MAX, u32::MAX, 0u32, 0u32);
    for y in 0..h {
        let row = &buf[(y * w * 4) as usize..((y + 1) * w * 4) as usize];
        for x in 0..w {
            if row[(x * 4 + 3) as usize] > threshold {
                x0 = x0.min(x);
                y0 = y0.min(y);
                x1 = x1.max(x + 1);
                y1 = y1.max(y + 1);
            }
        }
    }
    if x0 == u32::MAX {
        None
    } else {
        Some((x0, y0, x1, y1))
    }
}

pub fn crop(img: &RgbaImage, x0: u32, y0: u32, x1: u32, y1: u32) -> RgbaImage {
    image::imageops::crop_imm(img, x0, y0, x1 - x0, y1 - y0).to_image()
}

/// Trims fully (near) transparent borders.
pub fn trim(img: &RgbaImage) -> Option<RgbaImage> {
    alpha_bbox(img, 8).map(|(x0, y0, x1, y1)| crop(img, x0, y0, x1, y1))
}

/// Sets RGB of fully transparent pixels to 0 (stable, compressible output).
pub fn clean_transparent(img: &mut RgbaImage) {
    for p in img.pixels_mut() {
        if p.0[3] == 0 {
            p.0 = [0, 0, 0, 0];
        }
    }
}

/// Multi-source BFS (chamfer 3-4) distance from pixels where `seed` is true.
/// Returns distances in pixels (approximate Euclidean).
pub fn distance_from(seed: &[bool], w: usize, h: usize) -> Vec<f32> {
    let inf = f32::MAX / 4.0;
    let mut d: Vec<f32> = seed.iter().map(|&s| if s { 0.0 } else { inf }).collect();
    let (a, b) = (1.0f32, std::f32::consts::SQRT_2);
    // forward pass
    for y in 0..h {
        for x in 0..w {
            let i = y * w + x;
            let mut v = d[i];
            if x > 0 {
                v = v.min(d[i - 1] + a);
            }
            if y > 0 {
                v = v.min(d[i - w] + a);
                if x > 0 {
                    v = v.min(d[i - w - 1] + b);
                }
                if x + 1 < w {
                    v = v.min(d[i - w + 1] + b);
                }
            }
            d[i] = v;
        }
    }
    // backward pass
    for y in (0..h).rev() {
        for x in (0..w).rev() {
            let i = y * w + x;
            let mut v = d[i];
            if x + 1 < w {
                v = v.min(d[i + 1] + a);
            }
            if y + 1 < h {
                v = v.min(d[i + w] + a);
                if x + 1 < w {
                    v = v.min(d[i + w + 1] + b);
                }
                if x > 0 {
                    v = v.min(d[i + w - 1] + b);
                }
            }
            d[i] = v;
        }
    }
    d
}

/// Connected components (8-connectivity) of `mask`. Returns labels (0 = none)
/// and component sizes indexed by label.
pub fn components(mask: &[bool], w: usize, h: usize) -> (Vec<u32>, Vec<usize>) {
    let mut labels = vec![0u32; w * h];
    let mut sizes = vec![0usize];
    let mut stack = Vec::new();
    let mut next = 1u32;
    for start in 0..w * h {
        if !mask[start] || labels[start] != 0 {
            continue;
        }
        labels[start] = next;
        stack.push(start);
        let mut count = 0usize;
        while let Some(i) = stack.pop() {
            count += 1;
            let (x, y) = ((i % w) as isize, (i / w) as isize);
            for dy in -1..=1isize {
                for dx in -1..=1isize {
                    if dx == 0 && dy == 0 {
                        continue;
                    }
                    let (nx, ny) = (x + dx, y + dy);
                    if nx < 0 || ny < 0 || nx >= w as isize || ny >= h as isize {
                        continue;
                    }
                    let j = ny as usize * w + nx as usize;
                    if mask[j] && labels[j] == 0 {
                        labels[j] = next;
                        stack.push(j);
                    }
                }
            }
        }
        sizes.push(count);
        next += 1;
    }
    (labels, sizes)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn over_preserves_opaque_source() {
        let mut dst = RgbaImage::from_pixel(4, 4, image::Rgba([10, 20, 30, 255]));
        let src = RgbaImage::from_pixel(2, 2, image::Rgba([200, 100, 50, 255]));
        draw_over(&mut dst, &src, 1, 1, 1.0);
        assert_eq!(dst.get_pixel(1, 1).0, [200, 100, 50, 255]);
        assert_eq!(dst.get_pixel(0, 0).0, [10, 20, 30, 255]);
    }

    #[test]
    fn over_on_transparent_keeps_color() {
        let mut dst = RgbaImage::new(2, 2);
        let src = RgbaImage::from_pixel(2, 2, image::Rgba([200, 100, 50, 128]));
        draw_over(&mut dst, &src, 0, 0, 1.0);
        let p = dst.get_pixel(0, 0).0;
        assert_eq!(&p[..3], &[200, 100, 50]);
        assert_eq!(p[3], 128);
    }

    #[test]
    fn resize_keeps_alpha_edges_clean() {
        // red opaque square on transparent black: no dark fringe after resize
        let mut img = RgbaImage::new(64, 64);
        for y in 16..48 {
            for x in 16..48 {
                img.put_pixel(x, y, image::Rgba([255, 0, 0, 255]));
            }
        }
        let r = resize(&img, 23, 23);
        for p in r.pixels() {
            if p.0[3] > 20 {
                assert!(p.0[0] > 200, "fringe detected: {:?}", p.0);
            }
        }
    }

    #[test]
    fn distance_transform_basic() {
        let w = 5;
        let mut seed = vec![false; 25];
        seed[0] = true;
        let d = distance_from(&seed, w, 5);
        assert_eq!(d[0], 0.0);
        assert!((d[4] - 4.0).abs() < 1e-4);
    }
}
