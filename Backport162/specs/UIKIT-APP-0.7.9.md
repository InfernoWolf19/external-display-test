# UIKIT-APP-0.7.9: Backport162UIK, the in-app (UIKitCore) half of the 16.2 port

Dylib `Backport162UIK` (source `UIK.m`, filter `Backport162UIK.plist` = bundles `com.apple.UIKit` / `com.apple.UIKitCore`), loaded by the tweak loader into every process that links UIKit, then restricted at run time to **apps** (main executable inside `*.app/`, not `.appex`, not SpringBoard) on **build 20A8372** (`sysctl kern.osversion`). arm64 and arm64e slices (no addresses are used: plain Objective-C runtime hooks, `class_replaceMethod`, the 16.0 IMP is called for every unchanged case). Static analysis of the 16.0 and 16.2 dyld caches only; nothing ran.

Safety rules (all in the header of UIK.m): no work at load except the build / process checks and the hook installation; no ObjC messages at load; no signal handlers, threads or atexit; every hook is installed through `UIK_Hook()` which skips (and logs once, always) a hook whose class, selector or type encoding is not the one the port was written against; every hook asks its kill file at most once a second (`<jbroot>/tmp/Backport162.off`, `Backport162.off.uik`, `Backport162.off.uik_screenbounds` U1, `uik_keyboard` K1, `uik_screenlife` U2; a killed hook calls the original). Nothing can throw into the app (no `@try` needed: only ivar reads checked at install and selectors checked at install).

Log: `<jbroot>/var/mobile/Library/Caches/Backport162.uik.log` (apps may read `<jbroot>` but write only `<jbroot>/var/mobile`; first writable of `/var/jb/var/mobile/Library/Caches`, `/var/jb/var/mobile`, `/var/mobile/Library/Caches`, `/var/mobile`; rotated at 512 KiB to `.1`). Every line carries `[progname pid]`. Missing selector / class / ivar / encoding lines are written once per key without any switch; everything else needs `Backport162.debug`. Crash breadcrumb: with `Backport162.debug` the load line prints the image base of the dylib, so `Backport162UIK.dylib+offset` frames of an app crash report (ReportCrash writes one for apps) resolve against the CI build of the same commit; no handler is installed.

Items: U1 (this section), K1, U2 (later sections).

---

## U1. Screen bounds of an app window on the monitor (bug: "the window thinks it is vertical when it is horizontal after Move to display")

### What the brief assumed and what 16.2 really does
SpringBoard 16.2 writes the scene setting `screenBoundsIgnoresSceneOrientation` (`UIMutableApplicationSceneSettings setScreenBoundsIgnoresSceneOrientation:` 0x1898dd7c0 = `[[self otherSettings] setFlag:BSSettingFlagForBool(v) forSetting:0x2a]`, getter `UIApplicationSceneSettings` 0x1898dc6a0 = `[[self otherSettings] boolForSetting:0x2a]`, diff-inspector observer 0x1898de008 `_observeOtherSetting:0x2a`). **Nothing in 16.2 reads it.** Independent check done for this item: all 4.4 M instructions of the 16.2 UIKitCore `__text` were scanned for calls to the three selectors (`bl` to the `__objc_stubs` entries and direct selref loads, tables rebuilt for 20C65) with zero hits other than the definitions; the selector string exists only in UIKitCore (whole-cache string table). Setting ids 0x28 (`inLiveResize` observer, new in 16.2) and 0x2a are unused by 16.0 UIKit (ids used by the 16.0 diff inspector: 0x1-0x4, 0x6-0x8, 0xa, 0xb, 0xd, 0xf-0x14, 0x18, 0x1d, 0x20, 0x21, 0x23, 0x24, 0x26, 0x27, 0x29). So the accessor port would change nothing and is **not added**; SpringBoard's write of the setting (Y1/Y8 notes) would be dead too.

The behaviour that fixes the symptom is in `UIScreen` (found by body-diffing all 112 703 UIKitCore functions of 16.0 against 16.2, tokens: selectors, callees, immediates, branches; tools in the scratchpad `uik/`):

| method | 16.0 | 16.2 |
|---|---|---|
| `-[UIScreen _boundsForInterfaceOrientation:]` | 0x188f91da8 | 0x1890c7fc0 |
| `-[UIScreen _unjailedReferenceBoundsForInterfaceOrientation:]` | 0x18937e674 | 0x1894b4d00 |
| `-[UIScreen _mainSceneBoundsForInterfaceOrientation:]` | 0x188f91f04 | 0x1890c8150 |
| `-[UIScreen _connectScreen]` | 0x18902b55c | 0x189161788 |
| `-[UIScreen _setInterfaceOrientation:]` | 0x1890c2fe8 (body) | thunk to new `_setInterfaceOrientation:andNotify:` 0x18996a700 (same body, the two notifications only when `notify`) |

