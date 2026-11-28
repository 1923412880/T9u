//
//  BlockIntents.m
//  LiveContainer injection tweak
//
//  Purpose:  Completely block the iOS Intents framework when an app runs
//            inside LiveContainer with a personal developer certificate.
//
//  Why this works:  Personal certificates do not include SiriKit entitlements.
//            The Intents framework throws Objective-C exceptions as soon as
//            SiriKit classes (INPreferences, INVocabulary, …) are used.
//            Prior versions tried to swizzle a few known selectors or hook
//            SecTaskCopyValueForEntitlement, but Intents has many entry
//            points and can assert the entitlement directly inside the class.
//
//            v3 takes the name literally: it blocks the entire framework.
//            Whenever Intents.framework (or IntentsUI.framework) is loaded,
//            every class in that image gets all of its own methods replaced
//            by safe no-op stubs.  The framework becomes an inert shell.
//
//  Usage:    Build as BlockIntents.dylib and inject it into the target app
//            via LiveContainer's tweak mechanism.
//

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>

// ---------------------------------------------------------------------------
//  Generic no-op stubs.  They return zero/nil/false for every common scalar,
//  object and pointer return type.
// ---------------------------------------------------------------------------

static id       __bi_stub_id       (id self, SEL _cmd) { return nil; }
static void     __bi_stub_void     (id self, SEL _cmd) { }
static BOOL     __bi_stub_bool     (id self, SEL _cmd) { return NO; }
static char     __bi_stub_char     (id self, SEL _cmd) { return 0; }
static short    __bi_stub_short    (id self, SEL _cmd) { return 0; }
static int      __bi_stub_int      (id self, SEL _cmd) { return 0; }
static long     __bi_stub_long     (id self, SEL _cmd) { return 0; }
static long long __bi_stub_longlong(id self, SEL _cmd) { return 0; }
static unsigned char  __bi_stub_uchar  (id self, SEL _cmd) { return 0; }
static unsigned short __bi_stub_ushort (id self, SEL _cmd) { return 0; }
static unsigned int   __bi_stub_uint   (id self, SEL _cmd) { return 0; }
static unsigned long  __bi_stub_ulong  (id self, SEL _cmd) { return 0; }
static unsigned long long __bi_stub_ulonglong(id self, SEL _cmd) { return 0; }
static float    __bi_stub_float    (id self, SEL _cmd) { return 0.0f; }
static double   __bi_stub_double   (id self, SEL _cmd) { return 0.0; }
static CGFloat  __bi_stub_cgfloat  (id self, SEL _cmd) { return 0.0; }
static NSInteger __bi_stub_nsinteger(id self, SEL _cmd) { return 0; }
static NSUInteger __bi_stub_nsuinteger(id self, SEL _cmd) { return 0; }

// ---------------------------------------------------------------------------
//  Helpers
// ---------------------------------------------------------------------------

// Methods we must NEVER replace, otherwise the Objective-C runtime itself
// breaks (retain/release, isa dispatch, forwarding, NSObject contract).
static BOOL bi_isEssentialMethod(const char *name) {
    static const char *essentials[] = {
        "retain", "release", "autorelease", "dealloc",
        "class", "self", "superclass", "isKindOfClass:", "isMemberOfClass:",
        "respondsToSelector:", "conformsToProtocol:", "description", "debugDescription",
        "hash", "isEqual:", "isProxy",
        "performSelector:", "performSelector:withObject:", "performSelector:withObject:withObject:",
        "doesNotRecognizeSelector:", "forwardingTargetForSelector:", "forwardInvocation:",
        "methodSignatureForSelector:", "zone", "copy", "mutableCopy",
        "copyWithZone:", "mutableCopyWithZone:",
        "alloc", "allocWithZone:", "new",
        "initialize", "load",
        "retainCount",
        NULL
    };
    for (const char **p = essentials; *p; p++) {
        if (strcmp(name, *p) == 0) return YES;
    }
    return NO;
}

