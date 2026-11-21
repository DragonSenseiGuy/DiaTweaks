use std::{
    path::{Path, PathBuf},
    process::Command,
    thread,
    time::{Duration, Instant},
};

use anyhow::{bail, Context, Result};
use serde::Deserialize;

use crate::{
    child::{self, Finished, OnInterrupt},
    env::Env,
    signals::{self, Cancelled},
    ui::Spinner,
};

pub struct Diapatch(PathBuf);

#[derive(Deserialize)]
pub struct Status {
    pub official: Option<String>,
    pub installed: Option<String>,
    pub patched: bool,
    pub staged: Option<String>,
    pub feed: Option<String>,
    pub channel: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SafeMode {
    Off,
    TweaksOff,
    Disabled,
    Parked,
}

impl Diapatch {
    pub fn find(env: &Env) -> Result<Self> {
        let path = env.diapatch();
        if !path.is_file() {
            bail!(
                "DiaTweaks isn't installed: {} is missing. Run install.sh first.",
                path.display()
            );
        }
        Ok(Self(path))
    }

    pub fn run(
        &self,
        args: &[&str],
        on_interrupt: OnInterrupt,
        spinner: &Spinner,
    ) -> Result<Finished> {
        child::run(Command::new(&self.0).args(args), on_interrupt, spinner)
    }

    pub fn status(&self, spinner: &Spinner) -> Result<Status> {
        let done = self.run(&["status", "--json"], OnInterrupt::StopDownloads, spinner)?;
        if signals::interrupted() {
            bail!(Cancelled::nothing_changed());
        }
        let json = done.output.lines().rev().find(|line| line.starts_with('{'));
        match (done.status.success(), json) {
            (true, Some(json)) => serde_json::from_str(json)
                .context("diapatch status gave an answer diatweaks can't read"),
            _ => bail!("diapatch status failed:\n{}", done.tail(5)),
        }
    }
}

pub fn is_newer(version: &str, than: &str) -> bool {
    let version_parts = build(version)
        .split(|c: char| !c.is_ascii_digit())
        .filter_map(|part| part.parse::<u64>().ok());
    let than_parts = build(than)
        .split(|c: char| !c.is_ascii_digit())
        .filter_map(|part| part.parse::<u64>().ok());
    version_parts.gt(than_parts)
}

fn build(version: &str) -> &str {
    version
        .rsplit_once(" (")
        .and_then(|(_, build)| build.strip_suffix(')'))
        .unwrap_or(version)
}

fn dictionary(path: PathBuf) -> Option<plist::Dictionary> {
    plist::Value::from_file(path).ok()?.into_dictionary()
}

pub fn version_of(app: &Path) -> Option<String> {
    let info = dictionary(app.join("Contents/Info.plist"))?;
    let short = info.get("CFBundleShortVersionString")?.as_string()?;
    let build = info.get("CFBundleVersion")?.as_string()?;
    Some(format!("{short} ({build})"))
}

pub fn is_patched(app: &Path) -> bool {
    dictionary(app.join("Contents/Info.plist"))
        .and_then(|info| info.get("DiaPatches")?.as_boolean())
        .unwrap_or(false)
}

pub fn safe_mode(support: &Path) -> SafeMode {
    let Some(state) = dictionary(support.join("safe-mode.plist")) else {
        return SafeMode::Off;
    };
    let level = state
        .get("level")
        .and_then(plist::Value::as_signed_integer)
        .unwrap_or(0);
    match level {
        0 => SafeMode::Off,
        1 => SafeMode::TweaksOff,
        _ => {
            let parked = state
                .get("steppedDown")
                .and_then(plist::Value::as_boolean)
                .unwrap_or(false);
            if parked {
                SafeMode::Parked
            } else {
                SafeMode::Disabled
            }
        }
    }
}

pub fn is_paused(support: &Path) -> bool {
    support.join("paused").is_file()
}

fn has_running_process(root: &Path) -> bool {
    child::all_pids()
        .into_iter()
        .filter_map(child::pid_path)
        .any(|path| path.starts_with(root))
}

pub fn is_running(app: &Path) -> bool {
    app.canonicalize()
        .is_ok_and(|root| has_running_process(&root))
}

// Terminate by PID like ⌘Q: SIGTERM triggers safe mode and another Dia may be open.
pub fn quit(app: &Path) -> Result<()> {
    let root = app.canonicalize()?;
    let macos = root.join("Contents/MacOS");
    for pid in child::all_pids() {
        let Some(path) = child::pid_path(pid) else {
            continue;
        };
        if path.parent() != Some(macos.as_path()) {
            continue;
        }
        let script = format!(
            "ObjC.import('AppKit'); $.NSRunningApplication.runningApplicationWithProcessIdentifier({pid}).terminate"
        );
        child::quick(Command::new("/usr/bin/osascript").args(["-l", "JavaScript", "-e", &script]));
    }
    let deadline = Instant::now() + Duration::from_secs(60);
    while has_running_process(&root) {
        if Instant::now() > deadline {
            bail!(
                "Dia didn't quit. If it's showing a dialog, answer it, quit Dia, then try again."
            );
        }
        thread::sleep(Duration::from_millis(250));
    }
    Ok(())
}
