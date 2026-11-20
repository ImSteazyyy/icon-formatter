//! "Lightnt" rendering (translucent icons).
//!
//! Port of the rendering method of Nothing IconGen
//! (<https://github.com/linuxct/nothing-icongen>, AGPL-3.0-only, © linuxct):
//!
//! * `PortableMonochrome.generate`: the launcher's luminance → ink-alpha
//!   conversion (modal grey shift, quadratic ramp above the darkest opaque
//!   grey, complexity classification, light-ink inverted mask);
//! * `IconArtwork.buildIcon`: frosted backdrop plate (`container_frosted_backdrop`,
//!   `#66000000` dark / `#66FFFFFF` light) with the glyph tinted SRC_IN by the
//!   ink colour (`system_neutral1_50` dark / `system_neutral1_900` light);
//! * `PackIconEncoder`: compensation for a launcher drawing a pack icon
//!   as source → ShadowGenerator shadows → source again.
//!
//! Differences from IconGen, by design: the input is a raster icon (not an
//! Android `Drawable`), so the glyph comes from `segment::isolate`; the plate
//! follows the original icon silhouette instead of IconGen's fixed circle
//! (circle and squircle stay available), and the glyph can keep its original
//! position and size inside the icon.

use crate::imageops::resize;
use crate::squircle;
use image::{Rgba, RgbaImage};

const FALLBACK_NOTE: &str = "La sorgente non ha un piatto/sfondo: uso il piatto circolare";
/// Longest glyph side on the fallback circle for bare logos.
const BARE_LOGO_SCALE: f32 = 0.62;

/// Longest glyph side on the plate (launcher normalisation).
pub const GLYPH_SCALE: f32 = 0.388_888_9;
/// Plate size relative to the icon canvas.
pub const NATIVE_BACKGROUND_SCALE: f32 = 0.93;

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum PlateShape {
    /// Silhouette of the source icon (its alpha channel).
    Original,
    /// Circular plate.
    Circle,
    Squircle(squircle::Shape),
}

#[derive(Clone, Debug, PartialEq)]
pub struct LucentParams {
    /// Ink (foreground) colour, RGB.
    pub ink: [u8; 3],
    /// Frosted backdrop colour; `[3]` is its alpha (0x66 by default).
    pub backdrop: [u8; 4],
    pub shape: PlateShape,
    /// Ink conversion (optional). Default false: the glyph keeps its
    /// own colours and only the plate uses the Lightnt treatment.
    pub monochrome: bool,
    /// Keep the glyph's original position/size inside the icon; false uses
    /// the launcher normalisation (longest side 0.389 / 0.93).
    pub keep_composition: bool,
    /// Manual glyph scale multiplier.
    pub glyph_scale: f32,
    /// Manual glyph offset, fraction of the output size.
    pub offset_x: f32,
    pub offset_y: f32,
    /// Subtle light rim on the plate edge (0 = off).
    pub rim: f32,
    /// Dark plate: lift dark neutral greys of the glyph so they stay visible.
    pub lift_greys: bool,
    /// Dark plate: near-neutral dark glyph pixels (black, dark greys) become
    /// light, smoothly by lightness; chromatic pixels keep their colour.
    pub adapt_neutrals: bool,
    /// Bake the launcher's ShadowGenerator shadow into the PNG.
    pub launcher_shadow: bool,
    /// Apply the PackIconEncoder compensation (launchers that draw icons twice).
    pub launcher_encode: bool,
    /// How the symbol is taken from the source (per-app override).
    pub strategy: GlyphStrategy,
    /// Centre the symbol's alpha centroid on the anchor (off = unchanged).
    pub optical_centre: bool,
}

/// Per-app choice of how the symbol is taken from the original icon.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub enum GlyphStrategy {
    /// Decided per icon: full tiles are unwrapped, dark symbols on a coloured
    /// plate take the plate colour, everything else keeps its colours.
    #[default]
    Auto,
    /// The symbol takes the colour of the original plate (holes transparent).
    PlateColor,
    /// The whole original icon fills the plate edge to edge (maps, keyboards...).
    FullBleed,
    /// The isolated symbol as it is, no unwrap and no recolouring.
    AsIs,
    /// Auto, and full-screen icons lose the dark glow around coloured strips
    /// on their edge (only when the user asks for it on one icon).
    CleanEdge,
    /// The whole icon (a page: calendar, finished tile) covers the plate
    /// edge to edge, clipped by the shape; nothing removed, colours kept.
    Tile,
}

impl LucentParams {
    pub fn dark() -> Self {
        LucentParams {
            ink: [0xF1, 0xF0, 0xF4],
            backdrop: [0, 0, 0, 0x66],
            // the plate we render (reference squircle) is the clipping edge
            shape: PlateShape::Squircle(squircle::Shape { size_ratio: 0.93, exponent: 4.25 }),
            monochrome: false,
            keep_composition: true,
            glyph_scale: 1.0,
            offset_x: 0.0,
            offset_y: 0.0,
            rim: 0.0,
            lift_greys: false,
            adapt_neutrals: true,
            launcher_shadow: false,
            launcher_encode: false,
            strategy: GlyphStrategy::Auto,
            optical_centre: false,
        }
    }

    pub fn light() -> Self {
        // light plate: white at 60% (public Nothing widget value; not measured)
        LucentParams { ink: [0x1B, 0x1B, 0x1F], backdrop: [255, 255, 255, 0x99], adapt_neutrals: false, ..Self::dark() }
    }
}

impl Default for LucentParams {
    fn default() -> Self {
        Self::dark()
    }
}

/// Applies the manual corrections of a `Placement` (scale and offset).
pub fn with_placement(p: &LucentParams, pl: &crate::compose::Placement) -> LucentParams {
    LucentParams {
        glyph_scale: p.glyph_scale * pl.scale_mul,
        offset_x: p.offset_x + pl.offset_x,
        offset_y: p.offset_y + pl.offset_y,
        optical_centre: p.optical_centre || pl.optical_centre,
        ..p.clone()
    }
}

pub struct LucentOutput {
    pub image: RgbaImage,
    pub notes: Vec<String>,
}

/// Stair-stepped outlines (sources without anti-aliasing): an opaque pixel
/// right on a hard edge (its 3x3 holds both empty and solid pixels) gets the
/// mean alpha of that 3x3. Only alpha, only those pixels, only downwards:
/// the colours stay, nothing spreads outside the shape (no glow, no smear),
/// and already anti-aliased edges (no hard step) are left as they are.
pub fn soften_hard_edges(img: RgbaImage) -> RgbaImage {
    let (w, h) = img.dimensions();
    if w < 3 || h < 3 {
        return img;
    }
    let a = |x: u32, y: u32| img.get_pixel(x, y)[3];
    let mut out = img.clone();
    for y in 1..h - 1 {
        for x in 1..w - 1 {
            let c = a(x, y);
            if c < 230 {
                continue;
            }
            let (mut lo, mut sum) = (255u8, 0u32);
            for dy in 0..3 {
                for dx in 0..3 {
                    let v = a(x + dx - 1, y + dy - 1);
                    lo = lo.min(v);
                    sum += v as u32;
                }
            }
            if lo <= 20 {
                // half way to the 3x3 mean: a light touch, not a blur
                let mean = sum / 9;
                out.get_pixel_mut(x, y)[3] = ((c as u32 + mean) / 2) as u8;
            }
        }
    }
    out
}

/// A camera-like glyph: one big round dark area (the lens). Lifting its
/// greys would turn the lens flat grey, so it is left as it is. Separate dark
/// pieces (keyboard keys, roads) or a dark square background do not count.
fn dark_lens(img: &RgbaImage) -> bool {
    let (w, h) = (img.width() as usize, img.height() as usize);
    let dark: Vec<bool> = img
        .pixels()
        .map(|q| {
            let (mx, mn) = (q[0].max(q[1]).max(q[2]), q[0].min(q[1]).min(q[2]));
            q[3] > 127 && mx < 80 && mx - mn < 40
        })
        .collect();
    let opaque = img.pixels().filter(|q| q[3] > 127).count();
    if opaque == 0 {
        return false;
    }
    let mut seen = vec![false; w * h];
    for start in 0..w * h {
        if !dark[start] || seen[start] {
            continue;
        }
        seen[start] = true;
        let mut stack = vec![start];
        let (mut n, mut x0, mut y0, mut x1, mut y1) = (0usize, w, h, 0usize, 0usize);
        while let Some(i) = stack.pop() {
            let (x, y) = (i % w, i / w);
            n += 1;
            x0 = x0.min(x);
            y0 = y0.min(y);
            x1 = x1.max(x + 1);
            y1 = y1.max(y + 1);
            for j in [(x > 0).then(|| i - 1), (x + 1 < w).then(|| i + 1), (y > 0).then(|| i - w), (y + 1 < h).then(|| i + w)].into_iter().flatten() {
                if dark[j] && !seen[j] {
                    seen[j] = true;
                    stack.push(j);
                }
            }
        }
        if (n as f32) < 0.20 * opaque as f32 {
            continue;
        }
        let (bw, bh) = ((x1 - x0) as f32, (y1 - y0) as f32);
        let aspect = bw.max(bh) / bw.min(bh).max(1.0);
        let fill = n as f32 / (bw * bh).max(1.0);
        // a disc fills ~78% of its box; a square background ~100%
        if aspect <= 1.2 && (0.55..=0.88).contains(&fill) {
            return true;
        }
    }
    false
}

fn smoothstep(e0: f32, e1: f32, x: f32) -> f32 {
    let t = ((x - e0) / (e1 - e0)).clamp(0.0, 1.0);
    t * t * (3.0 - 2.0 * t)
}

fn luminance(r: u8, g: u8, b: u8) -> i32 {
    (r as f64 * 0.30 + g as f64 * 0.59 + b as f64 * 0.11) as i32
}

/// Source fitted into a `size` square (aspect preserved, centred).
/// Returns the fitted image, scale and offset.
fn fit_square(src: &RgbaImage, size: u32) -> (RgbaImage, f32, f32, f32) {
    let (w, h) = (src.width().max(1) as f32, src.height().max(1) as f32);
    let k = size as f32 / w.max(h);
    let (tw, th) = ((w * k).round().max(1.0) as u32, (h * k).round().max(1.0) as u32);
    let scaled = resize(src, tw, th);
    let (ox, oy) = ((size - tw) / 2, (size - th) / 2);
    let mut out = RgbaImage::new(size, size);
    for y in 0..th {
        for x in 0..tw {
            out.put_pixel(x + ox, y + oy, *scaled.get_pixel(x, y));
        }
    }
    (out, k, ox as f32, oy as f32)
}

