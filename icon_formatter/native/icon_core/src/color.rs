//! Colour helpers: sRGB <-> linear and OKLab for perceptual distances.

#[inline]
pub fn srgb_to_linear(c: f32) -> f32 {
    if c <= 0.04045 {
        c / 12.92
    } else {
        ((c + 0.055) / 1.055).powf(2.4)
    }
}

/// Lookup table for u8 sRGB -> linear.
pub fn linear_lut() -> [f32; 256] {
    let mut t = [0f32; 256];
    for (i, v) in t.iter_mut().enumerate() {
        *v = srgb_to_linear(i as f32 / 255.0);
    }
    t
}

/// OKLab colour (L in 0..1, a/b roughly -0.4..0.4).
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Lab {
    pub l: f32,
    pub a: f32,
    pub b: f32,
}

impl Lab {
    #[inline]
    pub fn dist(&self, o: &Lab) -> f32 {
        let dl = self.l - o.l;
        let da = self.a - o.a;
        let db = self.b - o.b;
        (dl * dl + da * da + db * db).sqrt()
    }
}

#[inline]
pub fn oklab_from_linear(r: f32, g: f32, b: f32) -> Lab {
    let l = 0.412_221_46 * r + 0.536_332_55 * g + 0.051_445_995 * b;
    let m = 0.211_903_5 * r + 0.680_699_5 * g + 0.107_396_96 * b;
    let s = 0.088_302_46 * r + 0.281_718_85 * g + 0.629_978_7 * b;
    let l_ = l.cbrt();
    let m_ = m.cbrt();
    let s_ = s.cbrt();
    Lab {
        l: 0.210_454_26 * l_ + 0.793_617_8 * m_ - 0.004_072_047 * s_,
        a: 1.977_998_5 * l_ - 2.428_592_2 * m_ + 0.450_593_7 * s_,
        b: 0.025_904_037 * l_ + 0.782_771_77 * m_ - 0.808_675_77 * s_,
    }
}

/// Converts a whole RGBA8 buffer to OKLab (alpha ignored).
pub fn rgba_to_oklab(buf: &[u8], lut: &[f32; 256]) -> Vec<Lab> {
    buf.chunks_exact(4)
        .map(|p| oklab_from_linear(lut[p[0] as usize], lut[p[1] as usize], lut[p[2] as usize]))
        .collect()
}
