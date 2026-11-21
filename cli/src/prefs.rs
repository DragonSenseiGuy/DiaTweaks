use std::ffi::{c_char, CString};

use anyhow::{bail, Result};
use core_foundation::{
    base::{CFType, TCFType},
    boolean::CFBoolean,
    number::CFNumber,
    string::CFString,
};
use core_foundation_sys::preferences::{
    CFPreferencesAppSynchronize, CFPreferencesCopyAppValue, CFPreferencesSetAppValue,
};

extern "C" {
    fn notify_post(name: *const c_char) -> u32;
}

pub struct Prefs {
    name: String,
    domain: CFString,
}

impl Prefs {
    pub fn new(domain: &str) -> Self {
        let cf_domain = CFString::new(domain);
        unsafe {
            CFPreferencesAppSynchronize(cf_domain.as_concrete_TypeRef());
        }
        Self {
            name: domain.to_string(),
            domain: cf_domain,
        }
    }

    pub fn get(&self, key: &str) -> Option<bool> {
        let key = CFString::new(key);
        let value = unsafe {
            CFPreferencesCopyAppValue(key.as_concrete_TypeRef(), self.domain.as_concrete_TypeRef())
        };
        if value.is_null() {
            return None;
        }
        let value = unsafe { CFType::wrap_under_create_rule(value) };
        if let Some(flag) = value.downcast::<CFBoolean>() {
            return Some(flag.into());
        }
        if let Some(number) = value.downcast::<CFNumber>() {
            return number.to_f64().map(|number| number != 0.0);
        }
        value
            .downcast::<CFString>()
            .map(|text| is_true_string(&text.to_string()))
    }

    pub fn set(&self, key: &str, on: bool) {
        let key = CFString::new(key);
        let value = CFBoolean::from(on);
        unsafe {
            CFPreferencesSetAppValue(
                key.as_concrete_TypeRef(),
                value.as_CFTypeRef(),
                self.domain.as_concrete_TypeRef(),
            );
        }
    }

    pub fn save(&self) -> Result<()> {
        if unsafe { CFPreferencesAppSynchronize(self.domain.as_concrete_TypeRef()) } == 0 {
            bail!("Couldn't save the settings in {}.", self.name);
        }
        notify(&self.name)
    }
}

pub fn notify(domain: &str) -> Result<()> {
    let notification = CString::new(format!("{domain}.changed"))?;
    let status = unsafe { notify_post(notification.as_ptr()) };
    if status != 0 {
        bail!("Saved, but couldn't tell Dia (notify_post returned {status}). Restart Dia to see the changes.");
    }
    Ok(())
}

// Matches NSString.boolValue.
fn is_true_string(text: &str) -> bool {
    let trimmed = text.trim_start();
    if matches!(trimmed.chars().next(), Some('Y' | 'y' | 'T' | 't')) {
        return true;
    }
    let unsigned = trimmed.strip_prefix(['+', '-']).unwrap_or(trimmed);
    matches!(
        unsigned.trim_start_matches('0').chars().next(),
        Some('1'..='9')
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use core_foundation_sys::preferences::CFPreferencesSetAppValue;

    #[test]
    fn string_bool_matches_foundation() {
        for truthy in ["YES", "yes", "true", "T", "1", " 1", "+1", "-1", "001", "+001", "-001", "2"] {
            assert!(is_true_string(truthy), "expected true for {truthy:?}");
        }
        for falsy in [
            "", "0", "NO", "false", "+YES", "-YES", "0YES", "++1", "+-1", "-true", " 000T", "0.5",
        ] {
            assert!(!is_true_string(falsy), "expected false for {falsy:?}");
        }
    }

    #[test]
    fn prefs_round_trips_booleans_and_numbers() {
        let domain = format!("com.diapatches.test.prefs.{}", std::process::id());
        let prefs = Prefs::new(&domain);
        prefs.set("flagOn", true);
        prefs.set("flagOff", false);
        assert!(prefs.save().is_ok());

        let reloaded = Prefs::new(&domain);
        assert_eq!(reloaded.get("flagOn"), Some(true));
        assert_eq!(reloaded.get("flagOff"), Some(false));
        assert_eq!(reloaded.get("missing"), None);

        for key in ["flagOn", "flagOff"] {
            let k = CFString::new(key);
            unsafe {
                CFPreferencesSetAppValue(
                    k.as_concrete_TypeRef(),
                    std::ptr::null(),
                    reloaded.domain.as_concrete_TypeRef(),
                );
            }
        }
        unsafe {
            CFPreferencesAppSynchronize(reloaded.domain.as_concrete_TypeRef());
        }
    }
}
