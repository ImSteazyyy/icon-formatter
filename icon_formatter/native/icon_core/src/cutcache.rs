//! Persistent cache of isolated glyphs ("cutouts").
//!
//! Isolation (background removal) is the slow step of a run. Plate, shape,
//! opacity, colour and placement settings only act after it, so a cached glyph
//! can be reused whenever the source pixels and every isolation input match.
//!
//! The key is FNV-1a (stable across runs, unlike `DefaultHasher`) over the
//! decoded RGBA pixels and size of the source, the isolation options and the
//! AI model identity, plus `CACHE_VERSION`. Entries are `<key>.png` (the glyph)
//! and `<key>.json` (bbox, source size, confidence, flags, notes). Writes go to
//! a temp file that is renamed into place. Any unreadable or inconsistent entry
//! is a miss.
use crate::ai::AiOptions;
use crate::segment::{SegmentMode, SegmentOptions, SegmentResult};
use image::{ExtendedColorType, ImageEncoder, RgbaImage};
use serde::{Deserialize, Serialize};
use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

/// Bump when an isolation algorithm changes its output: old entries then miss.
pub const CACHE_VERSION: u32 = 1;

const FNV_OFFSET: u64 = 0xcbf2_9ce4_8422_2325;
const FNV_PRIME: u64 = 0x0000_0100_0000_01b3;

/// FNV-1a over `bytes`, continuing from `h`.
#[inline]
pub fn fnv1a(mut h: u64, bytes: &[u8]) -> u64 {
    for &b in bytes {
        h ^= b as u64;
        h = h.wrapping_mul(FNV_PRIME);
    }
    h
}

/// Hash of the decoded source: dimensions, then the RGBA bytes in one pass.
pub fn image_hash(img: &RgbaImage) -> u64 {
    let h = fnv1a(FNV_OFFSET, &img.width().to_le_bytes());
    let h = fnv1a(h, &img.height().to_le_bytes());
    fnv1a(h, img.as_raw())
}

/// Identity of a model file: path, size and modification time. Replacing the
/// file in place therefore changes the key.
pub fn model_stamp(path: &str) -> u64 {
    let mut h = fnv1a(FNV_OFFSET, path.as_bytes());
    if let Ok(m) = fs::metadata(path) {
        h = fnv1a(h, &m.len().to_le_bytes());
        let t = m
            .modified()
            .ok()
            .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
            .map_or(0, |d| d.as_nanos() as u64);
        h = fnv1a(h, &t.to_le_bytes());
    }
    h
}

/// The AI part of a key (only when the AI model isolates the glyph).
pub struct AiKey<'a> {
    /// `ModelKind::id()`.
    pub model: &'a str,
    /// `model_stamp` of the model file.
    pub stamp: u64,
    pub opt: AiOptions,
}

/// Everything that decides the isolation result. Placement, plate, shape,
/// colour and effects are deliberately absent: they act after isolation.
/// `segment` must be the options actually used (after per-icon overrides, and
/// with `mode: KeepAlpha` for the keep-alpha path).
pub struct Key<'a> {
    pub image: u64,
    pub segment: &'a SegmentOptions,
    pub ai: Option<AiKey<'a>>,
}

/// Cache key: 16 hex digits.
pub fn key(k: &Key) -> String {
    let s = k.segment;
    let mut h = fnv1a(FNV_OFFSET, &CACHE_VERSION.to_le_bytes());
    h = fnv1a(h, &k.image.to_le_bytes());
    let mode: u8 = match s.mode {
        SegmentMode::Auto => 0,
        SegmentMode::KeepAlpha => 1,
        SegmentMode::RemoveBackground => 2,
        SegmentMode::None => 3,
    };
    h = fnv1a(h, &[mode, s.remove_holes as u8, s.refine_edges as u8]);
    h = fnv1a(h, &s.tolerance.to_bits().to_le_bytes());
    h = fnv1a(h, &s.min_component.to_bits().to_le_bytes());
    match &k.ai {
        None => h = fnv1a(h, &[0]),
        Some(a) => {
            h = fnv1a(h, &[1]);
            h = fnv1a(h, a.model.as_bytes());
            h = fnv1a(h, &[0]);
            h = fnv1a(h, &a.stamp.to_le_bytes());
            h = fnv1a(h, &a.opt.low.to_bits().to_le_bytes());
            h = fnv1a(h, &a.opt.high.to_bits().to_le_bytes());
        }
    }
    format!("{h:016x}")
}

