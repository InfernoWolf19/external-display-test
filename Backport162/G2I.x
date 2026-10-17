// G2I.x : diagnostics for the "Add Another Window" flow (menu > Add Another Window > pick an app): switch g2i_addwindiag (default ON, diagnostics only, writes only with Backport162.debug).
// Kill switch file: <jbroot>/tmp/Backport162.off.g2i_addwindiag.  Setup: G2I_Setup().  Log lines: "[g2i] ...".  Spec: specs/ADDWINDOW-GLITCH-0.7.7.md (evidence, what is known, what is not).
//
// Why this exists.  User report (recording cb05c277 = RPReplay_Final1792263287.mp4): after the app was picked in the add-window picker the new window opens normally, then a pale grey, tilted
// card sticks out BEHIND both windows (left edge ~245 pt, bottom-left corner ~(245, 727) pt, bottom edge rising ~13 degrees to the right, top edge leaving the screen) from t = 3.55 s to
// t = 4.25 s of the recording and disappears abruptly.  The logs that came with the recording do NOT cover that time (the ring log of that session starts 4 s after the recording ended), so
// the cause could not be pinned from the evidence; this file records what is needed to pin it with one more recording + log (spec section "What the next test must show").
//
// Nothing here changes behaviour.  Two wrappers (class_replaceMethod chains, installed after every other hook):
//  * -[SBContinuousExposeRootSwitcherModifier handleTransitionEvent:]  (G1C's %hook runs inside; our wrapper sees the modifier tree before and after it): for every transition event of an add-window
//    flow (peek start: toPeek valid, fromPeek not; peek end = the pick: fromPeek valid, toPeek not; everything that follows within 2 s of the last event, which includes the stock second
//    non-animated pass) one line with phase, animated, gesture, modes, peek configurations, the transition / peek modifier classes found in the tree, the whole stack description before and after
//    the handler, and the layout attributes of the NEW window(s) (items of the target layout that the source layout lacks) as the target layout holds them (size / center unspecified until the
//    first layout).
//  * -[SBFluidSwitcherViewController _layoutAppLayout:roleMask:completion:] (after G2B / G2F): the first layout pass after each event that touches a layout holding a new item dumps, per leaf of
//    the layouts of the switcher that hold a new item, the root's answers for its index (frameForIndex:, scaleForIndex:, alphaForIndex:, zPositionForIndex:), the layout attributes and the item
//    container (class, frame, bounds, centre, alpha, hidden, layer transform and presentation values, z index in the container view).  For phase 2 again ~3 frames (50 ms) later.
//  * At the end of the pick transition (phase 3 of the event that ends the peek) every item container that is still alive is dumped at +0 / +0.5 s / +1.5 s: those in _visibleItemContainers
//    (with: is its leaf still part of one of the switcher's app layouts, its index there, its z index in the container view) AND every other subview of the same container view that looks like an
//    item container (flagged "NOT in _visibleItemContainers"), plus the container view's sublayerTransform (the perspective of the strip cards).
// 16.0 = 20A8372.  All reads are guarded (respondsToSelector, @try) and happen only with Backport162.debug on.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <math.h>
#import "BP.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

#define G2I_ON() BP_OnName("g2i_addwindiag")

static IMP gG2IOrigEvent, gG2IOrigLayout;
static unsigned gG2IFlow;                                  // serial of the current add-window flow (0 = none yet); the delayed dumps compare it
static BOOL gG2IActive;                                    // a flow is being traced
static double gG2ILastEvent;                               // CACurrentMediaTime() of the last traced event
static BOOL gG2IPicked;                                    // the flow's pick (peek end) was seen
static double gG2IPickTime;                                // CACurrentMediaTime() of the last pick event
static BOOL gG2IEndScheduled;                              // the end-of-flow container dumps of this flow are queued
static NSArray *gG2IWatch;                                 // items of the new window(s) of the last traced event
static NSString *gG2IPendingTag;                           // tag of the dump the next layout pass of a layout with a new item writes (nil: none)
static __weak id gG2IVC;                                   // the switcher view controller that laid out a layout with a new item

