# Keyboard / floating dock collision (build 07f50ba): audit 0.7.2

Report: with a windowed app (Reynard, Stage Manager) the on-screen keyboard rises and the floating dock is drawn over the lower keyboard rows (keyboard "behind" the dock) and shows up while the
keyboard is visible; the window bottom edge stays under the keyboard. Evidence: RPReplay_Final1791818343.mp4 (frames: dock hidden while the keyboard is fully up in most frames, dock
over the keyboard bottom row while it slides in / out, compose box of the window covered by the keyboard) and Backport162.log (1d582193; `hosted keyboard window ... SHOWING/HIDING` bursts
around app activation, no dock or keyboard diagnostics in the log).
Pointer reveal of the strip: not a bug (hover at the left edge is the 16.2 reveal), dropped from the 0.7.1 residuals.

## Findings

| # | where | class | finding | fix |
|---|---|---|---|---|
| K1 | `SBFluidSwitcherViewController -_configureApplicationAndTransientOverlayDockBehaviorAssertionsForContext:` (16.0 0x1c5fc8890, 16.2 0x1c74414e4) | (d) invented/16.0 value instead of the 16.2 one | HIGH (device) | see analysis A | G1D.x group `G1D_DockHidden` (switch `g1d_dockhidden`): after the 16.0 body, a level 5 in-app hidden assertion is replaced by the 16.2 one (progress 0, animated, gesture possible, level 9, reason "in app") |

## Analysis

### A. Why the dock stays over the keyboard (dock hidden assertion level)
* The floating dock controller keeps its behaviour assertions in 13 level slots. `-_deriveActiveAssertion:dockProgress:` (16.2 0x1c76ea47c, 16.0 0x1c6254e44) walks the levels 0..12 and takes the HIGHEST
  non-empty level; inside a level the LAST added assertion defines the progress.
* Visible dock: `-_updateFloatingDockBehaviorAssertion` (16.0 0x1c5fe0a84 and 16.2 0x1c745a058 are the same code: queries `wantsDockBehaviorAssertion`, `dockUpdateMode`, `dockProgress` of the root modifier, builds
  `initWithFloatingDockController:visibleProgress:animated:gesturePossible:atLevel:reason:` with `animated = dockUpdateMode > 2`, gesturePossible NO, **level 9**). Our Stage Manager floor answers
  `wantsDockBehaviorAssertion = !shouldConfigureInAppDockHiddenAssertion` (16.2 0x1c75c411c), progress 1.0, mode 3 (G1C.x), so a progress 1 / level 9 assertion exists while the dock is wanted.
* Hidden dock: 16.2 `-_configureApplicationAndTransientOverlayDockBehaviorAssertionsForContext:` (called on every keyboard visibility change via `_updateSoftwareKeyboardVisibleWithKeyboardShowing:`, on transition begin / end and
  after every event) asks ONLY `shouldConfigureInAppDockHiddenAssertion` and, when YES and no in-app assertion exists, creates the hidden assertion: progress 0, animated YES, gesturePossible YES, **level 9**, reason
  "in app"; when it turns NO the assertion is invalidated. Being added later than the visible one at the same level it wins.
* The 16.0 body (still running, not replaced by G1C) does the same thing but at **level 5** (0x1c5fc89f8..0x1c5fc8a10: `movi d0,#0`, `w5 = 5`) and, for Stage Manager with an open dock folder, an extra over-folder branch that 16.2 dropped.
  Level 5 is outranked by the level 9 visible assertion, so whenever the hidden condition turned YES between two events (software keyboard shown, a window covering the dock, `prefersDockHidden`) the dock stayed
  presented until the next event invalidated the visible assertion, and it came back over the sliding keyboard on hide. Both the "dock over the keyboard rows" and "dock shows while the keyboard is visible" frames follow from this.
