//! Parallel batch engine with progress reporting and cooperative cancellation.

use crate::compose::Placement;
use crate::cutcache;
use crate::effects::{self, Effects};
use crate::error::{CoreError, Result};
use crate::imageops::{clean_transparent, decode, decode_file, resize, write_png};
use crate::lucent::{GlyphStrategy, PlateShape};
use crate::segment::{isolate, SegmentMode, SegmentOptions, SegmentResult};
use image::RgbaImage;
use rayon::prelude::*;
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::Arc;

#[derive(Clone)]
pub enum Source {
    Path(PathBuf),
    Bytes(Arc<Vec<u8>>),
}

#[derive(Clone)]
pub struct Job {
    pub id: String,
    pub name: String,
    pub source: Source,
    pub output: PathBuf,
    /// Per-item manual overrides.
    pub segment: Option<SegmentOptions>,
    pub placement: Option<Placement>,
    /// When set, the glyph is placed without isolation (already a glyph).
    pub skip_isolation: bool,
    /// Plate overrides for this icon (Lightnt only; ignored otherwise).
    pub shape: Option<PlateShape>,
    /// Plate colour and alpha, RGBA (Lightnt only).
    pub backdrop: Option<[u8; 4]>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct JobResult {
    pub id: String,
    pub name: String,
    pub ok: bool,
    pub error: Option<String>,
    pub output: Option<String>,
    pub ambiguous: bool,
    pub confidence: f32,
    pub method: String,
    pub notes: Vec<String>,
}

pub struct BatchConfig {
    pub size: u32,
    /// Background pre-rendered at `size`.
    pub background: Arc<RgbaImage>,
    pub placement: Placement,
    pub segment: SegmentOptions,
    /// Max worker threads (0 = all cores).
    pub threads: usize,
    /// Lightnt rendering: the plate is built per icon from its silhouette,
    /// so `background` is ignored.
    pub lucent: Option<crate::lucent::LucentParams>,
    /// Local AI background removal (cached model + mask options).
    pub ai: Option<(Arc<crate::ai::Model>, crate::ai::AiOptions)>,
    /// Global look options; `Effects::default()` changes nothing.
    pub effects: Effects,
    /// Folder of the cutout cache (`cutcache`); None = isolate every time.
    pub cut_cache: Option<PathBuf>,
}

/// Isolates the glyph, or reuses it from the cutout cache when the source
/// pixels and every isolation input match (see `cutcache::key`). `keep_alpha`
/// is the skip-isolation path (the glyph is already cut out). Errors come only
/// from the AI model; nothing is stored for them.
/// Notes added to an item's result when a cut-out cache is in use: the
/// Flutter side counts them ("N re-composed from cache, M re-cut") and hides them.
pub const NOTE_CACHE_HIT: &str = "cut:cache-hit";
pub const NOTE_CACHE_MISS: &str = "cut:cache-miss";

pub fn isolate_cached(
    img: &RgbaImage,
    cut_cache: Option<&Path>,
    seg: &SegmentOptions,
    ai: Option<(&crate::ai::Model, crate::ai::AiOptions)>,
    keep_alpha: bool,
) -> std::result::Result<SegmentResult, String> {
    let eff = if keep_alpha { SegmentOptions { mode: SegmentMode::KeepAlpha, ..seg.clone() } } else { seg.clone() };
    let key = cut_cache.map(|dir| {
        let ai_key = ai.filter(|_| !keep_alpha).map(|(m, opt)| cutcache::AiKey {
            model: m.kind.id(),
            stamp: cutcache::model_stamp(&m.path),
            opt,
        });
        let k = cutcache::key(&cutcache::Key { image: cutcache::image_hash(img), segment: &eff, ai: ai_key });
        (dir, k)
    });
    if let Some((dir, k)) = &key {
        if let Some(mut r) = cutcache::load(dir, k) {
            r.notes.push(NOTE_CACHE_HIT.to_string());
            return Ok(r);
        }
    }
    let mut res = if keep_alpha {
        isolate(img, &eff)
    } else if let Some((model, opt)) = ai {
        crate::ai::isolate_ai(img, model, opt)?.seg
    } else {
        isolate(img, &eff)
    };
    let miss = key.is_some();
    if let Some((dir, k)) = &key {
        // a failed store only costs a future isolation
        let _ = cutcache::store(dir, k, &res);
    }
    // added after the store, so the saved entry stays clean
    if miss {
        res.notes.push(NOTE_CACHE_MISS.to_string());
    }
    Ok(res)
}

pub fn process_one(img: &RgbaImage, cfg: &BatchConfig, job: &Job) -> (RgbaImage, JobResult) {
    let seg = job.segment.as_ref().unwrap_or(&cfg.segment);
    let pl = job.placement.as_ref().unwrap_or(&cfg.placement);
    let ai = cfg.ai.as_ref().map(|(m, o)| (&**m, *o));
    let mut res = match isolate_cached(img, cfg.cut_cache.as_deref(), seg, ai, job.skip_isolation) {
        Ok(r) => r,
        Err(e) => {
            let mut r = isolate(img, seg);
            r.notes.push(format!("AI non disponibile ({e}): segmentazione classica"));
            r.ambiguous = true;
            r
        }
    };
    let (mut canvas, extra) = compose_canvas(img, &mut res, cfg, pl, job.shape, job.backdrop);
    clean_transparent(&mut canvas);
    let r = JobResult {
        id: job.id.clone(),
        name: job.name.clone(),
        ok: true,
        error: None,
        output: None,
        ambiguous: res.ambiguous,
        confidence: res.confidence,
        method: res.method,
        notes: res.notes.into_iter().chain(extra).collect(),
    };
    (canvas, r)
}

/// Builds the icon from an isolated symbol, with the effects of `cfg`.
/// Shared by the batch and the preview, so the preview shows the export.
/// Returns the canvas and the notes the renderer added.
pub fn compose_canvas(
    img: &RgbaImage,
    res: &mut SegmentResult,
    cfg: &BatchConfig,
    pl: &Placement,
    shape: Option<PlateShape>,
    backdrop: Option<[u8; 4]>,
) -> (RgbaImage, Vec<String>) {
    let fx = &cfg.effects;
    if let Some(rgb) = fx.recolor {
        effects::recolor(&mut res.glyph, rgb);
    }
    let (mut canvas, extra) = if let Some(lp) = &cfg.lucent {
        let mut lp = crate::lucent::with_placement(lp, pl);
        if let Some(s) = shape {
            lp.shape = s;
        }
        if let Some(b) = backdrop {
            lp.backdrop = b;
        }
        if fx.plate_tint > 0.0 {
            if let Some(mean) = effects::mean_color(&res.glyph) {
                lp.backdrop = effects::tint_backdrop(lp.backdrop, mean, fx.plate_tint);
            }
        }
        if fx.recolor.is_some() {
            // a recoloured symbol is drawn as it is, not re-tinted from the source
            lp.strategy = GlyphStrategy::AsIs;
            lp.lift_greys = false;
        }
        let o = crate::lucent::render(img, &res.glyph, res.bbox, cfg.size, &lp);
        (o.image, o.notes)
    } else {
        let mut c = if cfg.background.width() == cfg.size {
            (*cfg.background).clone()
        } else {
            resize(&cfg.background, cfg.size, cfg.size)
        };
        crate::compose::place_on_plate(&mut c, img, res, pl);
        (c, Vec::new())
    };
    // symbol scaled up more than 2x (output size over its longest side)
    let (x0, y0, x1, y1) = res.bbox;
    let up = cfg.size as f32 / (x1 - x0).max(y1 - y0).max(1) as f32;
    if fx.sharpen > 0.0 && up > 2.0 {
        effects::unsharp(&mut canvas, fx.sharpen);
    }
    effects::adjust_color(&mut canvas, &fx.adjust);
    (canvas, extra)
}

fn run_job(job: &Job, cfg: &BatchConfig) -> Result<JobResult> {
    let img = match &job.source {
        Source::Path(p) => decode_file(p)?,
        Source::Bytes(b) => decode(b)?,
    };
    let (out, mut r) = process_one(&img, cfg, job);
    write_png(&out, &job.output)?;
    r.output = Some(job.output.to_string_lossy().to_string());
    Ok(r)
}

/// Runs all jobs in parallel. `progress(result, done, total)` is called from
/// worker threads after each item. Cancellation is checked before each item;
/// items not started are reported as cancelled.
pub fn run(
    jobs: &[Job],
    cfg: &BatchConfig,
    cancel: &AtomicBool,
    progress: &(dyn Fn(&JobResult, usize, usize) + Sync),
) -> Vec<JobResult> {
    let total = jobs.len();
    let done = AtomicUsize::new(0);
    in_pool(cfg.threads, || {
        run_jobs(jobs, cfg, cancel, &|r| {
            let d = done.fetch_add(1, Ordering::SeqCst) + 1;
            progress(r, d, total);
        })
    })
}

/// Jobs per parallel step of `run_chunked`.
pub const CHUNK: usize = 64;

/// Same output as `run`, but the jobs go through in chunks of `CHUNK`: the
/// results of a finished chunk are dropped before the next one starts, so the
/// memory held here does not grow with the number of icons. Nothing is
/// returned: every result is reported through `progress`.
pub fn run_chunked(jobs: &[Job], cfg: &BatchConfig, cancel: &AtomicBool, progress: &(dyn Fn(&JobResult, usize, usize) + Sync)) {
    let total = jobs.len();
    let done = AtomicUsize::new(0);
    in_pool(cfg.threads, || {
        for chunk in jobs.chunks(CHUNK) {
            let _ = run_jobs(chunk, cfg, cancel, &|r| {
                let d = done.fetch_add(1, Ordering::SeqCst) + 1;
                progress(r, d, total);
            });
        }
    })
}

/// Runs `work` in a pool of `threads` workers (0 = the shared pool).
fn in_pool<T: Send>(threads: usize, work: impl FnOnce() -> T + Send) -> T {
    if threads > 0 {
        match worker_pool(threads).build() {
            Ok(pool) => pool.install(work),
            Err(_) => work(),
        }
    } else {
        work()
    }
}

fn run_jobs(jobs: &[Job], cfg: &BatchConfig, cancel: &AtomicBool, progress: &(dyn Fn(&JobResult) + Sync)) -> Vec<JobResult> {
    jobs.par_iter()
        .map(|job| {
            let r = if cancel.load(Ordering::Relaxed) {
                JobResult {
                    id: job.id.clone(),
                    name: job.name.clone(),
                    ok: false,
                    error: Some(CoreError::Cancelled.to_string()),
                    output: None,
                    ambiguous: false,
                    confidence: 0.0,
                    method: String::new(),
                    notes: vec![],
                }
            } else {
                match std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| run_job(job, cfg))) {
                    Ok(Ok(r)) => r,
                    Ok(Err(e)) => failed(job, e.to_string()),
                    Err(_) => failed(job, "internal error while processing".into()),
                }
            };
            progress(&r);
            r
        })
        .collect::<Vec<_>>()
}

