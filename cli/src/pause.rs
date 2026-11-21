use std::{fs, io, path::PathBuf};

use anyhow::{Context, Result};

use crate::{
    dia,
    env::Env,
    lock,
    manifest::Manifest,
    prefs::{self, Prefs},
    tweaks,
    ui::Ui,
};

/// Beside the dylib and its safe-mode state: a file, so no tweak's own setting is touched.
fn path(env: &Env) -> PathBuf {
    env.support.join("paused")
}

pub fn set(env: &Env, ui: &Ui, paused: bool) -> Result<()> {
    let manifest = Manifest::load(&env.manifest())?;
    let state = manifest.state(&Prefs::new(&env.domain));
    let on: Vec<usize> = (0..state.len()).filter(|&index| state[index]).collect();
    if dia::paused(&env.support) == paused {
        ui.done(match paused {
            true => "Tweaks are already paused.",
            false => "Tweaks aren't paused.",
        });
        return Ok(());
    }

    let _lock = lock::acquire(&env.support)?;
    let file = path(env);
    if paused {
        fs::write(&file, b"").with_context(|| format!("Couldn't write {}", file.display()))?;
    } else {
        match fs::remove_file(&file) {
            Ok(()) => {}
            Err(err) if err.kind() == io::ErrorKind::NotFound => {}
            Err(err) => {
                return Err(err).with_context(|| format!("Couldn't delete {}", file.display()))
            }
        }
    }
    prefs::notify(&env.domain)?;

    if !paused {
        ui.success("Tweaks are back on.");
        ui.done(where_resumed(env));
        return Ok(());
    }
    match on.len() {
        0 => ui.success("Paused. No tweaks were on."),
        1 => ui.success("Paused 1 tweak. Its settings are kept."),
        count => ui.success(format_args!(
            "Paused {count} tweaks. Their settings are kept."
        )),
    }
    // Only a Dia that is running has anything left to finish: one that opens later starts with them all off.
    let waiting: Vec<&str> = match dia::is_running(&env.app)
        && dia::is_patched(&env.app)
        && dia::safe_mode(&env.support) == 0
    {
        true => on
            .iter()
            .filter(|&&index| manifest.patches[index].relaunch)
            .map(|&index| manifest.title(index))
            .collect(),
        false => Vec::new(),
    };
    if waiting.is_empty() {
        ui.done(tweaks::where_it_shows(env));
        return Ok(());
    }
    ui.warn(format_args!(
        "Relaunch Dia to finish: {}.",
        waiting.join(", ")
    ));
    ui.done("Dia shows the rest now.");
    Ok(())
}

/// A Dia that started with tweaks paused has nothing hooked up to turn back on, so it always needs a relaunch.
fn where_resumed(env: &Env) -> String {
    if dia::is_running(&env.app) && dia::is_patched(&env.app) && dia::safe_mode(&env.support) == 0 {
        return "Relaunch Dia to finish.".into();
    }
    tweaks::where_it_shows(env)
}
