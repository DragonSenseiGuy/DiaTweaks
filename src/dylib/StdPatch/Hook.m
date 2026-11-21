#import "StdPatch/StdPatch.h"
#import <stdatomic.h>

typedef struct { Class cls; SEL sel; IMP replacement, original; } DPHookRecord;
// Hooks are added on the main thread after launch while any thread may be inside DPOriginalIMP: the table never moves, and a record counts only once it is whole.
static DPHookRecord DPHooks[1024];
static _Atomic size_t DPHookCount;

void DPHookClass(Class cls, SEL sel, IMP replacement) {
    Method method = cls ? class_getInstanceMethod(cls, sel) : NULL;
    if (!method) return;
    IMP original = method_getImplementation(method);
    if (original == replacement) return;
    size_t count = atomic_load_explicit(&DPHookCount, memory_order_relaxed);
    // Already hooked here or in a superclass: a second copy would find itself as the original and recurse.
    for (size_t i = 0; i < count; i++) {
        if (DPHooks[i].sel != sel || DPHooks[i].replacement != replacement) continue;
        for (Class c = cls; c; c = class_getSuperclass(c)) if (c == DPHooks[i].cls) return;
    }
    if (count == sizeof DPHooks / sizeof *DPHooks) return NSLog(@"DiaPatches: hook table is full; not hooking -[%s %@]", class_getName(cls), NSStringFromSelector(sel));
    // The record goes in first: once the replacement is live, any thread that reaches it must find it.
    DPHooks[count] = (DPHookRecord){cls, sel, replacement, original};
    atomic_store_explicit(&DPHookCount, count + 1, memory_order_release);
    if (!class_addMethod(cls, sel, replacement, method_getTypeEncoding(method))) method_setImplementation(method, replacement);
}

void DPHook(const char *className, SEL sel, IMP replacement) {
    Class cls = objc_getClass(className);
    if (!class_getInstanceMethod(cls, sel)) NSLog(@"DiaPatches: can't hook -[%s %@]; Dia may have renamed it", className, NSStringFromSelector(sel));
    else DPHookClass(cls, sel, replacement);
}

IMP DPOriginalIMP(id object, SEL sel, IMP replacement) {
    size_t count = atomic_load_explicit(&DPHookCount, memory_order_acquire);
    Class cls = object_getClass(object);
    IMP best = NULL;
    size_t bestDepth = SIZE_MAX;
    for (size_t i = 0; i < count; i++) {
        if (DPHooks[i].replacement != replacement || DPHooks[i].sel != sel) continue;
        Class hooked = DPHooks[i].cls;
        if (hooked == cls) return DPHooks[i].original;
        size_t depth = 1;
        for (Class c = class_getSuperclass(cls); c && depth < bestDepth; c = class_getSuperclass(c), depth++)
            if (c == hooked) { best = DPHooks[i].original; bestDepth = depth; break; }
    }
    if (best) return best;
    abort();
}

IMP DPDiaIMP(Class cls, SEL sel) {
    size_t count = atomic_load_explicit(&DPHookCount, memory_order_acquire);
    for (size_t i = 0; i < count; i++)
        if (DPHooks[i].cls == cls && DPHooks[i].sel == sel) return DPHooks[i].original;
    return class_getMethodImplementation(cls, sel);
}