* 16.0 `_boundsForInterfaceOrientation:` (and the other two): take the rect, and if `orientation - 3 <= 1` (landscape right / left) swap width and height (origin kept) and return.
* 16.2: `if ([self _isExternal]) { if (![self _isMainLikeScreen]) swap when orientation-3 < 2 } else swap when orientation-3 <= 1`. I.e. the swap is **never done for an external screen that is main-like** (the Stage Manager extended display: SpringBoard calls `setUIKitMainLike` on it, 16.0 0x1c60612b0 / 16.2 0x1c74e0570; `_isMainLikeScreen` = `isUIKitMainLike` of the display configuration, `_isExternal` = `isExternal`). `_mainSceneBoundsForInterfaceOrientation:` also handles a nil screen like the non external branch (`cbz x20`), irrelevant for a message receiver.
* 16.2 `_connectScreen`: after `_updateUserInterfaceIdiom` and `_updateCapabilities`: `if ([self _isExternal] && [self _isMainLikeScreen]) [self _setInterfaceOrientation:1 andNotify:NO]; else [self _updateTraits];` then sets the connected flag. The UIScreen ivar `_interfaceOrientation` (+0x48) starts at 0, so the call sets portrait and, because it changed, runs `_updateTraits` and `_computeMetrics` (no notification, no periphery insets notification).

Why this is the bug: the native rect of the monitor is landscape (1920x1080). An app moved with "Move to display" gets a landscape interface orientation (3 / 4) on its scene / UIScreen (`-[_UIScreenBasedWindowScene _updateClientSettingsToInterfaceOrientation:...]`, `-[UIApplication setStatusBarOrientation:...windowScene:...]`, `_UIScenefbsSceneBasedMetricsCalculator _updateMetricsOnWindows:animated:` all end in `UIScreen _setInterfaceOrientation:`), and 16.0 then swaps the landscape rect to 1080x1920: `UIScreen.bounds`, `_mainSceneBounds`, the keyboard geometry (`UIKBScreenTraits initWithScreen:orientation:...`, `UIInputWindowController _defaultInitialViewFrame`, `+[UIKeyboard defaultFrameForInterfaceOrientation:]` all call these three methods) and the app's idea of its screen are vertical although the monitor is horizontal. Apps started on the monitor keep orientation 1 and are not swapped, which is why only Move to display shows it. 16.2 never swaps there.

### What was ported (`UIK.m`, `UIK_InstallU1`, switch `uik_screenbounds`)
* Hooks of the three bounds methods: if the orientation is 3 or 4 and the receiver is external and main-like, the 16.0 body is called with orientation 1 (16.0 swaps only for 3 / 4, so it returns the unswapped rect, exactly the 16.2 result); everything else calls the 16.0 body unchanged.
* Hook of `-_connectScreen`: the 16.0 body runs, then for an external main-like screen whose `_interfaceOrientation` ivar is not 1: store 1, `_updateTraits`, `_computeMetrics` (the 16.2 effect of `_setInterfaceOrientation:1 andNotify:NO`, no notification).
* Checked at install (and logged once if not): `UIScreen` selectors `_isExternal`, `_isMainLikeScreen`, `_updateTraits`, `_computeMetrics`, the three bounds selectors with encoding `{CGRect=...}q` (offset digits ignored), `_connectScreen` `v@:`, ivar `_interfaceOrientation` of type `q`. Receivers: all hooks and sends are on `UIScreen` instances; `_isExternal` / `_isMainLikeScreen` are in the 16.0 class dump (0x188f92f20 and 0x18982d28c, plain flag / configuration reads under the screen's unfair lock).
* Not ported on purpose: the thunk split `_setInterfaceOrientation:andNotify:` (no 16.0 caller needs `notify:NO` except `_connectScreen`, done above), the `screenBoundsIgnoresSceneOrientation` accessors (unused in 16.2, see above).

### Log lines (with `Backport162.debug`)
`hooked -[UIScreen _boundsForInterfaceOrientation:]` etc. at launch of every app; `U1 <selector>: main-like external screen 0x... , orientation N not applied to the bounds (16.2)` once per process; `U1 _connectScreen: main-like external screen 0x... put at portrait without notification (16.2)`. Always (no debug needed): `skip hook -[UIScreen ...]: ...` / `UIScreen ivar _interfaceOrientation ...` when a piece was skipped.

### Test (plain words)
Install, relaunch the app. Stage Manager on, monitor connected as extended display, open a landscape capable app (Notes, Files, Safari) in a window on the iPad, then three dots menu > Move to display. The window on the monitor must be laid out horizontally (landscape content, `UIScreen.bounds` wider than tall; the status bar and keyboard on the monitor are horizontal too). Move it back and forth, rotate the iPad while it is on the monitor: the monitor window must stay horizontal. A/B: create `/var/jb/tmp/Backport162.off.uik_screenbounds` and relaunch the app (hooks check the file once a second, so it also works live) to get the old behaviour back.

### Unproven
That `_isMainLikeScreen` is YES for the app-side UIScreen of the extended display (inferred from AV.x / 16.2 SpringBoard `setUIKitMainLike`; if it is NO the hooks never act: the debug line `U1 ...` never appears). That Move to display really reaches `_setInterfaceOrientation:` with 3 / 4 through the paths listed. Whether other causes of a vertical window remain on the SpringBoard side (scene frame / orientation settings: Z2Orient* and P1* work).
