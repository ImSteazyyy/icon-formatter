//! Plate transparency of finished icons.
//!
//! Icons that come from another pack (the calendar days, for example) often
//! carry a translucent background of their own, and the new plate is drawn
//! under it: the two stack and the icon ends up darker and less see-through
//! than the rest of the pack. [`plate_alpha`] measures how see-through the
//! plate of an icon is, and [`remap_plate_alpha`] brings another icon's plate
//! to that value without touching its colours or its opaque details.

use image::RgbaImage;

use crate::imageops::alpha_bbox;

/// Median alpha (0..1) of the plate of a finished icon.
///
/// Four bands inside the visible box are read, on the middle of each side and
/// away from the corners and from the outermost rim (where the light outline
/// is). Artwork rarely covers all four, so the median is the plate.
pub fn plate_alpha(img: &RgbaImage) -> Option<f32> {
    let (x0, y0, x1, y1) = alpha_bbox(img, 8)?;
    let (w, h) = ((x1 - x0) as f32, (y1 - y0) as f32);
    if w < 16.0 || h < 16.0 {
        return None;
    }
    // 7%..13% from the edge, over the middle 40% of the side
    let (near, far, from, to) = (0.07, 0.13, 0.30, 0.70);
    let span = |lo: f32, size: f32, a: f32, b: f32| ((lo + a * size) as u32, (lo + b * size) as u32);
    let (xa, xb) = span(x0 as f32, w, from, to);
    let (ya, yb) = span(y0 as f32, h, from, to);
    let (top0, top1) = span(y0 as f32, h, near, far);
    let (bot0, bot1) = span(y0 as f32, h, 1.0 - far, 1.0 - near);
    let (left0, left1) = span(x0 as f32, w, near, far);
    let (right0, right1) = span(x0 as f32, w, 1.0 - far, 1.0 - near);
    let mut v: Vec<u8> = Vec::new();
    let mut take = |xs: (u32, u32), ys: (u32, u32)| {
        for y in ys.0..ys.1.min(img.height()) {
            for x in xs.0..xs.1.min(img.width()) {
                v.push(img.get_pixel(x, y)[3]);
            }
        }
    };
    take((xa, xb), (top0, top1));
    take((xa, xb), (bot0, bot1));
    take((left0, left1), (ya, yb));
    take((right0, right1), (ya, yb));
    if v.is_empty() {
        return None;
    }
    v.sort_unstable();
    Some(v[v.len() / 2] as f32 / 255.0)
}

/// Brings a plate of alpha `own` to `target`: a piecewise-linear curve that
/// maps 0 to 0, `own` to `target` and 1 to 1. Colours are left as they are,
/// so opaque details (the number, the header) keep their full strength.
///
/// Returns false, and changes nothing, when there is nothing to tell the
/// plate from the artwork: a plate already at `target`, or a fully opaque one.
pub fn remap_plate_alpha(img: &mut RgbaImage, own: f32, target: f32) -> bool {
    if (own - target).abs() < 0.01 || own < 0.02 || own > 0.98 {
        return false;
    }
    let target = target.clamp(0.0, 1.0);
    for px in img.pixels_mut() {
        let a = px[3] as f32 / 255.0;
        let b = if a <= own { a * target / own } else { target + (a - own) * (1.0 - target) / (1.0 - own) };
        px[3] = (b * 255.0).round().clamp(0.0, 255.0) as u8;
    }
    true
}

/// Median of `values`; None when empty.
pub fn median(values: &mut [f32]) -> Option<f32> {
    if values.is_empty() {
        return None;
    }
    values.sort_by(|a, b| a.total_cmp(b));
    Some(values[values.len() / 2])
}

#[cfg(test)]
mod tests {
    use super::*;
    use image::Rgba;

    /// 128 px icon: plate of alpha `plate` over the whole box, an opaque white
    /// square in the middle (the "number") and an opaque red bar on top.
    fn icon(plate: u8) -> RgbaImage {
        let mut img = RgbaImage::from_pixel(128, 128, Rgba([20, 20, 24, plate]));
        for y in 44..84 {
            for x in 44..84 {
                img.put_pixel(x, y, Rgba([255, 255, 255, 255]));
            }
        }
        for y in 0..6 {
            for x in 0..128 {
                img.put_pixel(x, y, Rgba([220, 40, 40, 255]));
            }
        }
        img
    }

    #[test]
    fn measures_the_plate_not_the_artwork() {
        let a = plate_alpha(&icon(153)).unwrap();
        assert!((a - 0.6).abs() < 0.01, "{a}");
    }

    #[test]
    fn remap_moves_the_plate_and_keeps_the_artwork() {
        let mut img = icon(153);
        assert!(remap_plate_alpha(&mut img, 0.6, 0.4));
        let a = plate_alpha(&img).unwrap();
        assert!((a - 0.4).abs() < 0.01, "{a}");
        // artwork stays fully opaque, colours untouched
        assert_eq!(img.get_pixel(64, 64), &Rgba([255, 255, 255, 255]));
        assert_eq!(img.get_pixel(10, 2), &Rgba([220, 40, 40, 255]));
        assert_eq!(&img.get_pixel(20, 64).0[..3], &[20u8, 20, 24][..]);
        // fully transparent stays fully transparent
        let mut clear = RgbaImage::from_pixel(4, 4, Rgba([1, 2, 3, 0]));
        clear.put_pixel(0, 0, Rgba([9, 9, 9, 153]));
        assert!(remap_plate_alpha(&mut clear, 0.6, 0.3));
        assert_eq!(clear.get_pixel(3, 3)[3], 0);
    }

    #[test]
    fn opaque_plate_or_equal_plate_is_left_alone() {
        let mut opaque = icon(255);
        assert!(!remap_plate_alpha(&mut opaque, 1.0, 0.4));
        let mut same = icon(102);
        assert!(!remap_plate_alpha(&mut same, 0.4, 0.4));
    }
}