#[derive(Serialize, Deserialize)]
struct Meta {
    v: u32,
    bbox: (u32, u32, u32, u32),
    source_size: (u32, u32),
    confidence: f32,
    ambiguous: bool,
    method: String,
    notes: Vec<String>,
}

/// Returns the stored isolation for `key`, or None on a miss or a bad entry.
pub fn load(dir: &Path, key: &str) -> Option<SegmentResult> {
    let meta: Meta = serde_json::from_slice(&fs::read(dir.join(format!("{key}.json"))).ok()?).ok()?;
    if meta.v != CACHE_VERSION {
        return None;
    }
    let png = fs::read(dir.join(format!("{key}.png"))).ok()?;
    let glyph = image::load_from_memory_with_format(&png, image::ImageFormat::Png).ok()?.into_rgba8();
    let (x0, y0, x1, y1) = meta.bbox;
    let (sw, sh) = meta.source_size;
    let consistent = x0 <= x1
        && y0 <= y1
        && x1 <= sw
        && y1 <= sh
        && glyph.width() == x1 - x0
        && glyph.height() == y1 - y0
        && meta.confidence.is_finite();
    if !consistent {
        return None;
    }
    Some(SegmentResult {
        glyph,
        bbox: meta.bbox,
        source_size: meta.source_size,
        confidence: meta.confidence,
        ambiguous: meta.ambiguous,
        method: meta.method,
        notes: meta.notes,
    })
}

static SEQ: AtomicU64 = AtomicU64::new(0);

/// Writes `bytes` to a unique temp file next to `path`, then renames it over
/// `path`. Two writers of the same key never share a temp name.
fn write_atomic(path: &Path, bytes: &[u8]) -> io::Result<()> {
    let tmp = PathBuf::from(format!(
        "{}.{}-{}.tmp",
        path.display(),
        std::process::id(),
        SEQ.fetch_add(1, Ordering::Relaxed)
    ));
    fs::write(&tmp, bytes)?;
    fs::rename(&tmp, path).inspect_err(|_| {
        let _ = fs::remove_file(&tmp);
    })
}

/// Stores the isolation for `key`. Errors are returned, but callers may ignore
/// them: a missing entry only costs a future isolation.
pub fn store(dir: &Path, key: &str, r: &SegmentResult) -> io::Result<()> {
    fs::create_dir_all(dir)?;
    let mut png = Vec::new();
    // fast compression: the cache write sits on the miss path of every item
    image::codecs::png::PngEncoder::new_with_quality(
        &mut png,
        image::codecs::png::CompressionType::Fast,
        image::codecs::png::FilterType::Sub,
    )
    .write_image(r.glyph.as_raw(), r.glyph.width(), r.glyph.height(), ExtendedColorType::Rgba8)
    .map_err(io::Error::other)?;
    let meta = Meta {
        v: CACHE_VERSION,
        bbox: r.bbox,
        source_size: r.source_size,
        confidence: r.confidence,
        ambiguous: r.ambiguous,
        method: r.method.clone(),
        notes: r.notes.clone(),
    };
    let json = serde_json::to_vec(&meta).map_err(io::Error::other)?;
    // glyph first: `load` needs both files, so a half-written pair is a miss
    write_atomic(&dir.join(format!("{key}.png")), &png)?;
    write_atomic(&dir.join(format!("{key}.json")), &json)
}

/// One cache key in the folder: its files, total bytes and newest mtime.
struct Group {
    bytes: u64,
    mtime: SystemTime,
    files: Vec<PathBuf>,
}

/// Cache files of `dir` grouped by key. Only names that start with a 16-digit
/// hex key and end in png, json or tmp are considered, so unrelated files in
/// the folder are never touched.
fn groups(dir: &Path) -> Vec<Group> {
    let mut by_key: Vec<(String, Group)> = Vec::new();
    let Ok(rd) = fs::read_dir(dir) else { return Vec::new() };
    for e in rd.flatten() {
        let name = e.file_name().to_string_lossy().to_string();
        let Some((key, rest)) = name.split_once('.') else { continue };
        let ext = rest.rsplit('.').next().unwrap_or("");
        let valid = key.len() == 16 && key.bytes().all(|b| b.is_ascii_hexdigit()) && matches!(ext, "png" | "json" | "tmp");
        let Ok(md) = e.metadata() else { continue };
        if !valid || !md.is_file() {
            continue;
        }
        let mtime = md.modified().unwrap_or(UNIX_EPOCH);
        match by_key.iter_mut().find(|(k, _)| k == key) {
            Some((_, g)) => {
                g.bytes += md.len();
                g.mtime = g.mtime.max(mtime);
                g.files.push(e.path());
            }
            None => by_key.push((key.to_string(), Group { bytes: md.len(), mtime, files: vec![e.path()] })),
        }
    }
    by_key.into_iter().map(|(_, g)| g).collect()
}