static id G2I_IvarObj(id o, const char *name) {
    Ivar iv = o ? class_getInstanceVariable(object_getClass(o), name) : NULL;
    return iv ? BP_ObjIvar(o, iv) : nil;
}
static id G2I_Obj(id o, const char *sel) {
    SEL s = sel_registerName(sel);
    return (o && [o respondsToSelector:s]) ? ((id (*)(id, SEL))objc_msgSend)(o, s) : nil;
}
static id G2I_Obj1(id o, const char *sel, id a) {
    SEL s = sel_registerName(sel);
    return (o && [o respondsToSelector:s]) ? ((id (*)(id, SEL, id))objc_msgSend)(o, s, a) : nil;
}
static long long G2I_LL(id o, const char *sel) {
    SEL s = sel_registerName(sel);
    return (o && [o respondsToSelector:s]) ? ((long long (*)(id, SEL))objc_msgSend)(o, s) : 0;
}
static BOOL G2I_Bool(id o, const char *sel) {
    SEL s = sel_registerName(sel);
    return (o && [o respondsToSelector:s]) ? ((BOOL (*)(id, SEL))objc_msgSend)(o, s) : NO;
}
static BOOL G2I_PeekValid(long long cfg) { return (cfg & ~1LL) == 2; }       // _SBPeekConfigurationIsValid (16.2 0x1c77229fc): configurations 2 and 3

static NSString *G2I_T3(CATransform3D t) {
    return [NSString stringWithFormat:@"[%.3f %.3f | %.3f %.3f | m34 %.5f | t %.1f %.1f]", t.m11, t.m12, t.m21, t.m22, t.m34, t.m41, t.m42];
}
static NSString *G2I_Short(id o) {                                              // a layout / item in one short piece
    if (!o) return @"nil";
    NSString *d = [NSString stringWithFormat:@"%@", o];
    return d.length > 160 ? [[d substringToIndex:160] stringByAppendingString:@"..."] : d;
}

static BOOL G2I_Intersects(NSArray *a, NSArray *b) {
    for (id x in a) for (id y in b) if ([x isEqual:y]) return YES;
    return NO;
}
static NSArray *G2I_Items(id layout) { id a = G2I_Obj(layout, "allItems"); return [a isKindOfClass:[NSArray class]] ? a : @[]; }

static NSString *G2I_Stack(id root) {                                           // -[SBSwitcherModifier stackDescription] (16.0 0x1c63e8e5c)
    id s = G2I_Obj(root, "stackDescription");
    return [s isKindOfClass:[NSString class]] ? s : @"(no stackDescription)";
}
// the lines of the stack description that name a transition or peek modifier (there is no public child enumeration to rely on)
static NSString *G2I_StackMods(NSString *stack) {
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *line in [stack componentsSeparatedByString:@"\n"]) {
        if ([line rangeOfString:@"Transition"].location == NSNotFound && [line rangeOfString:@"Peek"].location == NSNotFound) continue;
        NSString *t = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        [out addObject:t.length > 120 ? [t substringToIndex:120] : t];
        if (out.count >= 12) break;
    }
    return out.count ? [out componentsJoinedByString:@" | "] : @"(none)";
}

// ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------
// item container dump
static void G2I_ContainerLine(NSString *tag, NSString *label, UIView *c, NSString *extra) {
    if (!c || ![c isKindOfClass:[UIView class]]) { BP_Log(@"[g2i] %@ %@: (no container)%@", tag, label, extra ?: @""); return; }
    CALayer *l = c.layer, *p = [l presentationLayer] ?: l;
    UIView *sv = nil;
    id svo = G2I_Obj(c, "superview");
    if ([svo isKindOfClass:[UIView class]]) sv = svo;
    NSUInteger z = sv ? [sv.subviews indexOfObject:c] : NSNotFound;
    const char *occSel = [c respondsToSelector:sel_registerName("isOccludedInContinuousExposeStage")] ? "isOccludedInContinuousExposeStage" : ([c respondsToSelector:sel_registerName("isOccludedInCenterStage")] ? "isOccludedInCenterStage" : NULL);
    NSString *occ = occSel ? (G2I_Bool(c, occSel) ? @" occludedInStage" : @" notOccludedInStage") : @"";
    BP_Log(@"[g2i] %@ %@: %@ %p frame %@ bounds %@ centre %@ alpha %.3f hidden %d layer.transform %@ zPos %.2f | presentation pos %@ bounds %@ transform %@ opacity %.3f | z-index %lu%@%@",
           tag, label, NSStringFromClass([c class]), (__bridge void *)c, NSStringFromCGRect(c.frame), NSStringFromCGRect(c.bounds), NSStringFromCGPoint(c.center), c.alpha, c.hidden,
           G2I_T3(l.transform), l.zPosition, NSStringFromCGPoint(p.position), NSStringFromCGRect(p.bounds), G2I_T3(p.transform), p.opacity,
           z == NSNotFound ? 999999UL : (unsigned long)z, occ, extra ?: @"");
}

static NSArray *G2I_LayoutsOf(id vc) {
    id aps = G2I_Obj(vc, "appLayouts");
    return [aps isKindOfClass:[NSArray class]] ? aps : @[];
}

// the new window(s): root answers, attributes, container of every leaf of the switcher's layouts that holds a watched item
static void G2I_DumpNew(id vc, NSString *tag) {
    if (!vc) { BP_Log(@"[g2i] %@ new window dump: no switcher view controller captured", tag); return; }
    id root = G2I_IvarObj(vc, "_rootModifier");
    NSArray *aps = G2I_LayoutsOf(vc);
    BOOL any = NO;
    for (id layout in aps) {
        id leafsO = G2I_Obj(layout, "leafAppLayouts");
        NSArray *leafs = [leafsO isKindOfClass:[NSArray class]] ? leafsO : @[layout];
        NSUInteger idx = [aps indexOfObject:layout];
        for (id leaf in leafs) {
            NSArray *items = G2I_Items(leaf);
            if (!G2I_Intersects(items, gG2IWatch)) continue;
            any = YES;
            NSMutableString *ans = [NSMutableString string];
            if (root && idx != NSNotFound) {
                SEL fs = sel_registerName("frameForIndex:"), ss = sel_registerName("scaleForIndex:"), rs = sel_registerName("rotationAngleForIndex:"), ans_ = sel_registerName("anchorPointForIndex:");
                if ([root respondsToSelector:fs]) [ans appendFormat:@" frameForIndex %@", NSStringFromCGRect(((CGRect (*)(id, SEL, unsigned long long))objc_msgSend)(root, fs, idx))];
                if ([root respondsToSelector:ss]) [ans appendFormat:@" scale %.4f", ((double (*)(id, SEL, unsigned long long))objc_msgSend)(root, ss, idx)];
                if ([root respondsToSelector:rs]) [ans appendFormat:@" rotationAngle %.4f", ((double (*)(id, SEL, unsigned long long))objc_msgSend)(root, rs, idx)];
                if ([root respondsToSelector:ans_]) [ans appendFormat:@" anchor %@", NSStringFromCGPoint(((CGPoint (*)(id, SEL, unsigned long long))objc_msgSend)(root, ans_, idx))];
            }
            BP_Log(@"[g2i] %@ new window: layout idx %lu of %lu, root answers:%@", tag, (unsigned long)idx, (unsigned long)aps.count, ans);
            for (id item in items) {
                if (![gG2IWatch containsObject:item]) continue;
                id at = G2I_Obj1(leaf, "layoutAttributesForItem:", item);
                BP_Log(@"[g2i] %@ new window: item %@ role %lld attributes %@", tag, G2I_Short(item),
                       [leaf respondsToSelector:sel_registerName("layoutRoleForItem:")] ? ((long long (*)(id, SEL, id))objc_msgSend)(leaf, sel_registerName("layoutRoleForItem:"), item) : -1LL, at ? [NSString stringWithFormat:@"%@", at] : @"(layoutAttributesForItem: not available)");
            }
            G2I_ContainerLine(tag, @"new window container", G2I_Obj1(vc, "_itemContainerForAppLayoutIfExists:", leaf), nil);
        }
    }
    if (!any) BP_Log(@"[g2i] %@ new window dump: none of the %lu layouts of the switcher holds a new item", tag, (unsigned long)aps.count);
}

