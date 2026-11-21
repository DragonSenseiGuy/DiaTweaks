#import <Foundation/Foundation.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <sys/xattr.h>
#include <unistd.h>

void DPForgetApp(NSString *app) {}
BOOL DPRunsThisDiapatch(audit_token_t token) { return NO; }
pid_t DPParentOf(pid_t pid) { return 0; }

#import "PasswordsLaunch.m"
#define send passkeysSend
#import "Passkeys.m"
#undef send

static NSString *makeTempDir(void) {
    NSString *base = [NSTemporaryDirectory() stringByAppendingPathComponent:@"diatweaks-pk-XXXXXX"];
    char *tmpl = strdup(base.fileSystemRepresentation);
    char *created = mkdtemp(tmpl);
    NSCAssert(created != NULL, @"mkdtemp failed");
    NSString *dir = [NSFileManager.defaultManager stringWithFileSystemRepresentation:created length:strlen(created)];
    free(tmpl);
    return dir;
}

static void writeBundle(NSString *app, NSString *contents) {
    NSString *exe = [app stringByAppendingPathComponent:@"Contents/MacOS/Dia"];
    [NSFileManager.defaultManager createDirectoryAtPath:exe.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    NSCAssert([contents writeToFile:exe atomically:YES encoding:NSUTF8StringEncoding error:nil], @"writeBundle failed");
}

static int countOpenFDs(void) {
    int count = 0;
    for (int fd = 0; fd < 256; fd++)
        if (fcntl(fd, F_GETFD) >= 0) count++;
    return count;
}

static void assertNoTempBundles(NSString *copyFolder) {
    NSArray<NSString *> *items = [NSFileManager.defaultManager contentsOfDirectoryAtPath:copyFolder error:nil];
    for (NSString *name in items)
        NSCAssert(![name hasPrefix:@"Dia.app."], @"leaked temp bundle %@ in %@", name, copyFolder);
}

static const char *gSelfExe;

static void testApplicationsCopy(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *root = makeTempDir();
    NSString *pristine = [root stringByAppendingPathComponent:@"pristine/Dia.app"];
    NSString *copyFolder = [root stringByAppendingPathComponent:@"copy"];
    NSString *clone = [copyFolder stringByAppendingPathComponent:@"Dia.app"];
    NSString *cloneExe = [clone stringByAppendingPathComponent:@"Contents/MacOS/Dia"];

    // 1. Missing pristine returns nil and does not create clone or temp leftovers.
    NSCAssert(applicationsCopyIn(copyFolder, pristine) == nil, @"missing pristine must return nil");
    NSCAssert(![fm fileExistsAtPath:clone], @"clone must not exist when pristine is missing");

    // 2. Initial clone succeeds, strips quarantine xattr, and leaves no temp bundles.
    writeBundle(pristine, @"v1-binary");
    const char *q = "0081;00000000;Test;";
    setxattr(pristine.fileSystemRepresentation, "com.apple.quarantine", q, strlen(q), 0, 0);
    // Pre-existing stale temp dir from PID reuse must not fail clonefile with EEXIST.
    NSString *stale = [clone stringByAppendingFormat:@".%d", getpid()];
    writeBundle(stale, @"stale");

    NSString *got = applicationsCopyIn(copyFolder, pristine);
    NSCAssert([got isEqualToString:clone], @"initial clone should succeed, got %@", got);
    NSCAssert([[NSString stringWithContentsOfFile:cloneExe encoding:NSUTF8StringEncoding error:nil] isEqual:@"v1-binary"], @"clone has v1");
    NSCAssert(getxattr(clone.fileSystemRepresentation, "com.apple.quarantine", NULL, 0, 0, 0) < 0, @"quarantine stripped");
    assertNoTempBundles(copyFolder);

    // 3. Failed refresh (pristine disappeared) does NOT destroy existing clone or leak temp bundles.
    [fm removeItemAtPath:pristine error:nil];
    NSCAssert(applicationsCopyIn(copyFolder, pristine) == nil, @"missing pristine returns nil");
    NSCAssert([[NSString stringWithContentsOfFile:cloneExe encoding:NSUTF8StringEncoding error:nil] isEqual:@"v1-binary"], @"existing clone preserved");
    assertNoTempBundles(copyFolder);

    // 4. Atomic swap on pristine update replaces clone cleanly with no temp leftovers.
    writeBundle(pristine, @"v2-updated-binary");
    got = applicationsCopyIn(copyFolder, pristine);
    NSCAssert([got isEqualToString:clone], @"updated clone should succeed");
    NSCAssert([[NSString stringWithContentsOfFile:cloneExe encoding:NSUTF8StringEncoding error:nil] isEqual:@"v2-updated-binary"], @"clone has v2");
    assertNoTempBundles(copyFolder);

    // 5. Concurrent multi-process clones serialize via flock with zero race failures or temp leaks.
    writeBundle(pristine, @"v3-concurrent-test-binary");
    pid_t children[6];
    const char *argv[] = { gSelfExe, "--child-copy", copyFolder.fileSystemRepresentation, pristine.fileSystemRepresentation, NULL };
    for (int i = 0; i < 6; i++) {
        NSCAssert(posix_spawn(&children[i], gSelfExe, NULL, NULL, (char *const *)argv, environ) == 0, @"posix_spawn failed");
    }
    for (int i = 0; i < 6; i++) {
        int status = 0;
        NSCAssert(waitpid(children[i], &status, 0) == children[i] && WIFEXITED(status) && WEXITSTATUS(status) == 0,
                  @"concurrent child %d failed (status %d)", i, status);
    }
    NSCAssert([[NSString stringWithContentsOfFile:cloneExe encoding:NSUTF8StringEncoding error:nil] isEqual:@"v3-concurrent-test-binary"], @"clone has v3");
    assertNoTempBundles(copyFolder);

    // 6. Unwritable copyFolder fails cleanly without leaving temp bundles or crashing.
    NSString *roFolder = [root stringByAppendingPathComponent:@"readonly"];
    [fm createDirectoryAtPath:roFolder withIntermediateDirectories:YES attributes:nil error:nil];
    chmod(roFolder.fileSystemRepresentation, 0555);
    NSCAssert(applicationsCopyIn(roFolder, pristine) == nil, @"readonly copyFolder must return nil");
    chmod(roFolder.fileSystemRepresentation, 0755);
    assertNoTempBundles(roFolder);

    [fm removeItemAtPath:root error:nil];
}

static NSDictionary *decodeFramed(uint32_t header, const void *body, size_t bodyLen) {
    NSMutableData *buf = [NSMutableData dataWithCapacity:4 + bodyLen];
    [buf appendBytes:&header length:4];
    if (bodyLen) [buf appendBytes:body length:bodyLen];
    FILE *f = fmemopen((void *)buf.bytes, buf.length, "r");
    NSCAssert(f != NULL, @"fmemopen failed");
    NSDictionary *msg = readMessageFrom(f);
    fclose(f);
    return msg;
}

static void testPasskeyMessageValidation(void) {
    // 1. Zero length, huge 32-bit length (4 GiB), and > 1 MiB cap all rejected without large allocation.
    NSCAssert(decodeFramed(0, "", 0) == nil, @"zero-length header rejected");
    NSCAssert(decodeFramed(0xffffffffU, "{}", 2) == nil, @"4 GiB header rejected");
    NSCAssert(decodeFramed(kMaxMessageLength + 1, "{}", 2) == nil, @"over-1-MiB header rejected");

    // 2. Truncated, malformed, and non-dictionary JSON all rejected.
    NSCAssert(decodeFramed(100, "{}", 2) == nil, @"truncated body rejected");
    NSCAssert(decodeFramed(3, "{no", 3) == nil, @"invalid JSON rejected");
    NSCAssert(decodeFramed(5, "[1,2]", 5) == nil, @"array JSON rejected");
    NSCAssert(decodeFramed(4, "null", 4) == nil, @"null JSON rejected");
    NSCAssert(decodeFramed(4, "\"hi\"", 4) == nil, @"string JSON rejected");

    // 3. Valid framed dictionary (including exact 1 MiB boundary).
    const char *ok = "{\"kind\":\"get\",\"origin\":\"https://example.com\",\"options\":{}}";
    NSDictionary *parsed = decodeFramed((uint32_t)strlen(ok), ok, strlen(ok));
    NSCAssert(validRequest(parsed), @"valid framed request accepted");

    NSMutableData *maxMsg = [NSMutableData dataWithLength:kMaxMessageLength];
    memset(maxMsg.mutableBytes, ' ', kMaxMessageLength);
    memcpy(maxMsg.mutableBytes, "{\"a\":1}", 7);
    NSDictionary *maxParsed = decodeFramed(kMaxMessageLength, maxMsg.bytes, maxMsg.length);
    NSCAssert([maxParsed[@"a"] isEqual:@1], @"exact 1 MiB message accepted");

    // 4. validRequest rejects missing/wrong-type fields; runInHelper guards nil fields without throwing.
    NSCAssert(!validRequest(nil), @"nil request rejected");
    NSCAssert(!validRequest(@{}), @"empty dict rejected");
    NSCAssert(!validRequest(@{ @"kind" : @"get", @"origin" : @"https://example.com" }), @"missing options rejected");
    NSCAssert(!validRequest(@{ @"kind" : @"get", @"options" : @{} }), @"missing origin rejected");
    NSCAssert(!validRequest(@{ @"origin" : @"https://example.com", @"options" : @{} }), @"missing kind rejected");
    NSCAssert(!validRequest(@{ @"kind" : @"bogus", @"origin" : @"https://example.com", @"options" : @{} }), @"unknown kind rejected");
    NSCAssert(!validRequest(@{ @"kind" : @"create", @"origin" : @"", @"options" : @{} }), @"empty origin rejected");
    NSCAssert(!validRequest(@{ @"kind" : @"create", @"origin" : @"https://example.com", @"options" : @[] }), @"non-dict options rejected");
    NSCAssert(validRequest(@{ @"kind" : @"create", @"origin" : @"https://example.com", @"options" : @{ @"challenge" : @"abc" } }), @"valid create accepted");
    NSCAssert(validRequest(@{ @"kind" : @"get", @"origin" : @"https://api-4b6bfd4c.duosecurity.com", @"path" : @"/frame/v4/auth/prompt", @"options" : @{} }), @"valid get with path accepted");

    NSDictionary *bad = runInHelper(0, nil, nil, nil, nil);
    NSCAssert([bad[@"error"][@"name"] isEqual:@"NotAllowedError"], @"runInHelper guards nil without crashing");
}

static NSDictionary *runHostChild(NSString *home, NSData *stdinBytes, BOOL closeStdinEarly, int *exitCode, BOOL *leakedFDs) {
    int inPipe[2], outPipe[2];
    NSCAssert(pipe(inPipe) == 0 && pipe(outPipe) == 0, @"pipe failed");
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, inPipe[0], STDIN_FILENO);
    posix_spawn_file_actions_adddup2(&actions, outPipe[1], STDOUT_FILENO);
    posix_spawn_file_actions_addclose(&actions, inPipe[0]);
    posix_spawn_file_actions_addclose(&actions, inPipe[1]);
    posix_spawn_file_actions_addclose(&actions, outPipe[0]);
    posix_spawn_file_actions_addclose(&actions, outPipe[1]);
    const char *argv[] = { gSelfExe, "--child-host", home.fileSystemRepresentation, NULL };
    pid_t pid = 0;
    NSCAssert(posix_spawn(&pid, gSelfExe, &actions, NULL, (char *const *)argv, environ) == 0, @"posix_spawn host failed");
    posix_spawn_file_actions_destroy(&actions);
    close(inPipe[0]);
    close(outPipe[1]);
    if (stdinBytes.length) (void)write(inPipe[1], stdinBytes.bytes, stdinBytes.length);
    if (closeStdinEarly) close(inPipe[1]), inPipe[1] = -1;

    NSMutableData *out = [NSMutableData data];
    char buf[4096];
    for (ssize_t n; (n = read(outPipe[0], buf, sizeof buf)) > 0;) [out appendBytes:buf length:(NSUInteger)n];
    close(outPipe[0]);
    if (inPipe[1] >= 0) close(inPipe[1]);

    int status = 0;
    NSCAssert(waitpid(pid, &status, 0) == pid && WIFEXITED(status), @"child exited abnormally (status=%d)", status);
    int code = WEXITSTATUS(status);
    if (leakedFDs) *leakedFDs = (code == 99);
    if (exitCode) *exitCode = code;
    if (out.length < 4) return nil;
    uint32_t len = 0;
    memcpy(&len, out.bytes, 4);
    if (4 + len > out.length) return nil;
    return [NSJSONSerialization JSONObjectWithData:[out subdataWithRange:NSMakeRange(4, len)] options:0 error:nil];
}

