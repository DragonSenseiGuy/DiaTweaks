#import "StdPatch/Hook.m"
#import <pthread.h>
#import <stdatomic.h>

@interface DPTarget : NSObject
- (int)work;
@end
@implementation DPTarget
- (int)work { return 1; }
@end

@interface DPBaseChain : NSObject
- (int)value;
- (int)recurse:(int)n;
@end
@implementation DPBaseChain
- (int)value { return 10; }
- (int)recurse:(int)n { return n <= 0 ? 0 : 1 + [self recurse:n - 1]; }
@end

@interface DPMidChain : DPBaseChain
@end
@implementation DPMidChain
- (int)value { return [super value] + 100; }
@end

@interface DPLeafChain : DPMidChain
@end
@implementation DPLeafChain
- (int)value { return [super value] + 1000; }
@end

@interface DPInheritedBase : NSObject
- (int)ping;
@end
@implementation DPInheritedBase
- (int)ping { return 5; }
@end

@interface DPInheritedSub : DPInheritedBase
@end
@implementation DPInheritedSub
@end

@interface DPOverrideSub : DPInheritedBase
@end
@implementation DPOverrideSub
- (int)ping { return 50; }
@end

static int DPTarget_work(id self, SEL _cmd) { return DPCallOriginal(DPTarget_work, self) + 1; }
static int DPSub_work(id self, SEL _cmd) { return DPCallOriginal(DPSub_work, self) + 1; }
static int DPShared_value(id self, SEL _cmd) { return DPCallOriginal(DPShared_value, self) + 1; }
static int DPRecurse_hook(id self, SEL _cmd, int n) { return DPCallOriginal(DPRecurse_hook, self, n); }
static int DPPing_sub(id self, SEL _cmd) { return DPCallOriginal(DPPing_sub, self) * 2; }
static int DPPing_base(id self, SEL _cmd) { return DPCallOriginal(DPPing_base, self) + 3; }

static atomic_bool stop;
static atomic_long calls, wrong;
static DPTarget *target;

static void *reader(void *unused) {
    while (!atomic_load(&stop)) {
        if ([target work] != 2) atomic_fetch_add(&wrong, 1);
        atomic_fetch_add(&calls, 1);
    }
    return NULL;
}

static Class subclass(int index) {
    Class cls = objc_allocateClassPair(NSObject.class, [NSString stringWithFormat:@"DPHookTableSub%d", index].UTF8String, 0);
    class_addMethod(cls, @selector(work), imp_implementationWithBlock(^int(id self) { return 1; }), "i@:");
    objc_registerClassPair(cls);
    return cls;
}

static atomic_int nextWriterClass;
static void *writer(void *unused) {
    for (int i = 0; i < 40; i++) {
        int idNum = atomic_fetch_add(&nextWriterClass, 1);
        Class cls = subclass(10000 + idNum);
        DPHookClass(cls, @selector(work), (IMP)DPSub_work);
        id inst = [cls new];
        if ([inst work] != 2) atomic_fetch_add(&wrong, 1);
    }
    return NULL;
}

int main(void) {
    int failures = 0;
    @autoreleasepool {
        // Reverse-order subclass-then-superclass hooking with the same replacement must not recurse infinitely on [super].
        DPHookClass(DPLeafChain.class, @selector(value), (IMP)DPShared_value);
        DPHookClass(DPMidChain.class, @selector(value), (IMP)DPShared_value);
        DPHookClass(DPBaseChain.class, @selector(value), (IMP)DPShared_value);
        DPLeafChain *leaf = [DPLeafChain new];
        if ([leaf value] != 1113) { failures++; printf("FAIL reverse-order [super] chain returned %d, expected 1113\n", [leaf value]); }
        if ([[DPMidChain new] value] != 112) { failures++; printf("FAIL mid [super] chain returned wrong value\n"); }
        if ([[DPBaseChain new] value] != 11) { failures++; printf("FAIL base returned wrong value\n"); }

        // Recursive [self sel] on a hooked class without superclass hooks still works.
        DPHookClass(DPBaseChain.class, @selector(recurse:), (IMP)DPRecurse_hook);
        if ([[DPBaseChain new] recurse:5] != 5) { failures++; printf("FAIL recursive [self] hook failed\n"); }

        // Subclass (not overriding ping) hooked before superclass must still chain through superclass hook, and DPDiaIMP must unwind both.
        IMP realBasePing = class_getMethodImplementation(DPInheritedBase.class, @selector(ping));
        IMP realOverridePing = class_getMethodImplementation(DPOverrideSub.class, @selector(ping));
        DPHookClass(DPInheritedSub.class, @selector(ping), (IMP)DPPing_sub);
        DPHookClass(DPInheritedBase.class, @selector(ping), (IMP)DPPing_base);
        if ([[DPInheritedSub new] ping] != 16) { failures++; printf("FAIL subclass-before-superclass re-chain got %d, expected 16\n", [[DPInheritedSub new] ping]); }
        if (DPDiaIMP(DPInheritedSub.class, @selector(ping)) != realBasePing) { failures++; printf("FAIL DPDiaIMP(DPInheritedSub) did not unwind to base original IMP\n"); }
        if (DPDiaIMP(DPOverrideSub.class, @selector(ping)) != realOverridePing) { failures++; printf("FAIL DPDiaIMP(DPOverrideSub) did not return subclass's own IMP\n"); }

        target = [DPTarget new];
        DPHookClass(DPTarget.class, @selector(work), (IMP)DPTarget_work);
        pthread_t readers[4], writers[3];
        for (int i = 0; i < 4; i++) pthread_create(&readers[i], NULL, reader, NULL);
        for (int i = 0; i < 3; i++) pthread_create(&writers[i], NULL, writer, NULL);
        for (int i = 0; i < 3; i++) pthread_join(writers[i], NULL);
        while (!atomic_load(&calls)) usleep(100);

        id first = nil, last = nil;
        int hooked = 0;
        for (; hooked < 4000; hooked++) {
            last = [subclass(hooked) new];
            DPHookClass(object_getClass(last), @selector(work), (IMP)DPSub_work);
            if ([last work] != 2) break;
            first = first ?: last;
            if (DPOriginalIMP(last, @selector(work), (IMP)DPSub_work) == (IMP)DPSub_work) { failures++; printf("FAIL the original of a new hook is its replacement\n"); }
        }
        atomic_store(&stop, YES);
        for (int i = 0; i < 4; i++) pthread_join(readers[i], NULL);

        if (atomic_load(&wrong)) { failures++; printf("FAIL %ld of %ld calls on other threads missed their hook\n", atomic_load(&wrong), atomic_load(&calls)); }
        if (hooked < 500 || hooked >= 4000) { failures++; printf("FAIL the table took %d hooks, expected it to fill up in between\n", hooked); }
        if ([last work] != 1) { failures++; printf("FAIL a hook past the end of the table took effect\n"); }
        if ([target work] != 2 || [first work] != 2) { failures++; printf("FAIL the full table broke earlier hooks\n"); }
        printf("%d hooks, %ld calls from 4 threads while they were added\n", hooked + 1, atomic_load(&calls));
    }
    if (!failures) printf("all hook table checks passed\n");
    return failures ? 1 : 0;
}
