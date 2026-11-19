//! Optional image effects around the renderers. Every option has a neutral
//! value that leaves the image untouched, so the default output does not
//! change. Each function is one pass over the pixels (the blur is separable).

use crate::lucent::NATIVE_BACKGROUND_SCALE;
use image::RgbaImage;

/// Global colour adjustment, neutral at all zeros.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Adjust {
    /// -1..1: towards black (negative) or white (positive).
    pub brightness: f32,
    /// -1..1: -1 is greyscale, +1 doubles the chroma.
    pub saturation: f32,
    /// Hue rotation in degrees.
    pub hue: f32,
}

impl Adjust {
    pub fn is_neutral(&self) -> bool {
        self.brightness == 0.0 && self.saturation == 0.0 && self.hue == 0.0
    }
}

/// Options that act on the symbol or the final icon. `Default` is off.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Effects {
    /// Applied to the whole final icon (RGB only).
    pub adjust: Adjust,
    /// Monochrome recolour of the symbol, its alpha kept.
    pub recolor: Option<[u8; 3]>,
    /// 0..1: plate colour pulled towards the symbol's mean colour.
    pub plate_tint: f32,
    /// 0..1: unsharp strength, used only when the symbol is scaled up more than 2x.
    pub sharpen: f32,
}

/// Applies brightness, saturation and hue to the straight RGB of every pixel.
/// Alpha is untouched, so translucent pixels stay translucent.
pub fn adjust_color(img: &mut RgbaImage, a: &Adjust) {
    if a.is_neutral() {
        return;
    }
    // hue rotation: the CSS hue-rotate matrix (rows sum to 1, greys stay grey)
    let th = a.hue.to_radians();
    let (c, s) = (th.cos(), th.sin());
    let m = [
        [0.213 + c * 0.787 - s * 0.213, 0.715 - c * 0.715 - s * 0.715, 0.072 - c * 0.072 + s * 0.928],
        [0.213 - c * 0.213 + s * 0.143, 0.715 + c * 0.285 + s * 0.140, 0.072 - c * 0.072 - s * 0.283],
        [0.213 - c * 0.213 - s * 0.787, 0.715 - c * 0.715 + s * 0.715, 0.072 + c * 0.928 + s * 0.072],
    ];
    let sat = (1.0 + a.saturation).max(0.0);
    let bri = a.brightness;
    for px in img.pixels_mut() {
        let (r, g, b) = (px[0] as f32, px[1] as f32, px[2] as f32);
        let rot = [
            m[0][0] * r + m[0][1] * g + m[0][2] * b,
            m[1][0] * r + m[1][1] * g + m[1][2] * b,
            m[2][0] * r + m[2][1] * g + m[2][2] * b,
        ];
        let luma = 0.2126 * rot[0] + 0.7152 * rot[1] + 0.0722 * rot[2];
        for (i, &v) in rot.iter().enumerate() {
            let v = luma + (v - luma) * sat;
            let v = if bri >= 0.0 { v + (255.0 - v) * bri } else { v * (1.0 + bri) };
            px[i] = v.round().clamp(0.0, 255.0) as u8;
        }
    }
}

/// Sets the colour of every visible pixel, keeping its alpha.
pub fn recolor(img: &mut RgbaImage, rgb: [u8; 3]) {
    for px in img.pixels_mut() {
        if px[3] > 0 {
            px[0] = rgb[0];
            px[1] = rgb[1];
            px[2] = rgb[2];
        }
    }
}

/// Alpha-weighted mean colour of the visible pixels (None when empty).
pub fn mean_color(img: &RgbaImage) -> Option<[u8; 3]> {
    let (mut s, mut n) = ([0f64; 3], 0f64);
    for px in img.pixels() {
        let a = px[3] as f64;
        if a > 0.0 {
            for c in 0..3 {
                s[c] += px[c] as f64 * a;
            }
            n += a;
        }
    }
    (n > 0.0).then(|| [0, 1, 2].map(|c| (s[c] / n).round() as u8))
}

/// Plate colour pulled towards `mean` by `strength` (0..1). The plate alpha stays.
pub fn tint_backdrop(bd: [u8; 4], mean: [u8; 3], strength: f32) -> [u8; 4] {
    let t = strength.clamp(0.0, 1.0);
    let mix = |b: u8, m: u8| (b as f32 + (m as f32 - b as f32) * t).round() as u8;
    [mix(bd[0], mean[0]), mix(bd[1], mean[1]), mix(bd[2], mean[2]), bd[3]]
}

const KERNEL: [f32; 5] = [1.0 / 16.0, 4.0 / 16.0, 6.0 / 16.0, 4.0 / 16.0, 1.0 / 16.0];