* Window levels checked (not the cause): the Medusa hosted keyboard window is base + 5 + 15 (16.0 0x1c60ff478, 16.2 0x1c75846dc, identical), the floating dock window is base + 5 + 20 (16.0 0x1c5e5b6b0, 16.2 0x1c72cdf1c,
  identical): the dock window is above the keyboard window in 16.2 as well, the dock is only supposed to be hidden while the keyboard is up. No in-app dock window level assertion exists in either version for the Stage Manager floor
  (`wantsDockWindowLevelAssertion` is NO along the chain), so there is nothing to port for z-order. The `newMedusaHostedKeyboardWindowLevelAssertion...` hook (CFRetain from the 0.7.1 audit) is only reached by
  Spotlight (`viewDidAppear:`) and `SBModalLibraryController _evaluateKeyboardWindowLevelAssertion` (both 16.0 and 16.2 callers), it does not influence the dock / keyboard order.
* Verified unchanged: `isSoftwareKeyboardVisible` (VC, 16.0 0x1c5fbf35c = 16.2 0x1c74379bc), `_updateSoftwareKeyboardVisibleWithKeyboardShowing:` (16.0 0x1c5fd40b4 = 16.2 0x1c744d174, `!isInHardwareKeyboardMode` when no UI
  position is known), `_keyboardWillShow/Hide/DidUIPosition` and `_handleKeyboardFrameWillChange:` are the same code. Our restored `shouldConfigureInAppDockHiddenAssertion` (G1C_FS_DockHidden) matches 16.2 0x1c75c405c
  instruction by instruction (keyboard visible -> YES; `containerViewBounds.height - boundingBox.height < floatingDockHeight + floatingDockViewTopMargin` -> YES; else `prefersDockHidden`). `G1C_FS_DockVisible`
  (the 16.0-only visible query, used for the over-folder branch) keeps the keyboard term.

### B. Hosted keyboard window SHOWING / HIDING bursts
`updateMedusaHostedKeyboardWindowForScene:isForeground:` (G3B.x) was re-checked against 16.2 0x1c76275f4 branch by branch: display identity filter, host lookup (token, keyboard proxy layers of the external foreground handles, identifier),
`hostFg && (presentedLayerTypes & ~2) == 0` -> Medusa and foreground; host == system app -> not Medusa, foreground; else Stage Manager + `enhancedWindowingEnabled` + `supportsChamoisSceneResizing` -> Medusa (foreground unchanged), anything else
-> not Medusa, not foreground; the PiP override; the window creation and `setHidden:`. Identical. The bursts happen around app activation (home <-> app, keyboard host scene changes between handles, so the host is briefly unknown and the
result is HIDING) and each is a full re-evaluation by a different 16.0 caller; the decision function itself has no 16.0/16.2 difference, so no change was made. `shouldKeyboardBeWindowSizedForHostWithIdentity:` returns NO for resizable
Stage Manager apps (YES only for non-resizable apps in the enhanced-windowing mode); its only caller is the 16.2 keyboard arbiter (UIKit), absent from the 16.0 UIKit running in the apps and in SpringBoard, so it cannot affect this behaviour.

### C. Window bottom edge under the keyboard
No SpringBoard code of 16.2 moves or resizes a Stage Manager window for the keyboard: the only consumers of `keyboardHeight` are the separator view and `_shouldSceneResizeGesture:receiveTouch:` (identical in both
versions), and the only new 16.2 keyboard-adjustment string (`SBKeyboardAdjustmentAnimationReason`, 0x1e18dbec0) is used only by the Spotlight view controller. The window keeps its frame; avoiding the keyboard is done by the
app through UIKit (keyboard frame in window coordinates, layout guide), i.e. by the 16.0 UIKit of the app process. Not resolvable in the SpringBoard tweak; to be checked on device with a native UIKit app (text field near the bottom
of a windowed app) versus the web view of Reynard (WebKit has its own avoidance).

## Test list
1. Windowed app, raise the keyboard (on-screen), check: dock disappears with the keyboard, never drawn over the keyboard; dismiss the keyboard: dock returns once (turn on the debug log to see the `dock: in-app hidden assertion level 5 -> 9` line).
2. Open a window so that it covers the dock area: the dock must hide and come back when it is moved away.
3. App activation from the home screen with the keyboard open (the SHOWING / HIDING bursts): keyboard stays in front of the app window.
4. Native UIKit app in a window with a text field at the bottom: does the content lift (item C).
