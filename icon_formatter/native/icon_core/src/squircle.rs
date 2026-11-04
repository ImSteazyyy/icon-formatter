//! Superellipse ("squircle") geometry. Never circular: the exponent is
//! clamped to >= 3.0 so the shape always keeps flat sides.

use serde::{Deserialize, Serialize};

#[derive(Clone, Copy, Debug, Serialize, Deserialize, PartialEq)]
pub struct Shape {
    /// Shape width as a fraction of the canvas (reference pack: 0.93).
    pub size_ratio: f32,
    /// Superellipse exponent (reference pack fit: 4.25; iOS-like ~5).
    pub exponent: f32,
}

impl Default for Shape {
    fn default() -> Self {
        Shape { size_ratio: 0.93, exponent: 4.25 }
    }
}

impl Shape {
    pub fn sanitized(&self) -> Shape {
        Shape {
            size_ratio: self.size_ratio.clamp(0.5, 1.0),
            exponent: self.exponent.clamp(3.0, 12.0),
        }
    }
}

/// Per-pixel geometric info used by the procedural renderer.
#[derive(Clone, Copy, Debug, Default)]
pub struct Sample {
    /// Anti-aliased coverage 0..1.
    pub coverage: f32,
    /// Approximate distance from the edge, in pixels (positive inside).
    pub edge_dist: f32,
    /// Outward unit normal.
    pub nx: f32,
    pub ny: f32,
    /// Normalised coordinates inside the shape (-1..1).
    pub u: f32,
    pub v: f32,
}

#[inline]
fn level(u: f32, v: f32, n: f32) -> f32 {
    (u.abs().powf(n) + v.abs().powf(n)).powf(1.0 / n)
}

/// Computes the geometric sample for pixel (px, py) of a canvas of `size`.
pub fn sample(px: u32, py: u32, size: u32, shape: &Shape) -> Sample {
    let s = shape.sanitized();
    let half = size as f32 * s.size_ratio / 2.0;
    let c = size as f32 / 2.0;
    let n = s.exponent;
    let x = px as f32 + 0.5 - c;
    let y = py as f32 + 0.5 - c;
    let u = x / half;
    let v = y / half;
    let f = level(u, v, n);
    // gradient of F for the normal and for converting level -> pixels
    let gu = u.signum() * u.abs().powf(n - 1.0) * f.powf(1.0 - n);
    let gv = v.signum() * v.abs().powf(n - 1.0) * f.powf(1.0 - n);
    let glen = (gu * gu + gv * gv).sqrt().max(1e-6);
    let edge_dist = (1.0 - f) * half / glen;
    // coverage: analytic AA where smooth, 4x4 supersampling near the edge
    let coverage = if edge_dist > 1.5 {
        1.0
    } else if edge_dist < -1.5 {
        0.0
    } else {
        let mut acc = 0;
        for j in 0..4 {
            for i in 0..4 {
                let su = (x - 0.5 + (i as f32 + 0.5) / 4.0) / half;
                let sv = (y - 0.5 + (j as f32 + 0.5) / 4.0) / half;
                if level(su, sv, n) <= 1.0 {
                    acc += 1;
                }
            }
        }
        acc as f32 / 16.0
    };
    Sample { coverage, edge_dist, nx: gu / glen, ny: gv / glen, u, v }
}

/// Alpha mask (0..255) of the shape on a square canvas.
pub fn mask(size: u32, shape: &Shape) -> Vec<u8> {
    let mut m = vec![0u8; (size * size) as usize];
    for y in 0..size {
        for x in 0..size {
            m[(y * size + x) as usize] = (sample(x, y, size, shape).coverage * 255.0).round() as u8;
        }
    }
    m
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn squircle_is_not_a_circle() {
        let shape = Shape { size_ratio: 1.0, exponent: 1.0 }; // clamped to 3
        let size = 200;
        let m = mask(size, &shape);
        // A circle of diameter 200 does not cover (25,25); the squircle (n>=3) does.
        assert!(m[(25 * size + 25) as usize] > 128);
        assert_eq!(m[0], 0);
        assert_eq!(m[(100 * size + 100) as usize], 255);
    }
}
