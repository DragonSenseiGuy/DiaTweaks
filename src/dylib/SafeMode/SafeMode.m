#import "SafeMode/SafeMode.h"
#import <dlfcn.h>
#import <mach-o/loader.h>

// Long on purpose: patches often crash only on a first resize or new tab.
static const int64_t DPSurviveSeconds = 180;

NSInteger DPSafeMode;
BOOL DPPaused, DPPausedAtLaunch;
static NSURL *DPStateURL, *DPPauseURL;
static NSMutableDictionary *DPState;

BOOL DPPauseSaved(void) { return [NSFileManager.defaultManager fileExistsAtPath:DPPauseURL.path]; }

void DPSetPaused(BOOL paused) {
    DPPaused = paused;
    if (paused) [NSData.data writeToFile:DPPauseURL.path atomically:YES];
    else [NSFileManager.defaultManager removeItemAtURL:DPPauseURL error:nil];
}

static NSString *DPBuildUUID(const struct mach_header_64 *header) {
    const struct load_command *command = (const void *)(header + 1);
    for (uint32_t i = 0; i < header->ncmds; i++, command = (const void *)((const uint8_t *)command + command->cmdsize))
        if (command->cmd == LC_UUID) return [[NSUUID alloc] initWithUUIDBytes:((const struct uuid_command *)command)->uuid].UUIDString;
    return @"";
}

static BOOL DPCrashed(NSDictionary *state) {
    NSDate *launched = state[@"launched"];
    if (!launched) return YES;
    NSFileManager *files = NSFileManager.defaultManager;
    NSString *prefix = [NSProcessInfo.processInfo.processName stringByAppendingString:@"-"];
    NSString *pid = [NSString stringWithFormat:@"\"pid\" : %@,", state[@"pid"]];
    NSURL *reports = [files.homeDirectoryForCurrentUser URLByAppendingPathComponent:@"Library/Logs/DiagnosticReports"];
    for (NSURL *url in [files contentsOfDirectoryAtURL:reports includingPropertiesForKeys:@[NSURLContentModificationDateKey] options:0 error:nil]) {
        if (![url.lastPathComponent hasPrefix:prefix] || ![url.pathExtension isEqual:@"ips"]) continue;
        NSDate *modified;
        [url getResourceValue:&modified forKey:NSURLContentModificationDateKey error:nil];
        if ([modified compare:launched] != NSOrderedDescending) continue;
        if ([[NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil] containsString:pid]) return YES;
    }
    return NO;
}

static void DPSurvived(void) {
    if (![DPState[@"launching"] boolValue]) return;
    // A newer relaunch may already own safe-mode.plist.
    if ([[NSDictionary dictionaryWithContentsOfURL:DPStateURL error:nil][@"pid"] integerValue] != getpid()) return;
    DPState[@"launching"] = @NO;
    // Level 2 skips Settings, so one clean launch steps down to 1 once per build.
    if (DPSafeMode == 2 && ![DPState[@"steppedDown"] boolValue]) {
        DPState[@"level"] = @1;
        DPState[@"steppedDown"] = @YES;
    }
    [DPState writeToURL:DPStateURL error:nil];
}

void DPBeginLaunch(void) {
    Dl_info info;
    dladdr((const void *)DPBeginLaunch, &info);
    DPStateURL = [NSURL fileURLWithPath:[@(info.dli_fname).stringByDeletingLastPathComponent stringByAppendingPathComponent:@"safe-mode.plist"]];
    DPPauseURL = [DPStateURL.URLByDeletingLastPathComponent URLByAppendingPathComponent:@"paused"];
    DPPaused = DPPausedAtLaunch = DPPauseSaved();
    NSString *build = DPBuildUUID(info.dli_fbase);
    NSDictionary *saved = [NSDictionary dictionaryWithContentsOfURL:DPStateURL error:nil];
    DPState = [saved[@"build"] isEqual:build] ? [saved mutableCopy] : [NSMutableDictionary dictionaryWithObject:build forKey:@"build"];
    NSInteger crashes = [DPState[@"crashes"] integerValue];
    // Crashes while paused neither count toward nor reset safe mode.
    if (!DPPaused) {
        if ([DPState[@"launching"] boolValue]) crashes += DPCrashed(DPState);
        else crashes = 0;
    }
    DPSafeMode = [DPState[@"level"] integerValue];
    if (crashes == 2 && DPSafeMode < 2) DPSafeMode++, crashes = 0;
    [DPState addEntriesFromDictionary:@{@"level": @(DPSafeMode), @"crashes": @(crashes), @"launching": @YES, @"launched": NSDate.date, @"pid": @(getpid())}];
    [DPState writeToURL:DPStateURL error:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, DPSurviveSeconds * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ DPSurvived(); });
    DPOnQuit(^{ DPSurvived(); });
}

void DPLeaveSafeMode(void) {
    DPState = [NSMutableDictionary dictionaryWithObject:DPState[@"build"] forKey:@"build"];
    [DPState writeToURL:DPStateURL error:nil];
}