static NSData *frameJSON(NSDictionary *dict) {
    NSData *body = [NSJSONSerialization dataWithJSONObject:dict options:0 error:nil];
    uint32_t len = (uint32_t)body.length;
    NSMutableData *out = [NSMutableData dataWithCapacity:4 + len];
    [out appendBytes:&len length:4];
    [out appendData:body];
    return out;
}

static void testPasskeyHostErrorPathsAndFDCleanup(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *root = makeTempDir();
    NSData *validReq = frameJSON(@{ @"kind" : @"get", @"origin" : @"https://example.com", @"options" : @{} });

    // 1. Oversized header exits cleanly with code 1 and zero leaked fds.
    uint32_t huge = 0xffffffffU;
    int code = 0;
    BOOL leaked = YES;
    NSDictionary *reply = runHostChild(root, [NSData dataWithBytes:&huge length:4], YES, &code, &leaked);
    NSCAssert(code == 1 && !leaked && reply == nil, @"oversized header must fail cleanly (code=%d leaked=%d)", code, leaked);

    // 2. Request missing options field exits cleanly with code 1 and zero leaked fds.
    reply = runHostChild(root, frameJSON(@{ @"kind" : @"get", @"origin" : @"https://example.com" }), YES, &code, &leaked);
    NSCAssert(code == 1 && !leaked && reply == nil, @"missing options must fail cleanly (code=%d leaked=%d)", code, leaked);

    // 3. Lock open() failure (home is a regular file) returns error JSON with zero leaked fds.
    NSString *fileHome = [root stringByAppendingPathComponent:@"not-a-dir"];
    [@"x" writeToFile:fileHome atomically:YES encoding:NSUTF8StringEncoding error:nil];
    reply = runHostChild(fileHome, validReq, NO, &code, &leaked);
    NSCAssert(code == 1 && !leaked && [reply[@"error"][@"name"] isEqual:@"NotAllowedError"],
              @"open() failure must return error JSON without fd leak (code=%d leaked=%d reply=%@)", code, leaked, reply);

    // 4. launchHelper() failure after pipe() succeeds (pristine Dia missing) cleans up all 4 pipe fds + lock.
    NSString *emptyHome = [root stringByAppendingPathComponent:@"empty-home"];
    [fm createDirectoryAtPath:emptyHome withIntermediateDirectories:YES attributes:nil error:nil];
    reply = runHostChild(emptyHome, validReq, NO, &code, &leaked);
    NSCAssert(code == 1 && !leaked && [reply[@"error"][@"name"] isEqual:@"NotAllowedError"],
              @"launchHelper failure must close all pipes and lock (code=%d leaked=%d reply=%@)", code, leaked, reply);

    // 5. Lock held by another fd + EOF cancellation closes lock cleanly with zero leaked fds.
    int held = openPasskeyLock(emptyHome);
    NSCAssert(held >= 0 && flock(held, LOCK_EX | LOCK_NB) == 0, @"parent lock failed");
    reply = runHostChild(emptyHome, validReq, YES, &code, &leaked);
    close(held);
    NSCAssert(code == 0 && !leaked && [reply[@"error"][@"name"] isEqual:@"NotAllowedError"],
              @"cancelled while waiting on lock must exit cleanly without fd leak (code=%d leaked=%d reply=%@)", code, leaked, reply);

    [fm removeItemAtPath:root error:nil];
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        gSelfExe = argv[0];
        if (argc == 4 && !strcmp(argv[1], "--child-copy")) {
            NSString *copyFolder = @(argv[2]), *pristine = @(argv[3]);
            NSString *clone = [copyFolder stringByAppendingPathComponent:@"Dia.app"];
            return [applicationsCopyIn(copyFolder, pristine) isEqualToString:clone] ? 0 : 1;
        }
        if (argc == 3 && !strcmp(argv[1], "--child-host")) {
            int before = countOpenFDs();
            int rc = DPRunPasskeyHost(@(argv[2]));
            int after = countOpenFDs();
            return after != before ? 99 : rc;
        }
        testApplicationsCopy();
        testPasskeyMessageValidation();
        testPasskeyHostErrorPathsAndFDCleanup();
        puts("all diapatch passkeys hardening checks passed");
    }
    return 0;
}
