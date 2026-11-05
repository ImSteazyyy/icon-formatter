//! FFI surface used by Flutter. Thin conversion layer over `icon_core`.
//! Heavy work runs on FRB worker threads (non-`sync` functions), batches use
//! rayon internally and report progress through a stream; images move as
//! file paths whenever possible to avoid copies across the FFI boundary.

use crate::frb_generated::StreamSink;
use anyhow::{anyhow, Result};
use icon_core::{
    ai, matching, batch, calibrate, compose, iconpack, imageops, lucent, pack, segment, squircle, translucent,
};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

// ---------------------------------------------------------------- settings

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SegMode {
    Auto,
    KeepAlpha,
    RemoveBackground,
    None,
}

#[derive(Clone, Debug)]
pub struct SegmentSettings {
    pub mode: SegMode,
    pub tolerance: f32,
    pub remove_holes: bool,
    pub refine_edges: bool,
}

#[derive(Clone, Debug)]
pub struct PlacementSettings {
    pub glyph_ratio: f32,
    pub area_ratio: f32,
    pub center_x: f32,
    pub center_y: f32,
    pub area_fit: bool,
    pub scale_mul: f32,
    pub offset_x: f32,
    pub offset_y: f32,
}

#[derive(Clone, Debug)]
pub struct TranslucentSettings {
    pub brightness: f32,
    pub frost: f32,
    pub transparency: f32,
    pub tint: f32,
    pub contrast: f32,
    pub border: f32,
    pub reflection: f32,
    pub depth: f32,
    pub shape_ratio: f32,
    pub exponent: f32,
    pub seed: u32,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum LucentShape {
    /// Silhouette of the source icon.
    Original,
    /// Nothing Launcher / IconGen circle.
    Circle,
    /// Reference squircle (0.93, n 4.25).
    Squircle,
}

/// Lucent (Nothing OS 5.0) plate, ported from Nothing IconGen.
#[derive(Clone, Debug)]
pub struct LucentSettings {
    /// Ink colour (ARGB) for the optional monochrome glyph.
    pub ink: u32,
    /// Frosted backdrop (ARGB, alpha 0x66 on Nothing OS).
    pub backdrop: u32,
    pub shape: LucentShape,
    pub monochrome: bool,
    pub keep_composition: bool,
    pub glyph_scale: f32,
    pub rim: f32,
    pub launcher_shadow: bool,
    pub nothing_encode: bool,
    /// How the symbol is taken from the original (per-app override).
    pub strategy: LucentStrategy,
}

/// Per-app choice in "Rigenera" (Automatica / Colore del piatto / Bordo pieno / Normale).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LucentStrategy {
    Auto,
    PlateColor,
    FullBleed,
    AsIs,
}

#[derive(Clone, Debug)]
pub enum BackgroundSettings {
    Transparent,
    BaseImage { path: String },
    Translucent { params: TranslucentSettings },
    Lucent { params: LucentSettings },
}

impl From<&LucentSettings> for lucent::LucentParams {
    fn from(l: &LucentSettings) -> Self {
        let c = |v: u32| [((v >> 16) & 255) as u8, ((v >> 8) & 255) as u8, (v & 255) as u8];
        let b = c(l.backdrop);
        lucent::LucentParams {
            ink: c(l.ink),
            backdrop: [b[0], b[1], b[2], (l.backdrop >> 24) as u8],
            shape: match l.shape {
                LucentShape::Original => lucent::PlateShape::Original,
                LucentShape::Circle => lucent::PlateShape::Circle,
                LucentShape::Squircle => lucent::PlateShape::Squircle(squircle::Shape::default()),
            },
            monochrome: l.monochrome,
            keep_composition: l.keep_composition,
            glyph_scale: l.glyph_scale,
            offset_x: 0.0,
            offset_y: 0.0,
            rim: l.rim,
            lift_greys: true,
            launcher_shadow: l.launcher_shadow,
            nothing_encode: l.nothing_encode,
            strategy: match l.strategy {
                LucentStrategy::Auto => lucent::GlyphStrategy::Auto,
                LucentStrategy::PlateColor => lucent::GlyphStrategy::PlateColor,
                LucentStrategy::FullBleed => lucent::GlyphStrategy::FullBleed,
                LucentStrategy::AsIs => lucent::GlyphStrategy::AsIs,
            },
        }
    }
}

