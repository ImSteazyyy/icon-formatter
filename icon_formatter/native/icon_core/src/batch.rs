//! Parallel batch engine with progress reporting and cooperative cancellation.

use crate::compose::Placement;
use crate::error::{CoreError, Result};
use crate::imageops::{clean_transparent, decode, decode_file, resize, write_png};
use crate::segment::{isolate, SegmentOptions};
use image::RgbaImage;
use rayon::prelude::*;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
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
    /// Lucent rendering: the plate is built per icon from its silhouette,
    /// so `background` is ignored.
    pub lucent: Option<crate::lucent::LucentParams>,
    /// Local AI background removal (cached model + mask options).
    pub ai: Option<(Arc<crate::ai::Model>, crate::ai::AiOptions)>,
}

pub fn process_one(img: &RgbaImage, cfg: &BatchConfig, job: &Job) -> (RgbaImage, JobResult) {
    let seg = job.segment.as_ref().unwrap_or(&cfg.segment);
    let pl = job.placement.as_ref().unwrap_or(&cfg.placement);
    let res = if job.skip_isolation {
        isolate(img, &SegmentOptions { mode: crate::segment::SegmentMode::KeepAlpha, ..seg.clone() })
    } else if let Some((model, opt)) = &cfg.ai {
        match crate::ai::isolate_ai(img, model, *opt) {
            Ok(r) => r.seg,
            Err(e) => {
                let mut r = isolate(img, seg);
                r.notes.push(format!("AI non disponibile ({e}): segmentazione classica"));
                r.ambiguous = true;
                r
            }
        }
    } else {
        isolate(img, seg)
    };
    let mut extra = Vec::new();
    let mut canvas = if let Some(lp) = &cfg.lucent {
        let o = crate::lucent::render(img, &res.glyph, res.bbox, cfg.size, &crate::lucent::with_placement(lp, pl));
        extra = o.notes;
        o.image
    } else {
        let mut c = if cfg.background.width() == cfg.size {
            (*cfg.background).clone()
        } else {
            resize(&cfg.background, cfg.size, cfg.size)
        };
        crate::compose::place_on_plate(&mut c, img, &res, pl);
        c
    };
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
    let work = || {
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
                let d = done.fetch_add(1, Ordering::SeqCst) + 1;
                progress(&r, d, total);
                r
            })
            .collect::<Vec<_>>()
    };
    if cfg.threads > 0 {
        match worker_pool(cfg.threads).build() {
            Ok(pool) => pool.install(work),
            Err(_) => work(),
        }
    } else {
        work()
    }
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
        };
        let cancel = AtomicBool::new(false);
        let r = run(&jobs, &cfg, &cancel, &|_, _, _| {});
        assert!(r.iter().all(|r| r.ok));
        assert!(t.path().join("o3.png").exists());
        let cancel = AtomicBool::new(true);
        let r = run(&jobs, &cfg, &cancel, &|_, _, _| {});
        assert!(r.iter().all(|r| !r.ok));
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
/// on the Phone (2a) Plus). At nice 10 they still use every idle cycle but
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
