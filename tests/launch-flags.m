#import "StdPatch/StdPatch.h"

static NSArray<NSString *> *seen;
static int seenCount;

@interface ArcBrowserApplicationConfiguration : NSObject
- (id)init:(int)argc argv:(NSArray<NSString *> *)argv profilePath:(NSString *)profilePath applicationID:(NSUInteger)applicationID
         isProduction:(BOOL)isProduction sessionRestorationPolicy:(NSUInteger)restorationPolicy shouldLoadAllProfilesAtStartup:(BOOL)loadAllProfiles
         quitRunLoopOnTermination:(BOOL)quitRunLoop userDefaultsSuiteName:(NSString *)suiteName;
@end
@implementation ArcBrowserApplicationConfiguration
- (id)init:(int)argc argv:(NSArray<NSString *> *)argv profilePath:(NSString *)profilePath applicationID:(NSUInteger)applicationID
         isProduction:(BOOL)isProduction sessionRestorationPolicy:(NSUInteger)restorationPolicy shouldLoadAllProfilesAtStartup:(BOOL)loadAllProfiles
         quitRunLoopOnTermination:(BOOL)quitRunLoop userDefaultsSuiteName:(NSString *)suiteName {
    seen = argv;
    seenCount = argc;
    return [super init];
}
@end

NSString *DPAppSupport(NSString *path) { return [@"/Users/test/Library/Application Support" stringByAppendingPathComponent:path]; }

#import "StdPatch/Extensions.m"

static NSString *const kDia = @"/Applications/Dia.app/Contents/MacOS/Dia";

static NSArray<NSString *> *DPLaunch(NSArray<NSString *> *wanted, NSArray<NSString *> *argv) {
    DPHookConfiguration();
    [DPExtensionFolders removeAllObjects];
    [DPLaunchFlags removeAllObjects];
    [DPDroppedFlags removeAllObjects];
    for (NSString *folder in wanted) DPLoadExtension(folder);
    (void)[[ArcBrowserApplicationConfiguration alloc] init:(int)argv.count argv:argv profilePath:@"" applicationID:1 isProduction:YES
                                  sessionRestorationPolicy:0 shouldLoadAllProfilesAtStartup:NO quitRunLoopOnTermination:NO userDefaultsSuiteName:nil];
    NSCAssert(seenCount == (int)seen.count, @"argc follows the argv it was given");
    return seen;
}

static void expectLaunch(NSArray<NSString *> *wanted, NSArray<NSString *> *argv, NSArray<NSString *> *expected, NSString *what) {
    NSArray<NSString *> *got = DPLaunch(wanted, argv);
    NSCAssert([got isEqual:expected], @"%@, got %@", what, got);
}

int main(void) {
    @autoreleasepool {
        NSString *little = DPAppSupport(@"DiaPatches/little-dia-2ee7906f"), *older = DPAppSupport(@"DiaPatches/little-dia-48da710a");
        NSString *passkeys = DPAppSupport(@"DiaPatches/passkeys-extension"), *mine = @"/Users/test/Developer/my-extension";
        NSString *other = @"/Users/test/Developer/another-extension";
        NSString *sibling = DPAppSupport(@"DiaPatches-old/extension"), *prefixed = DPAppSupport(@"DiaPatchesExtra/extension");
        NSString *(^load)(NSString *) = ^(NSString *list) { return [@"--load-extension=" stringByAppendingString:list]; };
        NSString *(^pair)(NSString *, NSString *) = ^(NSString *a, NSString *b) { return [NSString stringWithFormat:@"%@,%@", a, b]; };

        expectLaunch(@[], @[ kDia ], @[ kDia ], @"nothing wanted, nothing added");
        expectLaunch(@[ little ], @[ kDia ], @[ kDia, load(little) ], @"a wanted folder is loaded");
        expectLaunch(@[ little, passkeys ], @[ kDia ], @[ kDia, load(pair(little, passkeys)) ], @"every wanted folder shares one flag");

        expectLaunch(@[ little ], @[ kDia, load(little), @"--restart" ], @[ kDia, @"--restart", load(little) ], @"a relaunch lists its folder once");
        expectLaunch(@[ little ], @[ kDia, load(@"/a"), @"--restart", @"--restart" ], @[ kDia, @"--restart", @"--restart", load(pair(@"/a", little)) ], @"other flags keep their order");

        expectLaunch(@[ little ], @[ kDia, load(pair(little, little)) ], @[ kDia, load(little) ], @"a folder carried twice comes back once");
        expectLaunch(@[ little ], @[ kDia, load(pair(pair(little, little), little)) ], @[ kDia, load(little) ], @"later relaunches don't add another copy");

        expectLaunch(@[ little ], @[ kDia, load(older) ], @[ kDia, load(little) ], @"a folder an update replaced is dropped");
        expectLaunch(@[ little ], @[ kDia, load(pair(older, little)), @"--restart" ], @[ kDia, @"--restart", load(little) ], @"the old folder goes, the current one stays");
        expectLaunch(@[], @[ kDia, load(older), @"--restart" ], @[ kDia, @"--restart" ], @"with the tweak off no folder is carried");
        expectLaunch(@[ passkeys ], @[ kDia, load(pair(pair(passkeys, older), little)) ], @[ kDia, load(passkeys) ], @"only the tweaks that are on keep a folder");
        expectLaunch(@[ little, passkeys ], @[ kDia, load(pair(pair(passkeys, older), little)) ], @[ kDia, load(pair(little, passkeys)) ], @"each wanted folder once, in the order it was added");

        expectLaunch(@[ little ], @[ kDia, load(pair(mine, older)) ], @[ kDia, load(pair(mine, little)) ], @"the user's own folder survives and stays first");
        expectLaunch(@[ little ], @[ kDia, load(mine), load(other), load(older) ], @[ kDia, load(pair(pair(mine, other), little)) ], @"several flags of the user's still merge");
        expectLaunch(@[], @[ kDia, load(pair(pair(sibling, older), prefixed)) ], @[ kDia, load(pair(sibling, prefixed)) ], @"folders beside DiaPatches aren't ours");
        expectLaunch(@[], @[ kDia, load(mine) ], @[ kDia, load(mine) ], @"a user's folder alone is untouched");
        expectLaunch(@[], @[ kDia, load(pair(mine, mine)) ], @[ kDia, load(pair(mine, mine)) ], @"the user's own repeats are theirs to keep");
        expectLaunch(@[ little ], @[ kDia, @"--load-extension=" ], @[ kDia, load(little) ], @"empty --load-extension= does not inject a leading comma");

        // Dropping a boolean flag without '=' must remove only that flag and leave comma-bearing args untouched.
        DPHookConfiguration();
        [DPExtensionFolders removeAllObjects];
        [DPLaunchFlags removeAllObjects];
        [DPDroppedFlags removeAllObjects];
        DPDropLaunchFlag(@"--disable-gpu");
        DPDropLaunchFlag(@"--enable-features=Foo");
        NSArray<NSString *> *argv = @[ kDia, @"--disable-gpu", @"--user-agent=a, b", @"--enable-features=Foo" ];
        (void)[[ArcBrowserApplicationConfiguration alloc] init:(int)argv.count argv:argv profilePath:@"" applicationID:1 isProduction:YES
                                      sessionRestorationPolicy:0 shouldLoadAllProfilesAtStartup:NO quitRunLoopOnTermination:NO userDefaultsSuiteName:nil];
        NSCAssert([seen isEqual:(@[ kDia, @"--user-agent=a, b" ])], @"boolean drop leaves other flags intact and empty feature flag is removed, got %@", seen);

        puts("all launch flag checks passed");
    }
}
