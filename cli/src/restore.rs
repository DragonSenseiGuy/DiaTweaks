use anyhow::{anyhow, bail, Result};

use crate::{
    child::OnInterrupt,
    dia::{self, Diapatch},
    env::Env,
    lock,
    signals::Cancelled,
    ui::{self, Ui},
};

pub fn run(env: &Env, ui: &Ui, mut purge: bool) -> Result<()> {
    let diapatch = Diapatch::find(env)?;
    if !ui.interactive && !ui.yes {
        bail!("Restoring asks for confirmation. Run it in a terminal, or add --yes.");
    }
    if !ui.yes {
        let restore = ui::prompt(
            cliclack::confirm(
                "Restore the original Dia? It goes back to updating itself, without tweaks.",
            )
            .initial_value(false)
            .interact(),
        )?;
        if !restore {
            return Err(Cancelled::nothing_changed().into());
        }
        if !purge {
            purge = ui::prompt(
                cliclack::confirm(
                    "Also delete DiaTweaks' files? You'd need install.sh to patch Dia again.",
                )
                .initial_value(false)
                .interact(),
            )?;
        }
        let what = if purge {
            "Dia quits, reopens as the original app, and DiaTweaks' files are deleted."
        } else {
            "Dia quits and reopens as the original app."
        };
        let sure = ui::prompt(
            cliclack::confirm(format!("Are you sure? {what}"))
                .initial_value(false)
                .interact(),
        )?;
        if !sure {
            return Err(Cancelled::nothing_changed().into());
        }
    }
    let _lock = lock::acquire(&env.support)?;

    let spinner = ui.spinner("Restoring the original Dia");
    let was_running = dia::is_running(&env.app);
    if was_running {
        spinner.check(dia::quit(&env.app))?;
    }
    let mut args = vec!["uninstall"];
    if was_running {
        args.push("--relaunch");
    }
    if purge {
        args.push("--purge");
    }
    let done = spinner.check(diapatch.run(
        &args,
        OnInterrupt::Finish("Finishing so Dia isn't left half-restored…"),
        &spinner,
    ))?;
    if !done.status.success() {
        return Err(spinner.fail(anyhow!("Couldn't restore Dia:\n{}", done.tail(5))));
    }
    let label = match dia::version_of(&env.app) {
        Some(version) => format!("the original Dia {version}"),
        None => "the original Dia".into(),
    };
    spinner.stop(if was_running {
        format!("Restored {label} and reopened it")
    } else {
        format!("Restored {label}")
    });
    ui.done(if purge {
        "DiaTweaks is removed. Your tweak settings stay in case you install it again."
    } else {
        "Dia is the original app again. Run `diatweaks update` to patch it again."
    });
    Ok(())
}
