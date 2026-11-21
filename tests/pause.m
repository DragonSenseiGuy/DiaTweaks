#import <dlfcn.h>
#import "StdPatch/StdPatch.h"
#import "SafeMode/SafeMode.h"
#import "Settings/Settings.h"

void DPApplyHides(DPPatch *patch) {}
NSString *DPVerifyHides(DPPatch *patch) { return nil; }
void DPInstallHides(void) {}
void DPOnLaunch(void (^block)(void)) {}
void DPOnQuit(void (^block)(void)) {}
void DPSetHint(NSView *view, NSString *text) {}
NSString *DPHintOf(NSView *view) { return nil; }
NSView *DPShortcutRow(DPPatch *patch) { return [NSView new]; }
NSString *const DPDia = @"dia", *const DPTweaks = @"tweaks";
NSNotificationName const DPUpdatesDidChangeNotification = @"DPUpdatesDidChange";

static NSArray<NSString *> *lastHandOff, *lastCLI;
void DPHandOffAndQuit(NSArray<NSString *> *args) { lastHandOff = args; }
void DPRunCLI(NSArray<NSString *> *args, void (^completion)(NSString *output)) {
    lastCLI = args;
    if (completion) completion(@"");
}

@implementation DPPreviewView
- (instancetype)initWithKey:(NSString *)key { return [super initWithFrame:NSZeroRect]; }
+ (void)preload {}
@end

@implementation DPSoftwareUpdateView
@end

@implementation DPUpdates
+ (instancetype)shared {
    static DPUpdates *shared;
    if (!shared) shared = [DPUpdates new];
    return shared;
}
- (void)check:(void (^)(void))done {}
- (BOOL)available:(NSString *)part { return NO; }
- (BOOL)staged:(NSString *)part { return NO; }
- (BOOL)downloading:(NSString *)part { return NO; }
- (BOOL)failed:(NSString *)part { return NO; }
- (NSString *)failure:(NSString *)part { return nil; }
- (double)progress:(NSString *)part { return 0; }
- (void)download:(NSString *)part then:(void (^)(void))done {}
- (void)installAndRelaunch:(NSArray<NSString *> *)parts {}
- (void)pretend:(NSString *)part {}
- (void)stopPretending {}
@end

static const char *DPTestDylib;
static int DPTestDladdr(const void *address, Dl_info *info) {
    int found = dladdr(address, info);
    info->dli_fname = DPTestDylib;
    return found;
}
#define dladdr DPTestDladdr

static int applied;
static BOOL lastOn;
static void DPApplyStub(DPPatch *patch) {
    applied++;
    lastOn = patch->on;
}

static NSMenu *DPStubChoices(void) {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Style"];
    [menu addItemWithTitle:@"One" action:nil keyEquivalent:@""].representedObject = @"one";
    return menu;
}

DP_PATCH(DPStub) {
    .key = @"pauseTest",
    .title = @"Pause Test",
    .detail = @"",
    .symbol = @"star.fill",
    .tint = @"systemBlueColor",
    .section = @"Test",
    .choice = @"pauseTestChoice",
    .defaultChoice = @"one",
    .choices = DPStubChoices,
    .apply = DPApplyStub,
};

DP_PATCH(DPRelaunchStub) {
    .key = @"pauseRelaunchTest",
    .title = @"Relaunch Test",
    .detail = @"",
    .symbol = @"star.fill",
    .tint = @"systemBlueColor",
    .section = @"Test",
    .relaunch = YES,
};

#import "SafeMode/SafeMode.m"
#import "StdPatch/Patch.m"
#import "Settings/Controls.m"
#import "Settings/Items.m"
#import "Settings/Overview.m"
#import "Settings/Home.m"
#import "Settings/Page.m"

static int failures;

static void expect(BOOL ok, NSString *what) {
    if (ok) return;
    failures++;
    printf("FAIL %s\n", what.UTF8String);
}

static NSButton *findButton(NSView *root, BOOL (^match)(NSButton *)) {
    return (NSButton *)DPFindView(root, ^BOOL(NSView *v) { return [v isKindOfClass:NSButton.class] && match((NSButton *)v); });
}