/// Total bytes of the cache in `dir` (0 when the folder does not exist).
pub fn size(dir: &Path) -> u64 {
    groups(dir).iter().map(|g| g.bytes).sum()
}

/// Deletes every cache file in `dir`.
pub fn clear(dir: &Path) -> io::Result<()> {
    for g in groups(dir) {
        for p in &g.files {
            fs::remove_file(p)?;
        }
    }
    Ok(())
}

/// Deletes the oldest entries (by last store time) until the cache holds at
/// most `max_bytes`. Returns the remaining size. Loads do not refresh times,
/// so this is first-in-first-out rather than least recently used.
pub fn prune(dir: &Path, max_bytes: u64) -> io::Result<u64> {
    let mut gs = groups(dir);
    let mut total: u64 = gs.iter().map(|g| g.bytes).sum();
    gs.sort_by_key(|g| g.mtime);
    for g in gs {
        if total <= max_bytes {
            break;
        }
        // a file in use (a worker reading it) is skipped, not fatal
        for p in &g.files {
            let _ = fs::remove_file(p);
        }
        total -= g.bytes;
    }
    Ok(total)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::segment::isolate;
    use image::Rgba;
    use std::time::{Duration, Instant};

    fn sample(seed: u8) -> RgbaImage {
        let mut img = RgbaImage::from_pixel(64, 64, Rgba([240, 240, 240, 255]));
        for y in 16..48 {
            for x in 16..48 {
                img.put_pixel(x, y, Rgba([200, seed, 0, 255]));
            }
        }
        img
    }

    fn plain(img: &RgbaImage, seg: &SegmentOptions) -> String {
        key(&Key { image: image_hash(img), segment: seg, ai: None })
    }

    #[test]
    fn key_follows_pixels_and_isolation_settings() {
        let a = sample(10);
        let base = SegmentOptions::default();
        let k = plain(&a, &base);
        assert_eq!(k, plain(&sample(10), &base), "same pixels must hit");
        assert_ne!(k, plain(&sample(11), &base), "other pixels must miss");
        let mut s = base.clone();
        s.tolerance = 0.2;
        assert_ne!(k, plain(&a, &s), "tolerance");
        let mut s = base.clone();
        s.mode = SegmentMode::KeepAlpha;
        assert_ne!(k, plain(&a, &s), "mode");
        let mut s = base.clone();
        s.remove_holes = !s.remove_holes;
        assert_ne!(k, plain(&a, &s), "remove_holes");
        let mut s = base.clone();
        s.refine_edges = !s.refine_edges;
        assert_ne!(k, plain(&a, &s), "refine_edges");
        let mut s = base.clone();
        s.min_component = 0.001;
        assert_ne!(k, plain(&a, &s), "min_component");
        let ai = |model: &str, stamp: u64, low: f32| {
            key(&Key { image: image_hash(&a), segment: &base, ai: Some(AiKey { model, stamp, opt: AiOptions { low, high: 0.85 } }) })
        };
        let on = ai("u2netp", 1, 0.15);
        assert_ne!(k, on, "AI on vs classic");
        assert_ne!(on, ai("silueta", 1, 0.15), "model kind");
        assert_ne!(on, ai("u2netp", 2, 0.15), "model file changed");
        assert_ne!(on, ai("u2netp", 1, 0.2), "AI thresholds");
        assert_eq!(on, ai("u2netp", 1, 0.15), "AI key stable");
    }

    #[test]
    fn image_hash_depends_on_shape_not_only_bytes() {
        assert_ne!(image_hash(&RgbaImage::new(4, 8)), image_hash(&RgbaImage::new(8, 4)));
    }

    #[test]
    fn store_load_round_trip() {
        let dir = tempfile::tempdir().unwrap();
        let r = isolate(&sample(10), &SegmentOptions::default());
        store(dir.path(), "0123456789abcdef", &r).unwrap();
        let l = load(dir.path(), "0123456789abcdef").expect("hit");
        assert_eq!(l.glyph.as_raw(), r.glyph.as_raw());
        assert_eq!(l.bbox, r.bbox);
        assert_eq!(l.source_size, r.source_size);
        assert_eq!(l.confidence.to_bits(), r.confidence.to_bits());
        assert_eq!(l.ambiguous, r.ambiguous);
        assert_eq!(l.method, r.method);
        assert_eq!(l.notes, r.notes);
        assert!(load(dir.path(), "fedcba9876543210").is_none());
        assert!(load(&dir.path().join("missing"), "0123456789abcdef").is_none());
    }

    #[test]
    fn corrupt_entries_are_misses() {
        let dir = tempfile::tempdir().unwrap();
        let key = "0123456789abcdef";
        let r = isolate(&sample(10), &SegmentOptions::default());
        store(dir.path(), key, &r).unwrap();
        fs::write(dir.path().join(format!("{key}.png")), b"not a png").unwrap();
        assert!(load(dir.path(), key).is_none(), "bad png");
        store(dir.path(), key, &r).unwrap();
        fs::write(dir.path().join(format!("{key}.json")), b"{ broken").unwrap();
        assert!(load(dir.path(), key).is_none(), "bad json");
        store(dir.path(), key, &r).unwrap();
        fs::remove_file(dir.path().join(format!("{key}.png"))).unwrap();
        assert!(load(dir.path(), key).is_none(), "missing png");
    }

    #[test]
    fn concurrent_stores_of_one_key_stay_readable() {
        let dir = tempfile::tempdir().unwrap();
        let r = isolate(&sample(10), &SegmentOptions::default());
        std::thread::scope(|s| {
            for _ in 0..8 {
                s.spawn(|| store(dir.path(), "0123456789abcdef", &r).unwrap());
            }
        });
        let l = load(dir.path(), "0123456789abcdef").expect("hit after races");
        assert_eq!(l.glyph.as_raw(), r.glyph.as_raw());
        assert_eq!(groups(dir.path()).len(), 1);
    }

    #[test]
    fn prune_keeps_the_newest_and_clear_leaves_other_files() {
        let dir = tempfile::tempdir().unwrap();
        let r = isolate(&sample(10), &SegmentOptions::default());
        let keys = ["0000000000000001", "0000000000000002", "0000000000000003"];
        for k in keys {
            store(dir.path(), k, &r).unwrap();
            std::thread::sleep(Duration::from_millis(30));
        }
        fs::write(dir.path().join("notes.txt"), b"keep me").unwrap();
        let total = size(dir.path());
        assert!(total > 0);
        let left = prune(dir.path(), total - 1).unwrap();
        assert!(left < total && left > 0);
        assert!(load(dir.path(), keys[0]).is_none(), "oldest removed");
        assert!(load(dir.path(), keys[1]).is_some());
        assert!(load(dir.path(), keys[2]).is_some());
        assert_eq!(prune(dir.path(), 0).unwrap(), 0);
        for k in keys {
            store(dir.path(), k, &r).unwrap();
        }
        clear(dir.path()).unwrap();
        assert_eq!(size(dir.path()), 0);
        assert!(dir.path().join("notes.txt").exists());
    }

    /// Hit against miss on the sample icons. Run with:
    /// `cargo test --release --lib cutcache::tests::bench_hit_vs_miss -- --ignored --nocapture`
    #[test]
    #[ignore]
    fn bench_hit_vs_miss() {
        let inputs = Path::new("D:/Claude/cleanroom-lucent/shared/inputs");
        let Ok(rd) = fs::read_dir(inputs) else { return };
        let mut files: Vec<PathBuf> = rd.flatten().map(|e| e.path()).filter(|p| p.extension().is_some_and(|x| x == "png")).collect();
        files.sort();
        let cache = tempfile::tempdir().unwrap();
        let seg = SegmentOptions::default();
        let (mut hash, mut iso, mut store_t, mut load_t) = (0f64, 0f64, 0f64, 0f64);
        for p in &files {
            let img = crate::imageops::decode_file(p).unwrap();
            let t = Instant::now();
            let k = plain(&img, &seg);
            hash += t.elapsed().as_secs_f64();
            let t = Instant::now();
            let r = isolate(&img, &seg);
            iso += t.elapsed().as_secs_f64();
            let t = Instant::now();
            store(cache.path(), &k, &r).unwrap();
            store_t += t.elapsed().as_secs_f64();
            let t = Instant::now();
            let l = load(cache.path(), &k).expect("hit");
            load_t += t.elapsed().as_secs_f64();
            assert_eq!(l.glyph.as_raw(), r.glyph.as_raw());
        }
        let n = files.len().max(1) as f64;
        let ms = |s: f64| s * 1000.0 / n;
        println!(
            "{} icons | isolate (miss) {:.2} ms | store (miss extra) {:.2} ms | hash {:.3} ms | load (hit) {:.2} ms | hit total {:.2} ms",
            files.len(),
            ms(iso),
            ms(store_t),
            ms(hash),
            ms(load_t),
            ms(hash + load_t)
        );
    }
}
