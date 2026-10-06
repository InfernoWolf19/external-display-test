// AudioRouteProbe, SpringBoard side (passive; changes nothing).
//
// SpringBoard is not sandboxed like the media daemon, so it is a reliable place to write the log. It does two
// things:
//
//  1. Picker view: polls -[AVSystemController pickableRoutesForCategory:andMode:], the same call that feeds the
//     audio route picker in Control Centre, for a few categories, and logs the result whenever it changes. Plug
//     the monitor / AirPods Max in and out and the log shows exactly what the picker is offered each time.
//  2. Daemon beacons: logs the Darwin notifications posted by the daemon side (Probe.c), which prove whether the
//     probe loaded inside mediaserverd/audiomxd and which hooks fired, even if the daemon cannot write a file.
//
// Log: <jbroot>/tmp/AudioRouteProbe.picker.log (path resolved with libroot, never a rootful path).
// Kill switch: create <jbroot>/tmp/AudioRouteProbe.off and respring.

#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <notify.h>
#import <rootless.h>

static NSString *gLogPath;
static dispatch_queue_t gQueue;
static NSMutableDictionary<NSString *, NSString *> *gLast;       // last logged signature per category/mode
static NSMutableArray<NSNumber *> *gTokens;
static dispatch_source_t gTimer;                                 // keeps the poll timer alive
static BOOL gSnapshotPending;                                    // touched only on gQueue

static void sbp_log(NSString *msg) {
    if (!gLogPath) return;
    static NSDateFormatter *fmt;
    if (!fmt) {
        fmt = [[NSDateFormatter alloc] init];
        fmt.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        fmt.dateFormat = @"HH:mm:ss.SSS";
    }
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDictionary *attrs = [fm attributesOfItemAtPath:gLogPath error:NULL];
    if (attrs && [attrs fileSize] > 2 * 1024 * 1024) [fm removeItemAtPath:gLogPath error:NULL];
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [fmt stringFromDate:[NSDate date]], msg];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:gLogPath];
    if (!fh) {
        [fm createFileAtPath:gLogPath contents:nil attributes:nil];
        fh = [NSFileHandle fileHandleForWritingAtPath:gLogPath];
    }
    @try {
        [fh seekToEndOfFile];
        [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    } @catch (NSException *e) {
    }
}

static NSString *sbp_squash(NSString *s, NSUInteger max) {
    NSMutableString *m = [NSMutableString stringWithString:s ?: @""];
    [m replaceOccurrencesOfString:@"\n" withString:@" " options:0 range:NSMakeRange(0, m.length)];
    [m replaceOccurrencesOfString:@"\t" withString:@" " options:0 range:NSMakeRange(0, m.length)];
    while ([m rangeOfString:@"  "].location != NSNotFound) {
        [m replaceOccurrencesOfString:@"  " withString:@" " options:0 range:NSMakeRange(0, m.length)];
    }
    if (m.length > max) return [[m substringToIndex:max] stringByAppendingString:@"..."];
    return m;
}

// Category/mode names as they appear as C strings in MediaExperience.framework on 20A8372; "Audio/Video" +
// "Default" is also what the API itself uses when given nil. A name the daemon does not know returns nothing
// and is logged once as <nil>.
static NSArray<NSArray<NSString *> *> *sbp_combos(void) {
    return @[
        @[@"Audio/Video", @"Default"],
        @[@"MediaPlayback", @"Default"],
        @[@"MediaPlaybackNoSpeaker", @"Default"],
        @[@"PlayAndRecord", @"Default"],
        @[@"PlayAndRecord", @"VideoChat"],
        @[@"PlayAndRecord_WithBluetooth", @"Default"],
    ];
}

