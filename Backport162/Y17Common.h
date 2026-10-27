// Y17Common.h : helpers of the second delta-sweep pass (Y17 .. Y2x): logged guards.  Header only, static inline.
// Rule of the pass: a helper never silently returns NO / nil for a missing selector, class or ivar: the first miss per (tag, class, selector) is logged, later ones are counted silently.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "BPY.h"

static inline void Y17_GuardOnce(const char *tag, id obj, const char *what) {
    static NSMutableSet *seen;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ seen = [NSMutableSet set]; });
    NSString *key = [NSString stringWithFormat:@"%s|%s|%s", tag, obj ? class_getName(object_getClass(obj)) : "nil", what];
    BOOL fresh;
    @synchronized (seen) { fresh = ![seen containsObject:key]; if (fresh) [seen addObject:key]; }
    if (fresh) BP_Log(@"[y17] GUARD(%s) %s missing on %@ (logged once)", tag, what, obj ? NSStringFromClass(object_getClass(obj)) : @"nil");
}
// object message with a logged guard
static inline id Y17_Obj0(const char *tag, id o, const char *sel) {
    if (!o || ![o respondsToSelector:sel_registerName(sel)]) { Y17_GuardOnce(tag, o, sel); return nil; }
    return ((id (*)(id, SEL))objc_msgSend)(o, sel_registerName(sel));
}
static inline id Y17_Obj1(const char *tag, id o, const char *sel, id a) {
    if (!o || ![o respondsToSelector:sel_registerName(sel)]) { Y17_GuardOnce(tag, o, sel); return nil; }
    return ((id (*)(id, SEL, id))objc_msgSend)(o, sel_registerName(sel), a);
}
// 16.2 FBDisplayManager configurationForIdentity: scale of the display of an identity (0 when unknown, logged)
static inline double Y17_ScaleForIdentity(const char *tag, id identity) {
    Class fb = NSClassFromString(@"FBDisplayManager");
    id mgr = Y17_Obj0(tag, (id)fb, "sharedInstance");
    id cfg = Y17_Obj1(tag, mgr, "configurationForIdentity:", identity);
    if (!cfg || ![cfg respondsToSelector:sel_registerName("scale")]) { Y17_GuardOnce(tag, cfg, "scale"); return 0; }
    return ((double (*)(id, SEL))objc_msgSend)(cfg, sel_registerName("scale"));
}