/// Plate coverage mask (0..1) at `size`.
fn plate_mask(src: &RgbaImage, glyph: &RgbaImage, size: u32, shape: PlateShape, notes: &mut Vec<String>) -> Vec<f32> {
    let n = (size * size) as usize;
    let circle = |size: u32| -> Vec<f32> {
        let c = size as f32 / 2.0;
        let mut m = vec![0.0; (size * size) as usize];
        for y in 0..size {
            for x in 0..size {
                let d = ((x as f32 + 0.5 - c).powi(2) + (y as f32 + 0.5 - c).powi(2)).sqrt();
                m[(y * size + x) as usize] = (c - d + 0.5).clamp(0.0, 1.0);
            }
        }
        m
    };
    match shape {
        PlateShape::Circle => circle(size),
        PlateShape::Squircle(s) => squircle::mask(size, &s).iter().map(|&v| v as f32 / 255.0).collect(),
        PlateShape::Original => {
            let (fitted, ..) = fit_square(src, size);
            // Soft drop shadows (low alpha) are not part of the silhouette;
            // anti-aliased edges are kept.
            // The plate may itself be semi-transparent (already translucent
            // icons): normalise by its typical alpha level, so a plate at
            // alpha 0.5 still gives a full silhouette while fainter drop
            // shadows stay out.
            // level = median alpha sampled 4% inside the silhouette's edges:
            // the outer plate itself, not an opaque inner tile
            let level = {
                let (x0, y0, x1, y1) = crate::imageops::alpha_bbox(&fitted, 24).unwrap_or((0, 0, size, size));
                let inset = ((x1 - x0).min(y1 - y0) as f32 * 0.04).round().max(1.0) as u32;
                let (ax, ay) = (x0 + inset, y0 + inset);
                let (bx, by) = (x1.saturating_sub(inset + 1).max(ax), y1.saturating_sub(inset + 1).max(ay));
                let mut v: Vec<u8> = Vec::new();
                for k in 1..8u32 {
                    let x = x0 + (x1 - x0) * k / 8;
                    let y = y0 + (y1 - y0) * k / 8;
                    v.extend([fitted.get_pixel(x, ay)[3], fitted.get_pixel(x, by)[3], fitted.get_pixel(ax, y)[3], fitted.get_pixel(bx, y)[3]]);
                }
                v.sort_unstable();
                v[v.len() / 2].max(32) as f32 / 255.0
            };
            let m: Vec<f32> = fitted.pixels().map(|p| smoothstep(0.35 * level, 0.85 * level, p[3] as f32 / 255.0)).collect();
            let coverage = m.iter().sum::<f32>() / n as f32;
            // No plate when the isolated glyph is (almost) the whole opaque
            // area: the source is a bare logo, so there is no silhouette to keep.
            let count = |img: &RgbaImage, t: u8| img.pixels().filter(|p| p[3] > t).count() as f32;
            let bare = count(glyph, 16) >= 0.8 * count(src, 16).max(1.0);
            // ...unless the source itself is a plate: a solid, roughly square
            // silhouette (full-bleed tile, round icon, an icon already in the
            // frosted style). Then the symbol is the whole icon, and its
            // outline is still the shape the user asked to keep.
            let plate_like = || {
                let Some((x0, y0, x1, y1)) = crate::imageops::alpha_bbox(&fitted, 24) else { return false };
                let (bw, bh) = ((x1 - x0) as f32, (y1 - y0) as f32);
                let mut inside = 0.0f32;
                for y in y0..y1 {
                    for x in x0..x1 {
                        inside += m[(y * size + x) as usize];
                    }
                }
                let fill = inside / (bw * bh).max(1.0);
                let aspect = bw.max(bh) / bw.min(bh).max(1.0);
                // a disc fills 78.5% of its box, a squircle ~95%; logos far less
                fill >= 0.74 && aspect <= 1.15 && bw * bh >= 0.35 * (size * size) as f32
            };
            if coverage < 0.10 || (bare && !plate_like()) {
                notes.push(FALLBACK_NOTE.into());
                circle(size)
            } else {
                m
            }
        }
    }
}

/// Port of `PortableMonochrome.classifySource` on a 50 px sample.
fn is_complex(glyph: &RgbaImage) -> bool {
    const S: u32 = 50;
    let (w, h) = (glyph.width().max(1), glyph.height().max(1));
    let k = S as f32 / w.max(h) as f32;
    let (tw, th) = (((w as f32 * k).round() as u32).clamp(1, S), ((h as f32 * k).round() as u32).clamp(1, S));
    let small = resize(glyph, tw, th);
    let mut sample = RgbaImage::new(S, S);
    let (ox, oy) = ((S - tw) / 2, (S - th) / 2);
    for y in 0..th {
        for x in 0..tw {
            sample.put_pixel(x + ox, y + oy, *small.get_pixel(x, y));
        }
    }
    let mut bins = [false; 512];
    let mut colors = 0;
    let mut edges = 0;
    let dist = |a: &Rgba<u8>, b: &Rgba<u8>| -> i32 {
        (a[0] as i32 - b[0] as i32).abs() + (a[1] as i32 - b[1] as i32).abs() + (a[2] as i32 - b[2] as i32).abs()
    };
    for y in 0..S {
        for x in 0..S {
            let p = sample.get_pixel(x, y);
            let bin = (p[0] / 32) as usize * 64 + (p[1] / 32) as usize * 8 + (p[2] / 32) as usize;
            if !bins[bin] {
                bins[bin] = true;
                colors += 1;
            }
            if x + 1 < S && y + 1 < S && dist(p, sample.get_pixel(x + 1, y)) + dist(p, sample.get_pixel(x, y + 1)) > 10 {
                edges += 1;
            }
        }
    }
    colors > 34 || edges as f32 > (S * S) as f32 * 0.3
}

/// The background colour of a tile: the mean of the most common colour (8-step
/// bins) on its outer 3-pixel ring. None when the ring is transparent.
fn border_colour(tile: &RgbaImage) -> Option<[i32; 3]> {
    border_candidates(tile).into_iter().next()
}

/// The up to four most common border colours, most common first.
fn border_candidates(tile: &RgbaImage) -> Vec<[i32; 3]> {
    let (w, h) = tile.dimensions();
    let ring = |x: u32, y: u32| x < 3 || y < 3 || x + 3 >= w || y + 3 >= h;
    let mut bins: std::collections::HashMap<(u8, u8, u8), (usize, [u32; 3])> = std::collections::HashMap::new();
    for (x, y, q) in tile.enumerate_pixels() {
        if q[3] > 200 && ring(x, y) {
            let e = bins.entry((q[0] / 8, q[1] / 8, q[2] / 8)).or_insert((0, [0; 3]));
            e.0 += 1;
            for k in 0..3 {
                e.1[k] += q[k] as u32;
            }
        }
    }
    let mut v: Vec<(usize, [u32; 3])> = bins.into_values().collect();
    v.sort_by(|a, b| b.0.cmp(&a.0));
    v.into_iter().take(4).map(|(n, sum)| [0, 1, 2].map(|k| (sum[k] / n as u32) as i32)).collect()
}

fn dark_plate_of(p: &LucentParams) -> bool {
    (p.backdrop[0] as u32 + p.backdrop[1] as u32 + p.backdrop[2] as u32) < 384
}

/// Dark plate: near-neutral dark pixels of a glyph become light. The weight
/// is the neutrality (channel spread below ~18 is fully neutral, above ~48
/// is chromatic) times the darkness (black is fully remapped, mid greys
/// barely). The shift is added to each channel, so the tonal detail inside
/// the black parts is kept and chromatic pixels are not touched.
fn adapt_neutral_pixels(layer: &mut RgbaImage) {
    for q in layer.pixels_mut() {
        if q[3] == 0 {
            continue;
        }
        let (r, g, b) = (q[0] as f32, q[1] as f32, q[2] as f32);
        let spread = r.max(g).max(b) - r.min(g).min(b);
        let neutral = 1.0 - smoothstep(18.0, 48.0, spread);
        if neutral <= 0.0 {
            continue;
        }
        let l = (r + g + b) / 3.0;
        let dark = 1.0 - smoothstep(40.0, 110.0, l);
        if dark <= 0.0 {
            continue;
        }
        // lightness target: black goes to ~255, a grey of 40 to ~215
        let target = l + (255.0 - 2.0 * l) * dark;
        let shift = (target - l) * neutral;
        for k in 0..3 {
            q[k] = (q[k] as f32 + shift).round().clamp(0.0, 255.0) as u8;
        }
    }
}

/// Connected components (4-neighbour) of the pixels in `valid` that share the
/// same `key`. Returns the component id per pixel (u32::MAX outside `valid`),
/// the size of each component and whether it touches the tile's outer ring.
fn components(key: &[u8], w: u32, h: u32, valid: &[bool]) -> (Vec<u32>, Vec<usize>, Vec<bool>) {
    let (wu, hu, n) = (w as usize, h as usize, (w * h) as usize);
    let mut id = vec![u32::MAX; n];
    let (mut sizes, mut ring) = (Vec::new(), Vec::new());
    let mut stack = Vec::new();
    for s in 0..n {
        if !valid[s] || id[s] != u32::MAX {
            continue;
        }
        let c = sizes.len() as u32;
        id[s] = c;
        stack.push(s);
        let (mut size, mut touches) = (0usize, false);
        while let Some(p) = stack.pop() {
            size += 1;
            let (x, y) = (p % wu, p / wu);
            if x < 3 || y < 3 || x + 3 >= wu || y + 3 >= hu {
                touches = true;
            }
            let mut nb = [usize::MAX; 4];
            if x + 1 < wu {
                nb[0] = p + 1;
            }
            if x > 0 {
                nb[1] = p - 1;
            }
            if y + 1 < hu {
                nb[2] = p + wu;
            }
            if y > 0 {
                nb[3] = p - wu;
            }
            for q in nb.into_iter().filter(|&q| q != usize::MAX) {
                if valid[q] && id[q] == u32::MAX && key[q] == key[p] {
                    id[q] = c;
                    stack.push(q);
                }
            }
        }
        sizes.push(size);
        ring.push(touches);
    }
    (id, sizes, ring)
}