// every item container still alive
static void G2I_DumpAll(id vc, NSString *tag) {
    if (!vc) { BP_Log(@"[g2i] %@ container dump: no switcher view controller captured", tag); return; }
    NSArray *aps = G2I_LayoutsOf(vc);
    NSMutableArray *allLeafs = [NSMutableArray array];
    for (id layout in aps) {
        id leafsO = G2I_Obj(layout, "leafAppLayouts");
        for (id leaf in ([leafsO isKindOfClass:[NSArray class]] ? (NSArray *)leafsO : @[layout])) [allLeafs addObject:leaf];
    }
    id dict = G2I_IvarObj(vc, "_visibleItemContainers");
    NSMutableArray *seen = [NSMutableArray array];
    UIView *anySuper = nil;
    int n = 0;
    id keys = [dict respondsToSelector:@selector(keyEnumerator)] ? [[(id)dict keyEnumerator] allObjects] : nil;
    for (id key in ([keys isKindOfClass:[NSArray class]] ? (NSArray *)keys : @[])) {
        id c = G2I_Obj1(dict, "objectForKey:", key);
        if (![c isKindOfClass:[UIView class]]) continue;
        [seen addObject:c];
        NSUInteger li = NSNotFound;
        for (NSUInteger i = 0; i < aps.count; i++) {
            id layout = aps[i];
            id leafsO = G2I_Obj(layout, "leafAppLayouts");
            if ([layout isEqual:key] || ([leafsO isKindOfClass:[NSArray class]] && [(NSArray *)leafsO containsObject:key])) { li = i; break; }
        }
        BOOL watched = G2I_Intersects(G2I_Items(key), gG2IWatch);
        if (!anySuper) { id sv = G2I_Obj(c, "superview"); if ([sv isKindOfClass:[UIView class]]) anySuper = sv; }
        G2I_ContainerLine(tag, [NSString stringWithFormat:@"container #%d %@%@", n++, G2I_Short(key), watched ? @" [new window]" : @""], c,
                          li == NSNotFound ? @" | its layout is NOT among the switcher's appLayouts" : [NSString stringWithFormat:@" | in the switcher's appLayouts at index %lu", (unsigned long)li]);
        if (n >= 40) break;
    }
    BP_Log(@"[g2i] %@ container dump: %d in _visibleItemContainers, %lu app layouts, %lu leaves", tag, n, (unsigned long)aps.count, (unsigned long)allLeafs.count);
    if (anySuper) {
        CALayer *sl = anySuper.layer;
        BP_Log(@"[g2i] %@ container view %@ %p frame %@ sublayerTransform %@ subviews %lu", tag, NSStringFromClass([anySuper class]), (__bridge void *)anySuper, NSStringFromCGRect(anySuper.frame),
               G2I_T3(sl.sublayerTransform), (unsigned long)anySuper.subviews.count);
        int m = 0;
        for (UIView *sub in anySuper.subviews) {
            if ([seen containsObject:sub]) continue;
            NSString *cn = NSStringFromClass([sub class]);
            if ([cn rangeOfString:@"Container"].location == NSNotFound && [cn rangeOfString:@"Item"].location == NSNotFound) continue;
            G2I_ContainerLine(tag, [NSString stringWithFormat:@"NOT in _visibleItemContainers #%d", m++], sub, nil);
            if (m >= 20) break;
        }
        if (!m) BP_Log(@"[g2i] %@ container view: no other item container subview", tag);
    }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------
// -[SBFluidSwitcherViewController _layoutAppLayout:roleMask:completion:]  (G2B's port / the stock method, then G2F's wrapper, then ours)
static void G2I_Layout(id vc, SEL _cmd, id appLayout, unsigned long long roleMask, id completion) {
    ((void (*)(id, SEL, id, unsigned long long, id))gG2IOrigLayout)(vc, _cmd, appLayout, roleMask, completion);
    if (!gG2IActive || !appLayout || !BP_LogEnabled()) return;
    if (!gG2IVC) gG2IVC = vc;                                                            // fallback capture (the pass that holds a new item replaces it below)
    if (!gG2IPendingTag) return;
    @try {
        id leafsO = G2I_Obj(appLayout, "leafAppLayouts");
        BOOL holds = G2I_Intersects(G2I_Items(appLayout), gG2IWatch);
        if (!holds && [leafsO isKindOfClass:[NSArray class]]) for (id leaf in (NSArray *)leafsO) if (G2I_Intersects(G2I_Items(leaf), gG2IWatch)) { holds = YES; break; }
        if (!holds) return;
        NSString *tag = gG2IPendingTag;
        gG2IPendingTag = nil;
        gG2IVC = vc;
        unsigned serial = gG2IFlow;
        G2I_DumpNew(vc, [tag stringByAppendingString:@"+0"]);
        if ([tag isEqualToString:@"p2"]) {                                             // ~3 frames at 60 fps later
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (!BP_LogEnabled() || gG2IFlow != serial) return;
                @try { G2I_DumpNew(gG2IVC, @"p2+3f"); } @catch (NSException *e) { BP_Log(@"[g2i] exception %@", e); }
            });
        }
    } @catch (NSException *e) { BP_Log(@"[g2i] layout wrapper exception %@", e); }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------
