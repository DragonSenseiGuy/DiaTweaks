#import "StdPatch/StdPatch.h"

static NSMutableArray<NSString *> *DPExtensionFolders, *DPLaunchFlags, *DPDroppedFlags;

// Chromium keeps only the last of a flag, so a list flag given more than once becomes one listing every value.
static void DPMergeListFlag(NSMutableArray<NSString *> *args, NSString *flag) {
    NSMutableArray<NSString *> *values = [NSMutableArray array];
    NSUInteger first = NSNotFound;
    for (NSUInteger i = args.count; i-- > 0;)
        if ([args[i] hasPrefix:flag]) {
            [values insertObject:[args[i] substringFromIndex:flag.length] atIndex:0];
            [args removeObjectAtIndex:(first = i)];
        }
    if (values.count) [args insertObject:[flag stringByAppendingString:[values componentsJoinedByString:@","]] atIndex:first];
}

static NSMutableArray<NSString *> *DPListValues(NSString *list) {
    NSMutableArray<NSString *> *values = [NSMutableArray array];
    for (NSString *value in [list componentsSeparatedByString:@","]) {
        NSString *trimmed = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (trimmed.length) [values addObject:trimmed];
    }
    return values;
}

// A relaunch Dia starts itself repeats the flags it ran with, so a flag a tweak is off for has to come out again.
static void DPDropFlags(NSMutableArray<NSString *> *args) {
    for (NSString *dropped in DPDroppedFlags) {
        NSRange eq = [dropped rangeOfString:@"="];
        if (eq.location == NSNotFound) {
            [args removeObject:dropped];
            continue;
        }
        NSString *flag = [dropped substringToIndex:eq.location + 1];
        NSArray<NSString *> *values = DPListValues([dropped substringFromIndex:flag.length]);
        for (NSUInteger i = args.count; i-- > 0;) {
            if (![args[i] hasPrefix:flag]) continue;
            NSMutableArray<NSString *> *kept = DPListValues([args[i] substringFromIndex:flag.length]);
            [kept removeObjectsInArray:values];
            if (kept.count) args[i] = [flag stringByAppendingString:[kept componentsJoinedByString:@","]];
            else [args removeObjectAtIndex:i];
        }
    }
}

// Strip stale DiaPatches extension folders from relaunches and merge all extensions into one --load-extension flag.
static id DPConfiguration_init(id self, SEL _cmd, int argc, NSArray<NSString *> *argv, NSString *profilePath, NSUInteger applicationID,
                               BOOL isProduction, NSUInteger restorationPolicy, BOOL loadAllProfiles, BOOL quitRunLoop, NSString *suiteName) {
    static NSString *const flag = @"--load-extension=";
    NSString *ours = [DPAppSupport(@"DiaPatches") stringByAppendingString:@"/"];
    NSMutableArray<NSString *> *args = [argv mutableCopy], *folders = [NSMutableArray array];
    for (NSString *arg in argv)
        if ([arg hasPrefix:flag]) {
            for (NSString *folder in [[arg substringFromIndex:flag.length] componentsSeparatedByString:@","])
                if (folder.length && ![folder hasPrefix:ours]) [folders addObject:folder];
            [args removeObject:arg];
        }
    [folders addObjectsFromArray:DPExtensionFolders];
    if (folders.count) [args addObject:[flag stringByAppendingString:[folders componentsJoinedByString:@","]]];
    [args addObjectsFromArray:DPLaunchFlags];
    DPDropFlags(args);
    DPMergeListFlag(args, @"--enable-features=");
    DPMergeListFlag(args, @"--disable-features=");
    return DPCallOriginal(DPConfiguration_init, self, argc + ((int)args.count - (int)argv.count), args, profilePath, applicationID, isProduction,
                          restorationPolicy, loadAllProfiles, quitRunLoop, suiteName);
}

static void DPHookConfiguration(void) {
    if (DPExtensionFolders) return;
    DPExtensionFolders = [NSMutableArray array];
    DPLaunchFlags = [NSMutableArray array];
    DPDroppedFlags = [NSMutableArray array];
    DPHook("ArcBrowserApplicationConfiguration", @selector(init:argv:profilePath:applicationID:isProduction:sessionRestorationPolicy:shouldLoadAllProfilesAtStartup:quitRunLoopOnTermination:userDefaultsSuiteName:),
           (IMP)DPConfiguration_init);
}

void DPLoadExtension(NSString *folder) {
    DPHookConfiguration();
    if (![DPExtensionFolders containsObject:folder]) [DPExtensionFolders addObject:folder];
}

void DPAddLaunchFlag(NSString *flag) {
    DPHookConfiguration();
    [DPLaunchFlags addObject:flag];
}

void DPDropLaunchFlag(NSString *flag) {
    DPHookConfiguration();
    if (![DPDroppedFlags containsObject:flag]) [DPDroppedFlags addObject:flag];
}

void DPDropExtension(NSString *folder) {
    DPDropLaunchFlag([@"--load-extension=" stringByAppendingString:folder]);
}
