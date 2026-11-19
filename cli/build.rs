use std::{path::Path, process::Command};

fn main() {
    let commit = git(&["rev-parse", "HEAD"]).unwrap_or_else(|| "unknown".into());
    println!("cargo:rustc-env=DIATWEAKS_COMMIT={commit}");

    // A release is built from its tag, so the tag names the version. Any other build says "dev" rather than guess.
    let tag = git(&["describe", "--tags", "--exact-match", "--match", "v[0-9]*"]);
    let version = tag.as_deref().unwrap_or("dev").trim_start_matches('v');
    let short = commit.get(..7).unwrap_or(&commit);
    println!("cargo:rustc-env=DIATWEAKS_VERSION={version} ({short})");

    let mut watched = vec![
        "HEAD".to_string(),
        "packed-refs".to_string(),
        "refs/tags".to_string(),
    ];
    watched.extend(git(&["symbolic-ref", "-q", "HEAD"]));
    for name in watched {
        let Some(path) = git(&["rev-parse", "--git-path", &name]) else {
            continue;
        };
        // A missing path would make Cargo rerun this on every build, and install.sh relies on a no-op rebuild.
        if Path::new(&path).exists() {
            println!("cargo:rerun-if-changed={path}");
        }
    }
}

fn git(args: &[&str]) -> Option<String> {
    let output = Command::new("git").args(args).output().ok()?;
    let text = String::from_utf8_lossy(&output.stdout).trim().to_string();
    (output.status.success() && !text.is_empty()).then_some(text)
}
