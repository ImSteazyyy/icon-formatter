//! Automatic association between original icons and generated icons
//! (Icon Pack Builder): app name, package id, file name and visual similarity.

use crate::imageops::{decode_file, resize};
use crate::segment::{isolate, SegmentOptions};
use image::RgbaImage;
use rayon::prelude::*;
use std::collections::HashSet;
use std::path::Path;

const GRID: u32 = 16;
const HUE_BINS: usize = 12;

/// Visual signature of the glyph (plate removed by the segmenter).
#[derive(Clone, Debug)]
pub struct Signature {
    /// Glyph coverage on a 16x16 grid (aspect-preserving fit), 0..1.
    shape: Vec<f32>,
    /// Alpha/saturation-weighted hue histogram plus a grey bin, normalised.
    hue: [f32; HUE_BINS + 1],
}

/// Longest side used to compute a signature: the signature is a 16x16 grid,
/// so segmenting the full-size icon (432..1024 px) only costs time.
const SIG_SIDE: u32 = 160;

pub fn signature(img: &RgbaImage) -> Signature {
    let (w0, h0) = img.dimensions();
    let small;
    let img = if w0.max(h0) > SIG_SIDE {
        let k = SIG_SIDE as f32 / w0.max(h0) as f32;
        small = resize(img, ((w0 as f32 * k).round() as u32).max(1), ((h0 as f32 * k).round() as u32).max(1));
        &small
    } else {
        img
    };
    let res = isolate(img, &SegmentOptions::default());
    let g = &res.glyph;
    let (w, h) = (g.width().max(1), g.height().max(1));
    let k = GRID as f32 / w.max(h) as f32;
    let (tw, th) = (((w as f32 * k).round() as u32).clamp(1, GRID), ((h as f32 * k).round() as u32).clamp(1, GRID));
    let small = resize(g, tw, th);
    let mut shape = vec![0.0f32; (GRID * GRID) as usize];
    let (ox, oy) = ((GRID - tw) / 2, (GRID - th) / 2);
    for y in 0..th {
        for x in 0..tw {
            shape[((y + oy) * GRID + x + ox) as usize] = small.get_pixel(x, y)[3] as f32 / 255.0;
        }
    }
    let mut hue = [0.0f32; HUE_BINS + 1];
    for p in g.pixels() {
        let a = p[3] as f32 / 255.0;
        if a < 0.3 {
            continue;
        }
        let (r, gg, b) = (p[0] as f32 / 255.0, p[1] as f32 / 255.0, p[2] as f32 / 255.0);
        let max = r.max(gg).max(b);
        let min = r.min(gg).min(b);
        let s = if max > 0.0 { (max - min) / max } else { 0.0 };
        if s < 0.2 || max < 0.15 {
            hue[HUE_BINS] += a;
            continue;
        }
        let d = max - min;
        let mut hdeg = if max == r {
            60.0 * (((gg - b) / d) % 6.0)
        } else if max == gg {
            60.0 * ((b - r) / d + 2.0)
        } else {
            60.0 * ((r - gg) / d + 4.0)
        };
        if hdeg < 0.0 {
            hdeg += 360.0;
        }
        hue[((hdeg / 360.0 * HUE_BINS as f32) as usize).min(HUE_BINS - 1)] += a * s;
    }
    let sum: f32 = hue.iter().sum();
    if sum > 0.0 {
        hue.iter_mut().for_each(|v| *v /= sum);
    }
    Signature { shape, hue }
}

/// 0..1 visual similarity. Shape dominates (monochrome outputs keep the
/// silhouette but not the colours).
pub fn similarity(a: &Signature, b: &Signature) -> f32 {
    let (mut inter, mut uni) = (0.0f32, 0.0f32);
    for (x, y) in a.shape.iter().zip(b.shape.iter()) {
        inter += x.min(*y);
        uni += x.max(*y);
    }
    let shape = if uni > 0.0 { inter / uni } else { 0.0 };
    let hue: f32 = a.hue.iter().zip(b.hue.iter()).map(|(x, y)| x.min(*y)).sum();
    0.75 * shape + 0.25 * hue
}

