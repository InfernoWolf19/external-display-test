# Group 4 (external display lifecycle): findings so far

Build under test: 20A8372 (16.0). Reference: 20C65 (16.2). Addresses are 16.0 / 16.2 vm addresses.

## 1. Display configuration transform (mode / scale / size)

`-[SBSceneHostingDisplayController transformDisplayConfiguration:withBuilder:]` 0x1c5f46bf8 / 0x1c73bb2b8.

* 16.0: a thin pass-through. It calls the policy's `displayController:transformDisplayConfiguration:withBuilder:`.
  `-[SBSystemShellExtendedDisplayControllerPolicy displayController:transformDisplayConfiguration:withBuilder:]` (0x1c633981c)
  then does the sizing: `pixel = _preferredSizeInPixelsForTargetCADisplay:`, `point = _preferredSizeInPointsForTargetCADisplay:`,
  `contentsScale = _preferredContentsScale`, `mode = [display preferredModeWithCriteria:]`.
  Size = one uniform scale (from `logicalScaleForDisplayScale:`) x mode width/height. No clamp in this path.
  The controller's own `_preferredLogicalScale` (0x1c5f48360) does clamp to `CADisplay` min/max logical scale, but that
  value is not used by the transform.
* 16.2: the controller does the work. The policy returns a new `SBSceneHostingDisplayPreferences`
  (`displayPreferencesForDisplayController:`, policy 0x1c77dd034): `{displayConfigurationRequest, logicalScale (w,h), contentsScale, CADisplayModeCriteria, keepOtherModes}`.
  Transform:
  1. `mode = [CADisplay preferredModeWithCriteria:prefs.CADisplayModeCriteria]`; W,H = mode width/height.
  2. If `displayType != 2`: `lsX = clamp(prefs.logicalScale.width, display.minimumLogicalScale, display.maximumLogicalScale)`,
     same for `lsY` with `.height`. Else both 1.0.
  3. `pixel = (lsX*W, lsY*H)`, `cs = prefs.contentsScale`, `point = pixel/cs`.
  4. `mode' = [currentMode _copyWithOverrideSize:point scale:cs]`; `setCurrentMode:mode' preferredMode:mode' otherModes:(keepOtherModes ? availableModes minus preferred/current : nil)`.
  5. `setPixelSize:pixel nativeBounds:(0,0,pixel) bounds:(0,0,point)`; overscan unchanged from 16.0.
* Net behavioural change: per-axis clamp of the logical scale to the monitor's supported range, a criteria-based mode
  choice shared with `_ensureCADisplayUpToDate:completion:` (also changed, 0x1c5f48424 / 0x1c73bce50), and optional
  retention of the other modes. No user-visible symptom identified yet.

## 2. Scene auto-hosting on the external display

`-[SBSystemShellExternalDisplaySceneManager _shouldAutoHostScene:]` 0x1c63ae320 / 0x1c7858710.

* 16.0: `YES` if `!scene.clientProcess.isApplicationProcess || scene.clientProcess.isCurrentProcess`, else `NO`.
* 16.2 adds a first gate: `if (![UIKeyboard usesInputSystemUI] && [_UIKeyboardArbiter_SceneIdentifier isEqualToString:scene.identifier]) return NO;`
  i.e. the keyboard arbiter scene is not auto-hosted on the external display when the input-system-UI path is off.
* Portable as a simple hook (both `+[UIKeyboard usesInputSystemUI]` and the symbol exist in 16.0).

## 3. Window scene disconnect

`-[SBExternalDisplayWindowSceneDelegate sceneDidDisconnect:]` 0x1c5fed4f8 / 0x1c746826c.

* 16.2 additionally: suppresses keyboard focus evaluation for the display while it tears down
  (`[[SBWorkspaceKeyboardFocusController ...] suppressKeyboardFocusEvaluationForReason:]`, a new 16.2-only API, returns an assertion),
  sets `SBWindowScene.invalidating = YES` (new ivar/API), and notifies the new `SBMultiDisplayUserInteractionCoordinator`
  with `windowSceneDidDisconnect:`.
* Not portable as a one-method hook: needs the focus-suppression mechanism and the coordinator class.

## 4. Smaller items still to read

SBDisplayManager `displayMonitor:didConnectIdentity:withConfiguration:` (346 -> 88 insns, connect path moved to the provider),
SBExternalDisplayService `initWithDisplayManager:` (78 -> 2), `setDisplayMirroringEnabled:forDisplay:`,
SBExternalDisplayCoverSheetController (click-to-wake, visibility notification), SBNonInteractiveDisplaySceneManager
suspended-under-lock (+15 methods), SBLockedPointerManager (14 methods).