/// Foreground coverage per pixel of whole-tile art (1 = keep, 0 = background).
/// OKLab k-means (k = 4, deterministic seeds). A cluster is background when
/// it covers a good share of the outer ring, is flat (little luminance spread
/// and few edges) and has a big connected region. A compact cluster whose
/// chroma differs clearly from the border colour (a disc, a pin) is kept.
/// Thin or small specks are cleaned up, then the mask is feathered 3x3.
fn foreground_coverage(art: &RgbaImage) -> Option<Vec<f32>> {
    use crate::color::{linear_lut, rgba_to_oklab, Lab};
    const K: usize = 4;
    let (w, h) = art.dimensions();
    let (wu, hu, n) = (w as usize, h as usize, (w * h) as usize);
    let labs = rgba_to_oklab(art.as_raw(), &linear_lut());
    let raw = art.as_raw();
    let valid: Vec<bool> = (0..n).map(|i| raw[i * 4 + 3] > 200).collect();
    let opaque: Vec<usize> = (0..n).filter(|&i| valid[i]).collect();
    if opaque.len() < 100 {
        return None;
    }
    let ring = |i: usize| {
        let (x, y) = (i % wu, i / wu);
        x < 3 || y < 3 || x + 3 >= wu || y + 3 >= hu
    };
    let ring_total = opaque.iter().filter(|&&i| ring(i)).count();
    if ring_total == 0 {
        return None;
    }
    let dist2 = |a: &Lab, b: &Lab| (a.l - b.l).powi(2) + (a.a - b.a).powi(2) + (a.b - b.b).powi(2);
    let nearest = |c: &[Lab], p: &Lab| -> usize {
        (0..c.len())
            .min_by(|&i, &j| dist2(&c[i], p).partial_cmp(&dist2(&c[j], p)).unwrap())
            .unwrap()
    };
    // deterministic seeds: the first sample, then farthest-point sampling
    let stride = (opaque.len() / 40_000).max(1);
    let sample: Vec<usize> = opaque.iter().copied().step_by(stride).collect();
    let mut centres = vec![labs[sample[0]]];
    while centres.len() < K {
        let far = *sample
            .iter()
            .max_by(|&&a, &&b| {
                let da = centres.iter().map(|c| dist2(c, &labs[a])).fold(f32::MAX, f32::min);
                let db = centres.iter().map(|c| dist2(c, &labs[b])).fold(f32::MAX, f32::min);
                da.partial_cmp(&db).unwrap()
            })
            .unwrap();
        centres.push(labs[far]);
    }
    for _ in 0..10 {
        let mut acc = vec![[0f32; 4]; K];
        for &i in &sample {
            let a = &mut acc[nearest(&centres, &labs[i])];
            a[0] += labs[i].l;
            a[1] += labs[i].a;
            a[2] += labs[i].b;
            a[3] += 1.0;
        }
        for (k, a) in acc.iter().enumerate() {
            if a[3] > 0.0 {
                centres[k] = Lab { l: a[0] / a[3], a: a[1] / a[3], b: a[2] / a[3] };
            }
        }
    }
    let mut cid = vec![0u8; n];
    for &i in &opaque {
        cid[i] = nearest(&centres, &labs[i]) as u8;
    }
    // per-cluster statistics
    let mut count = [0usize; K];
    let mut ring_cnt = [0usize; K];
    let mut sum_l = [0f64; K];
    let mut sum_l2 = [0f64; K];
    let mut edges = [0usize; K];
    let mut bbox = [(usize::MAX, usize::MAX, 0usize, 0usize); K];
    for &i in &opaque {
        let k = cid[i] as usize;
        let (x, y) = (i % wu, i / wu);
        count[k] += 1;
        if ring(i) {
            ring_cnt[k] += 1;
        }
        sum_l[k] += labs[i].l as f64;
        sum_l2[k] += (labs[i].l as f64).powi(2);
        let b = &mut bbox[k];
        *b = (b.0.min(x), b.1.min(y), b.2.max(x), b.3.max(y));
        let right = x + 1 < wu && valid[i + 1] && (labs[i].l - labs[i + 1].l).abs() > 0.05;
        let down = y + 1 < hu && valid[i + wu] && (labs[i].l - labs[i + wu].l).abs() > 0.05;
        if right || down {
            edges[k] += 1;
        }
    }
    // big connected regions of each cluster: components of the cluster key
    let (comp_id, comp_size, _) = components(&cid, w, h, &valid);
    let mut big = [false; K];
    for &i in &opaque {
        if comp_size[comp_id[i] as usize] as f32 >= 0.03 * n as f32 {
            big[cid[i] as usize] = true;
        }
    }
    // the border colour: the cluster with most ring pixels
    let border = (0..K).max_by_key(|&k| ring_cnt[k]).unwrap();
    let chroma = |c: &Lab| (c.a * c.a + c.b * c.b).sqrt();
    let mut is_bg = [false; K];
    for k in 0..K {
        if count[k] == 0 {
            continue;
        }
        let m = sum_l[k] / count[k] as f64;
        let std_l = ((sum_l2[k] / count[k] as f64) - m * m).max(0.0).sqrt();
        // anti-aliased edges widen the spread a little: flat = calm, not noise-free
        let flat = std_l < 0.07 && (edges[k] as f32) < 0.15 * count[k] as f32;
        let ring_share = ring_cnt[k] as f32 / ring_total as f32;
        // background only when flat, big, border-connected and close in chroma to the border
        let chroma_ok = k == border || (chroma(&centres[k]) - chroma(&centres[border])).abs() <= 0.05;
        let large = count[k] as f32 >= 0.10 * opaque.len() as f32 || ring_share >= 0.25;
        is_bg[k] = ring_share >= 0.15 && flat && big[k] && chroma_ok && large;
    }
    let mut bg = vec![false; n];
    for &i in &opaque {
        bg[i] = is_bg[cid[i] as usize];
    }
    // clean-up: background specks inside the foreground, pinholes in it
    let bgkey: Vec<u8> = bg.iter().map(|&b| b as u8).collect();
    let (bid, bsize, bring) = components(&bgkey, w, h, &valid);
    for &i in &opaque {
        let c = bid[i] as usize;
        if bg[i] && !bring[c] && (bsize[c] as f32) < 0.003 * n as f32 {
            bg[i] = false;
        }
    }
    let fgkey: Vec<u8> = bg.iter().map(|&b| (!b) as u8).collect();
    let (fid, fsize, fring) = components(&fgkey, w, h, &valid);
    for &i in &opaque {
        let c = fid[i] as usize;
        if !bg[i] && !fring[c] && (fsize[c] as f32) < 0.003 * n as f32 {
            bg[i] = true;
        }
    }
    // feather: coverage = 1 - mean of the 3x3 background mask
    let mut fg = vec![0f32; n];
    for y in 0..hu {
        for x in 0..wu {
            let i = y * wu + x;
            if !valid[i] {
                continue;
            }
            let (mut s, mut k) = (0f32, 0f32);
            for dy in -1i32..=1 {
                for dx in -1i32..=1 {
                    let (nx, ny) = (x as i32 + dx, y as i32 + dy);
                    if nx < 0 || ny < 0 || nx >= wu as i32 || ny >= hu as i32 {
                        continue;
                    }
                    let j = ny as usize * wu + nx as usize;
                    if valid[j] {
                        s += bg[j] as u8 as f32;
                        k += 1.0;
                    }
                }
            }
            fg[i] = 1.0 - s / k.max(1.0);
        }
    }
    Some(fg)
}

/// Flood fill from the border through pixels within 40 of `seed`; returns the
/// background mask and its size (the earlier method, used as the fallback).
fn flood_background(art: &RgbaImage, seed: [i32; 3]) -> (Vec<bool>, usize) {
    const TOL: i32 = 40;
    let (w, h) = art.dimensions();
    let ring = |x: u32, y: u32| x < 3 || y < 3 || x + 3 >= w || y + 3 >= h;
    let dist = |q: &Rgba<u8>| (0..3).map(|k| (q[k] as i32 - seed[k]).abs()).max().unwrap_or(0);
    let mut bg = vec![false; (w * h) as usize];
    let mut stack = Vec::new();
    for y in 0..h {
        for x in 0..w {
            let q = art.get_pixel(x, y);
            if ring(x, y) && q[3] > 200 && dist(q) <= TOL {
                bg[(y * w + x) as usize] = true;
                stack.push((x, y));
            }
        }
    }
    let mut size = stack.len();
    while let Some((x, y)) = stack.pop() {
        for (dx, dy) in [(1i32, 0i32), (-1, 0), (0, 1), (0, -1)] {
            let (nx, ny) = (x as i32 + dx, y as i32 + dy);
            if nx < 0 || ny < 0 || nx >= w as i32 || ny >= h as i32 {
                continue;
            }
            let (nx, ny) = (nx as u32, ny as u32);
            let i = (ny * w + nx) as usize;
            let q = art.get_pixel(nx, ny);
            if !bg[i] && q[3] > 200 && dist(q) <= TOL {
                bg[i] = true;
                size += 1;
                stack.push((nx, ny));
            }
        }
    }
    (bg, size)
}

/// Adds to the background the enclosed flat regions of the border colour that
/// are at least 3% of the tile (the earlier method, used as the fallback).
fn add_flat_regions(art: &RgbaImage, seed: [i32; 3], bg: &mut [bool]) {
    let (w, h) = art.dimensions();
    let total = (w * h) as usize;
    let min_size = (total / 33).max(1);
    let within = |x: u32, y: u32| {
        let q = art.get_pixel(x, y);
        q[3] > 200 && (0..3).all(|k| (q[k] as i32 - seed[k]).abs() <= 40)
    };
    let mut seen = vec![false; total];
    for start in 0..total {
        if seen[start] || bg[start] {
            continue;
        }
        let (sx, sy) = ((start as u32) % w, (start as u32) / w);
        seen[start] = true;
        if !within(sx, sy) {
            continue;
        }
        let mut comp = vec![start];
        let mut i = 0;
        while i < comp.len() {
            let c = comp[i];
            i += 1;
            let (cx, cy) = ((c as u32) % w, (c as u32) / w);
            for (dx, dy) in [(1i32, 0i32), (-1, 0), (0, 1), (0, -1)] {
                let (nx, ny) = (cx as i32 + dx, cy as i32 + dy);
                if nx < 0 || ny < 0 || nx >= w as i32 || ny >= h as i32 {
                    continue;
                }
                let (nx, ny) = (nx as u32, ny as u32);
                let j = (ny * w + nx) as usize;
                if !seen[j] && !bg[j] && within(nx, ny) {
                    seen[j] = true;
                    comp.push(j);
                }
            }
        }
        if comp.len() < min_size {
            continue;
        }
        let n = comp.len() as f64;
        let mut mean = [0f64; 3];
        for &c in &comp {
            let q = art.get_pixel((c as u32) % w, (c as u32) / w);
            for k in 0..3 {
                mean[k] += q[k] as f64;
            }
        }
        let mut var = [0f64; 3];
        for &c in &comp {
            let q = art.get_pixel((c as u32) % w, (c as u32) / w);
            for k in 0..3 {
                var[k] += (q[k] as f64 - mean[k] / n).powi(2);
            }
        }
        if var.iter().all(|v| (v / n).sqrt() < 12.0) {
            for &c in &comp {
                bg[c] = true;
            }
        }
    }
}

/// Foreground coverage from the earlier flood method (1 = keep).
fn flood_foreground(art: &RgbaImage) -> Option<Vec<f32>> {
    let (seed, mut bg) = border_candidates(art)
        .into_iter()
        .map(|s| {
            let (m, n) = flood_background(art, s);
            (s, m, n)
        })
        .max_by_key(|(_, _, n)| *n)
        .map(|(s, m, _)| (s, m))?;
    add_flat_regions(art, seed, &mut bg);
    Some(bg.iter().map(|&b| if b { 0.0 } else { 1.0 }).collect())
}

/// Foreground pixels (coverage above one half) and the bounding box area.
fn fg_stats(fg: &[f32], w: u32) -> (usize, usize) {
    let wu = w as usize;
    let (mut count, mut x0, mut y0, mut x1, mut y1) = (0usize, usize::MAX, usize::MAX, 0usize, 0usize);
    for (i, &c) in fg.iter().enumerate() {
        if c > 0.5 {
            count += 1;
            let (x, y) = (i % wu, i / wu);
            x0 = x0.min(x);
            y0 = y0.min(y);
            x1 = x1.max(x);
            y1 = y1.max(y);
        }
    }
    let area = if count == 0 { 0 } else { (x1 - x0 + 1) * (y1 - y0 + 1) };
    (count, area)
}

/// Core of the flood foreground: pixels that are high-gradient (a neighbour
/// differs by more than 24 in some channel) or mid/high chroma (channel spread
/// above 40). These are the thin details a split must not drop.
fn core_indices(art: &RgbaImage, fg: &[f32]) -> Vec<usize> {
    let (w, h) = art.dimensions();
    let (wu, hu) = (w as usize, h as usize);
    let mut core = Vec::new();
    for (i, &c) in fg.iter().enumerate() {
        if c <= 0.5 {
            continue;
        }
        let (x, y) = (i % wu, i / wu);
        let q = art.get_pixel(x as u32, y as u32);
        let spread = q[0].max(q[1]).max(q[2]) as i32 - q[0].min(q[1]).min(q[2]) as i32;
        let mut grad = false;
        for (dx, dy) in [(1i32, 0i32), (-1, 0), (0, 1), (0, -1)] {
            let (nx, ny) = (x as i32 + dx, y as i32 + dy);
            if nx < 0 || ny < 0 || nx >= wu as i32 || ny >= hu as i32 {
                continue;
            }
            let p = art.get_pixel(nx as u32, ny as u32);
            if (0..3).any(|k| (p[k] as i32 - q[k] as i32).abs() > 24) {
                grad = true;
                break;
            }
        }
        if grad || spread > 40 {
            core.push(i);
        }
    }
    core
}

/// The coverage used for an opaque-plate-free tile: the cluster split when it
/// is safe, otherwise the flood method; a result under 2% of the tile keeps
/// the tile fully opaque. The safe split keeps at least 75% of the flood
/// foreground and at least 85% of its core.
fn choose_coverage(art: &RgbaImage) -> Vec<f32> {
    let total = (art.width() * art.height()) as usize;
    let w = art.width();
    let flood = flood_foreground(art);
    let split = foreground_coverage(art);
    let flood_n = flood.as_ref().map(|v| fg_stats(v, w).0).unwrap_or(0);
    let accepted = match (&split, &flood) {
        (Some(s), Some(f)) => {
            let s_n = fg_stats(s, w).0;
            let core = core_indices(art, f);
            let core_kept = core.iter().filter(|&&i| s[i] > 0.5).count();
            s_n as f32 >= 0.75 * flood_n as f32 && (core.is_empty() || core_kept as f32 >= 0.85 * core.len() as f32)
        }
        _ => false,
    };
    let fg = if accepted { split.unwrap() } else { flood.unwrap_or_else(|| vec![1.0; total]) };
    if (fg_stats(&fg, w).0 as f32) < 0.02 * total as f32 {
        return vec![1.0; total];
    }
    fg
}

/// Whole-tile art under the plate opacity: the background keeps its original
/// colour and takes the plate alpha (opacity 0 = gone); the foreground keeps
/// its own alpha. Coverage from `choose_coverage`.
fn apply_plate_alpha(art: &mut RgbaImage, plate_a: u8) {
    let fg = choose_coverage(art);
    let pa = plate_a as f32 / 255.0;
    for (i, q) in art.pixels_mut().enumerate() {
        if q[3] == 0 {
            continue;
        }
        let k = pa + (1.0 - pa) * fg[i];
        q[3] = (q[3] as f32 * k).round() as u8;
    }
}