/// Lowercase alphanumeric key; drops common decorations (`ic_`, size and
/// copy suffixes such as `_512`, ` 2`, `(1)`).
pub fn normalize(s: &str) -> String {
    let lower = s.to_lowercase();
    let is_img = [".png", ".webp", ".jpg", ".jpeg", ".xml", ".svg"].iter().any(|e| lower.ends_with(e));
    let stem = if is_img {
        Path::new(s).file_stem().map(|v| v.to_string_lossy().to_string()).unwrap_or_else(|| s.to_string())
    } else {
        s.to_string()
    };
    let mut t = stem.to_lowercase();
    for p in ["ic_launcher_", "ic_", "icon_"] {
        if let Some(r) = t.strip_prefix(p) {
            t = r.to_string();
        }
    }
    let t = t.trim_end_matches(|c: char| c.is_ascii_digit() || c == '_' || c == '-' || c == ' ' || c == '(' || c == ')');
    let t = if t.is_empty() { stem.to_lowercase() } else { t.to_string() };
    t.chars().filter(|c| c.is_alphanumeric()).collect()
}

fn tokens(s: &str) -> HashSet<String> {
    s.to_lowercase()
        .split(|c: char| !c.is_alphanumeric())
        .filter(|t| t.len() > 1 && !["com", "org", "net", "app", "android", "ic", "launcher", "icon", "png", "www"].contains(t))
        .map(|t| t.to_string())
        .collect()
}

#[derive(Clone, Debug, Default)]
pub struct Candidate {
    pub id: String,
    /// App label (may be empty).
    pub label: String,
    /// Package id or component (may be empty).
    pub package: String,
    /// File name (may be empty).
    pub file: String,
    pub path: Option<String>,
    pub image: Option<RgbaImage>,
    /// Encoded image (decoded only when its signature is not cached).
    pub png: Option<Vec<u8>>,
}

