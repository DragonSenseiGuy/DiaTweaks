#import "AppIcon.h"
#import "Updates/Updates.h"

static NSUInteger DPSwitches;

static NSString *DPUnlinkable;

static void DPAlert(NSString *message, NSString *detail) {
    NSAlert *alert = [NSAlert new];
    alert.messageText = message;
    alert.informativeText = detail;
    [alert runModal];
}

static NSString *DPLinkProblem(NSString *output) {
    for (NSString *line in [output componentsSeparatedByString:@"\n"]) {
        if (![line hasPrefix:@"warning: kept Dia's icon"]) continue;
        NSRange colon = [line rangeOfString:@": " options:0 range:NSMakeRange(9, line.length - 9)];
        if (colon.length) return [line substringFromIndex:NSMaxRange(colon)];
    }
    return nil;
}

static void DPAlertUnlinkable(void) {
    DPAlert(@"Couldn’t set up icon switching",
            [NSString stringWithFormat:@"DiaTweaks couldn’t prepare this version of Dia: %@. Dia keeps its current icon, "
                                       @"and relaunching won’t change that. Updating or reinstalling DiaTweaks may fix it.", DPUnlinkable]);
}

static void DPLinkCatalog(void) {
    if (DPUnlinkable) return DPAlertUnlinkable();
    DPRunCLI(@[ @"build" ], ^(NSString *output) {
        if (!output) return DPAlert(@"Couldn’t change Dia’s icon", @"Dia keeps its current icon.");
        if ((DPUnlinkable = DPLinkProblem(output))) return DPAlertUnlinkable();
        NSAlert *alert = [NSAlert new];
        alert.messageText = @"Relaunch Dia to change its icon";
        alert.informativeText = @"Until then, Dia keeps its current icon.";
        [alert addButtonWithTitle:@"Relaunch"];
        [alert addButtonWithTitle:@"Later"];
        if ([alert runModal] == NSAlertFirstButtonReturn) DPHandOffAndQuit(@[ @"apply" ]);
    });
}

static BOOL DPCatalogLinked(void) {
    return [NSBundle.mainBundle.infoDictionary[@"CFBundleIconName"] isEqual:@"DiaChosenIcon"];
}

static void DPApplyAppIcon(DPPatch *patch) {
    if (DPTesting) return;
    if (!DPCatalogLinked()) {
        if (patch->on) DPLinkCatalog();
        return;
    }
    CFPreferencesAppSynchronize(CFSTR("com.diapatches"));
    NSUInteger current = ++DPSwitches;
    DPRunCLI(@[ @"set-icon" ], ^(NSString *output) {
        if (current != DPSwitches) return;
        output ? DPDrawOwnTile() : DPAlert(@"Couldn’t change Dia’s icon", @"Dia keeps its current icon.");
    });
}

static BOOL DPWorkspace_setIcon(NSWorkspace *self, SEL _cmd, NSImage *image, NSString *path, NSWorkspaceIconCreationOptions options) {
    if (DPAppIcon.on && [path isEqual:NSBundle.mainBundle.bundlePath]) return YES;
    return DPCallOriginal(DPWorkspace_setIcon, self, image, path, options);
}

static void DPInstallAppIcon(void) {
    DPHook("NSWorkspace", @selector(setIcon:forFile:options:), (IMP)DPWorkspace_setIcon);
    DPInstallDockTile();
    // The Dock shows its cached icon after a relaunch, so draw the chosen one again.
    DPOnLaunch(^{ if ((DPAppIcon.on || DPOwnTileInDock()) && DPCatalogLinked()) DPDrawOwnTile(); });
}

static NSString *DPVerifyAppIcon(DPPatch *patch) {
    NSString *name = NSBundle.mainBundle.infoDictionary[@"CFBundleIconName"];
    return [NSImage imageNamed:name] ? nil : @"Dia’s icon isn’t in its asset catalog";
}

static void DPAddIcon(NSMenu *menu, NSString *title, NSString *name, NSImage *image) {
    NSMenuItem *item = [menu addItemWithTitle:title action:nil keyEquivalent:@""];
    item.representedObject = name;
    item.image = [image copy];
    item.image.size = NSMakeSize(16, 16);
}

static NSMenu *DPAppIconChoices(void) {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Icon"];
    NSString *section = @"Dia";
    [menu addItem:[NSMenuItem sectionHeaderWithTitle:section]];
    DPAddIcon(menu, @"Default", @"AppIcon", [NSImage imageNamed:NSBundle.mainBundle.infoDictionary[@"DiaTweaksOwnIcon"] ?: @"AppIcon"]);
    for (NSDictionary *icon in [NSArray arrayWithContentsOfFile:DPAppSupport(@"DiaPatches/app-icons/icons.plist")]) {
        if (![icon[@"section"] isEqual:section]) [menu addItem:[NSMenuItem sectionHeaderWithTitle:(section = icon[@"section"])]];
        NSString *preview = DPAppSupport([NSString stringWithFormat:@"DiaPatches/app-icons/%@.png", icon[@"name"]]);
        DPAddIcon(menu, icon[@"title"], icon[@"name"], [[NSImage alloc] initWithContentsOfFile:preview]);
    }
    return menu;
}

DP_PATCH(DPAppIcon) {
    .key = @"appIcon",
    .order = 115,
    .title = @"App Icon",
    .detail = @"Choose a different icon for Dia. It follows the icon style you choose in System Settings.",
    .symbol = @"app.badge.fill app.badge",
    .tint = @"systemBrownColor",
    .section = @"Window",
    .choice = @"appIconChoice",
    .defaultChoice = @"AppIcon",
    .choices = DPAppIconChoices,
    .install = DPInstallAppIcon,
    .apply = DPApplyAppIcon,
    .verify = DPVerifyAppIcon,
};