fn failed(job: &Job, e: String) -> JobResult {
    JobResult {
        id: job.id.clone(),
        name: job.name.clone(),
        ok: false,
        error: Some(e),
        output: None,
        ambiguous: true,
        confidence: 0.0,
        method: String::new(),
        notes: vec![],
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn batch_runs_and_cancels() {
        let t = tempfile::tempdir().unwrap();
        let mut img = RgbaImage::from_pixel(64, 64, image::Rgba([255, 255, 255, 255]));
        for y in 20..44 {
            for x in 20..44 {
                img.put_pixel(x, y, image::Rgba([200, 0, 0, 255]));
            }
        }
        let bytes = Arc::new(crate::imageops::encode_png(&img).unwrap());
        let jobs: Vec<Job> = (0..8)
            .map(|i| Job {
                id: i.to_string(),
                name: format!("i{i}"),
                source: Source::Bytes(bytes.clone()),
                output: t.path().join(format!("o{i}.png")),
                segment: None,
                placement: None,
                skip_isolation: false,
                shape: None,
                backdrop: None,
            })
            .collect();
        let cfg = BatchConfig {
            size: 96,
            background: Arc::new(RgbaImage::new(96, 96)),
            placement: Placement::default(),
            segment: SegmentOptions::default(),
            threads: 2,
            lucent: None,
            ai: None,
            effects: Effects::default(),
            cut_cache: None,
        };
        let cancel = AtomicBool::new(false);
        let r = run(&jobs, &cfg, &cancel, &|_, _, _| {});
        assert!(r.iter().all(|r| r.ok));
        assert!(t.path().join("o3.png").exists());
        let cancel = AtomicBool::new(true);
        let r = run(&jobs, &cfg, &cancel, &|_, _, _| {});
        assert!(r.iter().all(|r| !r.ok));
    }

    #[test]
    fn chunked_run_writes_the_same_pixels_as_one_shot() {
        let t = tempfile::tempdir().unwrap();
        let mut img = RgbaImage::from_pixel(48, 48, image::Rgba([255, 255, 255, 255]));
        for y in 12..36 {
            for x in 12..36 {
                img.put_pixel(x, y, image::Rgba([30, 90, 200, 255]));
            }
        }
        let bytes = Arc::new(crate::imageops::encode_png(&img).unwrap());
        // more than one chunk, so the chunk boundary is crossed
        let n = CHUNK + 5;
        let mk = |dir: &str| -> Vec<Job> {
            (0..n)
                .map(|i| Job {
                    id: i.to_string(),
                    name: format!("i{i}"),
                    source: Source::Bytes(bytes.clone()),
                    output: t.path().join(dir).join(format!("o{i}.png")),
                    segment: None,
                    placement: None,
                    skip_isolation: false,
                    shape: None,
                    backdrop: None,
                })
                .collect()
        };
        std::fs::create_dir_all(t.path().join("a")).unwrap();
        std::fs::create_dir_all(t.path().join("b")).unwrap();
        let cfg = BatchConfig {
            size: 64,
            background: Arc::new(RgbaImage::new(64, 64)),
            placement: Placement::default(),
            segment: SegmentOptions::default(),
            threads: 2,
            lucent: None,
            ai: None,
            effects: Effects::default(),
            cut_cache: None,
        };
        let cancel = AtomicBool::new(false);
        let one = run(&mk("a"), &cfg, &cancel, &|_, _, _| {});
        let seen = AtomicUsize::new(0);
        let last = AtomicUsize::new(0);
        run_chunked(&mk("b"), &cfg, &cancel, &|_, d, tot| {
            seen.fetch_add(1, Ordering::SeqCst);
            assert_eq!(tot, n);
            last.fetch_max(d, Ordering::SeqCst);
        });
        assert_eq!(seen.load(Ordering::SeqCst), n);
        assert_eq!(last.load(Ordering::SeqCst), n);
        assert!(one.iter().all(|r| r.ok));
        for i in 0..n {
            let a = std::fs::read(t.path().join("a").join(format!("o{i}.png"))).unwrap();
            let b = std::fs::read(t.path().join("b").join(format!("o{i}.png"))).unwrap();
            assert_eq!(a, b, "item {i} differs between one-shot and chunked");
        }
    }

    #[test]
    fn recolor_and_plate_override_reach_the_lucent_render() {
        let mut img = RgbaImage::from_pixel(64, 64, image::Rgba([255, 255, 255, 255]));
        for y in 20..44 {
            for x in 20..44 {
                img.put_pixel(x, y, image::Rgba([200, 0, 0, 255]));
            }
        }
        let cfg = BatchConfig {
            size: 96,
            background: Arc::new(RgbaImage::new(0, 0)),
            placement: Placement::default(),
            segment: SegmentOptions::default(),
            threads: 1,
            lucent: Some(crate::lucent::LucentParams::dark()),
            ai: None,
            effects: Effects { recolor: Some([0, 255, 0]), ..Effects::default() },
            cut_cache: None,
        };
        let job = Job {
            id: "a".into(),
            name: "a".into(),
            source: Source::Bytes(Arc::new(Vec::new())),
            output: PathBuf::new(),
            segment: None,
            placement: None,
            skip_isolation: false,
            shape: Some(PlateShape::Circle),
            backdrop: Some([255, 0, 0, 0x66]),
        };
        let (out, _) = process_one(&img, &cfg, &job);
        // the recoloured symbol keeps its alpha and gets the flat colour
        assert!(out.pixels().any(|p| p.0 == [0, 255, 0, 255]), "no recoloured pixel");
        assert!(!out.pixels().any(|p| p[0] > 150 && p[1] < 50 && p[3] > 200), "source colour left");
    }
    #[test]
    fn cutout_cache_hits_skip_isolation_and_keep_output_identical() {
        let t = tempfile::tempdir().unwrap();
        let mut img = RgbaImage::from_pixel(64, 64, image::Rgba([255, 255, 255, 255]));
        for y in 20..44 {
            for x in 20..44 {
                img.put_pixel(x, y, image::Rgba([200, 0, 0, 255]));
            }
        }
        let cfg_for = |cache: Option<PathBuf>, size: u32| BatchConfig {
            size,
            background: Arc::new(RgbaImage::from_pixel(size, size, image::Rgba([0, 0, 255, 255]))),
            placement: Placement::default(),
            segment: SegmentOptions::default(),
            threads: 1,
            lucent: None,
            ai: None,
            effects: Effects::default(),
            cut_cache: cache,
        };
        let job = Job {
            id: "a".into(),
            name: "a".into(),
            source: Source::Bytes(Arc::new(Vec::new())),
            output: PathBuf::new(),
            segment: None,
            placement: None,
            skip_isolation: false,
            shape: None,
            backdrop: None,
        };
        let count = |d: &Path| std::fs::read_dir(d).map(|rd| rd.count()).unwrap_or(0);
        let dir = t.path().join("cutouts");
        let (plain, _) = process_one(&img, &cfg_for(None, 96), &job);
        let (miss, r_miss) = process_one(&img, &cfg_for(Some(dir.clone()), 96), &job);
        assert_eq!(count(&dir), 2, "one entry: png + json");
        assert_eq!(miss.as_raw(), plain.as_raw(), "miss output differs from uncached");
        let (hit, r_hit) = process_one(&img, &cfg_for(Some(dir.clone()), 96), &job);
        assert_eq!(hit.as_raw(), plain.as_raw(), "hit output differs from uncached");
        assert_eq!(r_hit.method, r_miss.method);
        // a marked entry proves the next run reads the cache instead of isolating
        let key = cutcache::key(&cutcache::Key { image: cutcache::image_hash(&img), segment: &SegmentOptions::default(), ai: None });
        let mut marked = isolate(&img, &SegmentOptions::default());
        marked.method = "marker".into();
        cutcache::store(&dir, &key, &marked).unwrap();
        // a size change is not an isolation input: same key, cache hit
        let (_, r) = process_one(&img, &cfg_for(Some(dir.clone()), 128), &job);
        assert_eq!(r.method, "marker", "size change must reuse the cutout");
        // a tolerance change is an isolation input: new key, isolation runs
        let mut j2 = job.clone();
        j2.segment = Some(SegmentOptions { tolerance: 0.2, ..SegmentOptions::default() });
        let (_, r) = process_one(&img, &cfg_for(Some(dir.clone()), 96), &j2);
        assert_ne!(r.method, "marker", "tolerance change must not reuse the cutout");
        assert_eq!(count(&dir), 4, "second key adds png + json");
    }
}

/// Sizes the shared worker pool (matching, batches with `threads == 0`).
/// Must run before the first parallel job; later calls return false.
pub fn set_global_threads(n: usize) -> bool {
    n > 0 && worker_pool(n).build_global().is_ok()
}

/// Worker pool with named, background-priority threads.
///
/// On Android the workers are spawned from a thread of the app's top-app
/// group and inherit its nice -10, above Flutter's raster thread (-5): during
/// a batch they won the CPU over drawing and scrolling stuttered (p90 190 ms
/// on the test phone). At nice 10 they still use every idle cycle but
/// yield to the UI.
fn worker_pool(n: usize) -> rayon::ThreadPoolBuilder {
    rayon::ThreadPoolBuilder::new()
        .num_threads(n)
        .thread_name(|i| format!("icon-worker-{i}"))
        .start_handler(|_| lower_thread_priority())
}

#[cfg(target_os = "android")]
fn lower_thread_priority() {
    // who = 0 is the calling thread on Linux (nice is per thread)
    unsafe {
        libc::setpriority(libc::PRIO_PROCESS, 0, 10);
    }
    // Keep the workers off the fastest cores. On big.LITTLE phones (Phone
    // (2a) Plus: six 2.0 GHz + two 3.0 GHz cores) a niced worker still sits
    // on a big core and Flutter's UI/raster threads end up on a little one,
    // where a 120 Hz frame (8.3 ms) no longer fits. Phones with one cluster
    // keep every core.
    let slow = slow_cores();
    if slow.is_empty() {
        return;
    }
    unsafe {
        let mut set: libc::cpu_set_t = std::mem::zeroed();
        libc::CPU_ZERO(&mut set);
        for c in slow {
            libc::CPU_SET(c, &mut set);
        }
        libc::sched_setaffinity(0, std::mem::size_of::<libc::cpu_set_t>(), &set);
    }
}

/// Cores whose top frequency is below the fastest one (empty when all match
/// or the frequencies can't be read).
#[cfg(target_os = "android")]
fn slow_cores() -> Vec<usize> {
    let freqs: Vec<(usize, u64)> = (0..64)
        .map_while(|c| {
            std::fs::read_to_string(format!("/sys/devices/system/cpu/cpu{c}/cpufreq/cpuinfo_max_freq"))
                .ok()
                .map(|f| (c, f.trim().parse().unwrap_or(0)))
        })
        .collect();
    let max = freqs.iter().map(|f| f.1).max().unwrap_or(0);
    let slow: Vec<usize> = freqs.iter().filter(|f| f.1 > 0 && f.1 < max).map(|f| f.0).collect();
    // at least two cores for the workers, else don't restrict
    if slow.len() >= 2 { slow } else { Vec::new() }
}

#[cfg(not(target_os = "android"))]
fn lower_thread_priority() {}

#[cfg(test)]
mod cache_hit_tests {
    use super::*;
    use image::Rgba;
    use std::time::Instant;

    fn icon() -> RgbaImage {
        let mut img = RgbaImage::from_pixel(96, 96, Rgba([240, 240, 240, 255]));
        for y in 24..72 {
            for x in 24..72 {
                img.put_pixel(x, y, Rgba([200, 40, 30, 255]));
            }
        }
        img
    }

    fn cfg(backdrop: [u8; 4], cache: Option<PathBuf>) -> BatchConfig {
        BatchConfig {
            size: 96,
            background: Arc::new(RgbaImage::from_pixel(96, 96, Rgba(backdrop))),
            placement: Placement::default(),
            segment: SegmentOptions::default(),
            threads: 1,
            lucent: None,
            ai: None,
            effects: Effects::default(),
            cut_cache: cache,
        }
    }

    fn job() -> Job {
        Job {
            id: "a".into(),
            name: "a".into(),
            source: Source::Bytes(Arc::new(Vec::new())),
            output: PathBuf::from("a.png"),
            segment: None,
            placement: None,
            skip_isolation: false,
            shape: None,
            backdrop: None,
        }
    }

    #[test]
    fn cache_hit_is_marked_and_writes_the_same_pixels() {
        let t = tempfile::tempdir().unwrap();
        let img = icon();
        let fresh = process_one(&img, &cfg([255, 255, 255, 255], None), &job()).0;
        let (c1, r1) = process_one(&img, &cfg([255, 255, 255, 255], Some(t.path().into())), &job());
        let (c2, r2) = process_one(&img, &cfg([255, 255, 255, 255], Some(t.path().into())), &job());
        assert!(r1.notes.iter().any(|n| n == NOTE_CACHE_MISS));
        assert!(r2.notes.iter().any(|n| n == NOTE_CACHE_HIT));
        assert_eq!(c1.as_raw(), fresh.as_raw());
        assert_eq!(c2.as_raw(), fresh.as_raw());
    }

    #[test]
    fn plate_only_change_reuses_the_cut_and_matches_a_fresh_run() {
        let t = tempfile::tempdir().unwrap();
        let img = icon();
        // first processing fills the cache
        process_one(&img, &cfg([255, 255, 255, 255], Some(t.path().into())), &job());
        let t0 = Instant::now();
        let fresh = process_one(&img, &cfg([20, 20, 60, 255], None), &job()).0;
        let full = t0.elapsed();
        let t1 = Instant::now();
        let (hit, r) = process_one(&img, &cfg([20, 20, 60, 255], Some(t.path().into())), &job());
        let recomposed = t1.elapsed();
        assert!(r.notes.iter().any(|n| n == NOTE_CACHE_HIT), "plate-only change must hit the cut cache");
        assert_eq!(hit.as_raw(), fresh.as_raw(), "re-composed output must equal a fresh run");
        eprintln!("bench: full processing {full:?}, re-compose from cache {recomposed:?}");
    }
}