// -[SBContinuousExposeRootSwitcherModifier handleTransitionEvent:]
static BOOL G2I_Qualifies(id event, BOOL *startOut, BOOL *pickOut) {
    SEL tp = sel_registerName("toPeekConfiguration"), fp = sel_registerName("fromPeekConfiguration");
    if (![event respondsToSelector:tp] || ![event respondsToSelector:fp]) return NO;
    BOOL fromV = G2I_PeekValid(G2I_LL(event, "fromPeekConfiguration")), toV = G2I_PeekValid(G2I_LL(event, "toPeekConfiguration"));
    double now = CACurrentMediaTime();
    BOOL start = toV && !fromV, pick = fromV && !toV;
    *startOut = start; *pickOut = pick;
    if (start || pick || fromV || toV) return YES;                                      // peek start, pick, or an event while the peek is on
    return gG2IActive && gG2IPicked && now - gG2IPickTime < 2.0;                        // what follows the pick (stock second non-animated pass ...)
}

static void G2I_LogEvent(id root, id event, NSString *pre, BOOL start, BOOL pick) {
    long long phase = G2I_LL(event, "phase");
    BOOL animated = G2I_Bool(event, "isAnimated");
    double now = CACurrentMediaTime();
    BOOL fresh0 = !gG2IFlow || now - gG2ILastEvent > 30.0 || (start && (gG2IPicked || now - gG2ILastEvent > 1.5)) || (pick && gG2IPicked && now - gG2IPickTime > 2.0);   // phases 1 / 2 / 3 of one transition share a flow
    if (fresh0) { gG2IFlow++; gG2IPicked = NO; gG2IEndScheduled = NO; }
    gG2IActive = YES;
    gG2ILastEvent = now;
    if (pick) { gG2IPicked = YES; gG2IPickTime = now; }
    unsigned serial = gG2IFlow;
    id from = G2I_Obj(event, "fromAppLayout"), to = G2I_Obj(event, "toAppLayout");
    NSArray *fromItems = G2I_Items(from), *toItems = G2I_Items(to);
    NSMutableArray *fresh = [NSMutableArray array];
    for (id it in toItems) if (![fromItems containsObject:it]) [fresh addObject:it];
    if (!fresh.count) [fresh addObjectsFromArray:toItems];
    gG2IWatch = fresh;
    gG2IPendingTag = [NSString stringWithFormat:@"p%lld", phase];
    NSString *postStack = G2I_Stack(root);
    BP_Log(@"[g2i] flow %u %@ event: phase=%lld animated=%d gesture=%d modes %lld->%lld peek %lld->%lld from=%@ to=%@ new items=%lu transition/peek modifiers in the tree after the handler: %@",
           serial, start ? @"peek start" : (pick ? @"peek end (pick)" : @"within/after"), phase, animated, G2I_Bool(event, "isGestureInitiated"),
           G2I_LL(event, "fromEnvironmentMode"), G2I_LL(event, "toEnvironmentMode"), G2I_LL(event, "fromPeekConfiguration"), G2I_LL(event, "toPeekConfiguration"),
           G2I_Short(from), G2I_Short(to), (unsigned long)fresh.count, G2I_StackMods(postStack));
    for (id it in fresh) {
        id at = G2I_Obj1(to, "layoutAttributesForItem:", it);
        BP_Log(@"[g2i] flow %u phase %lld new item %@ attributes in the target layout: %@", serial, phase, G2I_Short(it), at ? [NSString stringWithFormat:@"%@", at] : @"(layoutAttributesForItem: not available)");
    }
    NSString *post = postStack;
    if ([pre isEqualToString:post]) BP_Log(@"[g2i] flow %u phase %lld modifier stack (before = after the handler):\n%@", serial, phase, post);
    else BP_Log(@"[g2i] flow %u phase %lld modifier stack before the handler:\n%@\n[g2i] flow %u phase %lld modifier stack after the handler:\n%@", serial, phase, pre, serial, phase, post);
    if (pick && phase == 3 && !gG2IEndScheduled) {
        gG2IEndScheduled = YES;
        static const double kDelay[] = { 0.0, 0.5, 1.5 };
        static NSString *const kTag[] = { @"end+0", @"end+0.5s", @"end+1.5s" };
        for (int i = 0; i < 3; i++) {
            NSString *tag = kTag[i];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kDelay[i] * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (!BP_LogEnabled() || gG2IFlow != serial) return;
                @try { BP_Log(@"[g2i] flow %u %@ (after the pick's last transition phase)", serial, tag); G2I_DumpAll(gG2IVC, tag); } @catch (NSException *e) { BP_Log(@"[g2i] exception %@", e); }
            });
        }
    }
}

