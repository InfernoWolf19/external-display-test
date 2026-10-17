# ADDWINDOW-GLITCH-0.7.7: stale tilted card behind the windows after "Add Another Window" > pick an app

Status: cause NOT determined. The evidence that came with the report does not contain the flow (section 2), so this build only adds diagnostics (`G2I.x`, switch
`g2i_addwindiag`, writes with `Backport162.debug` only, changes no behaviour). No speculative hook was added (user rule: faithful port, no guessed fixes).
16.0 = 20A8372, 16.2 = 20C65. Evidence files: recording `cb05c277-RPReplay_Final1792263287.mp4` (1920x1342, VFR ~60 fps in motion, 11.24 s), logs
`d54ebccf-Backport162.log.1` + `6a00205b-Backport162.log` (identical to `89646064` / `84256315`), user screenshot `images/25.webp`.

## 1. What the glitch is (frame-accurate, recording time)

Flow in the recording (t = seconds in the video, 1 pt = 1.608 px):

| t | what |
|---|---|
| 0 - 1.0 | one window (Filza, "File Provider Storage") |
| 1.0 - 1.5 | title-bar menu: Zoom / Add Another Window / Minimise / Close |
| 2.0 - 3.3 | app picker: grid of WHITE cards (Files, Aidoku, Reynard, Settings+Sileo stack; NewTerm and YouTube are real snapshots in the strip column on the left); Filza peeks at the right edge |
| 3.40 | the user taps "Files": the old window slides in from the right edge, the picker cards move left, the tapped card grows |
| 3.435 - 3.52 | the picked card (blank white, no content) grows over the old window to the window frame; behind it a second, tilted card is visible at the top edge (top edge slanted) |
| 3.535 - 3.585 | the new window's content ("Downloads", Files) fades in over the blank card; the remaining picker cards fly off to the left (gone at 3.70) |
| 3.60 - 3.85 | both windows slide / grow to their final frames (Filza 24,24 761x646 pt; Files 409,24 761x786 pt) |
| **3.60 - ~4.25** | **GLITCH: a pale grey, tilted card sticks out behind both windows, static, then disappears from one frame to the next (visible at 4.2, gone at 4.3)** |
| 5.0 - 5.5 | menu on the Files window ("Unzoom", Add Another Window ...) = second add-window flow |
| 6.0 - 8.9 | second picker, this time with real snapshots in every card |
| 8.95 - 9.15 | pick of Reynard: card -> window crossfade, see 1.2 |

### 1.1 The leftover card (the one the user pinned in `25.webp`)
Frames 3.60 .. 4.20 (identical in every frame): left edge vertical at about 239 pt, rounded bottom-left corner at about (239, 727) pt, bottom edge rising to the right at about 13 degrees
(from (252, 727) to (412+, 690) pt where the Files window hides it), top edge leaving the screen at the top. It lies BEHIND both windows (lowest z). It is a full window-sized card
(>= 722 pt tall, i.e. the height of a 761x786 window, not a strip-sized card) carrying a perspective rotation about the vertical axis (left edge vertical, top and bottom edges converge towards the
right): the signature of the strip / pile card transform (`perspective` 2000 in the `[defsize]` log lines, `rotationAngleForIndex:`), applied to a card that has the size of a window.
It does not move between 3.7 and 4.2, so it is a laid-out state, not an animation in flight; it is removed in one step at about 4.25 s (the length of the transition plus its spring tail).
Reference geometry: the default centred position of a 761x786 window on the 1194 pt wide screen is x = (1194 - 761) / 2 = 216.5 pt, which is where Reynard sits in the later stage (log
`sceneID:com.minh-ton.Reynard-default ... center: {0.5, 0.5}`); the sliver's left edge (239 pt) is what that position gives after a perspective rotation. NOT proven that this is the item.

### 1.2 Second glitch seen in the same recording (probably what the coordinator called the "ghost"), 8.98 - 9.15 s
Second pick (Reynard). The picked card (a snapshot of Reynard) grows to the window frame while the live window content of Reynard is already shown: for about 0.17 s (frames
9.011, 9.045, 9.078, 9.111, 9.145) two copies of the page ("Claude Code" web page) are visible, one at the card's scale and one at window size, plus the Files and Filza windows seen through them
(card alpha < 1 during the zoom). Doubled content = the card's snapshot and the live content are both on screen during the card -> window crossfade. No leftover card follows this pick (no
sliver after 9.2 s). Not analysed further (stock crossfade of `SBFluidSwitcherItemContainer` snapshot / live content, nothing in this build changes it); the diagnostics below dump it as well.

