//! Minimal reader for Android binary XML (AXML), enough to read the
//! compiled `res/xml/appfilter.xml` of an installed/downloaded icon pack APK.

use crate::pack::AppfilterEntry;

fn u16le(b: &[u8], o: usize) -> Option<u16> {
    b.get(o..o + 2).map(|s| u16::from_le_bytes([s[0], s[1]]))
}
fn u32le(b: &[u8], o: usize) -> Option<u32> {
    b.get(o..o + 4).map(|s| u32::from_le_bytes([s[0], s[1], s[2], s[3]]))
}

fn string_pool(b: &[u8], start: usize) -> Option<Vec<String>> {
    let header = u16le(b, start + 2)? as usize;
    let count = u32le(b, start + 8)? as usize;
    let flags = u32le(b, start + 16)?;
    let strings_start = u32le(b, start + 20)? as usize;
    let utf8 = flags & 0x100 != 0;
    let mut out = Vec::with_capacity(count);
    for i in 0..count {
        let off = u32le(b, start + header + i * 4)? as usize;
        let mut p = start + strings_start + off;
        if utf8 {
            // char length then byte length, each 1 or 2 bytes
            let skip = |p: &mut usize| -> Option<usize> {
                let a = *b.get(*p)? as usize;
                if a & 0x80 != 0 {
                    let v = ((a & 0x7f) << 8) | *b.get(*p + 1)? as usize;
                    *p += 2;
                    Some(v)
                } else {
                    *p += 1;
                    Some(a)
                }
            };
            skip(&mut p)?;
            let len = skip(&mut p)?;
            out.push(String::from_utf8_lossy(b.get(p..p + len)?).to_string());
        } else {
            let mut len = u16le(b, p)? as usize;
            p += 2;
            if len & 0x8000 != 0 {
                len = ((len & 0x7fff) << 16) | u16le(b, p)? as usize;
                p += 2;
            }
            let units: Vec<u16> = (0..len).filter_map(|k| u16le(b, p + k * 2)).collect();
            out.push(String::from_utf16_lossy(&units));
        }
    }
    Some(out)
}

/// `<item component=".." drawable=".."/>` entries of a binary appfilter.xml.
pub fn appfilter_entries(b: &[u8]) -> Option<Vec<AppfilterEntry>> {
    if u16le(b, 0)? != 0x0003 {
        return None;
    }
    let mut pos = u16le(b, 2)? as usize;
    let mut strings: Vec<String> = Vec::new();
    let mut out = Vec::new();
    while pos + 8 <= b.len() {
        let ty = u16le(b, pos)?;
        let size = u32le(b, pos + 4)? as usize;
        if size < 8 {
            break;
        }
        match ty {
            0x0001 => strings = string_pool(b, pos)?,
            0x0102 => {
                // start element: header 16 bytes, then ext (ns, name, attrStart, attrSize, attrCount, ...)
                let ext = pos + 16;
                let name = u32le(b, ext + 4)? as usize;
                let attr_start = u16le(b, ext + 8)? as usize;
                let attr_size = u16le(b, ext + 10)? as usize;
                let attr_count = u16le(b, ext + 12)? as usize;
                if strings.get(name).map(|s| s.as_str()) == Some("item") {
                    let (mut comp, mut draw) = (None, None);
                    for k in 0..attr_count {
                        let a = ext + attr_start + k * attr_size;
                        let an = u32le(b, a + 4)? as usize;
                        let raw = u32le(b, a + 8)?;
                        let data_type = *b.get(a + 15)?;
                        let data = u32le(b, a + 16)?;
                        let val = if raw != 0xFFFF_FFFF {
                            strings.get(raw as usize).cloned()
                        } else if data_type == 0x03 {
                            strings.get(data as usize).cloned()
                        } else {
                            None
                        };
                        match strings.get(an).map(|s| s.as_str()) {
                            Some("component") => comp = val,
                            Some("drawable") => draw = val,
                            _ => {}
                        }
                    }
                    if let (Some(c), Some(d)) = (comp, draw) {
                        out.push(AppfilterEntry { component: c, drawable: d });
                    }
                }
            }
            _ => {}
        }
        pos += size;
    }
    Some(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Builds a tiny AXML document with one `<item component drawable/>`.
    fn sample() -> Vec<u8> {
        let strs = ["item", "component", "drawable", "ComponentInfo{com.a/com.a.Main}", "a_icon"];
        // UTF-8 string pool
        let mut data = Vec::new();
        let mut offs = Vec::new();
        for s in strs {
            offs.push(data.len() as u32);
            data.push(s.len() as u8);
            data.push(s.len() as u8);
            data.extend_from_slice(s.as_bytes());
            data.push(0);
        }
        while data.len() % 4 != 0 {
            data.push(0);
        }
        let header = 28usize;
        let strings_start = header + offs.len() * 4;
        let mut pool = Vec::new();
        pool.extend_from_slice(&1u16.to_le_bytes());
        pool.extend_from_slice(&(header as u16).to_le_bytes());
        pool.extend_from_slice(&((strings_start + data.len()) as u32).to_le_bytes());
        pool.extend_from_slice(&(strs.len() as u32).to_le_bytes());
        pool.extend_from_slice(&0u32.to_le_bytes());
        pool.extend_from_slice(&0x100u32.to_le_bytes());
        pool.extend_from_slice(&(strings_start as u32).to_le_bytes());
        pool.extend_from_slice(&0u32.to_le_bytes());
        for o in offs {
            pool.extend_from_slice(&o.to_le_bytes());
        }
        pool.extend_from_slice(&data);
        // start element with 2 attributes
        let mut el = Vec::new();
        el.extend_from_slice(&0x0102u16.to_le_bytes());
        el.extend_from_slice(&16u16.to_le_bytes());
        el.extend_from_slice(&((16 + 20 + 2 * 20) as u32).to_le_bytes());
        el.extend_from_slice(&[0u8; 8]);
        el.extend_from_slice(&0xFFFF_FFFFu32.to_le_bytes()); // ns
        el.extend_from_slice(&0u32.to_le_bytes()); // name "item"
        el.extend_from_slice(&20u16.to_le_bytes());
        el.extend_from_slice(&20u16.to_le_bytes());
        el.extend_from_slice(&2u16.to_le_bytes());
        el.extend_from_slice(&[0u8; 6]);
        for (n, v) in [(1u32, 3u32), (2, 4)] {
            el.extend_from_slice(&0xFFFF_FFFFu32.to_le_bytes());
            el.extend_from_slice(&n.to_le_bytes());
            el.extend_from_slice(&v.to_le_bytes());
            el.extend_from_slice(&8u16.to_le_bytes());
            el.push(0);
            el.push(0x03);
            el.extend_from_slice(&v.to_le_bytes());
        }
        let mut doc = Vec::new();
        doc.extend_from_slice(&3u16.to_le_bytes());
        doc.extend_from_slice(&8u16.to_le_bytes());
        doc.extend_from_slice(&((8 + pool.len() + el.len()) as u32).to_le_bytes());
        doc.extend_from_slice(&pool);
        doc.extend_from_slice(&el);
        doc
    }

    #[test]
    fn reads_binary_appfilter() {
        let e = appfilter_entries(&sample()).unwrap();
        assert_eq!(e.len(), 1);
        assert_eq!(e[0].component, "ComponentInfo{com.a/com.a.Main}");
        assert_eq!(e[0].drawable, "a_icon");
    }
}
