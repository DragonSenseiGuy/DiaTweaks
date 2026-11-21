use anyhow::Result;

use crate::{
    dia,
    env::Env,
    pause, restore,
    signals::{self, Cancelled},
    status, tweaks,
    ui::{self, Ui},
    update, update_dia,
};

#[derive(Clone, Copy, PartialEq, Eq)]
enum Action {
    Tweaks,
    Pause,
    UpdateDia,
    UpdateDiaTweaks,
    Status,
    Restore,
    Quit,
}

pub fn run(env: &Env, ui: &Ui) -> Result<()> {
    ui.intro();
    ui.enter_menu(true);
    let mut action = Action::Tweaks;
    loop {
        let paused = dia::paused(&env.support);
        let (pause_label, pause_hint) = match paused {
            true => ("Resume tweaks", "turn tweaks back on"),
            false => ("Pause tweaks", "turn every tweak off, keeping settings"),
        };
        action = ui::prompt(
            cliclack::select("What do you want to do?")
                .item(Action::Tweaks, "Tweaks", "turn tweaks on or off")
                .item(Action::Pause, pause_label, pause_hint)
                .item(Action::UpdateDia, "Update Dia", "")
                .item(Action::UpdateDiaTweaks, "Update DiaTweaks", "")
                .item(Action::Status, "Status", "")
                .item(
                    Action::Restore,
                    "Restore original Dia",
                    "remove the patches",
                )
                .item(Action::Quit, "Quit", "")
                .initial_value(action)
                .interact(),
        )?;
        let result = match action {
            Action::Tweaks => tweaks::menu(env, ui),
            Action::Pause => pause::set(env, ui, !paused),
            Action::UpdateDia => update_dia::run(env, ui),
            Action::UpdateDiaTweaks => update::run(env, ui),
            Action::Status => status::show(env, ui),
            Action::Restore => restore::run(env, ui, false),
            Action::Quit => break,
        };
        match result {
            // The menu would go on with a replaced binary or a Dia without DiaTweaks.
            Ok(()) if matches!(action, Action::UpdateDiaTweaks | Action::Restore) => break,
            Ok(()) => {}
            Err(err) => match err.downcast_ref::<Cancelled>() {
                Some(_) if signals::interrupted() => return Err(err),
                Some(cancelled) => ui.remark(cancelled),
                None => ui.error(&err),
            },
        }
    }
    ui.enter_menu(false);
    ui.done("Bye.");
    Ok(())
}
