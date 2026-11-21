#import "LittleDia.h"

static id DPScriptWindow(void) {
    id app = NSApp.delegate;
    if (![app respondsToSelector:@selector(appleScriptWindows)]) return nil;
    for (id window in [app valueForKey:@"appleScriptWindows"])
        if ([window respondsToSelector:@selector(appleScriptProfiles)] && [[window valueForKey:@"appleScriptProfiles"] count]) return window;
    return nil;
}

NSArray<NSString *> *DPLittleDiaProfiles(void) {
    return [[DPScriptWindow() valueForKey:@"appleScriptProfiles"] valueForKey:@"name"] ?: @[];
}

// Single-profile setups and blank names (including Braille blank U+2800) keep "Open in Dia".
NSString *DPOpenInLabel(NSString *profile, NSUInteger profiles) {
    static NSCharacterSet *blank;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableCharacterSet *set = NSCharacterSet.whitespaceAndNewlineCharacterSet.mutableCopy;
        [set addCharactersInString:@"\u2800\u200B\u200C\u200D\u2060\uFEFF"];
        blank = set.copy;
    });
    if (profiles <= 1) return @"Open in Dia";
    NSString *name = [profile stringByTrimmingCharactersInSet:blank];
    return name.length ? [@"Open in " stringByAppendingString:name] : @"Open in Dia";
}

static NSMenu *DPFilled(NSMenu *menu) {
    if ([menu.delegate respondsToSelector:@selector(menuNeedsUpdate:)]) [menu.delegate menuNeedsUpdate:menu];
    return menu;
}

NSImage *DPLittleDiaProfileImage(NSString *name) {
    NSMenu *tabs = DPFilled([NSApp.mainMenu itemWithTitle:@"Tabs"].submenu);
    return [DPFilled([tabs itemWithTitle:@"Move to Profile"].submenu) itemWithTitle:name].image;
}

// Run off the main thread: Dia answers its Apple events there, so waiting there times out.
void DPOpenInProfile(NSString *url, NSUInteger index, void (^done)(BOOL opened)) {
    id window = DPScriptWindow();
    if (!window || !url.length) return done(NO);
    NSString *quoted = [[url stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"] stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    NSString *source = [NSString stringWithFormat:@"tell application id \"%@\" to tell window id \"%@\" to focus (make new tab at end of tabs of profile %lu with properties {URL:\"%@\"})",
                                                  NSBundle.mainBundle.bundleIdentifier, [window valueForKey:@"windowId"], (unsigned long)index + 1, quoted];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSDictionary *error;
        [[[NSAppleScript alloc] initWithSource:source] executeAndReturnError:&error];
        if (error) NSLog(@"DiaPatches: couldn't open in profile %lu: %@", (unsigned long)index + 1, error);
        dispatch_async(dispatch_get_main_queue(), ^{ done(!error); });
    });
}
