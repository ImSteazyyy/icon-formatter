//! Icon pack I/O: folders, ZIP archives, appfilter.xml mapping.
//! Originals are never modified: ZIPs are extracted to a work directory and
//! all results go to a separate output directory.

use crate::error::{CoreError, Result};
use quick_xml::events::Event;
use serde::{Deserialize, Serialize};
use std::collections::{BTreeSet, HashSet};
use std::fs;
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use walkdir::WalkDir;

pub const IMAGE_EXTS: [&str; 4] = ["png", "jpg", "jpeg", "webp"];

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct PackEntry {
    /// Relative path with forward slashes.
    pub rel: String,
    pub abs: PathBuf,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct AppfilterEntry {
    pub component: String,
    pub drawable: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct PackScan {
    pub root: PathBuf,
    pub images: Vec<PackEntry>,
    pub others: Vec<PackEntry>,
    pub appfilter: Option<PathBuf>,
    pub appfilter_entries: Vec<AppfilterEntry>,
    /// Drawables referenced by appfilter.xml but missing in the pack.
    pub missing_drawables: Vec<String>,
    /// Icons in the pack not referenced by appfilter.xml.
    pub unmapped_icons: Vec<String>,
    pub notes: Vec<String>,
}

/// Density rank of an Android resource folder (higher = sharper).
fn density_rank(rel: &str) -> u32 {
    let dir = rel.rsplit('/').nth(1).unwrap_or("");
    for (k, r) in [("xxxhdpi", 7), ("xxhdpi", 6), ("xhdpi", 5), ("hdpi", 4), ("mdpi", 3), ("ldpi", 2), ("nodpi", 8), ("anydpi", 1)] {
        if dir.contains(k) {
            return r;
        }
    }
    0
}

/// Keeps one image per drawable name: the highest density (APK resources).
fn dedupe_densities(images: Vec<PackEntry>) -> Vec<PackEntry> {
    let mut best: std::collections::BTreeMap<String, PackEntry> = Default::default();
    for e in images {
        let rel = e.rel.to_lowercase();
        if !(rel.starts_with("res/drawable") || rel.starts_with("res/mipmap") || rel.starts_with("assets/")) {
            continue;
        }
        let k = drawable_name(&e.rel);
        let keep = match best.get(&k) {
            Some(b) => density_rank(&e.rel) > density_rank(&b.rel),
            None => true,
        };
        if keep {
            best.insert(k, e);
        }
    }
    best.into_values().collect()
}

pub fn is_image(p: &Path) -> bool {
    p.extension()
        .and_then(|e| e.to_str())
        .map(|e| IMAGE_EXTS.contains(&e.to_ascii_lowercase().as_str()))
        .unwrap_or(false)
}

fn rel_string(root: &Path, p: &Path) -> String {
    p.strip_prefix(root)
        .unwrap_or(p)
        .components()
        .map(|c| c.as_os_str().to_string_lossy().to_string())
        .collect::<Vec<_>>()
        .join("/")
}

/// Extracts a ZIP safely (no path traversal) into `dest`.
pub fn extract_zip(zip_path: &Path, dest: &Path) -> Result<()> {
    let f = fs::File::open(zip_path)?;
    let mut ar = zip::ZipArchive::new(f)?;
    fs::create_dir_all(dest)?;
    for i in 0..ar.len() {
        let mut file = ar.by_index(i)?;
        let Some(rel) = file.enclosed_name() else { continue };
        let out = dest.join(rel);
        if file.is_dir() {
            fs::create_dir_all(&out)?;
            continue;
        }
        if let Some(p) = out.parent() {
            fs::create_dir_all(p)?;
        }
        let mut buf = Vec::with_capacity(file.size() as usize);
        file.read_to_end(&mut buf)?;
        fs::write(&out, buf)?;
    }
    Ok(())
}

/// Writes the content of `dir` into a new ZIP file.
pub fn zip_dir(dir: &Path, zip_path: &Path) -> Result<u32> {
    if let Some(p) = zip_path.parent() {
        fs::create_dir_all(p)?;
    }
    let f = fs::File::create(zip_path)?;
    let mut zw = zip::ZipWriter::new(f);
    let opts = zip::write::SimpleFileOptions::default()
        .compression_method(zip::CompressionMethod::Deflated);
    let mut n = 0;
    for e in WalkDir::new(dir).sort_by_file_name() {
        let e = e.map_err(|e| CoreError::Io(std::io::Error::other(e.to_string())))?;
        if !e.file_type().is_file() {
            continue;
        }
        if e.path() == zip_path {
            continue;
        }
        let rel = rel_string(dir, e.path());
        zw.start_file(rel, opts)?;
        let data = fs::read(e.path())?;
        zw.write_all(&data)?;
        n += 1;
    }
    zw.finish()?;
    Ok(n)
}

pub fn parse_appfilter(xml: &str) -> Result<Vec<AppfilterEntry>> {
    let mut r = quick_xml::Reader::from_str(xml);
    let mut out = Vec::new();
    loop {
        match r.read_event() {
            Ok(Event::Empty(e)) | Ok(Event::Start(e)) => {
                if e.name().as_ref() == b"item" {
                    let mut comp = String::new();
                    let mut draw = String::new();
                    for a in e.attributes().flatten() {
                        let v = a.unescape_value().map(|v| v.to_string()).unwrap_or_default();
                        match a.key.as_ref() {
                            b"component" => comp = v,
                            b"drawable" => draw = v,
                            _ => {}
                        }
                    }
                    if !draw.is_empty() {
                        out.push(AppfilterEntry { component: comp, drawable: draw });
                    }
                }
            }
            Ok(Event::Eof) => break,
            Err(e) => return Err(CoreError::Xml(e.to_string())),
            _ => {}
        }
    }
    Ok(out)
}

/// `<calendar component=".." prefix=".."/>` of a text appfilter.xml; the
/// prefix goes in `drawable`.
pub fn parse_calendars(xml: &str) -> Vec<AppfilterEntry> {
    let mut r = quick_xml::Reader::from_str(xml);
    let mut out = Vec::new();
    loop {
        match r.read_event() {
            Ok(Event::Empty(e)) | Ok(Event::Start(e)) if e.name().as_ref() == b"calendar" => {
                let (mut comp, mut prefix) = (String::new(), String::new());
                for a in e.attributes().flatten() {
                    let v = a.unescape_value().map(|v| v.to_string()).unwrap_or_default();
                    match a.key.as_ref() {
                        b"component" => comp = v,
                        b"prefix" => prefix = v,
                        _ => {}
                    }
                }
                if !prefix.is_empty() && !comp.is_empty() {
                    out.push(AppfilterEntry { component: comp, drawable: prefix });
                }
            }
            Ok(Event::Eof) | Err(_) => break,
            _ => {}
        }
    }
    out
}

/// Drawable name of an icon file: file stem.
pub fn drawable_name(rel: &str) -> String {
    let file = rel.rsplit('/').next().unwrap_or(rel);
    match file.rfind('.') {
        Some(i) => file[..i].to_string(),
        None => file.to_string(),
    }
}

/// Output path for a pack image: same relative path, `.png` extension.
pub fn output_rel(rel: &str) -> String {
    match rel.rfind('.') {
        Some(i) if !rel[i..].contains('/') => format!("{}.png", &rel[..i]),
        _ => format!("{rel}.png"),
    }
}

/// Opens a pack from a folder or a ZIP (extracted under `work_dir`).
pub fn open_pack(input: &Path, work_dir: &Path) -> Result<PackScan> {
    let mut notes = Vec::new();
    let root = if input.is_dir() {
        input.to_path_buf()
    } else {
        let ext = input.extension().and_then(|e| e.to_str()).unwrap_or("").to_ascii_lowercase();
        if ext != "zip" && ext != "apk" {
            return Err(CoreError::Invalid(format!("{} is not a folder or ZIP", input.display())));
        }
        let dest = work_dir.join("extracted");
        if dest.exists() {
            fs::remove_dir_all(&dest)?;
        }
        extract_zip(input, &dest)?;
        dest
    };
    let mut images = Vec::new();
    let mut others = Vec::new();
    let mut appfilter = None;
    let mut binary_appfilter: Option<PathBuf> = None;
    for e in WalkDir::new(&root).sort_by_file_name() {
        let e = e.map_err(|e| CoreError::Io(std::io::Error::other(e.to_string())))?;
        if !e.file_type().is_file() {
            continue;
        }
        let name = e.file_name().to_string_lossy().to_string();
        if name.starts_with('.') || name == "Thumbs.db" || name.starts_with("__MACOSX") {
            continue;
        }
        let rel = rel_string(&root, e.path());
        if rel.starts_with("__MACOSX") {
            continue;
        }
        let entry = PackEntry { rel: rel.clone(), abs: e.path().to_path_buf() };
        if is_image(e.path()) {
            images.push(entry);
        } else {
            if name.eq_ignore_ascii_case("appfilter.xml") {
                // prefer a plain-text one (assets/ in APKs, root in source packs)
                let text_ok = fs::read(e.path()).map(|b| b.starts_with(b"<") || b.starts_with(b"\xef\xbb\xbf<")).unwrap_or(false);
                if text_ok && appfilter.is_none() {
                    appfilter = Some(e.path().to_path_buf());
                } else if !text_ok && binary_appfilter.is_none() {
                    binary_appfilter = Some(e.path().to_path_buf());
                }
            }
            others.push(entry);
        }
    }
    let mut entries = Vec::new();
    if appfilter.is_none() {
        if let Some(b) = &binary_appfilter {
            // compiled res/xml/appfilter.xml of an APK
            match crate::axml::appfilter_entries(&fs::read(b)?) {
                Some(v) if !v.is_empty() => {
                    notes.push(format!("appfilter.xml binario letto ({} voci)", v.len()));
                    entries = v;
                }
                _ => notes.push("appfilter.xml binario non leggibile".into()),
            }
        }
    }
    // APKs carry one copy per density: keep the highest one per drawable
    if input.extension().map(|e| e.eq_ignore_ascii_case("apk")).unwrap_or(false) {
        images = dedupe_densities(images);
    }
    if let Some(p) = &appfilter {
        let txt = fs::read_to_string(p)?;
        match parse_appfilter(txt.trim_start_matches('\u{feff}')) {
            Ok(v) => entries = v,
            Err(e) => notes.push(format!("appfilter.xml could not be parsed: {e}")),
        }
    }
    let names: HashSet<String> = images.iter().map(|i| drawable_name(&i.rel)).collect();
    let referenced: BTreeSet<String> = entries.iter().map(|e| e.drawable.clone()).collect();
    let missing: Vec<String> = referenced.iter().filter(|d| !names.contains(*d)).cloned().collect();
    let unmapped: Vec<String> = if entries.is_empty() {
        vec![]
    } else {
        let mut v: Vec<String> = names.iter().filter(|n| !referenced.contains(*n)).cloned().collect();
        v.sort();
        v
    };
    if images.is_empty() {
        notes.push("no PNG/JPG/WEBP icons found".into());
    }
    Ok(PackScan {
        root,
        images,
        others,
        appfilter,
        appfilter_entries: entries,
        missing_drawables: missing,
        unmapped_icons: unmapped,
        notes,
    })
}

/// Copies the non-image files (appfilter.xml, drawable.xml, ...) unchanged
/// into the output, so mapping identifiers are preserved. If a source image
/// changed extension (jpg/webp -> png) and some text file references the old
/// file name explicitly, that reference is updated. Returns notes.
pub fn copy_pack_metadata(scan: &PackScan, out_dir: &Path) -> Result<Vec<String>> {
    let mut notes = Vec::new();
    let renamed: Vec<(String, String)> = scan
        .images
        .iter()
        .filter_map(|i| {
            let o = output_rel(&i.rel);
            if o != i.rel {
                let a = i.rel.rsplit('/').next().unwrap().to_string();
                let b = o.rsplit('/').next().unwrap().to_string();
                Some((a, b))
            } else {
                None
            }
        })
        .collect();
    for o in &scan.others {
        let dst = out_dir.join(&o.rel);
        if let Some(p) = dst.parent() {
            fs::create_dir_all(p)?;
        }
        let is_text = o.rel.ends_with(".xml") || o.rel.ends_with(".json") || o.rel.ends_with(".txt");
        if is_text && !renamed.is_empty() {
            if let Ok(mut txt) = fs::read_to_string(&o.abs) {
                let mut changed = 0;
                for (a, b) in &renamed {
                    let pat_a = format!("\"{a}\"");
                    if txt.contains(&pat_a) {
                        txt = txt.replace(&pat_a, &format!("\"{b}\""));
                        changed += 1;
                    }
                }
                if changed > 0 {
                    notes.push(format!("{}: {changed} file references updated to .png", o.rel));
                }
                fs::write(&dst, txt)?;
                continue;
            }
        }
        fs::copy(&o.abs, &dst)?;
    }
    Ok(notes)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn appfilter_parse() {
        let x = r#"<?xml version="1.0" encoding="utf-8"?>
<resources>
  <iconback img1="iconback" />
  <item component="ComponentInfo{com.whatsapp/com.whatsapp.Main}" drawable="whatsapp" />
  <item component="ComponentInfo{org.telegram.messenger/org.telegram.ui.LaunchActivity}" drawable="telegram"/>
</resources>"#;
        let v = parse_appfilter(x).unwrap();
        assert_eq!(v.len(), 2);
        assert_eq!(v[1].drawable, "telegram");
    }

    #[test]
    fn rel_names() {
        assert_eq!(output_rel("res/drawable/a.webp"), "res/drawable/a.png");
        assert_eq!(drawable_name("res/drawable/whats_app.png"), "whats_app");
    }

    #[test]
    fn zip_roundtrip_and_scan() {
        let t = tempfile::tempdir().unwrap();
        let src = t.path().join("src");
        fs::create_dir_all(src.join("icons")).unwrap();
        let img = image::RgbaImage::from_pixel(8, 8, image::Rgba([1, 2, 3, 255]));
        img.save(src.join("icons/a.png")).unwrap();
        fs::write(
            src.join("appfilter.xml"),
            r#"<resources><item component="ComponentInfo{a/b}" drawable="a"/><item component="ComponentInfo{c/d}" drawable="zz"/></resources>"#,
        )
        .unwrap();
        let z = t.path().join("p.zip");
        assert_eq!(zip_dir(&src, &z).unwrap(), 2);
        let scan = open_pack(&z, &t.path().join("work")).unwrap();
        assert_eq!(scan.images.len(), 1);
        assert_eq!(scan.appfilter_entries.len(), 2);
        assert_eq!(scan.missing_drawables, vec!["zz".to_string()]);
    }
}