/// One separable 5-tap pass over premultiplied RGBA (4 floats per pixel).
fn blur_pass(src: &[f32], dst: &mut [f32], w: usize, h: usize, horizontal: bool) {
    for y in 0..h {
        for x in 0..w {
            let mut acc = [0f32; 4];
            for (k, wgt) in KERNEL.iter().enumerate() {
                let off = k as isize - 2;
                let (sx, sy) = if horizontal {
                    ((x as isize + off).clamp(0, w as isize - 1) as usize, y)
                } else {
                    (x, (y as isize + off).clamp(0, h as isize - 1) as usize)
                };
                let si = (sy * w + sx) * 4;
                for c in 0..4 {
                    acc[c] += src[si + c] * wgt;
                }
            }
            let di = (y * w + x) * 4;
            dst[di..di + 4].copy_from_slice(&acc);
        }
    }
}

/// Unsharp mask on the colour. The blur runs on premultiplied colour, so
/// transparent neighbours cannot darken the edges. Alpha is not changed.
/// `amount` 0 is off, 1 is strong.
pub fn unsharp(img: &mut RgbaImage, amount: f32) {
    let k = amount.clamp(0.0, 1.0);
    let (w, h) = (img.width() as usize, img.height() as usize);
    if k <= 0.0 || w == 0 || h == 0 {
        return;
    }
    let mut pm = vec![0f32; w * h * 4];
    for (i, px) in img.pixels().enumerate() {
        let a = px[3] as f32 / 255.0;
        for c in 0..3 {
            pm[i * 4 + c] = px[c] as f32 * a;
        }
        pm[i * 4 + 3] = a;
    }
    let mut tmp = vec![0f32; w * h * 4];
    blur_pass(&pm, &mut tmp, w, h, true);
    let mut bl = vec![0f32; w * h * 4];
    blur_pass(&tmp, &mut bl, w, h, false);
    for (i, px) in img.pixels_mut().enumerate() {
        let (a, ba) = (pm[i * 4 + 3], bl[i * 4 + 3]);
        if a <= 0.0 || ba <= 0.0 {
            continue;
        }
        for c in 0..3 {
            let v = px[c] as f32;
            let blurred = bl[i * 4 + c] / ba;
            px[c] = (v + k * (v - blurred)).round().clamp(0.0, 255.0) as u8;
        }
    }
}

/// Largest optical shift per axis: the glyph box must stay on the plate
/// (plate = `NATIVE_BACKGROUND_SCALE` of the canvas) and move at most 4%.
pub fn optical_limit(cw: f32, ch: f32, tw: u32, th: u32) -> (f32, f32) {
    let lim = |size: f32, t: u32| ((NATIVE_BACKGROUND_SCALE * size - t as f32) / 2.0).clamp(0.0, 0.04 * size);
    (lim(cw, tw), lim(ch, th))
}

/// Shift (pixels) that moves the alpha-weighted centroid of `img` onto its
/// centre, clamped to `max` per axis. Zero for an empty image.
pub fn centroid_shift(img: &RgbaImage, max: (f32, f32)) -> (f32, f32) {
    let (w, h) = img.dimensions();
    let (mut sx, mut sy, mut sa) = (0f64, 0f64, 0f64);
    for (x, y, px) in img.enumerate_pixels() {
        let a = px[3] as f64;
        if a > 0.0 {
            sx += (x as f64 + 0.5) * a;
            sy += (y as f64 + 0.5) * a;
            sa += a;
        }
    }
    if sa <= 0.0 {
        return (0.0, 0.0);
    }
    let dx = (w as f64 / 2.0 - sx / sa) as f32;
    let dy = (h as f64 / 2.0 - sy / sa) as f32;
    (dx.clamp(-max.0, max.0), dy.clamp(-max.1, max.1))
}

#[cfg(test)]
mod tests {
    use super::*;
    use image::Rgba;

    fn grey_img() -> RgbaImage {
        let mut img = RgbaImage::new(8, 8);
        for (i, px) in img.pixels_mut().enumerate() {
            let v = (i * 4) as u8;
            *px = Rgba([v, v, v, 200]);
        }
        img
    }

    #[test]
    fn neutral_adjust_is_identity() {
        let mut img = grey_img();
        let before = img.clone();
        adjust_color(&mut img, &Adjust::default());
        assert_eq!(img, before);
    }

    #[test]
    fn adjust_keeps_alpha_and_greys() {
        let mut img = grey_img();
        let alpha: Vec<u8> = img.pixels().map(|p| p[3]).collect();
        adjust_color(&mut img, &Adjust { brightness: 0.0, saturation: -0.5, hue: 137.0 });
        // hue rotation keeps greys grey; saturation pulls them to grey too
        for (px, a) in img.pixels().zip(alpha) {
            assert_eq!(px[3], a);
            assert!((px[0] as i32 - px[1] as i32).abs() <= 1 && (px[1] as i32 - px[2] as i32).abs() <= 1);
        }
    }

    #[test]
    fn full_brightness_is_white_and_desaturate_is_grey() {
        let mut img = RgbaImage::from_pixel(2, 2, Rgba([200, 30, 60, 255]));
        adjust_color(&mut img, &Adjust { brightness: 1.0, saturation: 0.0, hue: 0.0 });
        assert_eq!(img.get_pixel(0, 0).0[..3], [255, 255, 255]);
        let mut img = RgbaImage::from_pixel(2, 2, Rgba([200, 30, 60, 128]));
        adjust_color(&mut img, &Adjust { brightness: 0.0, saturation: -1.0, hue: 0.0 });
        let p = img.get_pixel(0, 0);
        assert!(p[0] == p[1] && p[1] == p[2]);
        assert_eq!(p[3], 128);
    }