/// Text score 0..1 and the reason.
pub fn text_score(o: &Candidate, g: &Candidate) -> (f32, &'static str) {
    let pk = |s: &str| s.split('/').next().unwrap_or("").to_lowercase();
    let gfile = normalize(&g.file);
    if !o.package.is_empty() {
        let p = pk(&o.package);
        let pflat: String = p.chars().filter(|c| c.is_alphanumeric()).collect();
        if (!g.package.is_empty() && pk(&g.package) == p) || (!gfile.is_empty() && gfile == pflat) {
            return (1.0, "package");
        }
    }
    let ol = normalize(&o.label);
    if !ol.is_empty() && (ol == normalize(&g.label) || ol == gfile) {
        return (0.95, "nome app");
    }
    let of = normalize(&o.file);
    if !of.is_empty() && of == gfile {
        return (0.9, "nome file");
    }
    let a: HashSet<String> = tokens(&format!("{} {} {}", o.label, o.package, o.file));
    let b: HashSet<String> = tokens(&format!("{} {} {}", g.label, g.package, g.file));
    if a.is_empty() || b.is_empty() {
        return (0.0, "");
    }
    let inter = a.intersection(&b).count() as f32;
    let jac = inter / a.union(&b).count() as f32;
    if jac > 0.0 {
        (0.45 + 0.4 * jac, "parole in comune")
    } else {
        (0.0, "")
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum MatchStatus {
    Confident,
    Doubtful,
    /// Name or package match, but the drawing looks different: to be checked.
    Review,
    Missing,
}

#[derive(Clone, Debug)]
pub struct MatchResult {
    pub original: String,
    pub generated: Option<String>,
    pub score: f32,
    pub text: f32,
    pub visual: f32,
    pub status: MatchStatus,
    pub reason: String,
}

fn fnv(h: &mut u64, b: &[u8]) {
    for &x in b {
        *h ^= x as u64;
        *h = h.wrapping_mul(0x100_0000_01b3);
    }
}

/// Cache key of a candidate's image: file path + size + mtime, or the
/// bytes themselves. None for in-memory images (not cached).
fn cache_key(c: &Candidate) -> Option<u64> {
    let mut h: u64 = 0xcbf2_9ce4_8422_2325;
    if let Some(b) = &c.png {
        fnv(&mut h, b);
        return Some(h);
    }
    let p = c.path.as_ref()?;
    let m = std::fs::metadata(p).ok()?;
    fnv(&mut h, p.as_bytes());
    fnv(&mut h, &m.len().to_le_bytes());
    if let Ok(t) = m.modified().and_then(|t| t.duration_since(std::time::UNIX_EPOCH).map_err(std::io::Error::other)) {
        fnv(&mut h, &t.as_nanos().to_le_bytes());
    }
    Some(h)
}

static CACHE: std::sync::OnceLock<std::sync::Mutex<std::collections::HashMap<u64, Option<Signature>>>> = std::sync::OnceLock::new();

/// Signature of a candidate, computed once per image (path+mtime or bytes)
/// and kept for the whole session: repeated matching is almost free.
fn cached_signature(c: &Candidate) -> Option<Signature> {
    let cache = CACHE.get_or_init(Default::default);
    let key = cache_key(c);
    if let Some(k) = key {
        if let Some(v) = cache.lock().ok().and_then(|m| m.get(&k).cloned()) {
            return v;
        }
    }
    let img = c
        .image
        .clone()
        .or_else(|| c.png.as_ref().and_then(|b| crate::imageops::decode(b).ok()))
        .or_else(|| c.path.as_ref().and_then(|p| decode_file(Path::new(p)).ok()));
    let sig = img.map(|i| signature(&i));
    if let (Some(k), Ok(mut m)) = (key, cache.lock()) {
        if m.len() > 20_000 {
            m.clear();
        }
        m.insert(k, sig.clone());
    }
    sig
}

/// Precomputed text keys of a candidate (computed once, not per pair).
struct Keys {
    pkg: String,
    pflat: String,
    label: String,
    file: String,
    gfile: String,
    tokens: HashSet<String>,
}

fn keys(c: &Candidate) -> Keys {
    let pkg = c.package.split('/').next().unwrap_or("").to_lowercase();
    Keys {
        pflat: pkg.chars().filter(|c| c.is_alphanumeric()).collect(),
        pkg,
        label: normalize(&c.label),
        file: normalize(&c.file),
        gfile: normalize(&c.file),
        tokens: tokens(&format!("{} {} {}", c.label, c.package, c.file)),
    }
}

/// Same rules as [`text_score`], on precomputed keys.
fn text_score_k(o: &Keys, g: &Keys) -> (f32, &'static str) {
    if !o.pkg.is_empty() && ((!g.pkg.is_empty() && g.pkg == o.pkg) || (!g.gfile.is_empty() && g.gfile == o.pflat)) {
        return (1.0, "package");
    }
    if !o.label.is_empty() && (o.label == g.label || o.label == g.gfile) {
        return (0.95, "nome app");
    }
    if !o.file.is_empty() && o.file == g.gfile {
        return (0.9, "nome file");
    }
    if o.tokens.is_empty() || g.tokens.is_empty() {
        return (0.0, "");
    }
    let inter = o.tokens.intersection(&g.tokens).count() as f32;
    if inter == 0.0 {
        return (0.0, "");
    }
    let jac = inter / o.tokens.union(&g.tokens).count() as f32;
    (0.45 + 0.4 * jac, "parole in comune")
}

/// One-to-one association, greedy by combined score.
pub fn match_icons(originals: &[Candidate], generated: &[Candidate]) -> Vec<MatchResult> {
    // signatures (cached) and text keys, computed once per icon
    let os: Vec<Option<Signature>> = originals.par_iter().map(cached_signature).collect();
    let gs: Vec<Option<Signature>> = generated.par_iter().map(cached_signature).collect();
    let ok: Vec<Keys> = originals.par_iter().map(keys).collect();
    let gk: Vec<Keys> = generated.par_iter().map(keys).collect();
    struct Pair {
        o: usize,
        g: usize,
        score: f32,
        text: f32,
        visual: f32,
        reason: &'static str,
    }
    let mut pairs: Vec<Pair> = (0..originals.len())
        .into_par_iter()
        .flat_map_iter(|o| {
            let os = &os;
            let gs = &gs;
            let ok = &ok;
            let gk = &gk;
            (0..generated.len()).filter_map(move |g| {
                let (text, reason) = text_score_k(&ok[o], &gk[g]);
                let visual = match (&os[o], &gs[g]) {
                    (Some(a), Some(b)) => similarity(a, b),
                    _ => 0.0,
                };
                let score = if text > 0.0 { 0.7 * text + 0.3 * visual } else { 0.8 * visual };
                (score > 0.25).then_some(Pair { o, g, score, text, visual, reason })
            })
        })
        .collect();
    pairs.sort_by(|a, b| b.score.partial_cmp(&a.score).unwrap_or(std::cmp::Ordering::Equal));
    // second-best per original, to flag ambiguous visual matches
    let mut best2 = vec![(0.0f32, 0.0f32); originals.len()];
    for p in &pairs {
        let e = &mut best2[p.o];
        if p.score > e.0 {
            e.1 = e.0;
            e.0 = p.score;
        } else if p.score > e.1 {
            e.1 = p.score;
        }
    }
    let mut used_o = vec![false; originals.len()];
    let mut used_g = vec![false; generated.len()];
    let mut out: Vec<Option<MatchResult>> = vec![None; originals.len()];
    for p in pairs {
        if used_o[p.o] || used_g[p.g] {
            continue;
        }
        used_o[p.o] = true;
        used_g[p.g] = true;
        let margin = best2[p.o].0 - best2[p.o].1;
        let status = if p.text >= 0.9 && p.visual >= 0.35 {
            MatchStatus::Confident
        } else if p.text >= 0.9 {
            MatchStatus::Review // name matches but the drawing looks different
        } else if p.text == 0.0 && p.visual >= 0.82 && margin >= 0.04 {
            MatchStatus::Confident
        } else {
            MatchStatus::Doubtful
        };
        let reason = if p.text > 0.0 {
            format!("{} · somiglianza {:.0}%", p.reason, p.visual * 100.0)
        } else {
            format!("solo somiglianza visiva {:.0}%", p.visual * 100.0)
        };
        out[p.o] = Some(MatchResult {
            original: originals[p.o].id.clone(),
            generated: Some(generated[p.g].id.clone()),
            score: p.score,
            text: p.text,
            visual: p.visual,
            status,
            reason,
        });
    }
    out.into_iter()
        .enumerate()
        .map(|(i, r)| {
            r.unwrap_or(MatchResult {
                original: originals[i].id.clone(),
                generated: None,
                score: 0.0,
                text: 0.0,
                visual: 0.0,
                status: MatchStatus::Missing,
                reason: "nessuna icona generata corrispondente".into(),
            })
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use image::Rgba;

    fn icon(kind: u8, color: [u8; 3]) -> RgbaImage {
        let mut img = RgbaImage::from_pixel(96, 96, Rgba([20, 20, 20, 255]));
        for y in 0..96u32 {
            for x in 0..96u32 {
                let (dx, dy) = (x as f32 - 48.0, y as f32 - 48.0);
                let on = match kind {
                    0 => dx.hypot(dy) < 28.0,
                    1 => dx.abs() < 30.0 && dy.abs() < 10.0,
                    _ => dx.abs() < 8.0 && dy.abs() < 32.0,
                };
                if on {
                    img.put_pixel(x, y, Rgba([color[0], color[1], color[2], 255]));
                }
            }
        }
        img
    }

    fn cand(id: &str, label: &str, pkg: &str, file: &str, img: RgbaImage) -> Candidate {
        Candidate { id: id.into(), label: label.into(), package: pkg.into(), file: file.into(), path: None, image: Some(img), png: None }
    }

    #[test]
    fn normalizes_names() {
        assert_eq!(normalize("ic_WhatsApp_512.png"), "whatsapp");
        assert_eq!(normalize("Square Music 2.png"), "squaremusic");
        assert_eq!(normalize("com.whatsapp"), "comwhatsapp");
    }

    #[test]
    fn matches_by_package_name_and_visual() {
        let o = vec![
            cand("o1", "WhatsApp", "com.whatsapp", "", icon(0, [40, 200, 90])),
            cand("o2", "Telegram", "org.telegram.messenger", "", icon(1, [40, 150, 230])),
            cand("o3", "", "", "foo.png", icon(2, [230, 60, 60])),
            cand("o4", "Nothing", "", "", icon(0, [200, 200, 0])),
        ];
        let g = vec![
            cand("g2", "", "", "telegram.png", icon(1, [40, 150, 230])),
            cand("g1", "", "", "com_whatsapp.png", icon(0, [40, 200, 90])),
            cand("g3", "", "", "zzz.png", icon(2, [230, 60, 60])),
        ];
        let r = match_icons(&o, &g);
        assert_eq!(r[0].generated.as_deref(), Some("g1"));
        assert_eq!(r[0].status, MatchStatus::Confident);
        assert_eq!(r[1].generated.as_deref(), Some("g2"));
        assert_eq!(r[2].generated.as_deref(), Some("g3"), "{:?}", r[2]);
        assert_eq!(r[3].status, MatchStatus::Missing);
    }
}
