use std::{
    fs::{File, OpenOptions},
    io,
    os::fd::AsRawFd,
    path::Path,
};

use anyhow::{bail, Context, Result};

pub struct Lock {
    _file: File,
}

pub fn acquire(support: &Path) -> Result<Lock> {
    let path = support.join(".diatweaks.lock");
    let file = OpenOptions::new()
        .create(true)
        .truncate(false)
        .write(true)
        .open(&path)
        .with_context(|| format!("Couldn't open {}", path.display()))?;
    loop {
        if unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) } == 0 {
            return Ok(Lock { _file: file });
        }
        let err = io::Error::last_os_error();
        if err.kind() == io::ErrorKind::Interrupted {
            continue;
        }
        if err.kind() == io::ErrorKind::WouldBlock {
            bail!("Another diatweaks is running. Wait for it to finish, then try again.");
        }
        return Err(err).with_context(|| format!("Couldn't lock {}", path.display()));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lock_is_exclusive_and_released_on_drop() {
        let dir = tempfile::tempdir().unwrap();
        let first = acquire(dir.path()).unwrap();
        assert!(acquire(dir.path()).is_err());
        drop(first);
        assert!(acquire(dir.path()).is_ok());
    }
}