static id G2I_Event(id self, SEL _cmd, id event) {
    BOOL trace = NO, start = NO, pick = NO;
    NSString *pre = nil;
    if (event && BP_LogEnabled() && G2I_ON()) {
        @try { trace = G2I_Qualifies(event, &start, &pick); if (trace) pre = G2I_Stack(self); } @catch (NSException *e) { trace = NO; BP_Log(@"[g2i] exception %@", e); }
    }
    id r = ((id (*)(id, SEL, id))gG2IOrigEvent)(self, _cmd, event);
    if (trace) { @try { G2I_LogEvent(self, event, pre, start, pick); } @catch (NSException *e) { BP_Log(@"[g2i] event log exception %@", e); } }
    return r;
}

void G2I_Setup(void) {
    if (!G2I_ON()) return;
    Class rc = NSClassFromString(@"SBContinuousExposeRootSwitcherModifier");
    SEL es = sel_registerName("handleTransitionEvent:");
    Method em = rc ? class_getInstanceMethod(rc, es) : NULL;
    Class vcc = NSClassFromString(@"SBFluidSwitcherViewController");
    SEL ls = sel_registerName("_layoutAppLayout:roleMask:completion:");
    Method lm = vcc ? class_getInstanceMethod(vcc, ls) : NULL;
    if (!em || !lm) { BP_Log(@"[g2i] SBContinuousExposeRootSwitcherModifier handleTransitionEvent: / SBFluidSwitcherViewController _layoutAppLayout:roleMask:completion: not found, add-window diagnostics not installed"); return; }
    gG2IOrigEvent = method_getImplementation(em);
    class_replaceMethod(rc, es, (IMP)G2I_Event, method_getTypeEncoding(em));
    gG2IOrigLayout = method_getImplementation(lm);
    class_replaceMethod(vcc, ls, (IMP)G2I_Layout, method_getTypeEncoding(lm));
    BP_Log(@"[g2i] installed (add-window diagnostics: transition events, new window dumps, container dumps after the pick; nothing changes behaviour)");
}
#pragma clang diagnostic pop