### 1.3 Blank white cards
The first picker (2.0 - 3.4 s) shows white cards without snapshots, the second picker (6 - 8.9 s) shows real snapshots. Same code path, so it is the snapshot cache at the time (the
apps had no cached snapshot yet), not a layout defect. Not the glitch the user pinned.

## 2. The logs do not contain the flow

* Recording `cb05c277` is named after its END: `1792263287` = Sat 17 Oct 2026 18:54:47 UTC = 19:54:47 in the log time zone (container `creation_time` 18:54:47Z, the status bar shows 19:54).
  It therefore ran 19:54:36 .. 19:54:47.
* `d54ebccf` (`.log.1`) starts at 19:54:51.654 (the 256 KB ring file filled up within 10 s because of the verbose `exttrace` / `GLITCH VC ids` lines), `6a00205b` ends 19:55:06.431. Both recordings
  of the report (`a045f096` ended 19:49:23) ended BEFORE the first line of these logs. Neither the `[g3c] endpeek` lines, nor any `peek 1->2` / `peek 2->1` transition, nor the `GLITCH peek child`
  lines of the add-window flow are in them (the only `peek` values are `1->1`).
* What they do show (19:54:51 - 19:55:06): the state AFTER the recording (stage `primary Reynard, side Docs FF65AEEDC15F, additional side Filza`; Reynard 217,24 761x786, Files 409,24 761x786,
  Filza 24,24 761x646: the recording's last frames) and the user tapping the Filza window about every 0.5 - 1 s (`g1d: tap to bring forward`). Each tap gives the repeated "double transition" the
  coordinator noticed: an animated mode 3->3 `SBContinuousExposeAppToAppModifier` (replaced by `BP162ContinuousExposeAppToAppModifier`) phases 1 / 2 / 3, `addwin: transition end ... modes 3->3 peek 1->1`
  (our `addwin` trace in G1B.x, it logs EVERY coordinator end of transition, not only add-window ones), then phases 2 and 3 with animated=0 within 1 - 12 ms (the stock second layout pass, the
  same one as OPEN-ISSUES item 7). The `to` layout is identical to `from` in all of them, so it moves nothing. These are not the add-window flow and not the glitch.
* The `sceneID: ... size: unspecified; center: unspecified; occlusionState: unknown` attribute dumps the coordinator mentioned are not in these logs either (every dump in them has real sizes).

Consequence: the transition modifier of the add-window pick, the peek child state and the attributes of the new window have to come from a fresh log. From the OLD log 24cc0115 (build 0.7.3, a one-window
pick, 03:13:45) the pick is `modes 2->3 peek 2->1 animated=1`, main transition `SBContinuousExposeSwitcherToAppModifier` replaced by `BP162ContinuousExposeSwitcherToAppModifier`.

## 3. What the code does at the pick (static reading, 0.7.3 sources)

* Coordinator side: `G3C_EndPeekPick` (G3C.x, 16.2 0x1c7296020..0x1c7296f6c): picked entity -> role 1, every previous entity not already in the request -> first free role of {2,5,6,7,8,9}, peek := none,
  mode := 3 (`specs/ADDWINDOW-PICK-0.7.4.md`). The target layout holds the previous stage windows plus the picked one; the picked app's own picker card is a container of the SOURCE (picker) layout.
* Switcher side: `BP162ContinuousExposeSwitcherToAppModifier` animates picker -> stage. The peek child of the root (`SBContinuousExposePeekSwitcherModifier`, key `SBContinuousExposePeekModifierKey`) is
  only retired by our code at PHASE 3 of the pick (G1C.x `handleTransitionEvent:`, "GLITCH peek child retired", added in 130504d after log 43f88b77). Until then its content modifier (pile
  layout of the picker, `G1C_PC_Adjusted`) and the dismissal transition modifier (`G1C_BuildPeekTransition`, direction 1, created at phase 2 for an animated peek end) are in the chain.
  16.2 retires it through its own state change (`-[SBContinuousExposePeekSwitcherModifier setState:]` after the dismissal transition modifier ended, 0x1c78e5354).

## 4. Hypotheses (all unproven; each one predicts something the new diagnostics show)

* H1: the container of the picked app's picker card (an item of the `from` layout that is not in the `to` layout, because the pick created a NEW scene for Files: `sceneID:com.apple.DocumentsApp-A3C8031E-...`
  in the later log, while Reynard, picked in the second flow, is `Reynard-default`) is kept alive by the transition (16.2 `requireStripContentsInViewHierarchy` / items of the `from` layout stay until phase 3)
  and stays laid out with the pile / strip rotation until the transition ends and is then removed. Fits: only the first flow (new scene) leaves a card, the second (existing scene) does not;
  duration = transition length. Prediction: at `end+0` a container whose layout is "NOT among the switcher's appLayouts" with a rotated `layer.transform` (m12 / m34 != 0) and at `end+0.5s` it is gone.