static void sbp_snapshot(NSString *reason) {                      // call on gQueue
    Class av = NSClassFromString(@"AVSystemController");
    if (!av) {
        dlopen("/System/Library/PrivateFrameworks/MediaExperience.framework/MediaExperience", RTLD_LAZY);
        av = NSClassFromString(@"AVSystemController");
    }
    SEL shared = NSSelectorFromString(@"sharedAVSystemController");
    SEL pick = NSSelectorFromString(@"pickableRoutesForCategory:andMode:");
    if (!av || ![av respondsToSelector:shared]) { sbp_log(@"AVSystemController unavailable"); return; }
    id avsc = ((id (*)(Class, SEL))objc_msgSend)(av, shared);
    if (!avsc || ![avsc respondsToSelector:pick]) { sbp_log(@"AVSystemController has no pickableRoutesForCategory:andMode:"); return; }

    for (NSArray<NSString *> *combo in sbp_combos()) {
        NSString *key = [NSString stringWithFormat:@"%@/%@", combo[0], combo[1]];
        NSString *sig;
        NSUInteger count = 0;
        @try {
            id r = ((id (*)(id, SEL, id, id))objc_msgSend)(avsc, pick, combo[0], combo[1]);
            if (!r) sig = @"<nil>";
            else {
                count = [r respondsToSelector:@selector(count)] ? [(NSArray *)r count] : 0;
                sig = sbp_squash([r description], 4000);
            }
        } @catch (NSException *e) {
            sig = [NSString stringWithFormat:@"<exception %@>", e.name];
        }
        if (![gLast[key] isEqualToString:sig]) {
            gLast[key] = sig;
            sbp_log([NSString stringWithFormat:@"picker %@ (%@): %lu route(s) %@", key, reason, (unsigned long)count, sig]);
        }
    }
}

static void sbp_request_snapshot(NSString *reason) {              // coalesce bursts of events; call on gQueue
    if (gSnapshotPending) return;
    gSnapshotPending = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), gQueue, ^{
        gSnapshotPending = NO;
        sbp_snapshot(reason);
    });
}

static void sbp_register_beacon(const char *name, BOOL isEvent) {
    int token = 0;
    notify_register_dispatch(name, &token, gQueue, ^(int t) {
        uint64_t state = 0;
        notify_get_state(t, &state);
        // Event beacons fire very often; log the first one and then every 50th.
        if (!isEvent || state == 1 || state % 50 == 0) {
            sbp_log([NSString stringWithFormat:@"daemon beacon %s state=%llu (0x%llx)", name, (unsigned long long)state, (unsigned long long)state]);
        }
        if (isEvent) sbp_request_snapshot(@"daemon event");
    });
    [gTokens addObject:@(token)];
}

__attribute__((constructor))
static void sbp_init(void) {
    const char *pn = getprogname();
    if (!pn || strcmp(pn, "SpringBoard") != 0) return;
    @autoreleasepool {
        NSString *off = [ROOT_PATH_NS(@"/tmp") stringByAppendingPathComponent:@"AudioRouteProbe.off"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:off]) return;

        gLogPath = [ROOT_PATH_NS(@"/tmp") stringByAppendingPathComponent:@"AudioRouteProbe.picker.log"];
        gQueue = dispatch_queue_create("com.infernowolf19.audiorouteprobe.picker", DISPATCH_QUEUE_SERIAL);
        gLast = [NSMutableDictionary dictionary];
        gTokens = [NSMutableArray array];

        dispatch_async(gQueue, ^{
            sbp_log(@"---- AudioRouteProbe 0.4.0 SpringBoard side started");
            static const char *const names[] = {
                "com.infernowolf19.audiorouteprobe.loaded", "com.infernowolf19.audiorouteprobe.info",
                "com.infernowolf19.audiorouteprobe.hooks",
            };
            static const char *const events[] = {
                "com.infernowolf19.audiorouteprobe.ev.conn", "com.infernowolf19.audiorouteprobe.ev.incl",
                "com.infernowolf19.audiorouteprobe.ev.pick", "com.infernowolf19.audiorouteprobe.ev.rchg",
            };
            for (size_t i = 0; i < sizeof names / sizeof names[0]; i++) {
                sbp_register_beacon(names[i], NO);
                // The daemon may have posted before we registered: report the state it left behind.
                int t = 0; uint64_t st = 0;
                if (notify_register_check(names[i], &t) == NOTIFY_STATUS_OK) {
                    notify_get_state(t, &st);
                    sbp_log([NSString stringWithFormat:@"daemon beacon %s already at state=%llu (0x%llx)", names[i], (unsigned long long)st, (unsigned long long)st]);
                    notify_cancel(t);
                }
            }
            for (size_t i = 0; i < sizeof events / sizeof events[0]; i++) sbp_register_beacon(events[i], YES);

            sbp_snapshot(@"startup");
            // Poll as a safety net: route changes also arrive through the beacons, but not if the daemon part is absent.
            dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, gQueue);
            dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), 3 * NSEC_PER_SEC, 500 * NSEC_PER_MSEC);
            dispatch_source_set_event_handler(timer, ^{ sbp_snapshot(@"poll"); });
            dispatch_resume(timer);
            gTimer = timer;
        });
    }
}
