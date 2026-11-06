//! Android icon pack export (resources layout used by launcher icon packs).
//!
//! Produces:
//!   res/drawable-nodpi/<drawable>.png
//!   res/xml/appfilter.xml, assets/appfilter.xml
//!   res/xml/drawable.xml,  assets/drawable.xml
//!   icons/<Label> (<package>).png      (plain PNGs, human readable)
//!   mapping.json                         (label/package/activity/drawable)
//! The layout matches what icon-pack templates (e.g. Blueprint, CandyBar) and
//! launchers that read appfilter.xml expect. Building the final APK requires
//! an Android build of that template; this module does not sign APKs.

use crate::error::Result;
use crate::pack::zip_dir;
use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct IconPackEntry {
    pub label: String,
    pub package: String,
    /// Fully qualified launcher activity, may be empty.
    pub activity: String,
    pub png: PathBuf,
    /// 1..31: one day of a dynamic calendar icon (`<calendar>`), 0 otherwise.
    #[serde(default)]
    pub calendar_day: u32,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct IconPackReport {
    pub out_dir: String,
    pub zip: Option<String>,
    pub icons: u32,
    pub notes: Vec<String>,
}

/// Valid Android resource name from a package name.
pub fn sanitize_drawable(s: &str) -> String {
    let mut o: String = s
        .to_lowercase()
        .chars()
        .map(|c| if c.is_ascii_lowercase() || c.is_ascii_digit() { c } else { '_' })
        .collect();
    while o.contains("__") {
        o = o.replace("__", "_");
    }
    let o = o.trim_matches('_').to_string();
    if o.is_empty() || !o.chars().next().unwrap().is_ascii_lowercase() {
        format!("ic_{o}")
    } else {
        o
    }
}

fn xml_escape(s: &str) -> String {
    s.replace('&', "&amp;").replace('"', "&quot;").replace('<', "&lt;").replace('>', "&gt;")
}

fn file_safe(s: &str) -> String {
    s.chars()
        .map(|c| if "<>:\"/\\|?*".contains(c) || c.is_control() { '_' } else { c })
        .collect::<String>()
        .trim()
        .to_string()
}

pub fn build(entries: &[IconPackEntry], out_dir: &Path, pack_name: &str, zip_path: Option<&Path>) -> Result<IconPackReport> {
    let mut notes = Vec::new();
    fs::create_dir_all(out_dir.join("res/drawable-nodpi"))?;
    fs::create_dir_all(out_dir.join("res/xml"))?;
    fs::create_dir_all(out_dir.join("assets"))?;
    fs::create_dir_all(out_dir.join("icons"))?;
    let mut used = HashSet::new();
    let mut appfilter = String::from("<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<resources>\n");
    appfilter.push_str(&format!("    <!-- {} -->\n", xml_escape(pack_name)));
    let mut drawable = String::from(
        "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<resources>\n    <version>1</version>\n    <category title=\"All\" />\n",
    );
    let mut mapping = Vec::new();
    let mut count = 0;
    // dynamic calendar icons: drawables prefix1..prefix31 and one
    // <calendar component prefix/> per app; the launcher picks today's day
    let mut calendars: std::collections::BTreeMap<(String, String), String> = Default::default();
    for e in entries.iter().filter(|e| e.calendar_day >= 1 && e.calendar_day <= 31 && !e.package.is_empty()) {
        if !e.png.exists() {
            continue;
        }
        let prefix = calendars
            .entry((e.package.clone(), e.activity.clone()))
            .or_insert_with(|| format!("calendar_{}_", sanitize_drawable(&e.package)))
            .clone();
        let name = format!("{prefix}{}", e.calendar_day);
        if used.insert(name.clone()) {
            fs::copy(&e.png, out_dir.join(format!("res/drawable-nodpi/{name}.png")))?;
            count += 1;
        }
    }
    for ((pkg, act), prefix) in &calendars {
        let comp = if act.is_empty() { xml_escape(pkg) } else { format!("{}/{}", xml_escape(pkg), xml_escape(act)) };
        appfilter.push_str(&format!("    <calendar component=\"ComponentInfo{{{comp}}}\" prefix=\"{prefix}\" />
"));
        mapping.push(serde_json::json!({ "package": pkg, "activity": act, "calendar": prefix }));
    }
    for e in entries.iter().filter(|e| e.calendar_day == 0) {
        if !e.png.exists() {
            notes.push(format!("{}: processed icon missing, skipped", e.package));
            continue;
        }
        // drawable named after the package, or after the app/file name when
        // the package is unknown (folder/ZIP sources without appfilter.xml)
        let key = if e.package.is_empty() { e.label.as_str() } else { e.package.as_str() };
        let mut name = sanitize_drawable(key);
        let base = name.clone();
        let mut k = 2;
        while !used.insert(name.clone()) {
            name = format!("{base}_{k}");
            k += 1;
        }
        fs::copy(&e.png, out_dir.join(format!("res/drawable-nodpi/{name}.png")))?;
        let human = if e.package.is_empty() { format!("icons/{}.png", file_safe(&e.label)) } else { format!("icons/{} ({}).png", file_safe(&e.label), file_safe(&e.package)) };
        fs::copy(&e.png, out_dir.join(human))?;
        if e.package.is_empty() {
            notes.push(format!("{}: package sconosciuto, PNG incluso senza voce in appfilter.xml", e.label));
        } else if e.activity.is_empty() {
            appfilter.push_str(&format!(
                "    <item component=\"ComponentInfo{{{}}}\" drawable=\"{}\" />\n",
                xml_escape(&e.package),
                name
            ));
            notes.push(format!("{}: no launcher activity known, package-only mapping", e.package));
        } else {
            appfilter.push_str(&format!(
                "    <item component=\"ComponentInfo{{{}/{}}}\" drawable=\"{}\" />\n",
                xml_escape(&e.package),
                xml_escape(&e.activity),
                name
            ));
        }
        drawable.push_str(&format!("    <item drawable=\"{name}\" />\n"));
        mapping.push(serde_json::json!({
            "label": e.label, "package": e.package, "activity": e.activity, "drawable": name
        }));
        count += 1;
    }
    appfilter.push_str("</resources>\n");
    drawable.push_str("</resources>\n");
    fs::write(out_dir.join("res/xml/appfilter.xml"), &appfilter)?;
    fs::write(out_dir.join("assets/appfilter.xml"), &appfilter)?;
    fs::write(out_dir.join("res/xml/drawable.xml"), &drawable)?;
    fs::write(out_dir.join("assets/drawable.xml"), &drawable)?;
    fs::write(
        out_dir.join("mapping.json"),
        serde_json::to_string_pretty(&mapping).unwrap_or_default(),
    )?;
    fs::write(
        out_dir.join("README.txt"),
        format!(
            "{pack_name}\n\nGenerated by Icon Formatter.\n\n\
             res/ and assets/ follow the standard Android icon pack layout (appfilter.xml + drawable-nodpi).\n\
             Copy them into an icon pack template project (e.g. Blueprint or CandyBar) and build the APK,\n\
             then apply the pack from a launcher that supports icon packs.\n\
             icons/ contains the same icons as plain PNG files named after the apps.\n\
             Compatibility depends on the launcher; system launchers without icon pack support cannot use it.\n"
        ),
    )?;
    let zip = if let Some(z) = zip_path {
        zip_dir(out_dir, z)?;
        Some(z.to_string_lossy().to_string())
    } else {
        None
    };
    Ok(IconPackReport { out_dir: out_dir.to_string_lossy().to_string(), zip, icons: count, notes })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sanitize() {
        assert_eq!(sanitize_drawable("com.WhatsApp"), "com_whatsapp");
        assert_eq!(sanitize_drawable("9gag.app"), "ic_9gag_app");
    }

    #[test]
    fn build_pack() {
        let t = tempfile::tempdir().unwrap();
        let png = t.path().join("x.png");
        image::RgbaImage::new(4, 4).save(&png).unwrap();
        let entries = vec![
            IconPackEntry { label: "A".into(), package: "com.a".into(), activity: "com.a.Main".into(), png: png.clone(), calendar_day: 0 },
            IconPackEntry { label: "A2".into(), package: "com.a".into(), activity: "com.a.Other".into(), png, calendar_day: 0 },
        ];
        let out = t.path().join("pack");
        let r = build(&entries, &out, "Test", Some(&t.path().join("pack.zip"))).unwrap();
        assert_eq!(r.icons, 2);
        let xml = fs::read_to_string(out.join("res/xml/appfilter.xml")).unwrap();
        assert!(xml.contains("ComponentInfo{com.a/com.a.Main}"));
        assert!(xml.contains("drawable=\"com_a_2\""));
        let parsed = crate::pack::parse_appfilter(&xml).unwrap();
        assert_eq!(parsed.len(), 2);
    }
}