/// Auto keeps a tile whole (Tile strategy, colours untouched) when its content
/// is art: no plain background (a map, a multi-colour tile), or content that
/// reaches the tile's outer edge (a calendar page with its band on top). A
/// plain background with one glyph in the middle (a white tile with a star,
/// a black logo) is not kept: it takes the unwrap / glyph path.
fn keep_whole(tile: &RgbaImage) -> bool {
    let (w, h) = tile.dimensions();
    let ring = |x: u32, y: u32| x < 3 || y < 3 || x + 3 >= w || y + 3 >= h;
    let Some(bg) = border_colour(tile) else {
        // a translucent tile (alpha ramp at its edge) has no solid ring: only
        // its soft colour art is kept whole, the rest keeps the old path
        return soft_colour_whole(tile);
    };
    let (mut opaque, mut near_bg, mut edge_content) = (0usize, 0usize, false);
    for (x, y, q) in tile.enumerate_pixels() {
        if q[3] <= 200 {
            continue;
        }
        opaque += 1;
        if (0..3).all(|k| (q[k] as i32 - bg[k]).abs() <= 24) {
            near_bg += 1;
        } else if ring(x, y) {
            edge_content = true;
        }
    }
    let plain = near_bg as f32 > 0.5 * opaque as f32;
    !plain || edge_content || soft_colour_art(tile, bg, opaque)
}

/// The soft colour art test on its own (used for the result note): the tile
/// is soft when `soft_colour_art` holds against its solid or translucent border.
pub fn soft_colour_whole(tile: &RgbaImage) -> bool {
    let Some(bg) = border_colour(tile).or_else(|| loose_border_colour(tile)) else {
        return false;
    };
    let opaque = tile.pixels().filter(|q| q[3] > 200).count();
    soft_colour_art(tile, bg, opaque)
}

/// Result note when soft colour art (colour blur, glow) is kept whole.
pub const SOFT_COLOUR_NOTE: &str = "Arte a colori morbidi: mantenuta intera, senza ritaglio";

/// Mean colour of the visible ring pixels (alpha above 24), for tiles whose
/// edge is an alpha ramp and so have no solid border (see `border_colour`).
fn loose_border_colour(tile: &RgbaImage) -> Option<[i32; 3]> {
    let (w, h) = tile.dimensions();
    let (mut n, mut sum) = (0u32, [0u32; 3]);
    for (x, y, q) in tile.enumerate_pixels() {
        if q[3] > 24 && (x < 3 || y < 3 || x + 3 >= w || y + 3 >= h) {
            n += 1;
            for k in 0..3 {
                sum[k] += q[k] as u32;
            }
        }
    }
    (n > 0).then(|| sum.map(|s| (s / n) as i32))
}

/// Soft colour art on a plain tile (colour blur, glow, a gradient glyph): many
/// saturated pixels off the background that change gently, with almost no crisp
/// colour edge. Unwrapping such a tile takes its blur for background and cuts a
/// hard ring around it, so it is kept whole. A crisp coloured logo is not soft.
fn soft_colour_art(tile: &RgbaImage, bg: [i32; 3], opaque: usize) -> bool {
    let (w, h) = tile.dimensions();
    if w < 5 || h < 5 {
        return false;
    }
    let (mut soft, mut crisp) = (0usize, 0usize);
    for y in 2..h - 2 {
        for x in 2..w - 2 {
            let q = tile.get_pixel(x, y);
            if q[3] <= 200 || (0..3).all(|k| (q[k] as i32 - bg[k]).abs() <= 24) {
                continue;
            }
            let mx = q[0].max(q[1]).max(q[2]) as i32;
            let mn = q[0].min(q[1]).min(q[2]) as i32;
            if mx - mn < 40 {
                continue;
            }
            let (mut lo, mut hi) = (i32::MAX, i32::MIN);
            for dy in 0..5 {
                for dx in 0..5 {
                    let r = tile.get_pixel(x + dx - 2, y + dy - 2);
                    if r[3] > 200 {
                        let l = (r[0] as i32 + r[1] as i32 + r[2] as i32) / 3;
                        lo = lo.min(l);
                        hi = hi.max(l);
                    }
                }
            }
            match hi - lo {
                6..=72 => soft += 1,
                120.. => crisp += 1,
                _ => {}
            }
        }
    }
    // at least 8% of the tile is soft colour, and crisp colour edges are rare
    soft as f32 >= 0.08 * opaque as f32 && crisp * 10 <= soft
}

/// Port of `PortableMonochrome.generate` (pixel conversion) on an isolated
/// glyph: returns the ink alpha mask (same size as `glyph`) and complexity.
pub fn monochrome_mask(glyph: &RgbaImage) -> (Vec<u8>, bool) {
    let complex = is_complex(glyph);
    // modal grey of opaque pixels (32 bins of 8)
    let mut bins = [0u32; 32];
    for p in glyph.pixels() {
        if p[3] > 110 {
            bins[(luminance(p[0], p[1], p[2]) / 8).clamp(0, 31) as usize] += 1;
        }
    }
    let mut mode = 0;
    for i in 1..32 {
        if bins[i] > bins[mode] {
            mode = i;
        }
    }
    let modal = (mode as i32 + 1) * 8 - 1;
    let mut offset = 255 - modal;
    if complex && offset > 80 {
        offset = 0;
    }
    let mut gray = vec![0i32; (glyph.width() * glyph.height()) as usize];
    let mut minimum = 255;
    for (i, p) in glyph.pixels().enumerate() {
        if p[3] == 0 {
            continue;
        }
        let shifted = luminance(p[0], p[1], p[2]) + offset;
        let v = if shifted > 255 { 510 - shifted } else { shifted };
        gray[i] = v;
        if p[3] > 110 {
            minimum = minimum.min(v);
        }
    }
    let factor = if minimum < 248 { 210.0f32 / (248 * 248 - minimum * minimum) as f32 } else { 0.0 };
    let mask = glyph
        .pixels()
        .enumerate()
        .map(|(i, p)| {
            if p[3] > 110 && minimum < 248 {
                (((gray[i] * gray[i] - 248 * 248) as f32 * factor) as i32 + 255).clamp(0, 255) as u8
            } else {
                p[3]
            }
        })
        .collect();
    (mask, complex)
}

/// Port of `PortableMonochrome.lightMask` (used with dark ink on complex art):
/// alpha inverted inside the glyph's inscribed circle.
fn light_mask(mask: &[u8], w: u32, h: u32) -> Vec<u8> {
    let (cx, cy) = (w as f32 / 2.0, h as f32 / 2.0);
    let r = w.max(h) as f32 / 2.0;
    let mut out = vec![0u8; mask.len()];
    let (mut count, mut opaque) = (0u32, 0u32);
    for y in 0..h {
        for x in 0..w {
            let i = (y * w + x) as usize;
            if (x as f32 + 0.5 - cx).powi(2) + (y as f32 + 0.5 - cy).powi(2) <= r * r {
                count += 1;
                let a = 255 - mask[i];
                if a == 0 {
                    opaque += 1;
                }
                out[i] = a;
            }
        }
    }
    if count > 0 && opaque as f32 / count as f32 >= 0.1 {
        for v in out.iter_mut() {
            if *v > 0 {
                *v = v.saturating_add(10);
            }
        }
    }
    out
}

/// Gaussian blur (three box passes) of a single-channel f32 buffer.
pub fn gaussian_blur(buf: &[f32], w: usize, h: usize, sigma: f32) -> Vec<f32> {
    if sigma < 0.3 {
        return buf.to_vec();
    }
    // box sizes for 3 passes (Kovesi)
    let n = 3.0f32;
    let wi = ((12.0 * sigma * sigma / n) + 1.0).sqrt().floor();
    let wl = if (wi as i32) % 2 == 0 { wi - 1.0 } else { wi };
    let wu = wl + 2.0;
    let m = ((12.0 * sigma * sigma - n * wl * wl - 4.0 * n * wl - 3.0 * n) / (-4.0 * wl - 4.0)).round();
    let sizes: Vec<usize> = (0..3).map(|i| if (i as f32) < m { wl as usize } else { wu as usize }).collect();
    let mut a = buf.to_vec();
    let mut b = vec![0.0f32; buf.len()];
    for s in sizes {
        let r = (s.max(1) - 1) / 2;
        box_h(&a, &mut b, w, h, r);
        box_v(&b, &mut a, w, h, r);
    }
    a
}

fn box_h(src: &[f32], dst: &mut [f32], w: usize, h: usize, r: usize) {
    let norm = 1.0 / (2 * r + 1) as f32;
    for y in 0..h {
        let row = &src[y * w..(y + 1) * w];
        let mut acc = 0.0f32;
        for x in 0..=r.min(w - 1) {
            acc += row[x];
        }
        for x in 0..w {
            dst[y * w + x] = acc * norm;
            let add = x + r + 1;
            if add < w {
                acc += row[add];
            }
            if x >= r {
                acc -= row[x - r];
            }
        }
    }
}

fn box_v(src: &[f32], dst: &mut [f32], w: usize, h: usize, r: usize) {
    let norm = 1.0 / (2 * r + 1) as f32;
    for x in 0..w {
        let mut acc = 0.0f32;
        for y in 0..=r.min(h - 1) {
            acc += src[y * w + x];
        }
        for y in 0..h {
            dst[y * w + x] = acc * norm;
            let add = y + r + 1;
            if add < h {
                acc += src[add * w + x];
            }
            if y >= r {
                acc -= src[(y - r) * w + x];
            }
        }
    }
}

/// Nothing Launcher `ShadowGenerator` shadow alpha (0..1) for an alpha buffer:
/// blurred mask at 25/255, plus the key shadow offset by size/48 at 7/255.
pub fn launcher_shadow(alpha: &[f32], size: usize) -> Vec<f32> {
    let host = (size as f32 - 2.0 * (size as f32 * (1.0 - 0.92) / 2.0).round()) / size as f32;
    let radius = size as f32 * 0.035 / host;
    let sigma = 0.577_35 * radius + 0.5; // Skia BlurMaskFilter radius -> sigma
    let blurred = gaussian_blur(alpha, size, size, sigma);
    let dy = (size as f32 / 48.0 / host).round() as usize;
    let mut out = vec![0.0f32; alpha.len()];
    for y in 0..size {
        for x in 0..size {
            let i = y * size + x;
            let a1 = blurred[i] * 25.0 / 255.0;
            let a2 = if y >= dy { blurred[(y - dy) * size + x] * 7.0 / 255.0 } else { 0.0 };
            out[i] = a2 + a1 * (1.0 - a2);
        }
    }
    out
}

fn inverse_alpha(target: u8, shadow: u8) -> u8 {
    match target {
        0 => 0,
        255 => 255,
        t => {
            let remaining = ((255.0 - t as f64) / (255.0 - shadow as f64)).min(1.0);
            ((1.0 - remaining.sqrt()) * 255.0).round().clamp(0.0, 255.0) as u8
        }
    }
}

/// `PackIconEncoder.encode`: the returned PNG, drawn by
/// Nothing Launcher as source → shadows → source, reproduces `target`.
pub fn launcher_encode(target: &RgbaImage) -> RgbaImage {
    let size = target.width() as usize;
    assert_eq!(target.width(), target.height());
    let ta: Vec<u8> = target.pixels().map(|p| p[3]).collect();
    let mut a: Vec<u8> = ta.iter().map(|&t| inverse_alpha(t, 0)).collect();
    let shadow_of = |a: &[u8]| -> Vec<u8> {
        let f: Vec<f32> = a.iter().map(|&v| v as f32 / 255.0).collect();
        launcher_shadow(&f, size).iter().map(|&v| (v * 255.0).round().clamp(0.0, 255.0) as u8).collect()
    };
    let mut s = shadow_of(&a);
    for _ in 0..6 {
        let mut changed = false;
        for i in 0..a.len() {
            let v = inverse_alpha(ta[i], s[i]);
            if v != a[i] {
                a[i] = v;
                changed = true;
            }
        }
        if !changed {
            break;
        }
        s = shadow_of(&a);
    }
    let mut out = RgbaImage::new(target.width(), target.height());
    for (i, (o, t)) in out.pixels_mut().zip(target.pixels()).enumerate() {
        let av = a[i] as f64 / 255.0;
        if av == 0.0 {
            continue;
        }
        let sv = s[i] as f64 / 255.0;
        let weight = av * (1.0 + (1.0 - av) * (1.0 - sv));
        let gain = (t[3] as f64 / 255.0) / weight;
        let ch = |v: u8| (v as f64 * gain).round().clamp(0.0, 255.0) as u8;
        *o = Rgba([ch(t[0]), ch(t[1]), ch(t[2]), a[i]]);
    }
    out
}

