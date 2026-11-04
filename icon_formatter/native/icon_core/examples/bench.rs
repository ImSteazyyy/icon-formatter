//! Batch benchmark: processes the reference icons N times at 512 px.
//! cargo run --release --example bench -- [repeat] [size]
use icon_core::batch::{run, BatchConfig, Job, Source};
use icon_core::compose::{render_background, Background, Placement};
use icon_core::segment::SegmentOptions;
use icon_core::translucent::TranslucentParams;
use std::sync::atomic::AtomicBool;
use std::sync::Arc;
use std::time::Instant;

fn main() {
    let repeat: usize = std::env::args().nth(1).and_then(|s| s.parse().ok()).unwrap_or(8);
    let size: u32 = std::env::args().nth(2).and_then(|s| s.parse().ok()).unwrap_or(512);
    let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../..");
    let srcs: Vec<Arc<Vec<u8>>> = std::fs::read_dir(&dir)
        .unwrap()
        .flatten()
        .filter(|e| e.path().extension().map(|x| x == "png").unwrap_or(false))
        .map(|e| Arc::new(std::fs::read(e.path()).unwrap()))
        .collect();
    let out = std::env::temp_dir().join("icon_core_bench");
    std::fs::create_dir_all(&out).unwrap();
    let mut jobs = Vec::new();
    for r in 0..repeat {
        for (i, s) in srcs.iter().enumerate() {
            jobs.push(Job {
                id: format!("{r}_{i}"),
                name: format!("{r}_{i}"),
                source: Source::Bytes(s.clone()),
                output: out.join(format!("{r}_{i}.png")),
                segment: None,
                placement: None,
                skip_isolation: false,
            });
        }
    }
    let t = Instant::now();
    let bg = render_background(&Background::Translucent(TranslucentParams::default()), size);
    let bg_ms = t.elapsed().as_secs_f64() * 1000.0;
    for threads in [1usize, 0] {
        let cfg = BatchConfig {
            size,
            background: Arc::new(bg.clone()),
            placement: Placement::default(),
            segment: SegmentOptions::default(),
            threads,
        };
        let t = Instant::now();
        let r = run(&jobs, &cfg, &AtomicBool::new(false), &|_, _, _| {});
        let s = t.elapsed().as_secs_f64();
        let ok = r.iter().filter(|r| r.ok).count();
        println!(
            "threads={:<4} icons={} ok={} total={:.2}s per-icon={:.1}ms throughput={:.1} icons/s (bg render {:.1}ms @{}px)",
            if threads == 0 { "all".to_string() } else { threads.to_string() },
            jobs.len(),
            ok,
            s,
            s * 1000.0 / jobs.len() as f64,
            jobs.len() as f64 / s,
            bg_ms,
            size
        );
    }
}
