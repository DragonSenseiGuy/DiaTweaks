use std::{path::Path, process::Command};

fn main() {
    let commit = git(&["rev-parse", "HEAD"]).unwrap_or_else(|| "unknown".into());
    println!("cargo:rustc-env=DIATWEAKS_COMMIT={commit}");

    let tag = git(&["describe", "--tags", "--exact-match", "--match", "v[0-9]*"]);
    let version = tag.as_deref().unwrap_or("dev").trim_start_matches('v');
    let short = commit.get(..7).unwrap_or(&commit);
    println!("cargo:rustc-env=DIATWEAKS_VERSION={version} ({short})");

    let head_ref = git(&["symbolic-ref", "-q", "HEAD"]);
    for name in ["HEAD", "packed-refs", "refs/tags"]
        .into_iter()
        .chain(head_ref.as_deref())
    {
        let Some(path) = git(&["rev-parse", "--git-path", name]) else {
            continue;
        };
        // Missing paths force Cargo to rerun every build.
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