/// Simulates Nothing Launcher drawing a pack PNG (source, shadows, source)
/// over a transparent surface; used by tests and the "launcher" preview.
pub fn simulate_launcher(png: &RgbaImage) -> RgbaImage {
    let size = png.width() as usize;
    let a: Vec<f32> = png.pixels().map(|p| p[3] as f32 / 255.0).collect();
    let s = launcher_shadow(&a, size);
    let mut out = RgbaImage::new(png.width(), png.height());
    for (i, (o, p)) in out.pixels_mut().zip(png.pixels()).enumerate() {
        let av = a[i];
        // premultiplied: src, then black shadow, then src again
        let c = |v: u8| v as f32 / 255.0 * av;
        let (mut r, mut g, mut b, mut al) = (c(p[0]), c(p[1]), c(p[2]), av);
        let sv = s[i];
        r *= 1.0 - sv;
        g *= 1.0 - sv;
        b *= 1.0 - sv;
        al = sv + al * (1.0 - sv);
        r = c(p[0]) + r * (1.0 - av);
        g = c(p[1]) + g * (1.0 - av);
        b = c(p[2]) + b * (1.0 - av);
        al = av + al * (1.0 - av);
        if al > 0.0 {
            let un = |v: f32| (v / al * 255.0).round().clamp(0.0, 255.0) as u8;
            *o = Rgba([un(r), un(g), un(b), (al * 255.0).round() as u8]);
        }
    }
    out
}

/// Gamma lift (v^0.35) of neutral greys. It fades out with chroma (16..40)
/// instead of a hard cut: on soft gradients (a grey lens turning into a pastel
/// highlight) a hard threshold lifted every other pixel (dotted pattern).
fn lift_neutral(layer: &mut RgbaImage) {
    let lut: Vec<u8> = (0..256).map(|v| ((v as f32 / 255.0).powf(0.35) * 255.0).round() as u8).collect();
    for px in layer.pixels_mut() {
        let mx = px[0].max(px[1]).max(px[2]);
        let mn = px[0].min(px[1]).min(px[2]);
        let w = 1.0 - smoothstep(16.0, 40.0, (mx - mn) as f32);
        if w > 0.0 {
            let mix = |v: u8| (v as f32 + (lut[v as usize] as f32 - v as f32) * w).round().clamp(0.0, 255.0) as u8;
            *px = Rgba([mix(px[0]), mix(px[1]), mix(px[2]), px[3]]);
        }
    }
}

/// Renders a Lightnt icon at `size` from the source icon and its isolated glyph
/// (`glyph_bbox` in source coordinates, as returned by `segment::isolate`).
/// Renders the icon. Universal net: when the result would keep less than 1.5%
/// of the tile opaque although the source is more than 20% opaque, the source
/// art is drawn whole on the plate (opacity 1, no recolouring): no icon vanishes.
pub fn render(src: &RgbaImage, glyph: &RgbaImage, glyph_bbox: (u32, u32, u32, u32), size: u32, p: &LucentParams) -> LucentOutput {
    let out = render_layers(src, glyph, glyph_bbox, size, p);
    let kept = out.image.pixels().filter(|q| q[3] >= 200).count() as f32;
    let src_opaque = src.pixels().filter(|q| q[3] > 200).count() as f32;
    let src_total = (src.width() * src.height()) as f32;
    if kept < 0.015 * (size * size) as f32 && src_opaque > 0.2 * src_total {
        let mut lp = p.clone();
        lp.strategy = GlyphStrategy::Tile;
        lp.backdrop[3] = 255;
        let full = (0, 0, src.width(), src.height());
        return render_layers(src, src, full, size, &lp);
    }
    out
}