fn lucent_of(b: &BackgroundSettings) -> Option<lucent::LucentParams> {
    match b {
        BackgroundSettings::Lucent { params } => Some(params.into()),
        _ => None,
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AiModelKind {
    U2netp,
    Silueta,
    IsnetGeneral,
}

/// Local AI background removal (ONNX model on disk).
#[derive(Clone, Debug)]
pub struct AiSettings {
    pub model_path: String,
    pub model: AiModelKind,
    /// Mask remap thresholds (0..1).
    pub low: f32,
    pub high: f32,
}

#[derive(Clone, Debug)]
pub struct ProcessSettings {
    pub size: u32,
    pub background: BackgroundSettings,
    pub placement: PlacementSettings,
    pub segment: SegmentSettings,
    /// When set, the glyph is isolated by the local AI model.
    pub ai: Option<AiSettings>,
}

fn ai_kind(k: AiModelKind) -> ai::ModelKind {
    match k {
        AiModelKind::U2netp => ai::ModelKind::U2netp,
        AiModelKind::Silueta => ai::ModelKind::Silueta,
        AiModelKind::IsnetGeneral => ai::ModelKind::IsnetGeneral,
    }
}

fn ai_of(s: &Option<AiSettings>) -> Result<Option<(Arc<ai::Model>, ai::AiOptions)>> {
    Ok(match s {
        None => None,
        Some(a) => Some((
            ai::model(&a.model_path, ai_kind(a.model)).map_err(|e| anyhow!(e))?,
            ai::AiOptions { low: a.low, high: a.high },
        )),
    })
}

fn isolate_with(img: &image::RgbaImage, s: &ProcessSettings) -> Result<segment::SegmentResult> {
    Ok(match ai_of(&s.ai)? {
        Some((m, o)) => ai::isolate_ai(img, &m, o).map_err(|e| anyhow!(e))?.seg,
        None => segment::isolate(img, &(&s.segment).into()),
    })
}

impl From<&SegmentSettings> for segment::SegmentOptions {
    fn from(s: &SegmentSettings) -> Self {
        segment::SegmentOptions {
            mode: match s.mode {
                SegMode::Auto => segment::SegmentMode::Auto,
                SegMode::KeepAlpha => segment::SegmentMode::KeepAlpha,
                SegMode::RemoveBackground => segment::SegmentMode::RemoveBackground,
                SegMode::None => segment::SegmentMode::None,
            },
            tolerance: s.tolerance,
            remove_holes: s.remove_holes,
            min_component: 0.0004,
            refine_edges: s.refine_edges,
        }
    }
}

impl From<&PlacementSettings> for compose::Placement {
    fn from(p: &PlacementSettings) -> Self {
        compose::Placement {
            glyph_ratio: p.glyph_ratio,
            area_ratio: p.area_ratio,
            center_x: p.center_x,
            center_y: p.center_y,
            fit: if p.area_fit { compose::FitMode::Area } else { compose::FitMode::MaxSide },
            scale_mul: p.scale_mul,
            offset_x: p.offset_x,
            offset_y: p.offset_y,
        }
    }
}

fn placement_dto(p: &compose::Placement) -> PlacementSettings {
    PlacementSettings {
        glyph_ratio: p.glyph_ratio,
        area_ratio: p.area_ratio,
        center_x: p.center_x,
        center_y: p.center_y,
        area_fit: p.fit == compose::FitMode::Area,
        scale_mul: p.scale_mul,
        offset_x: p.offset_x,
        offset_y: p.offset_y,
    }
}

impl From<&TranslucentSettings> for translucent::TranslucentParams {
    fn from(t: &TranslucentSettings) -> Self {
        translucent::TranslucentParams {
            brightness: t.brightness,
            frost: t.frost,
            transparency: t.transparency,
            tint: t.tint,
            contrast: t.contrast,
            border: t.border,
            reflection: t.reflection,
            depth: t.depth,
            shape: squircle::Shape { size_ratio: t.shape_ratio, exponent: t.exponent },
            seed: t.seed,
        }
    }
}

fn background_image(b: &BackgroundSettings, size: u32) -> Result<image::RgbaImage> {
    Ok(match b {
        BackgroundSettings::Transparent => compose::render_background(&compose::Background::Transparent, size),
        BackgroundSettings::BaseImage { path } => {
            let img = imageops::decode_file(Path::new(path))?;
            compose::render_background(&compose::Background::Image(Arc::new(img)), size)
        }
        BackgroundSettings::Translucent { params } => {
            compose::render_background(&compose::Background::Translucent(params.into()), size)
        }
        BackgroundSettings::Lucent { params } => {
            // plate alone, on the reference squircle silhouette
            let sq = squircle::mask(size, &squircle::Shape::default());
            let mut src = image::RgbaImage::new(size, size);
            for (p, &m) in src.pixels_mut().zip(sq.iter()) {
                *p = image::Rgba([128, 128, 128, m]);
            }
            let p: lucent::LucentParams = params.into();
            lucent::render(&src, &image::RgbaImage::new(1, 1), (0, 0, 1, 1), size, &p).image
        }
    })
}

fn check_size(size: u32) -> Result<u32> {
    if !(16..=4096).contains(&size) {
        return Err(anyhow!("output size must be between 16 and 4096 px (got {size})"));
    }
    Ok(size)
}

// ---------------------------------------------------------------- defaults

#[flutter_rust_bridge::frb(sync)]
pub fn default_segment_settings() -> SegmentSettings {
    SegmentSettings { mode: SegMode::Auto, tolerance: 0.10, remove_holes: true, refine_edges: true }
}

#[flutter_rust_bridge::frb(sync)]
pub fn default_placement_settings() -> PlacementSettings {
    placement_dto(&compose::Placement::default())
}

#[flutter_rust_bridge::frb(sync)]
pub fn default_translucent_settings() -> TranslucentSettings {
    let d = translucent::TranslucentParams::default();
    TranslucentSettings {
        brightness: d.brightness,
        frost: d.frost,
        transparency: d.transparency,
        tint: d.tint,
        contrast: d.contrast,
        border: d.border,
        reflection: d.reflection,
        depth: d.depth,
        shape_ratio: d.shape.size_ratio,
        exponent: d.shape.exponent,
        seed: d.seed,
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn default_lucent_settings(dark: bool) -> LucentSettings {
    let d = if dark { lucent::LucentParams::dark() } else { lucent::LucentParams::light() };
    let argb = |a: u8, c: [u8; 3]| ((a as u32) << 24) | ((c[0] as u32) << 16) | ((c[1] as u32) << 8) | c[2] as u32;
    LucentSettings {
        ink: argb(255, d.ink),
        backdrop: argb(d.backdrop[3], [d.backdrop[0], d.backdrop[1], d.backdrop[2]]),
        shape: LucentShape::Squircle,
        monochrome: d.monochrome,
        keep_composition: d.keep_composition,
        glyph_scale: d.glyph_scale,
        rim: d.rim,
        launcher_shadow: d.launcher_shadow,
        nothing_encode: d.nothing_encode,
        strategy: LucentStrategy::Auto,
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn core_version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}

// ---------------------------------------------------------------- preview

pub struct PreviewResult {
    pub png: Vec<u8>,
    pub glyph_png: Vec<u8>,
    pub size: u32,
    pub bbox: Vec<u32>,
    pub source_width: u32,
    pub source_height: u32,
    pub confidence: f32,
    pub ambiguous: bool,
    pub method: String,
    pub notes: Vec<String>,
}

fn preview_image(img: &image::RgbaImage, s: &ProcessSettings) -> Result<PreviewResult> {
    let size = check_size(s.size)?;
    let placement: compose::Placement = (&s.placement).into();
    let (out, res) = if let Some(lp) = lucent_of(&s.background) {
        // same function the batch uses: preview == export
        let res = isolate_with(img, s)?;
        let mut o = lucent::render(img, &res.glyph, res.bbox, size, &lucent::with_placement(&lp, &placement));
        imageops::clean_transparent(&mut o.image);
        let mut res = res;
        res.notes.extend(o.notes);
        (o.image, res)
    } else {
        let mut bg = background_image(&s.background, size)?;
        let res = isolate_with(img, s)?;
        compose::place_on_plate(&mut bg, img, &res, &placement);
        imageops::clean_transparent(&mut bg);
        (bg, res)
    };
    Ok(PreviewResult {
        png: imageops::encode_png(&out)?,
        glyph_png: imageops::encode_png(&res.glyph)?,
        size,
        bbox: vec![res.bbox.0, res.bbox.1, res.bbox.2, res.bbox.3],
        source_width: res.source_size.0,
        source_height: res.source_size.1,
        confidence: res.confidence,
        ambiguous: res.ambiguous,
        method: res.method,
        notes: res.notes,
    })
}

/// Composes one icon from a file and returns PNG bytes (preview / single export).
pub fn preview_file(path: String, settings: ProcessSettings) -> Result<PreviewResult> {
    let img = imageops::decode_file(Path::new(&path))?;
    preview_image(&img, &settings)
}

pub fn preview_bytes(bytes: Vec<u8>, settings: ProcessSettings) -> Result<PreviewResult> {
    let img = imageops::decode(&bytes)?;
    preview_image(&img, &settings)
}

/// Renders only the background (live preview of Nothing Translucent / base).
pub fn render_background_png(background: BackgroundSettings, size: u32) -> Result<Vec<u8>> {
    let size = check_size(size)?;
    Ok(imageops::encode_png(&background_image(&background, size)?)?)
}

/// Renders a glyph PNG (already isolated) on the given background.
pub fn compose_glyph_png(glyph_png: Vec<u8>, settings: ProcessSettings) -> Result<Vec<u8>> {
    let size = check_size(settings.size)?;
    let glyph = imageops::decode(&glyph_png)?;
    if let Some(lp) = lucent_of(&settings.background) {
        let bbox = (0, 0, glyph.width(), glyph.height());
        let pl: compose::Placement = (&settings.placement).into();
        let mut o = lucent::render(&glyph, &glyph, bbox, size, &lucent::with_placement(&lp, &pl)).image;
        imageops::clean_transparent(&mut o);
        return Ok(imageops::encode_png(&o)?);
    }
    let mut bg = background_image(&settings.background, size)?;
    compose::place_glyph(&mut bg, &glyph, &(&settings.placement).into());
    imageops::clean_transparent(&mut bg);
    Ok(imageops::encode_png(&bg)?)
}

/// Writes PNG bytes to a file (creates parent folders). Refuses to overwrite
/// unless `overwrite` is true.
pub fn write_file(path: String, bytes: Vec<u8>, overwrite: bool) -> Result<()> {
    let p = PathBuf::from(&path);
    if p.exists() && !overwrite {
        return Err(anyhow!("{path} already exists"));
    }
    if let Some(parent) = p.parent() {
        std::fs::create_dir_all(parent)?;
    }
    std::fs::write(p, bytes)?;
    Ok(())
}

/// Width/height of an image file (header decode only).
pub fn image_dimensions(path: String) -> Result<Vec<u32>> {
    let (w, h) = image::image_dimensions(&path)?;
    Ok(vec![w, h])
}

/// Resizes an image to a square PNG thumbnail.
pub fn thumbnail_png(path: String, size: u32) -> Result<Vec<u8>> {
    let img = imageops::decode_file(Path::new(&path))?;
    let (w, h) = img.dimensions();
    let s = size as f32 / w.max(h) as f32;
    let t = imageops::resize(&img, ((w as f32 * s).round() as u32).max(1), ((h as f32 * s).round() as u32).max(1));
    Ok(imageops::encode_png(&t)?)
}

/// Copies an image into `dest` as PNG RGBA (used to import base icons).
pub fn import_as_png(src: String, dest: String) -> Result<Vec<u32>> {
    let img = imageops::decode_file(Path::new(&src))?;
    imageops::write_png(&img, Path::new(&dest))?;
    Ok(vec![img.width(), img.height()])
}

// ---------------------------------------------------------------- batch

#[flutter_rust_bridge::frb(opaque)]
pub struct CancelToken {
    flag: Arc<AtomicBool>,
}

impl CancelToken {
    #[flutter_rust_bridge::frb(sync)]
    pub fn new() -> CancelToken {
        CancelToken { flag: Arc::new(AtomicBool::new(false)) }
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn cancel(&self) {
        self.flag.store(true, Ordering::SeqCst);
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn is_cancelled(&self) -> bool {
        self.flag.load(Ordering::SeqCst)
    }

    #[flutter_rust_bridge::frb(ignore)]
    fn handle(&self) -> Arc<AtomicBool> {
        self.flag.clone()
    }
}

pub struct BatchItem {
    pub id: String,
    pub name: String,
    pub path: Option<String>,
    pub bytes: Option<Vec<u8>>,
    pub output: String,
    pub segment: Option<SegmentSettings>,
    pub placement: Option<PlacementSettings>,
    pub skip_isolation: bool,
}

#[derive(Clone, Debug)]
pub struct ItemResult {
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

pub struct BatchProgress {
    pub result: ItemResult,
    pub done: u32,
    pub total: u32,
}

fn item_result(r: &batch::JobResult) -> ItemResult {
    ItemResult {
        id: r.id.clone(),
        name: r.name.clone(),
        ok: r.ok,
        error: r.error.clone(),
        output: r.output.clone(),
        ambiguous: r.ambiguous,
        confidence: r.confidence,
        method: r.method.clone(),
        notes: r.notes.clone(),
    }
}

/// Processes all items in parallel, streaming one progress event per item.
/// Never overwrites the source: an output path equal to the input is rejected.
pub fn run_batch(
    items: Vec<BatchItem>,
    settings: ProcessSettings,
    threads: u32,
    cancel: &CancelToken,
    sink: StreamSink<BatchProgress>,
) -> Result<()> {
    let size = check_size(settings.size)?;
    let bg = Arc::new(background_image(&settings.background, size)?);
    let mut jobs = Vec::with_capacity(items.len());
    for it in items {
        let source = match (it.path, it.bytes) {
            (Some(p), _) => {
                if Path::new(&p) == Path::new(&it.output) {
                    return Err(anyhow!("output would overwrite the original: {p}"));
                }
                batch::Source::Path(PathBuf::from(p))
            }
            (None, Some(b)) => batch::Source::Bytes(Arc::new(b)),
            _ => return Err(anyhow!("item {} has neither path nor bytes", it.name)),
        };
        jobs.push(batch::Job {
            id: it.id,
            name: it.name,
            source,
            output: PathBuf::from(it.output),
            segment: it.segment.as_ref().map(Into::into),
            placement: it.placement.as_ref().map(Into::into),
            skip_isolation: it.skip_isolation,
        });
    }
    let cfg = batch::BatchConfig {
        size,
        background: bg,
        placement: (&settings.placement).into(),
        segment: (&settings.segment).into(),
        threads: threads as usize,
        lucent: lucent_of(&settings.background),
        ai: ai_of(&settings.ai)?,
    };
    let flag = cancel.handle();
    let sink = std::sync::Mutex::new(sink);
    batch::run(&jobs, &cfg, &flag, &|r, done, total| {
        if let Ok(s) = sink.lock() {
            let _ = s.add(BatchProgress { result: item_result(r), done: done as u32, total: total as u32 });
        }
    });
    Ok(())
}

// ---------------------------------------------------------------- calibration

pub struct CalibrationSample {
    pub name: String,
    pub bbox: Vec<f32>,
    pub max_side_ratio: f32,
    pub area_ratio: f32,
    pub center_x: f32,
    pub center_y: f32,
    pub method: String,
    pub outlier: bool,
    pub error: Option<String>,
}

pub struct CalibrationOutput {
    pub placement: PlacementSettings,
    pub max_side_mad: f32,
    pub center_mad: f32,
    /// left, top, right, bottom (fractions of the canvas)
    pub margins: Vec<f32>,
    /// x0, y0, x1, y1 (fractions)
    pub useful_area: Vec<f32>,
    pub median_aspect: f32,
    pub inliers: u32,
    pub samples: Vec<CalibrationSample>,
}

/// Robust calibration from correctly composed examples. `base_path` is the
/// base icon the examples were composed on (optional).
pub fn calibrate_base(base_path: Option<String>, sample_paths: Vec<String>) -> Result<CalibrationOutput> {
    if sample_paths.is_empty() {
        return Err(anyhow!("no calibration samples"));
    }
    let base = match base_path {
        Some(p) => Some(imageops::decode_file(Path::new(&p))?),
        None => None,
    };
    let mut measures = Vec::new();
    for p in &sample_paths {
        let name = Path::new(p).file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default();
        match imageops::decode_file(Path::new(p)) {
            Ok(img) => measures.push(calibrate::measure_sample(&name, base.as_ref(), &img)),
            Err(e) => measures.push(calibrate::SampleMeasure {
                name,
                bbox: [0.0; 4],
                max_side_ratio: 0.0,
                area_ratio: 0.0,
                width_ratio: 0.0,
                height_ratio: 0.0,
                center_x: 0.0,
                center_y: 0.0,
                method: String::new(),
                outlier: true,
                error: Some(e.to_string()),
            }),
        }
    }
    let c = calibrate::aggregate(&mut measures);
    if c.inliers == 0 {
        return Err(anyhow!("no usable calibration sample"));
    }
    Ok(CalibrationOutput {
        placement: placement_dto(&c.placement),
        max_side_mad: c.max_side_mad,
        center_mad: c.center_mad,
        margins: vec![c.margin_left, c.margin_top, c.margin_right, c.margin_bottom],
        useful_area: c.useful_area.to_vec(),
        median_aspect: c.median_aspect,
        inliers: c.inliers,
        samples: c
            .samples
            .iter()
            .map(|s| CalibrationSample {
                name: s.name.clone(),
                bbox: s.bbox.to_vec(),
                max_side_ratio: s.max_side_ratio,
                area_ratio: s.area_ratio,
                center_x: s.center_x,
                center_y: s.center_y,
                method: s.method.clone(),
                outlier: s.outlier,
                error: s.error.clone(),
            })
            .collect(),
    })
}

// ---------------------------------------------------------------- packs / files

pub struct PackImage {
    pub rel: String,
    pub abs: String,
    pub output_rel: String,
}

pub struct AppfilterItem {
    pub component: String,
    pub drawable: String,
}

pub struct PackInfo {
    pub root: String,
    pub images: Vec<PackImage>,
    pub appfilter: Option<String>,
    pub appfilter_items: Vec<AppfilterItem>,
    pub missing_drawables: Vec<String>,
    pub unmapped_icons: Vec<String>,
    pub other_files: u32,
    pub notes: Vec<String>,
}

fn pack_info(s: pack::PackScan) -> PackInfo {
    PackInfo {
        root: s.root.to_string_lossy().to_string(),
        images: s
            .images
            .iter()
            .map(|i| PackImage {
                rel: i.rel.clone(),
                abs: i.abs.to_string_lossy().to_string(),
                output_rel: pack::output_rel(&i.rel),
            })
            .collect(),
        appfilter: s.appfilter.map(|p| p.to_string_lossy().to_string()),
        appfilter_items: s
            .appfilter_entries
            .iter()
            .map(|e| AppfilterItem { component: e.component.clone(), drawable: e.drawable.clone() })
            .collect(),
        missing_drawables: s.missing_drawables,
        unmapped_icons: s.unmapped_icons,
        other_files: s.others.len() as u32,
        notes: s.notes,
    }
}

/// Opens an icon pack from a folder or ZIP. ZIPs are extracted in `work_dir`.
pub fn open_pack(input: String, work_dir: String) -> Result<PackInfo> {
    Ok(pack_info(pack::open_pack(Path::new(&input), Path::new(&work_dir))?))
}

/// Copies appfilter/metadata into `out_dir`, optionally zipping the result.
pub fn finalize_pack(root: String, out_dir: String, zip_path: Option<String>) -> Result<Vec<String>> {
    let scan = pack::open_pack(Path::new(&root), Path::new(&out_dir))?;
    let mut notes = pack::copy_pack_metadata(&scan, Path::new(&out_dir))?;
    if let Some(z) = zip_path {
        let n = pack::zip_dir(Path::new(&out_dir), Path::new(&z))?;
        notes.push(format!("{n} files written to {z}"));
    }
    Ok(notes)
}

pub fn zip_directory(dir: String, zip_path: String) -> Result<u32> {
    Ok(pack::zip_dir(Path::new(&dir), Path::new(&zip_path))?)
}

/// Expands files, folders and ZIPs into a flat list of importable images.
/// ZIPs are extracted under `work_dir/<n>`.
pub fn collect_images(inputs: Vec<String>, work_dir: String) -> Result<Vec<PackImage>> {
    let mut out = Vec::new();
    for (k, input) in inputs.iter().enumerate() {
        let p = Path::new(input);
        if p.is_file() && pack::is_image(p) {
            let name = p.file_name().unwrap().to_string_lossy().to_string();
            out.push(PackImage { output_rel: pack::output_rel(&name), rel: name, abs: input.clone() });
            continue;
        }
        let ext = p.extension().and_then(|e| e.to_str()).unwrap_or("").to_ascii_lowercase();
        if p.is_dir() || ext == "zip" || ext == "apk" {
            let scan = pack::open_pack(p, &Path::new(&work_dir).join(format!("import_{k}")))?;
            for i in scan.images {
                out.push(PackImage {
                    output_rel: pack::output_rel(&i.rel),
                    rel: i.rel,
                    abs: i.abs.to_string_lossy().to_string(),
                });
            }
        }
    }
    Ok(out)
}

// ---------------------------------------------------------------- android icon pack

pub struct IconPackApp {
    pub label: String,
    pub package: String,
    pub activity: String,
    pub png: String,
}

pub struct IconPackResult {
    pub out_dir: String,
    pub zip: Option<String>,
    pub icons: u32,
    pub notes: Vec<String>,
}

pub fn build_icon_pack(apps: Vec<IconPackApp>, out_dir: String, pack_name: String, zip_path: Option<String>) -> Result<IconPackResult> {
    let entries: Vec<iconpack::IconPackEntry> = apps
        .into_iter()
        .map(|a| iconpack::IconPackEntry { label: a.label, package: a.package, activity: a.activity, png: PathBuf::from(a.png) })
        .collect();
    let r = iconpack::build(&entries, Path::new(&out_dir), &pack_name, zip_path.as_deref().map(Path::new))?;
    Ok(IconPackResult { out_dir: r.out_dir, zip: r.zip, icons: r.icons, notes: r.notes })
}

#[flutter_rust_bridge::frb(sync)]
pub fn sanitize_drawable_name(name: String) -> String {
    iconpack::sanitize_drawable(&name)
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

// ---------------------------------------------------------------- local AI

pub struct AiPreview {
    /// Alpha mask (white = kept) at source resolution.
    pub mask_png: Vec<u8>,
    pub glyph_png: Vec<u8>,
    /// False when the source already has a transparent background.
    pub needed: bool,
    pub uncertain: bool,
    pub confidence: f32,
    pub notes: Vec<String>,
    pub millis: u32,
}

/// Runs the local model on one image (model loaded once and cached).
pub fn ai_preview(path: String, settings: AiSettings) -> Result<AiPreview> {
    let img = imageops::decode_file(Path::new(&path))?;
    let t = std::time::Instant::now();
    let m = ai::model(&settings.model_path, ai_kind(settings.model)).map_err(|e| anyhow!(e))?;
    let r = ai::isolate_ai(&img, &m, ai::AiOptions { low: settings.low, high: settings.high }).map_err(|e| anyhow!(e))?;
    Ok(AiPreview {
        mask_png: imageops::encode_png(&r.mask)?,
        glyph_png: imageops::encode_png(&r.seg.glyph)?,
        needed: r.needed,
        uncertain: r.uncertain,
        confidence: r.seg.confidence,
        notes: r.seg.notes,
        millis: t.elapsed().as_millis() as u32,
    })
}

/// Frees the cached model.
pub fn ai_unload_model() {
    ai::unload();
}

// ---------------------------------------------------------------- pack builder matching

pub struct MatchInput {
    pub id: String,
    pub label: String,
    pub package: String,
    pub file: String,
    pub path: Option<String>,
    pub png: Option<Vec<u8>>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum MatchState {
    Confident,
    Doubtful,
    Missing,
}

pub struct MatchOutput {
    pub original: String,
    pub generated: Option<String>,
    pub score: f32,
    pub text: f32,
    pub visual: f32,
    pub state: MatchState,
    pub reason: String,
}

fn candidates(v: Vec<MatchInput>) -> Vec<matching::Candidate> {
    v.into_iter()
        .map(|m| matching::Candidate {
            id: m.id,
            label: m.label,
            package: m.package,
            file: m.file,
            path: m.path,
            image: m.png.and_then(|b| imageops::decode(&b).ok()),
        })
        .collect()
}

/// Associates originals with generated icons (name, package, file, visual).
pub fn match_icons(originals: Vec<MatchInput>, generated: Vec<MatchInput>) -> Result<Vec<MatchOutput>> {
    let r = matching::match_icons(&candidates(originals), &candidates(generated));
    Ok(r.into_iter()
        .map(|m| MatchOutput {
            original: m.original,
            generated: m.generated,
            score: m.score,
            text: m.text,
            visual: m.visual,
            state: match m.status {
                matching::MatchStatus::Confident => MatchState::Confident,
                matching::MatchStatus::Doubtful => MatchState::Doubtful,
                matching::MatchStatus::Missing => MatchState::Missing,
            },
            reason: m.reason,
        })
        .collect())
}

/// Visual similarity 0..1 between two images (manual verification).
pub fn visual_similarity(a: String, b: String) -> Result<f32> {
    let ia = imageops::decode_file(Path::new(&a))?;
    let ib = imageops::decode_file(Path::new(&b))?;
    Ok(matching::similarity(&matching::signature(&ia), &matching::signature(&ib)))
}