    #[test]
    fn recolor_keeps_alpha() {
        let mut img = grey_img();
        let alpha: Vec<u8> = img.pixels().map(|p| p[3]).collect();
        recolor(&mut img, [10, 20, 30]);
        for (px, a) in img.pixels().zip(alpha) {
            assert_eq!(px.0[..3], [10, 20, 30]);
            assert_eq!(px[3], a);
        }
    }

    #[test]
    fn mean_color_is_alpha_weighted() {
        let mut img = RgbaImage::new(2, 1);
        img.put_pixel(0, 0, Rgba([255, 255, 255, 255]));
        img.put_pixel(1, 0, Rgba([0, 0, 0, 0]));
        // the transparent black does not count
        assert_eq!(mean_color(&img), Some([255, 255, 255]));
        img.put_pixel(1, 0, Rgba([0, 0, 0, 255]));
        assert_eq!(mean_color(&img), Some([128, 128, 128]));
        assert_eq!(mean_color(&RgbaImage::new(2, 2)), None);
    }

    #[test]
    fn tint_strength_and_alpha() {
        let bd = [0, 0, 0, 0x66];
        assert_eq!(tint_backdrop(bd, [200, 100, 50], 0.0), bd);
        assert_eq!(tint_backdrop(bd, [200, 100, 50], 1.0), [200, 100, 50, 0x66]);
    }

    #[test]
    fn unsharp_flat_image_unchanged_and_edges_sharpen() {
        let mut flat = RgbaImage::from_pixel(9, 9, Rgba([90, 90, 90, 255]));
        unsharp(&mut flat, 1.0);
        assert!(flat.pixels().all(|p| p[0] == 90));
        // a step edge gets more contrast, alpha is kept
        let mut step = RgbaImage::new(8, 4);
        for (x, _, px) in step.enumerate_pixels_mut() {
            *px = if x < 4 { Rgba([100, 100, 100, 255]) } else { Rgba([160, 160, 160, 255]) };
        }
        unsharp(&mut step, 0.5);
        assert!(step.get_pixel(3, 1)[0] < 100);
        assert!(step.get_pixel(4, 1)[0] > 160);
        assert!(step.pixels().all(|p| p[3] == 255));
        // transparent pixels are untouched
        let mut clear = RgbaImage::from_pixel(5, 5, Rgba([7, 8, 9, 0]));
        unsharp(&mut clear, 1.0);
        assert!(clear.pixels().all(|p| p.0[..3] == [7, 8, 9]));
    }

    #[test]
    fn centroid_shift_moves_mass_to_centre_within_limit() {
        // mass on the left: the shift points right
        let mut img = RgbaImage::new(40, 40);
        for y in 0..40 {
            for x in 0..10 {
                img.put_pixel(x, y, Rgba([0, 0, 0, 255]));
            }
        }
        let (dx, dy) = centroid_shift(&img, (100.0, 100.0));
        assert!(dx > 10.0 && dy.abs() < 1e-3);
        let (dx, _) = centroid_shift(&img, (3.0, 3.0));
        assert!((dx - 3.0).abs() < 1e-6);
        assert_eq!(centroid_shift(&RgbaImage::new(4, 4), (9.0, 9.0)), (0.0, 0.0));
    }

    #[test]
    fn optical_limit_keeps_glyph_on_plate() {
        // a glyph as wide as the plate cannot move at all
        assert_eq!(optical_limit(100.0, 100.0, 93, 10).0, 0.0);
        // a small glyph moves at most 4% of the canvas
        assert_eq!(optical_limit(100.0, 100.0, 40, 40).0, 4.0);
    }

    #[test]
    fn placement_optical_centre_moves_centroid() {
        use crate::compose::{place_glyph, Placement};
        // L shape: a full bar at the bottom and a column on the left
        let mut glyph = RgbaImage::new(40, 40);
        for y in 0..40 {
            for x in 0..40 {
                if x < 8 || y >= 32 {
                    glyph.put_pixel(x, y, Rgba([0, 0, 0, 255]));
                }
            }
        }
        let centroid_x = |c: &RgbaImage| {
            let (mut s, mut n) = (0f64, 0f64);
            for (x, _, p) in c.enumerate_pixels() {
                s += x as f64 * p[3] as f64;
                n += p[3] as f64;
            }
            s / n
        };
        let mut off = RgbaImage::new(100, 100);
        place_glyph(&mut off, &glyph, &Placement::default());
        let mut on = RgbaImage::new(100, 100);
        place_glyph(&mut on, &glyph, &Placement { optical_centre: true, ..Placement::default() });
        let (c_off, c_on) = (centroid_x(&off), centroid_x(&on));
        assert!((c_on - 50.0).abs() < (c_off - 50.0).abs());
        // clamped: the shift is at most 4% of the canvas
        assert!((c_on - c_off).abs() <= 4.5);
    }
}