fn render_layers(src: &RgbaImage, glyph: &RgbaImage, glyph_bbox: (u32, u32, u32, u32), size: u32, p: &LucentParams) -> LucentOutput {
    let mut notes = Vec::new();
    let n = size as usize;
    let plate = plate_mask(src, glyph, size, p.shape, &mut notes);
    let icon_gen_mode = p.shape == PlateShape::Circle && !p.keep_composition;

    // bare logo (no plate in the source): centred at BARE_LOGO_SCALE on any plate
    let count = |img: &RgbaImage, t: u8| img.pixels().filter(|q| q[3] > t).count() as f32;
    let bare = count(glyph, 16) >= 0.8 * count(src, 16).max(1.0);
    let fallback = bare || notes.iter().any(|n| n == FALLBACK_NOTE);
    // "icon inside the icon": strip the inner tile's own background too and
    // map the tile onto the plate box (cover), clipped by the plate below
    // the source itself may be the tile (launcher / adaptive icons are a
    // full rounded square): unwrap it directly instead of the isolated glyph
    use GlyphStrategy as G;
    let clean_edge = p.strategy == G::CleanEdge;
    let st = if clean_edge { G::Auto } else { p.strategy };
    // launcher icons often carry a transparent margin around the tile:
    // detect the tile on the icon cropped to its visible box
    let src_tile = crate::compose::crop_to_content(src);
    // Auto: pages and full-artwork tiles (maps, gradients) are kept whole
    let st = if st == G::Auto && crate::compose::is_tile_loose(&src_tile) && keep_whole(&src_tile) { G::Tile } else { st };
    // the source is already a finished frosted icon: its tones were already
    // lifted once, a second lift turns dark outlines into speckled grey
    let mut already_styled = false;
    // whole-tile art: the plate opacity is applied to its background region
    let mut whole_tile = false;
    // extra cover for tiles whose own corners must not show the plate behind
    let mut cover_scale = 1.0f32;
    let src_unwrap = match st {
        G::Auto | G::FullBleed if crate::compose::is_tile(&src_tile) => crate::compose::unwrap_tile(&src_tile),
        _ => None,
    };
    // dark symbol on a coloured disc/tile: the symbol takes the plate colour
    // (also when the coloured disc sits on a dark/neutral tile: the tile's
    // background is stripped and the disc becomes the plate)
    let on_tile = || crate::compose::strip_border_background(&src_tile);
    let recolored = match st {
        G::Auto if src_unwrap.is_none() => crate::compose::recolor_on_colored_plate(src, false),
        G::Auto => on_tile().and_then(|c| crate::compose::recolor_on_colored_plate(&c, false)),
        G::PlateColor => crate::compose::recolor_on_colored_plate(src, true)
            .or_else(|| on_tile().and_then(|c| crate::compose::recolor_on_colored_plate(&c, true))),
        _ => None,
    };
    if recolored.is_some() {
        notes.push("Simbolo ricolorato con il colore del piatto originale".to_string());
    } else if st == G::PlateColor {
        notes.push("Colore del piatto: nessun piatto colorato pieno trovato, simbolo lasciato com'è".to_string());
    }
    // a recoloured symbol keeps its size relative to the original plate; an
    // unwrapped tile's content is stretched to the plate edge
    let keep_tile_scale = recolored.is_some();
    let (tile_dims, unwrapped) = if let Some((g, gb, pb)) = recolored {
        ((pb.2 - pb.0, pb.3 - pb.1), Some((g, gb)))
    } else if src_unwrap.is_some() {
        (src_tile.dimensions(), src_unwrap)
    } else if st == G::FullBleed {
        // forced edge to edge: the isolated symbol keeps its place inside the
        // original icon box, and that box is mapped onto the whole plate
        let unw = crate::compose::unwrap_tile(glyph);
        match unw {
            Some(u) => (glyph.dimensions(), Some(u)),
            None => {
                let (bx0, by0, bx1, by1) = crate::imageops::alpha_bbox(src, 16).unwrap_or((0, 0, src.width(), src.height()));
                let gb = (
                    glyph_bbox.0.saturating_sub(bx0),
                    glyph_bbox.1.saturating_sub(by0),
                    glyph_bbox.0.saturating_sub(bx0) + glyph.width(),
                    glyph_bbox.1.saturating_sub(by0) + glyph.height(),
                );
                notes.push("Bordo pieno: icona originale estesa a tutto il piatto".to_string());
                ((bx1 - bx0, by1 - by0), Some((glyph.clone(), gb)))
            }
        }
    } else if st == G::Tile {
        // a whole tile/page (or any finished image): kept as it is, colours
        // untouched; a tile covers the plate edge to edge (without its own
        // light outline), anything else keeps its proportions on the plate
        already_styled = true;
        if crate::compose::is_tile_loose(&src_tile) {
            whole_tile = true;
            let art = crate::compose::strip_light_rim(&src_tile).unwrap_or_else(|| src_tile.clone());
            let (w, h) = art.dimensions();
            // nameable for the UI: the colour blur was kept whole, not cut out
            if soft_colour_whole(&src_tile) {
                notes.push(SOFT_COLOUR_NOTE.to_string());
            }
            notes.push("Pagina intera: estesa fino al bordo del piatto".to_string());
            cover_scale = 1.04;
            ((w, h), Some((art, (0, 0, w, h))))
        } else {
            notes.push("Immagine com'è: solo posizione e dimensione".to_string());
            (glyph.dimensions(), None)
        }
    } else if st == G::AsIs {
        (glyph.dimensions(), None)
    } else {
        // the "symbol" is the whole icon and that icon is a translucent tile:
        // an icon already in the frosted style whose artwork touches the edge
        // (tabs, mascots), so nothing could be separated
        // from it. Re-mask it onto the new plate as it is, edge to edge,
        // instead of shrinking it into a tile inside the tile.
        if bare && crate::compose::is_tile_loose(glyph) && !crate::compose::is_tile(glyph) {
            notes.push("Icona già nello stile: riportata sulla nuova forma".to_string());
            already_styled = true;
            // on request only: the glow around coloured strips along one
            // edge (Contacts' tabs) takes the plate colour
            let flat = if clean_edge { crate::compose::flatten_edge_color(glyph) } else { (glyph.clone(), false) };
            if flat.1 {
                notes.push("Alone del bordo colorato uniformato al piatto".to_string());
            }
            // its own light outline goes: the new plate draws the edge
            let art = match crate::compose::strip_light_rim(&flat.0) {
                Some(a) => {
                    notes.push("Bordo luminoso dell'icona originale rimosso".to_string());
                    cover_scale = 1.04;
                    a
                }
                None => flat.0,
            };
            let (aw, ah) = art.dimensions();
            ((aw, ah), Some((art, (0, 0, aw, ah))))
        } else if let Some((art, bx)) = if bare { crate::compose::strip_light_disc(glyph) } else { None } {
            // round icon on a light background, artwork to the edge: the
            // background goes, the artwork keeps its place on the plate
            notes.push("Icona rotonda: sfondo chiaro rimosso, disegno esteso al piatto".to_string());
            (art.dimensions(), Some((art, bx)))
        } else {
            (glyph.dimensions(), if fallback { None } else { crate::compose::unwrap_tile(glyph) })
        }
    };
    let fallback = fallback && unwrapped.is_none();
    let inner_box = unwrapped.as_ref().map(|u| u.1);
    let glyph: &RgbaImage = match &unwrapped {
        Some((g, _)) => g,
        None => glyph,
    };

    // ---- glyph layer (straight RGBA at glyph resolution)
    let mut layer = glyph.clone();
    if whole_tile {
        apply_plate_alpha(&mut layer, p.backdrop[3]);
    }
    if p.adapt_neutrals && dark_plate_of(p) && !whole_tile && !p.monochrome {
        adapt_neutral_pixels(&mut layer);
    }
    let dark_plate = (p.backdrop[0] as u32 + p.backdrop[1] as u32 + p.backdrop[2] as u32) < 384;
    // a large dark area (a camera lens, a dark disc) is the artwork's own
    // look: lifting it turns it flat grey. Only small dark details (roads,
    // keys, outlines) are lifted.
    let mostly_dark = dark_lens(&layer);
    if mostly_dark && p.lift_greys && dark_plate && !p.monochrome {
        notes.push("Lente scura mantenuta (non schiarita)".to_string());
    }
    if p.lift_greys && dark_plate && !p.monochrome && !already_styled && !mostly_dark {
        // neutral greys get a gamma lift (v^0.35): dark details (roads, keys)
        // become visible on the dark frosted plate while the tonal steps
        // between greys (e.g. a figure on a grey disc) are kept
        lift_neutral(&mut layer);
    }
    let mostly_light = {
        let opaque: Vec<_> = layer.pixels().filter(|q| q[3] > 127).collect();
        let light = opaque.iter().filter(|q| q[0].min(q[1]).min(q[2]) > 150).count();
        !opaque.is_empty() && light as f32 > 0.5 * opaque.len() as f32
    };
    if p.monochrome && glyph.width() > 0 && glyph.height() > 0 {
        let (mut mask, complex) = monochrome_mask(glyph);
        let ink_dark = 0.2126 * p.ink[0] as f32 + 0.7152 * p.ink[1] as f32 + 0.0722 * p.ink[2] as f32 <= 128.0;
        // the inverted mask is defined on the circular plate only
        if complex && ink_dark && icon_gen_mode {
            mask = light_mask(&mask, glyph.width(), glyph.height());
        }
        for (px, &m) in layer.pixels_mut().zip(mask.iter()) {
            *px = Rgba([p.ink[0], p.ink[1], p.ink[2], m]);
        }
    }

    // ---- glyph placement
    let (gw, gh) = (glyph.width().max(1) as f32, glyph.height().max(1) as f32);
    let plate_box = {
        let (mut x0, mut y0, mut x1, mut y1) = (size, size, 0u32, 0u32);
        for y in 0..size {
            for x in 0..size {
                if plate[(y * size + x) as usize] > 0.5 {
                    x0 = x0.min(x);
                    y0 = y0.min(y);
                    x1 = x1.max(x + 1);
                    y1 = y1.max(y + 1);
                }
            }
        }
        (x1 > x0 && y1 > y0).then_some((x0, y0, x1, y1))
    };
    let (cx, cy, scale) = if let (Some(ib), Some((x0, y0, x1, y1))) = (inner_box, plate_box) {
        let (tw0, th0) = (tile_dims.0.max(1) as f32, tile_dims.1.max(1) as f32);
        let (bw, bh) = ((ib.2 - ib.0).max(1) as f32, (ib.3 - ib.1).max(1) as f32);
        let k = if keep_tile_scale {
            ((x1 - x0) as f32 / tw0).min((y1 - y0) as f32 / th0)
        } else {
            ((x1 - x0) as f32 / bw).max((y1 - y0) as f32 / bh)
        };
        let icx = (ib.0 + ib.2) as f32 / 2.0 - tw0 / 2.0;
        let icy = (ib.1 + ib.3) as f32 / 2.0 - th0 / 2.0;
        ((x0 + x1) as f32 / 2.0 + icx * k, (y0 + y1) as f32 / 2.0 + icy * k, k)
    } else if fallback {
        (size as f32 / 2.0, size as f32 / 2.0, size as f32 * BARE_LOGO_SCALE / gw.max(gh))
    } else if p.keep_composition {
        let (sw, sh) = (src.width().max(1) as f32, src.height().max(1) as f32);
        let k = size as f32 / sw.max(sh);
        let (ox, oy) = ((size as f32 - sw * k) / 2.0, (size as f32 - sh * k) / 2.0);
        let bx = (glyph_bbox.0 + glyph_bbox.2) as f32 / 2.0;
        let by = (glyph_bbox.1 + glyph_bbox.3) as f32 / 2.0;
        (ox + bx * k, oy + by * k, k)
    } else {
        let longest = size as f32 * GLYPH_SCALE / NATIVE_BACKGROUND_SCALE;
        (size as f32 / 2.0, size as f32 / 2.0, longest / gw.max(gh))
    };
    // a page's own rounded corners must not show the plate behind them
    let scale = scale * cover_scale;
    let scale = scale * p.glyph_scale.clamp(0.2, 3.0);
    let (tw, th) = ((gw * scale).round().max(1.0) as u32, (gh * scale).round().max(1.0) as u32);
    // jagged (non anti-aliased) outlines get a one-pixel alpha step
    let scaled = soften_hard_edges(resize(&layer, tw, th));
    let cx = cx + p.offset_x * size as f32;
    let cy = cy + p.offset_y * size as f32;
    // optical centring (opt-in): the alpha centroid goes to the anchor
    let (cx, cy) = if p.optical_centre {
        let lim = crate::effects::optical_limit(size as f32, size as f32, tw, th);
        let (dx, dy) = crate::effects::centroid_shift(&scaled, lim);
        (cx + dx, cy + dy)
    } else {
        (cx, cy)
    };
    let ox = (cx - tw as f32 / 2.0).round() as i64;
    let oy = (cy - th as f32 / 2.0).round() as i64;

    // light plate + mostly light glyph: soft dark shadow under the glyph so a
    // white figure stays readable (the glyph keeps its own colours)
    let glyph_shadow: Option<Vec<f32>> = if p.lift_greys && !dark_plate && !p.monochrome && mostly_light {
        let mut a = vec![0.0f32; n * n];
        for y in 0..th {
            for x in 0..tw {
                let (gx, gy) = (ox + x as i64, oy + y as i64 + (size as f32 * 0.012) as i64);
                if gx >= 0 && gy >= 0 && (gx as u32) < size && (gy as u32) < size {
                    a[(gy as u32 * size + gx as u32) as usize] = scaled.get_pixel(x, y)[3] as f32 / 255.0;
                }
            }
        }
        Some(gaussian_blur(&a, n, n, size as f32 * 0.022))
    } else {
        None
    };

    // ---- composite: plate (backdrop tint) then glyph clipped to the plate
    // the art's background already carries the plate alpha: no tint under it
    let bd = if whole_tile { [p.backdrop[0], p.backdrop[1], p.backdrop[2], 0] } else { p.backdrop };
    let mut out = RgbaImage::new(size, size);
    let rim = p.rim.clamp(0.0, 1.0);
    let edge = if rim > 0.0 {
        let blurred = gaussian_blur(&plate, n, n, size as f32 * 0.012);
        Some(blurred)
    } else {
        None
    };
    for y in 0..size {
        for x in 0..size {
            let i = (y * size + x) as usize;
            let m = plate[i];
            if m <= 0.0 {
                continue;
            }
            // premultiplied accumulation
            let pa = bd[3] as f32 / 255.0 * m;
            let mut r = bd[0] as f32 / 255.0 * pa;
            let mut g = bd[1] as f32 / 255.0 * pa;
            let mut b = bd[2] as f32 / 255.0 * pa;
            let mut a = pa;
            if let Some(e) = &edge {
                // inner edge band, brighter towards the top
                let band = (m - e[i]).max(0.0) * 2.0;
                let light = 0.55 + 0.45 * (1.0 - y as f32 / size as f32);
                let ra = (band * light * rim * 0.6).clamp(0.0, 1.0) * m;
                r = ra + r * (1.0 - ra);
                g = ra + g * (1.0 - ra);
                b = ra + b * (1.0 - ra);
                a = ra + a * (1.0 - ra);
            }
            if let Some(sh) = &glyph_shadow {
                let sa = (sh[i] * 0.45).min(1.0) * m;
                r *= 1.0 - sa;
                g *= 1.0 - sa;
                b *= 1.0 - sa;
                a = sa + a * (1.0 - sa);
            }
            let gx = x as i64 - ox;
            let gy = y as i64 - oy;
            if gx >= 0 && gy >= 0 && (gx as u32) < tw && (gy as u32) < th {
                let q = scaled.get_pixel(gx as u32, gy as u32);
                let qa = q[3] as f32 / 255.0 * m;
                r = q[0] as f32 / 255.0 * qa + r * (1.0 - qa);
                g = q[1] as f32 / 255.0 * qa + g * (1.0 - qa);
                b = q[2] as f32 / 255.0 * qa + b * (1.0 - qa);
                a = qa + a * (1.0 - qa);
            }
            if a > 0.0 {
                let un = |v: f32| (v / a * 255.0).round().clamp(0.0, 255.0) as u8;
                out.put_pixel(x, y, Rgba([un(r), un(g), un(b), (a * 255.0).round() as u8]));
            }
        }
    }

    if p.launcher_encode {
        out = launcher_encode(&out);
        notes.push("Codificata per il launcher".into());
    } else if p.launcher_shadow {
        let a: Vec<f32> = out.pixels().map(|q| q[3] as f32 / 255.0).collect();
        let s = launcher_shadow(&a, n);
        for (i, px) in out.pixels_mut().enumerate() {
            let av = a[i];
            let sa = s[i] * (1.0 - av);
            let total = av + sa;
            if total > 0.0 {
                let k = av / total;
                *px = Rgba([
                    (px[0] as f32 * k).round() as u8,
                    (px[1] as f32 * k).round() as u8,
                    (px[2] as f32 * k).round() as u8,
                    (total * 255.0).round() as u8,
                ]);
            }
        }
    }
    LucentOutput { image: out, notes }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A full-bleed tile (artwork to the edge, nothing to cut out): with the
    /// "Original" shape the plate keeps the tile's square outline, it does
    /// not fall back to a circle.
    #[test]
    fn original_shape_keeps_full_bleed_tile_outline() {
        let n = 192u32;
        let shape = squircle::Shape { size_ratio: 0.93, exponent: 4.25 };
        let mask = squircle::mask(n, &shape);
        let mut src = RgbaImage::new(n, n);
        for y in 0..n {
            for x in 0..n {
                let a = mask[(y * n + x) as usize];
                // stripes to the edge, like a map
                let c = if (x + y) / 24 % 2 == 0 { [40, 120, 230] } else { [90, 90, 96] };
                src.put_pixel(x, y, Rgba([c[0], c[1], c[2], a]));
            }
        }
        let res = crate::segment::isolate(&src, &crate::segment::SegmentOptions::default());
        let lp = LucentParams { shape: PlateShape::Original, ..LucentParams::dark() };
        let out = render(&src, &res.glyph, res.bbox, 256, &lp);
        // a point near the corner: inside the squircle, outside the circle
        let k = 256.0 / n as f32;
        let (cx, cy) = ((n as f32 * 0.115 * k) as u32, (n as f32 * 0.115 * k) as u32);
        assert!(out.image.get_pixel(cx, cy)[3] > 40, "corner lost: {:?} notes {:?}", out.image.get_pixel(cx, cy), out.notes);
        assert!(!out.notes.iter().any(|t| t == FALLBACK_NOTE), "fell back to the circle: {:?}", out.notes);
    }

    /// A bare logo (transparent around it) still gets the round fallback.
    #[test]
    fn original_shape_bare_logo_still_round() {
        let n = 128u32;
        let mut src = RgbaImage::new(n, n);
        for y in 0..n {
            for x in 0..n {
                // a thin cross: far from a plate
                if (x as i32 - 64).abs() < 8 || (y as i32 - 64).abs() < 8 {
                    if x > 16 && x < 112 && y > 16 && y < 112 {
                        src.put_pixel(x, y, Rgba([250, 60, 60, 255]));
                    }
                }
            }
        }
        let res = crate::segment::isolate(&src, &crate::segment::SegmentOptions::default());
        let lp = LucentParams { shape: PlateShape::Original, ..LucentParams::dark() };
        let out = render(&src, &res.glyph, res.bbox, 128, &lp);
        assert!(out.notes.iter().any(|t| t == FALLBACK_NOTE));
    }

    fn icon() -> RgbaImage {
        // rounded square plate (blue) with a white bar glyph; transparent corners
        let mut img = RgbaImage::new(120, 120);
        for y in 0..120u32 {
            for x in 0..120u32 {
                let (dx, dy) = ((x as f32 - 59.5).abs(), (y as f32 - 59.5).abs());
                let inside = dx.max(dy) < 50.0 && !(dx > 35.0 && dy > 35.0 && (dx - 35.0).hypot(dy - 35.0) > 15.0);
                if inside {
                    let glyph = dx < 25.0 && dy < 8.0;
                    img.put_pixel(x, y, if glyph { Rgba([255, 255, 255, 255]) } else { Rgba([30, 80, 220, 255]) });
                }
            }
        }
        img
    }

    #[test]
    fn plate_follows_original_silhouette_and_glyph_is_inked() {
        let src = icon();
        let res = crate::segment::isolate(&src, &crate::segment::SegmentOptions::default());
        let lp = LucentParams { shape: PlateShape::Original, ..LucentParams::dark() };
        let out = render(&src, &res.glyph, res.bbox, 120, &lp);
        // transparent corner of the source stays transparent
        assert_eq!(out.image.get_pixel(12, 12)[3], 0);
        // plate interior: Nothing frosted backdrop alpha 0x66
        let p = out.image.get_pixel(60, 20);
        assert!((p[3] as i32 - 0x66).abs() <= 2, "plate alpha {}", p[3]);
        assert!(p[0] < 5);
        // glyph centre: ink colour, opaque
        let g = out.image.get_pixel(60, 60);
        assert!(g[3] > 240 && g[0] > 230, "glyph {:?}", g);
    }

    #[test]
    fn monochrome_ramp_matches_icongen_formula() {
        // two-tone glyph: modal grey -> 255 alpha; darker tone gets the 45 floor
        let mut g = RgbaImage::new(10, 10);
        for (i, p) in g.pixels_mut().enumerate() {
            *p = if i < 70 { Rgba([200, 200, 200, 255]) } else { Rgba([60, 60, 60, 255]) };
        }
        let (m, complex) = monochrome_mask(&g);
        assert!(!complex);
        assert_eq!(m[0], 255);
        assert_eq!(m[99], 45);
    }

    #[test]
    fn grey_lift_is_continuous_on_gradients() {
        // grey turning into a pastel red one step at a time: neighbouring
        // pixels must stay close after the lift (no dotted pattern)
        let mut g = RgbaImage::new(64, 1);
        for x in 0..64u32 {
            g.put_pixel(x, 0, Rgba([110 + x as u8, 110, 110, 255]));
        }
        lift_neutral(&mut g);
        for x in 1..64u32 {
            let (a, b) = (g.get_pixel(x - 1, 0), g.get_pixel(x, 0));
            let d = (0..3).map(|k| (a[k] as i32 - b[k] as i32).abs()).max().unwrap();
            assert!(d <= 6, "jump {} at {}", d, x);
        }
        // pure neutral grey is lifted
        assert!(g.get_pixel(0, 0)[1] > 150);
    }

    #[test]
    fn encoder_round_trips_through_launcher_draw() {
        let src = icon();
        let res = crate::segment::isolate(&src, &crate::segment::SegmentOptions::default());
        let target = render(&src, &res.glyph, res.bbox, 96, &LucentParams::dark()).image;
        let encoded = launcher_encode(&target);
        let shown = simulate_launcher(&encoded);
        let mut worst = 0i32;
        for (a, b) in shown.pixels().zip(target.pixels()).filter(|(_, b)| b[3] > 0) {
            worst = worst.max((a[3] as i32 - b[3] as i32).abs());
        }
        assert!(worst <= 3, "alpha error {}", worst);
    }
}

