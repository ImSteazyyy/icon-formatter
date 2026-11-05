//! Visual-only matching check: reference icons vs their Lucent renders
//! (names hidden). cargo run --release --example match_check -- <dir>
use icon_core::{imageops, lucent, matching::*, segment};
fn main() {
    let dir = std::env::args().nth(1).unwrap();
    let mut o = vec![]; let mut g = vec![];
    for e in std::fs::read_dir(&dir).unwrap() {
        let p = e.unwrap().path();
        if p.extension().map(|x| x == "png").unwrap_or(false) {
            let img = imageops::decode_file(&p).unwrap();
            let r = segment::isolate(&img, &Default::default());
            let mono = o.len() % 2 == 0; // half monochrome, half coloured
            let lp = lucent::LucentParams { monochrome: mono, ..Default::default() };
            let out = lucent::render(&img, &r.glyph, r.bbox, 256, &lp).image;
            let id = p.file_name().unwrap().to_string_lossy().to_string();
            o.push(Candidate { id: id.clone(), image: Some(img), ..Default::default() });
            g.push(Candidate { id: format!("gen:{id}"), image: Some(out), ..Default::default() });
        }
    }
    g.reverse();
    let r = match_icons(&o, &g);
    let ok = r.iter().filter(|m| m.generated.as_deref() == Some(&format!("gen:{}", m.original))).count();
    let conf = r.iter().filter(|m| m.status == MatchStatus::Confident).count();
    let wrong_conf = r.iter().filter(|m| m.status == MatchStatus::Confident && m.generated.as_deref() != Some(&format!("gen:{}", m.original))).count();
    println!("correct {ok}/{}  confident {conf}  confident-but-wrong {wrong_conf}", r.len());
    for m in r.iter().filter(|m| m.generated.as_deref() != Some(&format!("gen:{}", m.original))) { println!("  miss {} -> {:?} {:?} {}", m.original, m.generated, m.status, m.reason); }
}
