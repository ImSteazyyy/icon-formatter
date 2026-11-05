//! cargo run --release --example bench_match -- N in1.png in2.png ...
//! N originals and N generated icons (inputs reused round-robin, with
//! distinct names), matched twice; prints the time of each call.
use icon_core::matching::{match_icons, Candidate};
fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let n: usize = args[0].parse().unwrap();
    let files = &args[1..];
    let mk = |pre: &str| -> Vec<Candidate> {
        (0..n)
            .map(|i| Candidate {
                id: format!("{pre}{i}"),
                label: format!("App {i}"),
                package: format!("com.example.app{i}"),
                file: if pre == "g" { format!("com_example_app{i}.png") } else { String::new() },
                path: Some(files[i % files.len()].clone()),
                ..Default::default()
            })
            .collect()
    };
    let (o, g) = (mk("o"), mk("g"));
    for run in 0..2 {
        let t = std::time::Instant::now();
        let r = match_icons(&o, &g);
        let ok = r.iter().enumerate().filter(|(i, m)| m.generated.as_deref() == Some(&format!("g{i}"))).count();
        println!("run {run}: {:.2}s, {ok}/{n} correct", t.elapsed().as_secs_f32());
    }
}
