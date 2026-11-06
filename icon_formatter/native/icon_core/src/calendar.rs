//! Dynamic calendar icons of an icon pack: `<calendar component prefix/>` in
//! appfilter.xml names drawables `prefix1` .. `prefix31`; the launcher shows
//! the one of today's day. Only these icons are taken from the pack.

use crate::error::Result;
use crate::pack::{open_pack, parse_calendars, AppfilterEntry};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct CalendarIcon {
    /// ComponentInfo{pkg/activity} as written in the pack.
    pub component: String,
    pub package: String,
    pub activity: String,
    /// The pack's own prefix (drawable = prefix + day).
    pub prefix: String,
    pub day: u32,
    pub path: PathBuf,
}

/// package / activity of `ComponentInfo{pkg/activity}` (".Act" expanded).
pub fn split_component(c: &str) -> (String, String) {
    let inner = c.split('{').nth(1).and_then(|s| s.split('}').next()).unwrap_or(c);
    let mut it = inner.splitn(2, '/');
    let pkg = it.next().unwrap_or("").trim().to_string();
    let mut act = it.next().unwrap_or("").trim().to_string();
    if act.starts_with('.') {
        act = format!("{pkg}{act}");
    }
    (pkg, act)
}

/// Opens a pack (APK, ZIP or folder) and returns only its calendar icons,
/// one per day per calendar entry, in the highest density available.
pub fn find_calendar_icons(input: &Path, work_dir: &Path) -> Result<Vec<CalendarIcon>> {
    let scan = open_pack(input, work_dir)?;
    let mut entries: Vec<AppfilterEntry> = Vec::new();
    if let Some(p) = &scan.appfilter {
        let txt = fs::read_to_string(p)?;
        entries = parse_calendars(txt.trim_start_matches('\u{feff}'));
    }
    if entries.is_empty() {
        for o in &scan.others {
            if o.rel.to_ascii_lowercase().ends_with("appfilter.xml") {
                if let Some(v) = crate::axml::calendar_entries(&fs::read(&o.abs)?) {
                    if !v.is_empty() {
                        entries = v;
                        break;
                    }
                }
            }
        }
    }
    let by_name: HashMap<String, &PathBuf> = scan.images.iter().map(|i| (crate::pack::drawable_name(&i.rel), &i.abs)).collect();
    let mut out = Vec::new();
    let mut seen = std::collections::HashSet::new();
    for e in entries {
        let (package, activity) = split_component(&e.component);
        if package.is_empty() || !seen.insert((package.clone(), activity.clone())) {
            continue;
        }
        for day in 1..=31u32 {
            if let Some(p) = by_name.get(&format!("{}{}", e.drawable, day)) {
                out.push(CalendarIcon { component: e.component.clone(), package: package.clone(), activity: activity.clone(), prefix: e.drawable.clone(), day, path: (*p).clone() });
            }
        }
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn finds_only_the_calendar_days() {
        let dir = std::env::temp_dir().join(format!("ifcal_{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(dir.join("pack")).unwrap();
        let png = image::RgbaImage::from_pixel(4, 4, image::Rgba([255, 0, 0, 255]));
        for n in ["calendar_g_1", "calendar_g_2", "calendar_g_31", "chrome"] {
            png.save(dir.join("pack").join(format!("{n}.png"))).unwrap();
        }
        fs::write(
            dir.join("pack/appfilter.xml"),
            r#"<resources><item component="ComponentInfo{com.android.chrome/com.google.android.apps.chrome.Main}" drawable="chrome"/>
<calendar component="ComponentInfo{com.google.android.calendar/com.android.calendar.AllInOneActivity}" prefix="calendar_g_"/></resources>"#,
        )
        .unwrap();
        let v = find_calendar_icons(&dir.join("pack"), &dir.join("work")).unwrap();
        assert_eq!(v.iter().map(|c| c.day).collect::<Vec<_>>(), vec![1, 2, 31]);
        assert!(v.iter().all(|c| c.package == "com.google.android.calendar" && c.prefix == "calendar_g_"));
        let _ = fs::remove_dir_all(&dir);
    }
}
