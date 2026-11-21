#import "Settings.h"

void DPForEachOption(DPPatch *patch, void (^body)(DPPatch *option)) {
    for (NSUInteger i = 0; i < DPPatchCount; i++)
        if (DPRequired(DPPatches[i]) == patch) body(DPPatches[i]);
}

NSString *DPWhyDisabled(DPPatch *patch) {
    if (patch->unavailable) return @"Unavailable on this Dia version.";
    DPPatch *required = DPRequired(patch), *cover = DPPatchNamed(patch->coveredBy);
    if (required && !required->on) return [NSString stringWithFormat:@"Needs %@.", required->title];
    return cover && cover->on ? [NSString stringWithFormat:@"%@ hides this too.", cover->title] : nil;
}

NSString *DPWhyHiddenBy(DPPatch *disabler) {
    if (!disabler || !disabler->on) return nil;
    for (NSUInteger i = 0; i < DPPatchCount; i++)
        if (DPRequired(DPPatches[i]) == disabler && DPPatches[i]->on) return nil;
    return [NSString stringWithFormat:@"Hidden while %@ is on", disabler->title];
}

NSString *DPWhyHidden(DPPatch *patch) { return patch->on ? DPWhyHiddenBy(DPPatchNamed(patch->disabledBy)) : nil; }

NSURL *DPWikiURL(DPPatch *patch) {
    NSString *page = [patch->title stringByReplacingOccurrencesOfString:@" " withString:@"-"];
    return [NSURL URLWithString:[@"https://github.com/JaceThings/DiaTweaks/wiki/" stringByAppendingString:page]];
}

NSArray<NSString *> *DPRelaunchingOnPause(void) {
    if (DPSafeMode || DPPausedAtLaunch) return @[];
    NSMutableArray<NSString *> *waiting = [NSMutableArray new];
    for (NSUInteger i = 0; i < DPPatchCount; i++)
        if (DPPatches[i]->relaunch && DPPatches[i]->on) [waiting addObject:DPPatches[i]->title];
    return waiting;
}

void DPSyncPauseRow(NSTextField *label, NSButton *button) {
    label.stringValue = DPPaused ? @"Tweaks are paused, so none of them are running. Your settings are kept."
                                 : @"Pause every tweak and keep their settings.";
    button.title = !DPPaused ? @"Pause Tweaks"
        : DPPausedAtLaunch && !DPSafeMode ? @"Resume and Relaunch" : @"Resume Tweaks";
}

void DPSetTweaksPaused(BOOL paused, NSWindow *window) {
    if (DPPaused == paused) return;
    NSArray<NSString *> *waiting = paused ? DPRelaunchingOnPause() : @[];
    DPSetPaused(paused);
    if (!paused && DPPausedAtLaunch && !DPSafeMode) {
        DPPatch *icon = DPPatchNamed(@"appIcon");
        BOOL catalog = [NSBundle.mainBundle.infoDictionary[@"CFBundleIconName"] isEqual:@"DiaChosenIcon"];
        if (icon && DPSavedOn(icon) && catalog)
            return DPRunCLI(@[@"set-icon"], ^(NSString *output) { DPHandOffAndQuit(@[@"apply"]); });
        return DPHandOffAndQuit(@[@"apply"]);
    }
    DPApplySavedSettings();
    if (!waiting.count) return;
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"Relaunch Dia to finish pausing?";
    alert.informativeText = [NSString stringWithFormat:@"%@ only %@ after a relaunch. Every other tweak is already off.",
                             [waiting componentsJoinedByString:@", "], waiting.count == 1 ? @"stops" : @"stop"];
    [alert addButtonWithTitle:@"Relaunch"];
    [alert addButtonWithTitle:@"Later"];
    void (^finish)(NSModalResponse) = ^(NSModalResponse response) {
        if (response == NSAlertFirstButtonReturn) DPHandOffAndQuit(@[@"apply"]);
    };
    if (window) [alert beginSheetModalForWindow:window completionHandler:finish];
    else finish([alert runModal]);
}

@implementation DPPatchSwitch

- (instancetype)initWithPatch:(DPPatch *)patch {
    if (!(self = [super initWithFrame:NSZeroRect])) return nil;
    _patch = patch;
    _hiddenIcon = DPSymbol(@"eye.slash", 12, NSColor.secondaryLabelColor);
    self.controlSize = NSControlSizeSmall;
    self.accessibilityLabel = patch->title;
    self.target = self;
    self.action = @selector(flip);
    [self sync];
    return self;
}

- (NSSize)intrinsicContentSize {
    static NSSize size;
    if (!size.width) size = [super intrinsicContentSize];
    return size;
}

- (void)flip {
    DPSetPatch(self.patch, self.state == NSControlStateValueOn, YES);
    [NSNotificationCenter.defaultCenter postNotificationName:DPPatchesDidChangeNotification object:nil];
}

- (NSView *)withHiddenIcon {
    NSStackView *stack = [NSStackView new];
    stack.spacing = 8;
    stack.detachesHiddenViews = NO;  // Before adding the icon, which a stack drops if it's already hidden.
    [stack addArrangedSubview:self.hiddenIcon];
    [stack addArrangedSubview:self];
    return stack;
}

- (void)sync {
    self.state = DPPaused ? DPSavedOn(self.patch) : self.patch->on;
    self.enabled = !DPWhyDisabled(self.patch) && !DPPaused;
    NSString *hint = DPWhyHidden(self.patch);
    DPSetHint(self.hiddenIcon, hint);
    self.hiddenIcon.hidden = !hint;
}
@end