static NSTextField *findLabel(NSView *root, NSString *text) {
    return (NSTextField *)DPFindView(root, ^BOOL(NSView *v) { return [v isKindOfClass:NSTextField.class] && [((NSTextField *)v).stringValue isEqual:text]; });
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSString *temporary = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
        NSString *support = [temporary stringByAppendingPathComponent:@"support"];
        [NSFileManager.defaultManager createDirectoryAtPath:support withIntermediateDirectories:YES attributes:nil error:nil];
        DPTestDylib = [[support stringByAppendingPathComponent:@"DiaPatches.dylib"] fileSystemRepresentation];
        NSString *pause = [support stringByAppendingPathComponent:@"paused"];

        // Registered defaults avoid writing to disk.
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches.pause-test"];
        [defaults registerDefaults:@{ @"pauseTest" : @YES, @"pauseRelaunchTest" : @NO }];
        DPDefaults = defaults;
        static DPPatch *patches[] = { &DPStub, &DPRelaunchStub };
        DPPatches = patches;
        DPPatchCount = 2;

        DPBeginLaunch();
        expect(!DPPaused && !DPPausedAtLaunch, @"a launch without the pause file isn't paused");
        for (NSUInteger i = 0; i < DPPatchCount; i++) DPPatches[i]->on = DPEffectiveOn(DPPatches[i]);
        expect(DPSavedOn(&DPStub) && DPStub.on, @"it starts on, as saved");

        [NSData.data writeToFile:pause atomically:YES];
        DPApplySavedSettings();
        expect(DPPaused && !DPStub.on && applied == 1 && !lastOn, @"pausing turns it off");
        expect(DPSavedOn(&DPStub), @"pausing keeps its saved setting");

        DPSetPatch(&DPStub, YES, NO);
        expect(!DPStub.on && applied == 1, @"a tweak can't be turned on while paused");

        [NSFileManager.defaultManager removeItemAtPath:pause error:nil];
        DPApplySavedSettings();
        expect(!DPPaused && DPStub.on && applied == 2 && lastOn, @"resuming turns it back on");

        DPOverviewView *overview = [[DPOverviewView alloc] initWithFrame:NSMakeRect(0, 0, 560, 600)];
        DPHomeView *home = [[DPHomeView alloc] initWithFrame:NSMakeRect(0, 0, 560, 600)];
        DPPageView *page = [[DPPageView alloc] initWithPatch:&DPStub];
        NSTextField *pausedHeader = findLabel(overview, @"Paused");
        NSButton *overviewPause = findButton(overview, ^BOOL(NSButton *b) { return [b.title isEqual:@"Pause Tweaks"]; });
        NSButton *homePause = findButton(home, ^BOOL(NSButton *b) { return [b.title isEqual:@"Pause Tweaks"]; });
        DPPatchSwitch *stubSwitch = (DPPatchSwitch *)DPFindView(overview, ^BOOL(NSView *v) { return [v isKindOfClass:DPPatchSwitch.class] && ((DPPatchSwitch *)v).patch == &DPStub; });
        NSPopUpButton *picker = (NSPopUpButton *)DPFindView(page, ^BOOL(NSView *v) { return [v isKindOfClass:NSPopUpButton.class]; });

        expect(overviewPause && !overviewPause.hiddenOrHasHiddenAncestor, @"Patches shows a Pause Tweaks button while unpaused");
        expect(pausedHeader && pausedHeader.hidden, @"Patches hides the Paused header while unpaused");
        expect(homePause != nil, @"Home shows a Pause Tweaks button");
        expect(stubSwitch.state == NSControlStateValueOn && stubSwitch.enabled, @"switch starts on and enabled");
        expect(picker.enabled, @"page choice picker starts enabled");

        [overview syncWithQuery:@"relaunch"];
        expect(overviewPause.hiddenOrHasHiddenAncestor, @"unrelated search hides the pause row");
        [overview syncWithQuery:@"pause"];
        expect(!overviewPause.hiddenOrHasHiddenAncestor && pausedHeader.hidden, @"searching pause finds the row without the Paused header");
        [overview syncWithQuery:@""];

        lastHandOff = nil;
        [overviewPause performClick:nil];
        [overview syncWithQuery:@""];
        [page sync];
        expect(DPPaused && DPPauseSaved() && !DPStub.on && applied == 3 && !lastOn, @"Settings Pause turns tweaks off and writes paused");
        expect(!lastHandOff, @"Settings Pause does not relaunch when no launch-time tweak is on");
        expect(DPSavedOn(&DPStub) && stubSwitch.state == NSControlStateValueOn && !stubSwitch.enabled, @"switch keeps its saved state and disables");
        expect(!picker.enabled, @"page choice picker disables while paused");
        expect(!pausedHeader.hidden && [overviewPause.title isEqual:@"Resume Tweaks"], @"Patches shows Paused header and Resume Tweaks");
        expect([homePause.title isEqual:@"Resume Tweaks"], @"Home syncs to Resume Tweaks via notification");

        [homePause performClick:nil];
        [overview syncWithQuery:@""];
        [page sync];
        expect(!DPPaused && !DPPauseSaved() && DPStub.on && applied == 4 && lastOn, @"Settings Resume turns tweaks back on live");
        expect(!lastHandOff, @"Settings Resume does not relaunch when Dia started unpaused");
        expect(pausedHeader.hidden && [overviewPause.title isEqual:@"Pause Tweaks"] && [homePause.title isEqual:@"Pause Tweaks"], @"both panes return to Pause Tweaks");
        expect(stubSwitch.enabled && picker.enabled, @"switch and picker re-enable on resume");

        expect(DPRelaunchingOnPause().count == 0, @"no launch-time tweaks listed when none are on");
        DPRelaunchStub.on = YES;
        expect([DPRelaunchingOnPause() isEqual:@[@"Relaunch Test"]], @"active launch-time tweak is named for relaunch");
        DPRelaunchStub.on = NO;

        [NSData.data writeToFile:pause atomically:YES];
        DPBeginLaunch();
        for (NSUInteger i = 0; i < DPPatchCount; i++) DPPatches[i]->on = DPEffectiveOn(DPPatches[i]);
        expect(DPPaused && DPPausedAtLaunch && !DPStub.on && DPSavedOn(&DPStub), @"a launch while paused starts with it off");
        [overview syncWithQuery:@""];
        [home refresh];
        expect([overviewPause.title isEqual:@"Resume and Relaunch"] && [homePause.title isEqual:@"Resume and Relaunch"], @"paused launch labels the button Resume and Relaunch");

        int appliedBefore = applied;
        lastHandOff = nil;
        [overviewPause performClick:nil];
        expect(!DPPaused && !DPPauseSaved(), @"Resume and Relaunch clears the pause file");
        expect([lastHandOff isEqual:@[@"apply"]], @"Resume and Relaunch hands off to diapatch apply");
        expect(applied == appliedBefore, @"paused launch does not run live apply handlers");

        DPSafeMode = 1;
        DPPaused = NO;
        [overview syncWithQuery:@""];
        expect(overviewPause.hiddenOrHasHiddenAncestor, @"Safe Mode hides the unpaused pause row on Patches");
        DPSetPaused(YES);
        [overview syncWithQuery:@""];
        expect(!overviewPause.hiddenOrHasHiddenAncestor && [overviewPause.title isEqual:@"Resume Tweaks"], @"Safe Mode + Paused shows Resume Tweaks");
        lastHandOff = nil;
        [overviewPause performClick:nil];
        expect(!DPPaused && !DPPauseSaved() && !lastHandOff, @"resuming in Safe Mode clears pause without relaunching");
        DPSafeMode = 0;

        DPSetPaused(YES);
        DPLeaveSafeMode();
        expect(DPPauseSaved(), @"leaving safe mode leaves the pause alone");

        [NSFileManager.defaultManager removeItemAtPath:temporary error:nil];
    }
    if (!failures) printf("all pause checks passed\n");
    return failures ? 1 : 0;
}