#[cfg(test)]
mod quality_tests {
    use super::*;
    use crate::segment::{isolate, SegmentOptions};

    /// Mean RGB of the opaque (alpha >= 200) pixels.
    fn opaque_mean(img: &RgbaImage) -> [f32; 3] {
        let (mut s, mut n) = ([0f64; 3], 0f64);
        for q in img.pixels().filter(|q| q[3] >= 200) {
            for k in 0..3 {
                s[k] += q[k] as f64;
            }
            n += 1.0;
        }
        [0, 1, 2].map(|k| (s[k] / n.max(1.0)) as f32)
    }

    /// Mean luminance over mid-grey (#808080) of the pixels with alpha >= 200.
    fn grey_lum(img: &RgbaImage) -> f32 {
        let (mut s, mut n) = (0f64, 0f64);
        for q in img.pixels().filter(|q| q[3] >= 200) {
            let a = q[3] as f32 / 255.0;
            let c = |v: u8| v as f32 * a + 128.0 * (1.0 - a);
            s += (0.2126 * c(q[0]) + 0.7152 * c(q[1]) + 0.0722 * c(q[2])) as f64;
            n += 1.0;
        }
        (s / n.max(1.0)) as f32
    }

    fn rr(n: u32, r: f32, x: u32, y: u32) -> bool {
        let (fx, fy) = (x as f32, y as f32);
        let (c, m) = (r, n as f32 - r);
        let (dx, dy) = ((c - fx).max(fx - m).max(0.0), (c - fy).max(fy - m).max(0.0));
        dx * dx + dy * dy <= r * r
    }

    fn fill(n: u32, f: impl Fn(u32, u32) -> Option<[u8; 4]>) -> RgbaImage {
        let mut img = RgbaImage::new(n, n);
        for y in 0..n {
            for x in 0..n {
                if let Some(c) = f(x, y) {
                    img.put_pixel(x, y, Rgba(c));
                }
            }
        }
        img
    }

    /// White rounded page, red band, dark digit block (a calendar icon).
    fn page() -> RgbaImage {
        fill(192, |x, y| {
            if !rr(192, 36.0, x, y) {
                return None;
            }
            if y < 56 {
                return Some([226, 40, 44, 255]);
            }
            if (60..140).contains(&x) && (90..160).contains(&y) {
                return Some([30, 30, 34, 255]);
            }
            Some([255, 255, 255, 255])
        })
    }

    /// Multi-colour full-bleed tile (a map): no transparency, several hues.
    fn map() -> RgbaImage {
        fill(192, |x, y| {
            let c = if y < 70 && x < 100 {
                [246, 214, 92]
            } else if y > 130 && x > 100 {
                [120, 170, 235]
            } else if x > 150 {
                [150, 200, 120]
            } else if x % 40 < 8 || y % 50 < 8 {
                [255, 255, 255]
            } else {
                [200, 230, 190]
            };
            Some([c[0], c[1], c[2], 255])
        })
    }

    /// Blue tile with a white bar glyph (the control that must keep working).
    fn control() -> RgbaImage {
        fill(192, |x, y| {
            if !rr(192, 36.0, x, y) {
                return None;
            }
            if (60..132).contains(&x) && (88..104).contains(&y) {
                return Some([255, 255, 255, 255]);
            }
            Some([30, 80, 220, 255])
        })
    }

    /// Near-black bold glyph on transparent (a black logo).
    fn black_logo() -> RgbaImage {
        fill(192, |x, y| {
            let (dx, dy) = (x as f32 - 96.0, y as f32 - 96.0);
            let ring = (dx * dx + dy * dy).sqrt();
            if (ring > 50.0 && ring < 80.0) || ((70..122).contains(&x) && (70..122).contains(&y) && ring < 0.0) {
                return Some([11, 11, 15, 255]);
            }
            if (88..104).contains(&x) && (60..150).contains(&y) {
                return Some([11, 11, 15, 255]);
            }
            None
        })
    }

    fn run(src: &RgbaImage, lp: &LucentParams) -> RgbaImage {
        let r = isolate(src, &SegmentOptions::default());
        render(src, &r.glyph, r.bbox, 256, lp).image
    }

    /// Symbol colour: the opaque output colour matches the opaque input colour.
    #[test]
    fn symbol_colours_are_kept_under_auto() {
        for (name, src) in [("map", map()), ("page", page())] {
            for mut lp in [LucentParams::dark(), LucentParams::light()] {
            if name != "black_logo" {
                lp.backdrop[3] = 255; // opacity 1: whole-tile art intact (glyph case keeps the default plate)
            }
                let out = run(&src, &lp);
                let (a, b) = (opaque_mean(&src), opaque_mean(&out));
                let d = (0..3).map(|k| (a[k] - b[k]).abs()).fold(0f32, f32::max);
                assert!(d <= 12.0, "{name}: input {a:?} output {b:?} (max diff {d})");
            }
        }
    }

    /// Black glyph on the dark plate: remapped to light (the dark-plate
    /// readability rule), so it does not vanish into the plate.
    #[test]
    fn black_glyph_becomes_light_on_dark_plate() {
        let out = run(&black_logo(), &LucentParams::dark());
        let m = opaque_mean(&out);
        assert!(m[0] > 150.0 && m[2] > 150.0, "black not lightened: {m:?}");
    }

    /// Black glyph on the light plate: no remap, it stays dark.
    #[test]
    fn black_glyph_stays_dark_on_light_plate() {
        assert!(!LucentParams::light().adapt_neutrals);
        let out = run(&black_logo(), &LucentParams::light());
        let m = opaque_mean(&out);
        assert!(m[0] < 60.0 && m[2] < 60.0, "light plate changed the black: {m:?}");
    }

    /// Red and black parts on one glyph: the red keeps its colour, the black
    /// becomes light on the dark plate.
    #[test]
    fn two_colour_glyph_red_kept_black_lightened() {
        let n = 192u32;
        let src = fill(n, |x, y| {
            if (50..150).contains(&x) && (40..100).contains(&y) {
                return Some([230, 40, 40, 255]);
            }
            if (50..150).contains(&x) && (110..150).contains(&y) {
                return Some([11, 11, 15, 255]);
            }
            None
        });
        let out = run(&src, &LucentParams::dark());
        let red = out.pixels().filter(|q| q[3] == 255 && (q[0] as i32 - 230).abs() <= 6 && (q[1] as i32 - 40).abs() <= 6 && (q[2] as i32 - 40).abs() <= 6).count();
        assert!(red > 1000, "red changed or lost: {red} px");
        let dark = out.pixels().filter(|q| q[3] > 200 && q[0] < 80 && q[1] < 80 && q[2] < 80).count();
        let light = out.pixels().filter(|q| q[3] > 200 && q[0] > 150 && q[1] > 150 && q[2] > 150).count();
        assert!(light > 500 && dark < 200, "black not lightened: light {light}, dark {dark}");
    }

    /// Full-bleed map: Auto keeps the whole tile (opaque, no plate recolouring).
    #[test]
    fn full_bleed_map_is_kept_whole() {
        let src = map();
        let out = run(&src, &LucentParams::dark());
        assert!(keep_whole(&crate::compose::crop_to_content(&src)));
        let transparent = out.pixels().filter(|q| q[3] < 100).count();
        // the squircle corners are outside the plate; the art itself is not dropped
        assert!(transparent > 0 && out.pixels().filter(|q| q[3] > 0).count() > 40_000);
        assert!(!out.pixels().any(|q| q[3] > 200 && q[0] == q[1] && q[1] == q[2] && q[0] < 40));
    }

    /// Calendar page: the body is not darker than the page once composited on grey.
    #[test]
    fn calendar_page_is_not_darker_than_original() {
        let src = page();
        let mut lp = LucentParams::dark();
        lp.backdrop[3] = 255; // opacity 1; at the default 0x66 the page is glass by design
        let out = run(&src, &lp);
        let ratio = grey_lum(&out) / grey_lum(&src);
        assert!(ratio >= 0.9, "page darkened: ratio {ratio}");
    }

    /// Control (blue tile, white glyph): the plate pipeline output stays as it was
    /// (no lift_greys on this white glyph; max per-channel change 3/255 measured).
    #[test]
    fn blue_control_is_unchanged() {
        let src = control();
        let out = run(&src, &LucentParams::dark());
        let white = out.pixels().filter(|q| q[3] > 200 && q[0] > 240 && q[1] > 240 && q[2] > 240).count();
        assert!(white > 200, "white glyph lost: {white}");
        assert_eq!(out.get_pixel(2, 2)[3], 0, "corner must stay transparent");
    }