* H2: an item of the target layout without layout attributes (`size / center unspecified`, the new window right after the add) is laid out at the default centred frame (216.5, 24, 761x786) at the lowest
  z with the strip rotation until its attributes are filled in at the first layout pass. Prediction: the `new item ... attributes in the target layout` line shows `size: unspecified; center: unspecified`
  for an item whose container frame in `p2+0` / `p2+3f` is about x 217 and has a rotated transform.
* H3: the peek child (`SBContinuousExposePeekSwitcherModifier` with its content modifier) keeps laying out a pile card for the previously peeking window until our phase 3 retirement. Prediction: the
  stack description at phase 2 still lists `SBContinuousExposePeekSwitcherModifier` / `_SBContinuousExposePeekContentSwitcherModifier`, and the card disappears within one frame of the
  `GLITCH peek child retired` line.

If H3 holds the faithful fix is to retire the peek child with its dismissal transition modifier (the 16.2 behaviour) instead of at phase 3; if H1 / H2 hold the cause is in the layout answers of the
transition modifier for items that are not in the target layout / have no attributes (16.2 `SBContinuousExposeSwitcherToAppModifier` family, G1C.x). Nothing of this is implemented.

## 5. What this build logs (debug on, `[g2i]` lines, switch `g2i_addwindiag`, kill file `<jbroot>/tmp/Backport162.off.g2i_addwindiag`)

* Wrapper on `-[SBContinuousExposeRootSwitcherModifier handleTransitionEvent:]` (G1C's hook runs inside it). For every event of an add-window flow (peek start `fromPeek` invalid -> `toPeek` valid,
  peek end = the pick, everything within 2 s after the pick, which includes the stock second non-animated pass): `flow N <peek start|peek end (pick)|within/after> event: phase animated gesture modes
  peek from= to= new items=` plus the transition / peek modifier lines of the stack description, the layout attributes of every NEW item (items of the target layout that the source layout lacks)
  as the target layout holds them, and the whole `stackDescription` before and after the handler (the transition modifier class is in it).
* Wrapper on `-[SBFluidSwitcherViewController _layoutAppLayout:roleMask:completion:]` (outermost, after G2B / G2F): first layout pass after each event that touches a layout with a new item writes
  `<tag> new window: layout idx i of n, root answers: frameForIndex scale rotationAngle anchor`, the item's role and attributes, and the item container (class, frame, bounds, centre, alpha, hidden,
  `layer.transform`, zPosition, presentation position / bounds / transform / opacity, z index in the container view, occluded-in-stage flag). Tags `p1+0`, `p2+0`, `p2+3f` (50 ms later), `p3+0`.
* At the pick's phase 3 (once): `end+0`, `end+0.5s`, `end+1.5s` dump EVERY item container still alive: those of `_visibleItemContainers` (is its layout among the switcher's `appLayouts` and at which
  index, is it a new window, z index) and every other item-container-looking subview of the same container view (`NOT in _visibleItemContainers`), plus the container view's `sublayerTransform`.
* One recording + the log of the same time (start the recording, do menu > Add Another Window > pick Files (an app that has no window yet), wait 3 s, pull the log immediately: the ring file is 256 KB and
  fills in about 10 s with `Backport162.debug` on, so stop tapping afterwards) pins the item, its transform and its owner modifier.

## 6. Unproven / not done
* Which container the leftover card is, why it lingers, whether stock 16.2 shows it (no 16.2 device).
* Everything in section 4.
* The doubled content at the second pick (1.2) is not analysed.
* The `G2I.x` code compiled only against stub headers (`clang -fsyntax-only`); CI builds it with Theos. The selectors used on the root (`frameForIndex:`, `scaleForIndex:`, `rotationAngleForIndex:`,
  `anchorPointForIndex:`), `stackDescription` (16.0 `-[SBSwitcherModifier stackDescription]` 0x1c63e8e5c), `layoutAttributesForItem:` (`-[SBAppLayout ...]` 0x1c628d6ec), `leafAppLayouts`,
  `allItems`, `_itemContainerForAppLayoutIfExists:` (0x1c5e31310) exist in 16.0; every call is guarded with `respondsToSelector:` and `@try`.
