//! Procedural "Nothing Translucent"-inspired background.
//!
//! Neutral smoky charcoal glass rendered into the PNG (no dependency on the
//! launcher's live blur or wallpaper): vertical light falloff, frosted grain,
//! soft top reflection, thin light-facing rim and an inner depth shadow.
//! Colours stay neutral: the optional tint is limited to +-2/255 per channel.

use crate::squircle::{self, Shape};
use image::RgbaImage;
use rayon::prelude::*;
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct TranslucentParams {
    /// 0..1 overall luminance of the glass (0.5 = default charcoal).
    pub brightness: f32,
    /// 0..1 frosted grain and milky diffusion.
    pub frost: f32,
    /// 0..1 simulated transparency; 0 = fully opaque baked PNG.
    pub transparency: f32,
    /// -1..1 neutral warm/cool micro tint (max +-2/255).
    pub tint: f32,
    /// 0..1 top-to-bottom light falloff.
    pub contrast: f32,
    /// 0..1 rim/border intensity.
    pub border: f32,
    /// 0..1 glossy reflections.
    pub reflection: f32,
    /// 0..1 inner shadow / depth.
    pub depth: f32,
    pub shape: Shape,
    pub seed: u32,
}

impl Default for TranslucentParams {
    fn default() -> Self {
        TranslucentParams {
            brightness: 0.5,
            frost: 0.5,
            transparency: 0.0,
            tint: 0.0,
            contrast: 0.5,
            border: 0.6,
            reflection: 0.45,
            depth: 0.5,
            shape: Shape::default(),
            seed: 7,
        }
    }
}

#[inline]
fn hash(x: i32, y: i32, seed: u32) -> f32 {
    let mut h = (x as u32).wrapping_mul(374_761_393)
        ^ (y as u32).wrapping_mul(668_265_263)
        ^ seed.wrapping_mul(2_246_822_519);
    h = (h ^ (h >> 13)).wrapping_mul(1_274_126_177);
    h ^= h >> 16;
    (h & 0x00ff_ffff) as f32 / 16_777_215.0
}

#[inline]
fn smooth(t: f32) -> f32 {
    t * t * (3.0 - 2.0 * t)
}

fn value_noise(x: f32, y: f32, seed: u32) -> f32 {
    let (xi, yi) = (x.floor() as i32, y.floor() as i32);
    let (tx, ty) = (smooth(x - xi as f32), smooth(y - yi as f32));
    let a = hash(xi, yi, seed);
    let b = hash(xi + 1, yi, seed);
    let c = hash(xi, yi + 1, seed);
    let d = hash(xi + 1, yi + 1, seed);
    let ab = a + (b - a) * tx;
    let cd = c + (d - c) * tx;
    ab + (cd - ab) * ty
}

fn fbm(x: f32, y: f32, seed: u32) -> f32 {
    let mut amp = 0.5;
    let mut f = 1.0;
    let mut s = 0.0;
    for o in 0..4 {
        s += amp * (value_noise(x * f, y * f, seed.wrapping_add(o * 101)) - 0.5);
        f *= 2.0;
        amp *= 0.5;
    }
    s
}