// Choose a stub IMP based on the method's return-type encoding.
static IMP bi_stubForEncoding(const char *type) {
    if (!type || type[0] == 'v') return (IMP)__bi_stub_void;

    switch (type[0]) {
        case '@': return (IMP)__bi_stub_id;     // id, block, Class
        case '#': return (IMP)__bi_stub_id;     // Class
        case ':': return (IMP)__bi_stub_nsuinteger; // SEL (should not be returned, but safe)
        case 'B': return (IMP)__bi_stub_bool;   // C++ bool / _Bool
        case 'c': return (IMP)__bi_stub_char;
        case 'C': return (IMP)__bi_stub_uchar;
        case 's': return (IMP)__bi_stub_short;
        case 'S': return (IMP)__bi_stub_ushort;
        case 'i': return (IMP)__bi_stub_int;
        case 'I': return (IMP)__bi_stub_uint;
        case 'l': return (IMP)__bi_stub_long;
        case 'L': return (IMP)__bi_stub_ulong;
        case 'q': return (IMP)__bi_stub_longlong;
        case 'Q': return (IMP)__bi_stub_ulonglong;
        case 'f': return (IMP)__bi_stub_float;
        case 'd': return (IMP)__bi_stub_double;
        case '^': return (IMP)__bi_stub_id;     // pointer -> NULL
        case '*': return (IMP)__bi_stub_id;     // char*   -> NULL
        default:  return NULL;                  // complex: leave untouched
    }
}

// Replace every method that belongs to `cls` itself (not inherited) with a
// safe stub.  Inherited NSObject methods keep working normally.
static void bi_blockClassMethods(Class cls) {
    if (!cls) return;

    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    for (unsigned int i = 0; i < count; i++) {
        SEL sel = method_getName(methods[i]);
        const char *name = sel_getName(sel);
        const char *type = method_getTypeEncoding(methods[i]);

        if (bi_isEssentialMethod(name)) continue;

        // Skip methods whose return type is a structure, union, array or
        // unknown function pointer — their calling convention is not safely
        // representable by a single generic IMP.
        if (strchr(type, '{')) continue;
        if (strchr(type, '(')) continue;
        if (type[0] == '[') continue;
        if (type[0] == '?') continue;

        IMP stub = bi_stubForEncoding(type);
        if (stub) {
            class_replaceMethod(cls, sel, stub, type);
        }
    }
    free(methods);
}

static void bi_blockClass(Class cls) {
    if (!cls) return;

    // Instance methods.
    bi_blockClassMethods(cls);

    // Class methods live on the metaclass.
    Class meta = object_getClass(cls);
    if (meta && class_isMetaClass(meta)) {
        bi_blockClassMethods(meta);
    }
}

// ---------------------------------------------------------------------------
//  dyld image callback — the heart of the blocker
// ---------------------------------------------------------------------------

static void bi_blockImage(const char *imageName) {
    unsigned int count = 0;
    const char **classNames = objc_copyClassNamesForImage(imageName, &count);
    if (!classNames) return;

    for (unsigned int i = 0; i < count; i++) {
        Class cls = objc_getClass(classNames[i]);
        if (cls) {
            bi_blockClass(cls);
        }
    }
    free(classNames);

    NSLog(@"[BlockIntents] blocked %u class(es) in %s", count, imageName);
}

static void bi_imageCallback(const struct mach_header *mh, intptr_t slide) {
    Dl_info info;
    if (dladdr(mh, &info) == 0) return;
    const char *imageName = info.dli_fname;
    if (!imageName) return;

    // We take the project name literally: block Intents and IntentsUI.
    if ((strstr(imageName, "Intents.framework") ||
         strstr(imageName, "IntentsUI.framework")) &&
        strstr(imageName, ".framework/")) {
        NSLog(@"[BlockIntents] Intents image detected: %s", imageName);
        bi_blockImage(imageName);
    }
}

// ---------------------------------------------------------------------------
//  Constructor
// ---------------------------------------------------------------------------

__attribute__((constructor))
static void BlockIntentsInitialize(void) {
    NSLog(@"[BlockIntents] loaded — registering Intents.framework blocker");

    // Register for every future Intents image load.  dyld also calls this
    // immediately for every image already loaded, so already-present Intents
    // classes are blocked right away.
    _dyld_register_func_for_add_image(bi_imageCallback);

    // Double-check: scan every class currently known to the runtime.  This
    // catches cases where dyld has loaded the image but the callback timing
    // differs from class registration timing.
    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    for (unsigned int i = 0; i < count; i++) {
        const char *imageName = class_getImageName(classes[i]);
        if (imageName &&
            (strstr(imageName, "Intents.framework") ||
             strstr(imageName, "IntentsUI.framework"))) {
            bi_blockClass(classes[i]);
        }
    }
    free(classes);

    NSLog(@"[BlockIntents] blocker installed (%u classes inspected)", count);
}