    /// Gemini-like input: rainbow 4-point star with anti-aliased edges on pure
    /// white, RGB without alpha. Output: star colours kept, white not kept,
    /// edges not darkened.
    #[test]
    fn rainbow_star_on_white_loses_background() {
        let n = 240u32;
        let (c, r) = (120.0f32, 100.0f32);
        let inside = |x: f32, y: f32| {
            let (dx, dy) = ((x - c).abs(), (y - c).abs());
            dx.powf(2.0 / 3.0) + dy.powf(2.0 / 3.0) <= r.powf(2.0 / 3.0)
        };
        let stops = [[255.0f32, 80.0, 80.0], [60.0, 170.0, 255.0], [120.0, 220.0, 90.0]];
        let mut src = RgbaImage::from_pixel(n, n, Rgba([255, 255, 255, 255]));
        for y in 0..n {
            for x in 0..n {
                let mut cov = 0.0f32;
                for sy in 0..4 {
                    for sx in 0..4 {
                        if inside(x as f32 + (sx as f32 + 0.5) / 4.0, y as f32 + (sy as f32 + 0.5) / 4.0) {
                            cov += 1.0 / 16.0;
                        }
                    }
                }
                if cov > 0.0 {
                    let u = y as f32 / n as f32 * (stops.len() - 1) as f32;
                    let i = (u as usize).min(stops.len() - 2);
                    let f = u - i as f32;
                    let col = [0, 1, 2].map(|k| stops[i][k] + (stops[i + 1][k] - stops[i][k]) * f);
                    let px = [0, 1, 2].map(|k| (col[k] * cov + 255.0 * (1.0 - cov)).round() as u8);
                    src.put_pixel(x, y, Rgba([px[0], px[1], px[2], 255]));
                }
            }
        }
        let lum = |q: &Rgba<u8>| 0.2126 * q[0] as f32 + 0.7152 * q[1] as f32 + 0.0722 * q[2] as f32;
        let star: Vec<&Rgba<u8>> = src.pixels().filter(|q| q[0].min(q[1]).min(q[2]) <= 200).collect();
        let star_min_lum = star.iter().map(|q| lum(q)).fold(f32::MAX, f32::min);
        let star_mean = {
            let mut s = [0f64; 3];
            for q in &star {
                for k in 0..3 {
                    s[k] += q[k] as f64;
                }
            }
            [0, 1, 2].map(|k| (s[k] / star.len() as f64) as f32)
        };
        for lp in [LucentParams::dark(), LucentParams::light()] {
            let out = run(&src, &lp);
            let opaque: Vec<&Rgba<u8>> = out.pixels().filter(|q| q[3] >= 200).collect();
            assert!(!opaque.is_empty());
            // symbol colours kept (opaque output vs star pixels of the input)
            let m = opaque_mean(&out);
            let d = (0..3).map(|k| (m[k] - star_mean[k]).abs()).fold(0f32, f32::max);
            assert!(d <= 12.0, "star colour changed: {m:?} vs {star_mean:?}");
            // the white background is gone: few opaque near-white pixels
            let white = opaque.iter().filter(|q| q[0].min(q[1]).min(q[2]) > 235).count();
            assert!(white * 100 < opaque.len(), "white kept: {white} of {}", opaque.len());
            // plate corner is not opaque white
            let corner = out.get_pixel(4, 4);
            assert!(corner[3] < 200 || corner[0].min(corner[1]).min(corner[2]) < 235, "corner white {corner:?}");
            // anti-aliased edges are not darkened below the star's darkest colour
            let darkest = opaque.iter().map(|q| lum(q)).fold(f32::MAX, f32::min);
            assert!(darkest >= star_min_lum - 15.0, "edge darkened: {darkest} < {star_min_lum}");
        }
    }

    /// Plate opacity 0: the page body (the flood-filled background) is gone,
    /// the dark digits and the red band keep their alpha and colour.
    #[test]
    fn page_background_vanishes_at_zero_opacity() {
        let mut lp = LucentParams::dark();
        lp.backdrop[3] = 0;
        let out = run(&page(), &lp);
        // interior only: a thin rim at the page's outer edge is a known leftover (see the report)
        let body_left = out
            .enumerate_pixels()
            .filter(|(x, y, q)| *x > 6 && *y > 80 && *x < 250 && *y < 206 && q[3] > 40 && q[0] > 240 && q[1] > 240 && q[2] > 240)
            .count();
        let pts: Vec<(u32, u32)> = out.enumerate_pixels().filter(|(_, _, q)| q[3] > 40 && q[0] > 240 && q[1] > 240 && q[2] > 240).map(|(x, y, _)| (x, y)).collect();
        let bb = (pts.iter().map(|p| p.0).min(), pts.iter().map(|p| p.1).min(), pts.iter().map(|p| p.0).max(), pts.iter().map(|p| p.1).max());
        // under 1% of the interior: the white counter inside the 9 is a known leftover
        assert!(body_left * 100 < 240 * 126, "white page body kept at opacity 0: {body_left} px, bbox {bb:?}");
        let digits = out.pixels().filter(|q| q[3] >= 250 && q[0] < 60 && q[1] < 60 && q[2] < 60).count();
        assert!(digits > 500, "digits lost at opacity 0: {digits} opaque dark px");
    }

    /// Map tile: grey ground (flat, touches the border), a blue disc with a
    /// thin light ring, a red pin. At opacity 0 the ground is gone and the
    /// disc and the pin stay opaque with their colours; no dark outline.
    #[test]
    fn map_tile_at_zero_opacity_keeps_disc_and_pin() {
        let n = 192u32;
        let src = fill(n, |x, y| {
            if !rr(n, 36.0, x, y) {
                return None;
            }
            let (dx, dy) = (x as f32 - 96.0, y as f32 - 96.0);
            let d = (dx * dx + dy * dy).sqrt();
            if d < 34.0 {
                return Some([30, 110, 240, 255]);
            }
            if (30.0..34.0).contains(&d) {
                return Some([200, 205, 215, 255]);
            }
            // pin: a disc at (96,132) with a tail down to (96,160)
            let (px, py) = (x as f32 - 96.0, y as f32 - 132.0);
            if px * px + py * py < 13.0 * 13.0 || ((y as f32) > 132.0 && (y as f32) < 160.0 && (x as f32 - 96.0).abs() < (160.0 - y as f32) * 0.45) {
                return Some([220, 50, 50, 255]);
            }
            Some([120, 120, 128, 255])
        });
        let mut lp = LucentParams::dark();
        lp.backdrop[3] = 0;
        let out = run(&src, &lp);
        let a = |x: u32, y: u32| out.get_pixel(x, y)[3];
        // disc centre and pin head: opaque
        assert!(a(128, 128) >= 240, "disc centre alpha {}", a(128, 128));
        assert!(a(128, 176) >= 200, "pin alpha {}", a(128, 176));
        // ground: gone
        assert!(a(40, 40) <= 20 && a(40, 210) <= 20 && a(210, 40) <= 20, "ground kept");
        // no dark outline: no dark opaque pixels
        let dark = out.pixels().filter(|q| q[3] > 150 && q[0] < 50 && q[1] < 50 && q[2] < 50).count();
        assert!(dark * 200 < out.pixels().count(), "dark outline: {dark} px");
    }

    /// Avatar tile: flat light tile, a centred figure and a darker strip along
    /// the right edge. At opacity 0 the strip is background, the figure stays.
    #[test]
    fn avatar_tile_drops_the_edge_strip() {
        let n = 192u32;
        let src = fill(n, |x, y| {
            if !rr(n, 36.0, x, y) {
                return None;
            }
            if x >= 176 {
                return Some([120, 130, 150, 255]);
            }
            let (dx, dy) = (x as f32 - 96.0, y as f32 - 70.0);
            if dx * dx + dy * dy < 22.0 * 22.0 {
                return Some([60, 60, 70, 255]);
            }
            if (60..132).contains(&x) && (100..170).contains(&y) {
                return Some([60, 60, 70, 255]);
            }
            Some([210, 225, 240, 255])
        });
        let mut lp = LucentParams::dark();
        lp.backdrop[3] = 0;
        let out = run(&src, &lp);
        let a = |x: u32, y: u32| out.get_pixel(x, y)[3];
        assert!(a(128, 93) >= 240, "figure head alpha {}", a(128, 93));
        assert!(a(128, 200) >= 240 || a(128, 180) >= 240, "figure body gone");
        assert!(a(250, 128) <= 30, "edge strip kept: alpha {}", a(250, 128));
        assert!(a(40, 40) <= 20, "tile ground kept");
    }

    /// Share of the pixels of colour `pred` that are still opaque (alpha >= 250).
    fn opaque_share(out: &RgbaImage, pred: impl Fn(&Rgba<u8>) -> bool) -> f32 {
        let (mut n, mut k) = (0usize, 0usize);
        for q in out.pixels().filter(|q| q[3] > 0 && pred(q)) {
            n += 1;
            if q[3] >= 250 {
                k += 1;
            }
        }
        k as f32 / n.max(1) as f32
    }

    /// HoYoLAB-like: flat dark-blue tile, a centred light character and a
    /// mid-blue hexagon. At opacity 0 the character stays opaque.
    #[test]
    fn hoyolab_like_character_survives_zero_opacity() {
        let n = 192u32;
        let src = fill(n, |x, y| {
            if !rr(n, 36.0, x, y) {
                return None;
            }
            let (dx, dy) = (x as f32 - 96.0, y as f32 - 100.0);
            if dx * dx + dy * dy < 30.0 * 30.0 && (dx.abs() + dy.abs()) > 0.0 {
                return Some([60, 90, 170, 255]);
            }
            let (hx, hy) = (x as f32 - 96.0, y as f32 - 84.0);
            if hx * hx + hy * hy < 24.0 * 24.0 {
                return Some([225, 230, 240, 255]);
            }
            if (66..126).contains(&x) && (112..160).contains(&y) {
                return Some([225, 230, 240, 255]);
            }
            Some([30, 50, 110, 255])
        });
        let mut lp = LucentParams::dark();
        lp.backdrop[3] = 0;
        let out = run(&src, &lp);
        let share = opaque_share(&out, |q| q[0] > 200 && q[1] > 200 && q[2] > 200);
        assert!(share >= 0.9, "character lost at opacity 0: {share:.2} opaque");
    }

    /// ATM-like: flat purple tile with white text bars and a darker outline
    /// band. At opacity 0 the text stays opaque.
    #[test]
    fn atm_like_text_survives_zero_opacity() {
        let n = 192u32;
        let src = fill(n, |x, y| {
            if !rr(n, 36.0, x, y) {
                return None;
            }
            if x < 10 || x >= n - 10 || y < 10 || y >= n - 10 {
                return Some([60, 20, 80, 255]);
            }
            let bar = (60..132).contains(&x) && ((74..82).contains(&y) || (96..104).contains(&y) || (118..126).contains(&y));
            if bar {
                return Some([255, 255, 255, 255]);
            }
            Some([120, 40, 140, 255])
        });
        let mut lp = LucentParams::dark();
        lp.backdrop[3] = 0;
        let out = run(&src, &lp);
        let share = opaque_share(&out, |q| q[0] > 230 && q[1] > 230 && q[2] > 230);
        assert!(share >= 0.9, "text lost at opacity 0: {share:.2} opaque");
    }

    /// Universal net: a full coloured tile whose only glyph is a thin outline
    /// would leave the glyph path nearly empty at opacity 0; the art is kept.
    #[test]
    fn thin_outline_on_full_tile_is_not_lost() {
        let n = 192u32;
        let src = fill(n, |x, y| {
            if !rr(n, 36.0, x, y) {
                return None;
            }
            let ring = (x == 60 || x == 131) && (60..132).contains(&y) || (y == 60 || y == 131) && (60..132).contains(&x);
            if ring {
                return Some([255, 255, 255, 255]);
            }
            Some([30, 80, 220, 255])
        });
        let mut lp = LucentParams::dark();
        lp.backdrop[3] = 0;
        let out = run(&src, &lp);
        let kept = out.pixels().filter(|q| q[3] >= 200).count();
        assert!(kept as f32 >= 0.015 * 256.0 * 256.0, "art lost at opacity 0: {kept} px");
    }
}