/// Renders the background at `size` x `size`.
pub fn render(size: u32, p: &TranslucentParams) -> RgbaImage {
    let size = size.max(16);
    let mut img = RgbaImage::new(size, size);
    let shape = p.shape.sanitized();
    let half = size as f32 * shape.size_ratio / 2.0;
    let px_unit = 1.0 / half; // one pixel in normalised units
    // base charcoal: 0.5 -> ~#333333 at the centre; never near-absolute black
    let base = 0.11 + p.brightness.clamp(0.0, 1.0) * 0.24;
    let frost = p.frost.clamp(0.0, 1.0);
    let refl = p.reflection.clamp(0.0, 1.0);
    let border = p.border.clamp(0.0, 1.0);
    let depth = p.depth.clamp(0.0, 1.0);
    let contrast = p.contrast.clamp(0.0, 1.0);
    let tint = p.tint.clamp(-1.0, 1.0) * 2.0 / 255.0;
    let alpha_scale = 1.0 - p.transparency.clamp(0.0, 1.0) * 0.6;
    let noise_scale = 24.0 / size as f32 * (size as f32 / 192.0).sqrt();
    let (lx, ly) = (-0.6f32, -0.8f32); // light from top-left

    img.par_chunks_mut((size * 4) as usize).enumerate().for_each(|(y, row)| {
        for x in 0..size as usize {
            let s = squircle::sample(x as u32, y as u32, size, &shape);
            if s.coverage <= 0.0 {
                continue;
            }
            let (u, v) = (s.u, s.v);
            let e = s.edge_dist.max(0.0) * px_unit; // normalised edge distance
            // vertical falloff, lighter top
            let mut g = base * (1.0 + contrast * 0.42 * (-v) * 0.5);
            // frosted milky diffusion (top centre) and grain
            g += frost * 0.045 * (-((u * u) / 0.9 + (v + 0.55) * (v + 0.55) / 0.35)).exp();
            let grain_lo = fbm(x as f32 * noise_scale, y as f32 * noise_scale, p.seed);
            let grain_hi = hash(x as i32, y as i32, p.seed ^ 0x9e37) - 0.5;
            g += frost * (grain_lo * 0.05 + grain_hi * 0.018);
            // glossy reflection: soft top ellipse + diagonal sheen
            g += refl * 0.07 * (-((u + 0.15) * (u + 0.15) * 1.6 + (v + 0.78) * (v + 0.78) * 9.0)).exp();
            let diag = (u + v + 1.15) / 0.55;
            if diag < 1.0 && diag > -1.0 {
                g += refl * 0.035 * (1.0 - diag * diag) * (1.0 - (v + 1.0) * 0.5).max(0.0);
            }
            // depth: inner shadow at the bottom, slight vignette
            let facing_down = s.ny.max(0.0);
            g -= depth * 0.10 * (-e / 0.10).exp() * facing_down;
            g -= depth * 0.035 * (u * u + v * v).min(2.0) * 0.5;
            // rim: thin bright edge facing the light, faint everywhere else
            let facing = (s.nx * lx + s.ny * ly).max(0.0);
            let rim = (-(s.edge_dist.max(0.0)) / 1.15).exp();
            let rim_wide = (-e / 0.035).exp();
            g += border * rim * (0.05 + 0.40 * facing.powf(1.6));
            g += border * rim_wide * 0.05 * facing;
            g = g.clamp(0.0, 1.0);
            let dither = (hash(x as i32, y as i32, 0x51ed) - 0.5) / 255.0;
            let r = (g + tint + dither).clamp(0.0, 1.0);
            let gg = (g + dither).clamp(0.0, 1.0);
            let b = (g - tint + dither).clamp(0.0, 1.0);
            // rim stays more opaque than the body when transparency is used
            let body_a = alpha_scale + (1.0 - alpha_scale) * (rim * border * 0.8);
            let a = (s.coverage * body_a).clamp(0.0, 1.0);
            let o = x * 4;
            row[o] = (r * 255.0).round() as u8;
            row[o + 1] = (gg * 255.0).round() as u8;
            row[o + 2] = (b * 255.0).round() as u8;
            row[o + 3] = (a * 255.0).round() as u8;
        }
    });
    img
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn neutral_and_brighter_than_black() {
        let img = render(192, &TranslucentParams::default());
        let c = img.get_pixel(96, 120).0;
        assert_eq!(c[3], 255);
        assert!(c[0] > 30, "too dark: {:?}", c);
        let spread = c[0].max(c[1]).max(c[2]) - c[0].min(c[1]).min(c[2]);
        assert!(spread <= 2, "colour cast: {:?}", c);
        assert_eq!(img.get_pixel(0, 0).0[3], 0);
    }

    #[test]
    fn transparency_lowers_alpha() {
        let p = TranslucentParams { transparency: 1.0, ..Default::default() };
        let img = render(128, &p);
        let a = img.get_pixel(64, 64).0[3];
        assert!(a < 120 && a > 80, "{}", a);
    }
}
