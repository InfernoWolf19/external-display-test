// AV.x - AVKit side of iPadOS 16.2 (20C65) extended display video behaviour, loaded into app processes (filter com.apple.AVKit, see Backport162AV.plist).
// Spec: specs/VIDEO-EXTDISPLAY-0.7.4.md.
//
// 16.0 AVKit chooses a second screen (AVSecondScreen type 3 wired / 4 AirPlay) whenever one is available, so with an extended display connected the video of an
// AVPlayerViewController moves to a window of the extended display's scene and the player on the iPad shows the external playback placeholder (audio only).
// 16.2 asks the XPC service com.apple.avkit.SharedPreferences -extendedDisplayActive: on iPad and never makes the second screen connection ready while an extended
// display is active:
//   -[AVPlayerViewController _updateSecondScreenConnectionReadyToConnect]  16.0 0x1aa0e4b68 / 16.2 0x1aa86d1d8 (reply block 0x1aa86d3a0: active ? NO : synchronous checks)
//   PiP adapter block that creates the connection (addConnectionForPlayer:playerLayer: + setSecondScreenConnection:) 16.0 0x1aa0b16dc / 16.2 0x1aa8386e8 (block 0x1aa838860)
// The 16.0 service does not implement -extendedDisplayActive:, so it must not be called; the answer is computed locally: an extended display is a connected screen that
// is not the main screen and is "main like" (SpringBoard sets setUIKitMainLike on the extended display in the shell controller policy, 16.0 0x1c60612b0 / 16.2 0x1c74e0570).
// Switch: <jbroot>/tmp/Backport162.off.avkit.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <sys/sysctl.h>
#import <string.h>
#import <unistd.h>
#import <rootless.h>

@interface UIScreen (BPAV)
- (BOOL)_isMainLikeScreen;
@end

static BOOL BPAV_On(void) {
    static BOOL on;
    static CFAbsoluteTime t;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (now - t > 1.0 || t == 0) {
        t = now;
        NSString *p = ROOT_PATH_NS(@"/tmp/Backport162.off.avkit");
        NSString *all = ROOT_PATH_NS(@"/tmp/Backport162.off");
        on = !(access(p.fileSystemRepresentation, F_OK) == 0 || access(all.fileSystemRepresentation, F_OK) == 0);
    }
    return on;
}

static BOOL BPAV_ExtendedDisplayActive(void) {
    UIScreen *main = [UIScreen mainScreen];
    for (UIScreen *s in [UIScreen screens]) {
        if (s != main && [s respondsToSelector:@selector(_isMainLikeScreen)] && [s _isMainLikeScreen]) return YES;
    }
    return NO;
}

static BOOL BPAV_Pad(void) { return [[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad; }

static NSHashTable *gBPAVPlayers;     // live AVPlayerViewControllers (weak): 16.2 re-runs the check from its observers when the answer can change

%group BPAV_Hooks

%hook AVPlayerViewController
- (void)_updateSecondScreenConnectionReadyToConnect {
    if (!BPAV_On() || !BPAV_Pad()) {
        %orig;
        return;
    }
    if (!gBPAVPlayers) gBPAVPlayers = [NSHashTable weakObjectsHashTable];
    [gBPAVPlayers addObject:self];
    if (!BPAV_ExtendedDisplayActive()) {
        %orig;
        return;
    }
    // 16.2: the XPC reply says "active" -> readyToConnect NO
    Ivar iv = class_getInstanceVariable(object_getClass(self), "_secondScreenConnection");
    id conn = iv ? object_getIvar(self, iv) : nil;
    if (conn && [conn respondsToSelector:@selector(isReadyToConnect)] && ((BOOL (*)(id, SEL))objc_msgSend)(conn, @selector(isReadyToConnect))) {
        NSLog(@"[Backport162AV] extended display active: second screen connection of %@ set to not ready", self);
        ((void (*)(id, SEL, BOOL))objc_msgSend)(conn, @selector(setReadyToConnect:), NO);
    }
}
%end

%hook AVSecondScreenController
- (id)addConnectionForPlayer:(id)player playerLayer:(id)layer {
    if (BPAV_On() && BPAV_Pad() && BPAV_ExtendedDisplayActive()) {
        NSLog(@"[Backport162AV] extended display active: no second screen connection for the PiP player");
        return nil;
    }
    return %orig;
}
%end

%end // BPAV_Hooks

static BOOL BPAV_BuildMatches(void) {
    char buf[64] = {0};
    size_t n = sizeof buf;
    if (sysctlbyname("kern.osversion", buf, &n, NULL, 0) != 0) return NO;
    return strcmp(buf, "20A8372") == 0;
}

static void BPAV_ScreensChanged(void) {
    // the answer of 16.2's service can change with the display: re-run the readiness check on live players (16.2 observers do the same)
    for (id pvc in [gBPAVPlayers allObjects]) {
        if ([pvc respondsToSelector:@selector(_updateSecondScreenConnectionReadyToConnect)]) ((void (*)(id, SEL))objc_msgSend)(pvc, @selector(_updateSecondScreenConnectionReadyToConnect));
    }
}

%ctor {
    if (!BPAV_BuildMatches()) return;
    %init(BPAV_Hooks);
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    for (NSNotificationName n in @[UIScreenDidConnectNotification, UIScreenDidDisconnectNotification]) {
        [nc addObserverForName:n object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) { BPAV_ScreensChanged(); }];
    }
}
