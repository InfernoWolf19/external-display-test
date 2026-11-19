#!/usr/bin/env python3
"""gen_y42.py [name ...] : regenerates the lifted C files of the Y42+ ports (Backport162/Y42*Lift.c) from the 16.2 machine code with a2c.py (same job format as gen_y34.py; a body may list
`locals`: address -> C name of block invoke / helper bodies lifted earlier in the same file).  Kinds: 'sel=k' for a selector, 'fn:name=k' for a C function."""
import sys, os
sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import a2c

OUT = os.path.join(HERE, '..', '..')
KINDS_ALL = 'invalidate=v,addObserver:=v'      # selectors whose return kind differs between classes of the dumps: the receivers here return void
JOBS = {
 'shelf': dict(file='Y42ShelfLift.c',
  head='''// Y42ShelfLift.c : -[SBShelfLiveContentOverlayCoordinator _addOverlaysIfNeededForTransitionContext:] of iPadOS 16.2 (20C65, 0x1c798ac94 .. 0x1c798b330) and its block invoke
// 0x1c798b338, recompiled from the 16.2 machine code by tools/a2c/a2c.py (a stack block: arm64e pacda isa / pacia invoke, descriptor, one captured object).  Plain C, no ARC.
// The 16.2 init of SBShelfLiveContentOverlay (0x1c798b6b8, 84 instructions) is lifted too: the 16.0 class only has the referenceOrientation: init, the 16.2 coordinator body asks for the new selector.  Installed by Y42Shelf.x (switch y42_shelf).  Verified with tools/a2c/tests/tracecmp.py (calls, ownership events, PAC logs, block image against the Unicorn emulation).  NOT device tested.
''',
  bodies=[('162', 0x1c798b338, 0x1c798b344, 'shelfblk7', 'x,x', 'x', 'SBShelfLiveContentOverlayCoordinator', '', {}),
          ('162', 0x1c798ac94, 0x1c798b330, 'shelf162', 'x,x,x', 'v', 'SBShelfLiveContentOverlayCoordinator', '', {0x1c798b338: 'shelfblk7'}),
          ('162', 0x1c798b6b8, 0x1c798b808, 'shelfinit', 'x,x,x,d,d,x,x,x,x', 'x', 'SBShelfLiveContentOverlay', '', {})],
  tcargs=['--datasyms', 'kCAFilterBox=box'],
  tail='''
void y42_shelf_add(void *self, void *cmd, void *context) { shelf162((uint64_t)(uintptr_t)self, (uint64_t)(uintptr_t)cmd, (uint64_t)(uintptr_t)context); }
// -[SBShelfLiveContentOverlay initWithSceneHandle:referenceSize:contentOrientation:containerOrientation:livePortalView:isInsetForHomeAffordance:] 0x1c798b6b8, installed as an IMP (the ownership
// is the machine code's: self arrives +1 and is returned +1)
uint64_t y42_shelf_init(uint64_t self, uint64_t cmd, uint64_t handle, double w, double h, uint64_t contentOri, uint64_t containerOri, uint64_t portal, uint64_t inset) {
    return shelfinit(self, cmd, handle, w, h, contentOri, containerOri, portal, inset & 1);
}
const char *y42_shelf_preflight(void) { const char *m = shelf162_preflight(); return m ? m : shelfinit_preflight(); }
'''),
 'peek': dict(file='Y42PeekLift.c',
  head='''// Y42PeekLift.c : two methods of SBPeekSplitViewRoutingSwitcherModifier of iPadOS 16.2 (20C65), recompiled from the 16.2 machine code by tools/a2c/a2c.py together with their stack blocks and block invokes:
//   -responseForProposedChildResponse:childModifier:event:   0x1c74e7210 (16.0 0x1c6065a50): the 16.2 body adds itemForLayoutRole: before setPeekConfiguration:   (blocks 0x1c74e77ac, 0x1c74e7878)
//   -routingModifier:event:forModifier:                      0x1c74e7a88 (16.0 0x1c6066294): routes one more event type (0xf)                                      (blocks 0x1c74e8018, 0x1c74e8024, 0x1c74e8030, 0x1c74e8054)
// Plain C, no ARC.  Installed by Y42Peek.x (switch y42_peek).  Verified with tools/a2c/tests/tracecmp.py (calls, ownership events, PAC logs, block images).  NOT device tested.
''',
  bodies=[('162', 0x1c74e77ac, 0x1c74e7878, 'pkblk3', 'x,x', 'x', 'SBPeekSplitViewRoutingSwitcherModifier', '', {}),
          ('162', 0x1c74e7878, 0x1c74e7a88, 'pkblk4', 'x,x', 'x', 'SBPeekSplitViewRoutingSwitcherModifier', '', {}),
          ('162', 0x1c74e7210, 0x1c74e7714, 'pk1', 'x,x,x,x,x', 'x', 'SBPeekSplitViewRoutingSwitcherModifier', '', {0x1c74e77ac: 'pkblk3', 0x1c74e7878: 'pkblk4'}),
          ('162', 0x1c74e8018, 0x1c74e8024, 'pkb0', 'x,x', 'x', 'SBPeekSplitViewRoutingSwitcherModifier', '', {}),
          ('162', 0x1c74e8024, 0x1c74e8030, 'pkb1', 'x,x', 'x', 'SBPeekSplitViewRoutingSwitcherModifier', '', {}),
          ('162', 0x1c74e8030, 0x1c74e8054, 'pkb2', 'x,x', 'x', 'SBPeekSplitViewRoutingSwitcherModifier', '', {}),
          ('162', 0x1c74e8054, 0x1c74e8078, 'pkb3', 'x,x', 'x', 'SBPeekSplitViewRoutingSwitcherModifier', '', {}),
          ('162', 0x1c74e7a88, 0x1c74e8018, 'pk2', 'x,x,x,x,x', 'x', 'SBPeekSplitViewRoutingSwitcherModifier', '', {0x1c74e8018: 'pkb0', 0x1c74e8024: 'pkb1', 0x1c74e8030: 'pkb2', 0x1c74e8054: 'pkb3'})],
  tail='''
uint64_t y42_peek_response(uint64_t self, uint64_t cmd, uint64_t response, uint64_t child, uint64_t event) { return pk1(self, cmd, response, child, event); }
uint64_t y42_peek_routing(uint64_t self, uint64_t cmd, uint64_t routing, uint64_t event, uint64_t forModifier) { return pk2(self, cmd, routing, event, forModifier); }
const char *y42_peek_preflight(void) { const char *m = pk1_preflight(); return m ? m : pk2_preflight(); }
'''),
 'deck': dict(file='Y42DeckLift.c',
  head='''// Y42DeckLift.c : the app suggestion handling of the card deck switcher (SBDeckSwitcherViewController) of iPadOS 16.2 (20C65), recompiled from the 16.2 machine code by tools/a2c/a2c.py:
//   -performTransitionWithContext:animated:completion:  0x1c73151d8 (+ block invoke 0x1c77c9724)        -layoutStateTransitionCoordinator:transitionDidBeginWithTransitionContext:  0x1c77c97c0
//   -layoutStateTransitionCoordinator:transitionDidEndWithTransitionContext:  0x1c77c99cc (+ block invokes 0x1c77c9c40, 0x1c77c9c4c)          -_assertionReason 0x1c77c9e2c
//   -appSuggestionManager 0x1c77c9ecc, -setAppSuggestionManager: 0x1c77c9f00 (the weak ivar _appSuggestionManager lives in a runtime subclass, Y42Deck.x)
// Plain C, no ARC.  Installed by Y42Deck.x (switch y42_deck).  Verified with tools/a2c/tests/tracecmp.py (calls, ownership events, PAC logs, block images).  NOT device tested.
''',
  bodies=[('162', 0x1c77c9724, 0x1c77c97c0, 'dkblk1', 'x,x', 'v', 'SBDeckSwitcherViewController', '', {}),
          ('162', 0x1c73151d8, 0x1c731530c, 'dk1', 'x,x,x,x,x', 'v', 'SBDeckSwitcherViewController', '', {0x1c77c9724: 'dkblk1'}),
          ('162', 0x1c77c97c0, 0x1c77c99cc, 'dk2', 'x,x,x,x', 'v', 'SBDeckSwitcherViewController', '', {}),
          ('162', 0x1c77c9c40, 0x1c77c9c4c, 'dkblk3a', 'x,x', 'v', 'SBDeckSwitcherViewController', '', {}),
          ('162', 0x1c77c9c4c, 0x1c77c9ccc, 'dkblk3b', 'x,x', 'v', 'SBDeckSwitcherViewController', '', {}),
          ('162', 0x1c77c99cc, 0x1c77c9c40, 'dk3', 'x,x,x,x', 'v', 'SBDeckSwitcherViewController', '', {0x1c77c9c40: 'dkblk3a', 0x1c77c9c4c: 'dkblk3b'}),
          ('162', 0x1c77c9e2c, 0x1c77c9ea8, 'dkreason', 'x,x', 'x', 'SBDeckSwitcherViewController', '', {}),
          ('162', 0x1c77c9ecc, 0x1c77c9f00, 'dkget', 'x,x', 'x', 'SBDeckSwitcherViewController', '', {}),
          ('162', 0x1c77c9f00, 0x1c77c9f14, 'dkset', 'x,x,x', 'v', 'SBDeckSwitcherViewController', '', {}),
          ('162', 0x1c77c96a0, 0x1c77c9724, 'dkinval', 'x,x', 'v', 'SBDeckSwitcherViewController', '', {})],
  tail='''
void y42_deck_perform(uint64_t self, uint64_t cmd, uint64_t context, uint64_t animated, uint64_t completion) { dk1(self, cmd, context, animated & 1, completion); }
void y42_deck_begin(uint64_t self, uint64_t cmd, uint64_t coordinator, uint64_t context) { dk2(self, cmd, coordinator, context); }
void y42_deck_end(uint64_t self, uint64_t cmd, uint64_t coordinator, uint64_t context) { dk3(self, cmd, coordinator, context); }
uint64_t y42_deck_reason(uint64_t self, uint64_t cmd) { return dkreason(self, cmd); }
uint64_t y42_deck_getmanager(uint64_t self, uint64_t cmd) { return dkget(self, cmd); }
void y42_deck_setmanager(uint64_t self, uint64_t cmd, uint64_t manager) { dkset(self, cmd, manager); }
void y42_deck_invalidate(uint64_t self, uint64_t cmd) { dkinval(self, cmd); }
const char *y42_deck_preflight(void) {
    const char *m = dk1_preflight(); if (m) return m;
    m = dk2_preflight(); if (m) return m;
    m = dk3_preflight(); if (m) return m;
    m = dkreason_preflight(); if (m) return m;
    if ((m = dkget_preflight())) return m; if ((m = dkset_preflight())) return m; return dkinval_preflight();
}
'''),
 'traits': dict(file='Y42TraitsLift.c',
  head='''// Y42TraitsLift.c : the orientation request handling of the traits scene participant of iPadOS 16.2 (20C65), recompiled from the 16.2 machine code by tools/a2c/a2c.py:
//   SBTraitsSceneOrientationRequestAssistant (a class that only exists in 16.2, it replaces the alter ego of SBTraitsSceneParticipantDelegate): -initWithTraitsSceneDelegate:errorDomain: 0x1c78246e0, -invalidate
//   0x1c782476c, -checkValidityAgainstUpdateReasons: 0x1c7824818, -setUpForTransitionContextIfNeeded: 0x1c7824a00, -_startSceneOrientationRequestWithDesiredOrientations:error: 0x1c7824cfc,
//   -_performCoalescedBroadcastArbitrationUpdateWithReason: 0x1c7824f3c, -traitsDelegate 0x1c7825078, -errorDomain 0x1c78250a4, -.cxx_destruct 0x1c78250d0 and the blocks 0x1c78249ac 0x1c7824cd8 0x1c7825008;
//   SBTraitsSceneParticipantDelegate rows: -_supportedOrientations 0x1c77736b8, -actuateOrientationSettingsWithContext: 0x1c7773c68, -needsActuationForUpdateReasons: 0x1c77743e4,
//   -scene:didUpdateClientSettingsWithDiff:oldClientSettings:transitionContext: 0x1c7774a98, -_resetToInitialState 0x1c77750bc, -didChangeSettingsForParticipant:context: 0x1c77752c8 with their blocks and the
//   16.2 C function SBTraitsSceneParticipantDelegateOrientationChangeInspector 0x1c7772d24 (+ its cold path 0x1c7a08fd0) that is not exported by 16.0.
// Plain C, no ARC.  Installed by Y42Traits.x (switch y42_traits).  Verified with tools/a2c/tests/tracecmp.py (calls, ownership events, PAC logs, block images).  NOT device tested.
''',
  tcargs=['--safemem', '--datasyms', 'NSLocalizedDescriptionKey=NSLocalizedDescription'],
  tcbody={'tri': ['--ptrargs', '2,3,4'], 'tdneedb': ['--ptrargs', '3'], 'asstart': ['--ptrargs', '3']},
  bodies=[
          ('162', 0x1c7a08fd0, 0x1c7a08ffc, 'tricold', 'x', 'v', 'SBTraitsSceneParticipantDelegate', '', {}),
          ('162', 0x1c7772d24, 0x1c7772f48, 'tri', 'x,x,x,x,x', 'x', 'SBTraitsSceneParticipantDelegate', '', {0x1c7a08fd0: 'tricold'}),
          ('162', 0x1c77736b8, 0x1c7773768, 'tdsupp', 'x,x', 'x', 'SBTraitsSceneParticipantDelegate', '', {}),
          ('162', 0x1c7773f0c, 0x1c7773fac, 'tdactb1', 'x,x,x', 'v', 'SBTraitsSceneParticipantDelegate', '', {}),
          ('162', 0x1c7773fac, 0x1c7773fc4, 'tdactb2', 'x,x', 'v', 'SBTraitsSceneParticipantDelegate', '', {}),
          ('162', 0x1c7773c68, 0x1c7773f0c, 'tdact', 'x,x,x', 'v', 'SBTraitsSceneParticipantDelegate', '', {0x1c7773f0c: 'tdactb1', 0x1c7773fac: 'tdactb2', 0x1c7772d24: 'tri'}),
          ('162', 0x1c7774600, 0x1c7774704, 'tdneedb', 'x,x,x,x', 'v', 'SBTraitsSceneParticipantDelegate', '', {}),
          ('162', 0x1c77743e4, 0x1c7774600, 'tdneed', 'x,x,x', 'x', 'SBTraitsSceneParticipantDelegate', '', {0x1c7774600: 'tdneedb'}),
          ('162', 0x1c7774d28, 0x1c7774d78, 'tdscenb', 'x,x', 'v', 'SBTraitsSceneParticipantDelegate', '', {}),
          ('162', 0x1c7774a98, 0x1c7774d28, 'tdscene', 'x,x,x,x,x,x', 'v', 'SBTraitsSceneParticipantDelegate', '', {0x1c7774d28: 'tdscenb', 0x1c7772d24: 'tri'}),
          ('162', 0x1c77750bc, 0x1c7775158, 'tdreset', 'x,x', 'v', 'SBTraitsSceneParticipantDelegate', '', {}),
          ('162', 0x1c77752c8, 0x1c77754bc, 'tddid', 'x,x,x,x', 'v', 'SBTraitsSceneParticipantDelegate', '', {0x1c7772d24: 'tri'}),
          ('162', 0x1c78246e0, 0x1c782476c, 'asinit', 'x,x,x,x', 'x', 'SBTraitsSceneOrientationRequestAssistant', '', {}),
          ('162', 0x1c782476c, 0x1c7824818, 'asinval', 'x,x', 'v', 'SBTraitsSceneOrientationRequestAssistant', '', {}),
          ('162', 0x1c78249ac, 0x1c7824a00, 'ascheckb', 'x', 'v', 'SBTraitsSceneOrientationRequestAssistant', '', {}),
          ('162', 0x1c7824818, 0x1c78249ac, 'ascheck', 'x,x,x', 'v', 'SBTraitsSceneOrientationRequestAssistant', '', {0x1c78249ac: 'ascheckb'}),
          ('162', 0x1c7824cd8, 0x1c7824cfc, 'assetb', 'x,x', 'v', 'SBTraitsSceneOrientationRequestAssistant', '', {}),
          ('162', 0x1c7824a00, 0x1c7824cd8, 'asset', 'x,x,x', 'v', 'SBTraitsSceneOrientationRequestAssistant', '', {0x1c7824cd8: 'assetb'}),
          ('162', 0x1c7824cfc, 0x1c7824f3c, 'asstart', 'x,x,x,x', 'v', 'SBTraitsSceneOrientationRequestAssistant', '', {}),
          ('162', 0x1c7825008, 0x1c7825078, 'asperb', 'x,x', 'v', 'SBTraitsSceneOrientationRequestAssistant', '', {}),
          ('162', 0x1c7824f3c, 0x1c7825008, 'asper', 'x,x,x', 'v', 'SBTraitsSceneOrientationRequestAssistant', '', {0x1c7825008: 'asperb'}),
          ('162', 0x1c7825078, 0x1c78250a4, 'asdel', 'x,x', 'x', 'SBTraitsSceneOrientationRequestAssistant', '', {}),
          ('162', 0x1c78250a4, 0x1c78250d0, 'asdom', 'x,x', 'x', 'SBTraitsSceneOrientationRequestAssistant', '', {}),
          ('162', 0x1c78250d0, 0x1c782510c, 'asdestr', 'x,x', 'v', 'SBTraitsSceneOrientationRequestAssistant', '', {}),
          ('162', 0x1c77754bc, 0x1c7775574, 'tdwill', 'x,x,x', 'v', 'SBTraitsSceneParticipantDelegate', '', {})],
  tail='''
uint64_t y42_as_init(uint64_t self, uint64_t cmd, uint64_t delegate, uint64_t domain) { return asinit(self, cmd, delegate, domain); }
void y42_as_invalidate(uint64_t self, uint64_t cmd) { asinval(self, cmd); }
void y42_as_check(uint64_t self, uint64_t cmd, uint64_t reasons) { ascheck(self, cmd, reasons); }
void y42_as_setup(uint64_t self, uint64_t cmd, uint64_t context) { asset(self, cmd, context); }
void y42_as_start(uint64_t self, uint64_t cmd, uint64_t orientations, uint64_t errorOut) { asstart(self, cmd, orientations, errorOut); }
void y42_as_perform(uint64_t self, uint64_t cmd, uint64_t reason) { asper(self, cmd, reason); }
uint64_t y42_as_delegate(uint64_t self, uint64_t cmd) { return asdel(self, cmd); }
uint64_t y42_as_errordomain(uint64_t self, uint64_t cmd) { return asdom(self, cmd); }
void y42_as_destruct(uint64_t self, uint64_t cmd) { asdestr(self, cmd); }
uint64_t y42_td_supported(uint64_t self, uint64_t cmd) { return tdsupp(self, cmd); }
void y42_td_actuate(uint64_t self, uint64_t cmd, uint64_t context) { tdact(self, cmd, context); }
uint64_t y42_td_needs(uint64_t self, uint64_t cmd, uint64_t reasons) { return tdneed(self, cmd, reasons) & 1; }
void y42_td_scene(uint64_t self, uint64_t cmd, uint64_t scene, uint64_t diff, uint64_t old, uint64_t context) { tdscene(self, cmd, scene, diff, old, context); }
void y42_td_reset(uint64_t self, uint64_t cmd) { tdreset(self, cmd); }
void y42_td_didchange(uint64_t self, uint64_t cmd, uint64_t participant, uint64_t context) { tddid(self, cmd, participant, context); }
void y42_td_willinvalidate(uint64_t self, uint64_t cmd, uint64_t participant) { tdwill(self, cmd, participant); }
const char *y42_traits_preflight(void) {
    const char *m;
    if ((m = asinit_preflight())) return m; if ((m = asinval_preflight())) return m; if ((m = ascheck_preflight())) return m; if ((m = asset_preflight())) return m;
    if ((m = asstart_preflight())) return m; if ((m = asper_preflight())) return m; if ((m = asdel_preflight())) return m; if ((m = asdom_preflight())) return m; if ((m = asdestr_preflight())) return m;
    if ((m = tdsupp_preflight())) return m; if ((m = tdact_preflight())) return m; if ((m = tdneed_preflight())) return m; if ((m = tdscene_preflight())) return m;
    if ((m = tdreset_preflight())) return m; if ((m = tddid_preflight())) return m; return tdwill_preflight();
}
'''),
 'scenevc': dict(file='Y42SceneVCLift.c',
  head='''// Y42SceneVCLift.c : -[SBSceneViewController viewDidLoad] of iPadOS 16.2 (20C65, 0x1c72e7db8 .. 0x1c72e8060, 170 instructions), recompiled from the 16.2 machine code by tools/a2c/a2c.py: the scene view is created with
// newSceneViewWithReferenceSize:contentOrientation:containerOrientation:hostRequester: of the scene handle (16.0 asked for orientation: only).  Plain C, no ARC.  Installed by Y42SceneVC.x (switch y42_scenevc).
// Verified with tools/a2c/tests/tracecmp.py (calls, ownership events).  NOT device tested.
''',
  tcargs=['--safemem'],
  bodies=[('162', 0x1c72e7db8, 0x1c72e8060, 'svcvdl', 'x,x', 'v', 'SBSceneViewController', '', {})],
  tail='''
void y42_svc_viewdidload(uint64_t self, uint64_t cmd) { svcvdl(self, cmd); }
const char *y42_scenevc_preflight(void) { return svcvdl_preflight(); }
'''),
 'resize': dict(file='Y42ResizeLift.c',
  head='''// Y42ResizeLift.c : the item resize gesture modifier of iPadOS 16.2 (20C65), recompiled from the 16.2 machine code by tools/a2c/a2c.py:
//   SBItemResizeGestureSwitcherModifier  -handleGestureEvent: 0x1c76be31c, -_responseForGestureUpdateAtGestureEnd: 0x1c76be610 (+ block invoke 0x1c76bed0c), -_responseForSceneSizeUpdateToSize:center:sceneUpdatesOnly:
//   0x1c76bed98, -_initialScaledFrameInScreenCoordinatesForSelectedDisplayItemInAppLayout: 0x1c76bfa80, -_anyItemExceedsWidthThresholdToHideStrip 0x1c76bfd40.
// Plain C, no ARC.  Installed by Y42Resize.x (switch y42_resize).  Verified with tools/a2c/tests/tracecmp.py (calls, ownership events, PAC logs, block images).  NOT device tested.
''',
  bodies=[('162', 0x1c76bed0c, 0x1c76bed98, 'rsblk', 'x,d,d', 'size', 'SBItemResizeGestureSwitcherModifier', 'fn:BSUIConstrainValueToIntervalWithRubberBand=d,fn:SBRectWithSize=rect,frameForIndex:=rect,locationInContainerView=size,normalizedPointForPoint:inBounds:=size,fn:SBDisplayItemSizingPolicyAllowingSmallestSize=x,fn:SBDisplayItemSizingPolicyAllowingLargestSize=x,fn:BSFloatGreaterThanFloat=x,fn:SBDisplayItemAttributedSizeInfer=m56,fn:UIRectCenteredAboutPoint=rect', {}),
          ('162', 0x1c76be610, 0x1c76bed0c, 'rsend', 'x,x,x', 'x', 'SBItemResizeGestureSwitcherModifier', 'fn:BSUIConstrainValueToIntervalWithRubberBand=d,fn:SBRectWithSize=rect,frameForIndex:=rect,locationInContainerView=size,normalizedPointForPoint:inBounds:=size,fn:SBDisplayItemSizingPolicyAllowingSmallestSize=x,fn:SBDisplayItemSizingPolicyAllowingLargestSize=x,fn:BSFloatGreaterThanFloat=x,fn:SBDisplayItemAttributedSizeInfer=m56,fn:UIRectCenteredAboutPoint=rect', {0x1c76bed0c: 'rsblk'}),
          ('162', 0x1c76be31c, 0x1c76be610, 'rsevent', 'x,x,x', 'x', 'SBItemResizeGestureSwitcherModifier', 'fn:BSUIConstrainValueToIntervalWithRubberBand=d,fn:SBRectWithSize=rect,frameForIndex:=rect,locationInContainerView=size,normalizedPointForPoint:inBounds:=size,fn:SBDisplayItemSizingPolicyAllowingSmallestSize=x,fn:SBDisplayItemSizingPolicyAllowingLargestSize=x,fn:BSFloatGreaterThanFloat=x,fn:SBDisplayItemAttributedSizeInfer=m56,fn:UIRectCenteredAboutPoint=rect', {}),
          ('162', 0x1c76bed98, 0x1c76bf134, 'rsscene', 'x,x,d,d,d,d,x', 'x', 'SBItemResizeGestureSwitcherModifier', 'fn:BSUIConstrainValueToIntervalWithRubberBand=d,fn:SBRectWithSize=rect,frameForIndex:=rect,locationInContainerView=size,normalizedPointForPoint:inBounds:=size,fn:SBDisplayItemSizingPolicyAllowingSmallestSize=x,fn:SBDisplayItemSizingPolicyAllowingLargestSize=x,fn:BSFloatGreaterThanFloat=x,fn:SBDisplayItemAttributedSizeInfer=m56,fn:UIRectCenteredAboutPoint=rect', {}),
          ('162', 0x1c76bfa80, 0x1c76bfbe8, 'rsinit', 'x,x,x', 'rect', 'SBItemResizeGestureSwitcherModifier', 'fn:BSUIConstrainValueToIntervalWithRubberBand=d,fn:SBRectWithSize=rect,frameForIndex:=rect,locationInContainerView=size,normalizedPointForPoint:inBounds:=size,fn:SBDisplayItemSizingPolicyAllowingSmallestSize=x,fn:SBDisplayItemSizingPolicyAllowingLargestSize=x,fn:BSFloatGreaterThanFloat=x,fn:SBDisplayItemAttributedSizeInfer=m56,fn:UIRectCenteredAboutPoint=rect', {}),
          ('162', 0x1c76bfd40, 0x1c76bfd84, 'rsany', 'x,x', 'x', 'SBItemResizeGestureSwitcherModifier', 'fn:BSUIConstrainValueToIntervalWithRubberBand=d,fn:SBRectWithSize=rect,frameForIndex:=rect,locationInContainerView=size,normalizedPointForPoint:inBounds:=size,fn:SBDisplayItemSizingPolicyAllowingSmallestSize=x,fn:SBDisplayItemSizingPolicyAllowingLargestSize=x,fn:BSFloatGreaterThanFloat=x,fn:SBDisplayItemAttributedSizeInfer=m56,fn:UIRectCenteredAboutPoint=rect', {})],
  tail='''
uint64_t y42_rs_event(uint64_t self, uint64_t cmd, uint64_t event) { return rsevent(self, cmd, event); }
uint64_t y42_rs_end(uint64_t self, uint64_t cmd, uint64_t end) { return rsend(self, cmd, end & 1); }
uint64_t y42_rs_scene(uint64_t self, uint64_t cmd, double w, double h, double cx, double cy, uint64_t only) { return rsscene(self, cmd, w, h, cx, cy, only & 1); }
uint64_t y42_rs_any(uint64_t self, uint64_t cmd) { return rsany(self, cmd) & 1; }
void y42_rs_init(double out[4], uint64_t self, uint64_t cmd, uint64_t layout) { LiftRect r = rsinit(self, cmd, layout); out[0] = r.x; out[1] = r.y; out[2] = r.w; out[3] = r.h; }
const char *y42_resize_preflight(void) {
    const char *m;
    if ((m = rsend_preflight())) return m; if ((m = rsevent_preflight())) return m; if ((m = rsscene_preflight())) return m; if ((m = rsinit_preflight())) return m; return rsany_preflight();
}
'''),
 'sceneview': dict(file='Y42SceneViewLift.c',
  head='''// Y42SceneViewLift.c : the 16.2 init chain of the scene views of iPadOS 16.2 (20C65), recompiled from the 16.2 machine code by tools/a2c/a2c.py:
//   -[SBDeviceApplicationSceneView initWithSceneHandle:referenceSize:contentOrientation:containerOrientation:hostRequester:]  0x1c773c654 (+ three block invokes 0x1c773caf4, 0x1c773cc40, 0x1c773ccb8)
//   -[SBApplicationSceneView initWithSceneHandle:referenceSize:contentOrientation:containerOrientation:hostRequester:]         0x1c7962f44
//   SpringBoardUI (SBSceneView): -initWithSceneHandle:referenceSize:contentOrientation:containerOrientation:hostRequester: 0x1f2cca72c, -invalidate 0x1f2cc5f28, -sceneHandle:didUpdateContentState: 0x1f2ccb3e0,
//   -_configureLiveHostView 0x1f2ccb470 (16.0 name _configureHostView)
// Plain C, no ARC.  Installed by Y42SceneView.x (switch y42_sceneview).  Verified with tools/a2c/tests/tracecmp.py (calls, ownership events, PAC logs, block images).  NOT device tested.
''',
  tcargs=['--safemem'],
  bodies=[('162', 0x1f2cca72c, 0x1f2cca9f0, 'sbsinit', 'x,x,x,d,d,x,x,x', 'x', 'SBSceneView', '', {}),
          ('162', 0x1f2cc5f28, 0x1f2cc6070, 'sbsinval', 'x,x', 'v', 'SBSceneView', '', {}),
          ('162', 0x1f2ccb3e0, 0x1f2ccb428, 'sbsstate', 'x,x,x,x', 'v', 'SBSceneView', '', {}),
          ('162', 0x1f2ccb470, 0x1f2ccb588, 'sbslive', 'x,x', 'v', 'SBSceneView', '', {}),
          ('162', 0x1c7962f44, 0x1c7963004, 'asvinit', 'x,x,x,d,d,x,x,x', 'x', 'SBApplicationSceneView', '', {}),
          ('162', 0x1c773caf4, 0x1c773cc40, 'dsvb0', 'x,x,x', 'v', 'SBDeviceApplicationSceneView', '', {}),
          ('162', 0x1c773cc40, 0x1c773ccb8, 'dsvb1', 'x,x,x,x', 'v', 'SBDeviceApplicationSceneView', '', {}),
          ('162', 0x1c773ccb8, 0x1c773cd30, 'dsvb2', 'x,x,x,x', 'v', 'SBDeviceApplicationSceneView', '', {}),
          ('162', 0x1c773c654, 0x1c773caf4, 'dsvinit', 'x,x,x,d,d,x,x,x', 'x', 'SBDeviceApplicationSceneView', '', {0x1c773caf4: 'dsvb0', 0x1c773cc40: 'dsvb1', 0x1c773ccb8: 'dsvb2'})],
  tail='''
uint64_t y42_sbs_init(uint64_t self, uint64_t cmd, uint64_t handle, double w, double h, uint64_t content, uint64_t container, uint64_t requester) { return sbsinit(self, cmd, handle, w, h, content, container, requester); }
void y42_sbs_invalidate(uint64_t self, uint64_t cmd) { sbsinval(self, cmd); }
void y42_sbs_state(uint64_t self, uint64_t cmd, uint64_t handle, uint64_t state) { sbsstate(self, cmd, handle, state); }
void y42_sbs_live(uint64_t self, uint64_t cmd) { sbslive(self, cmd); }
uint64_t y42_asv_init(uint64_t self, uint64_t cmd, uint64_t handle, double w, double h, uint64_t content, uint64_t container, uint64_t requester) { return asvinit(self, cmd, handle, w, h, content, container, requester); }
uint64_t y42_dsv_init(uint64_t self, uint64_t cmd, uint64_t handle, double w, double h, uint64_t content, uint64_t container, uint64_t requester) { return dsvinit(self, cmd, handle, w, h, content, container, requester); }
const char *y42_sceneview_preflight(void) {
    const char *m;
    if ((m = sbsinit_preflight())) return m; if ((m = sbsinval_preflight())) return m; if ((m = sbsstate_preflight())) return m; if ((m = sbslive_preflight())) return m;
    if ((m = asvinit_preflight())) return m; return dsvinit_preflight();
}
'''),
 'fsal': dict(file='Y42FullScreenLift.c',
  head='''// Y42FullScreenLift.c : -[SBFullScreenAlwaysLiveLiveContentOverlay initWithSceneHandle:referenceSize:containerOrientation:] of iPadOS 16.2 (20C65, 0x1c74d0d24 .. 0x1c74d0efc; 16.0 0x1c6053fdc), recompiled from the 16.2
// machine code by tools/a2c/a2c.py together with the PRIVATE SpringBoard function _SBApplicationMightHaveTransparentBackground (0x1c74cef10, not exported: 16.0 has it as a local symbol, so the call is recompiled as a local): it creates the scene view with the 16.2 init that carries content AND container orientation (Y42SceneView.x), asks the handle for _supportsMixedOrientation and sets
// content / container orientation of the transform wrapper.  Plain C, no ARC.  Installed by Y42FullScreen.x (switch y42_fullscreen).  Verified with tools/a2c/tests/tracecmp.py.  NOT device tested.
''',
  tcargs=['--safemem'],
  bodies=[('162', 0x1c74cef10, 0x1c74cef84, 'fsalmight', 'x', 'x', None, '', {}),
          ('162', 0x1c74d0d24, 0x1c74d0efc, 'fsalinit', 'x,x,x,d,d,x', 'x', 'SBFullScreenAlwaysLiveLiveContentOverlay', '', {0x1c74cef10: 'fsalmight'})],
  tail='''
uint64_t y42_fsal_init(uint64_t self, uint64_t cmd, uint64_t handle, double w, double h, uint64_t containerOrientation) { return fsalinit(self, cmd, handle, w, h, containerOrientation); }
const char *y42_fullscreen_preflight(void) { return fsalinit_preflight(); }
'''),
 'u2': dict(file='Y42U2Lift.c',
  head='''// Y42U2Lift.c : the two UIKitCore default scene handlers of iPadOS 16.2 (20C65), recompiled from the 16.2 machine code by tools/a2c/a2c.py:
//   __UIApplicationSceneConnectionHandler_block_invoke      0x1893148b4 (16.0 0x1891de700): migrates the windows of EVERY _UIPlaceholderWindowScene to the connecting scene and drops the auto invalidation assertion of the default scene
//   __UIApplicationSceneDisconnectionHandler_block_invoke_3 0x1895f2db8 (16.0 0x1894ba73c): takes [placeholderScene _preventAutoInvalidationForReason:@"default scene disconnected"] into a static
// Both are bodies of GLOBAL blocks (___block_literal_global / .8 in UIKitCore's __AUTH_CONST.__const): UIKU2b.m replaces their signed invoke pointers.  The static they share (__MergedGlobals of UIKitCore) is ONE zero
// initialised cell of this file.  Plain C, no ARC.  Verified with tools/a2c/tests/tracecmp.py.  NOT device tested.
''',
  tcargs=['--safemem', '--datasyms', 'UIApp=#0'],
  bodies=[('162', 0x1893148b4, 0x189314e5c, 'u2conn', 'x,x,x', 'v', None, '', {}),
          ('162', 0x1895f2db8, 0x1895f3218, 'u2disc', 'x,x', 'v', None, '', {})],
  tail='''
void y42_u2_conn(uint64_t block, uint64_t scene, uint64_t fbsScene) { u2conn(block, scene, fbsScene); }
void y42_u2_disc(uint64_t block, uint64_t scene) { u2disc(block, scene); }
const char *y42_u2_preflight(void) { const char *m = u2conn_preflight(); return m ? m : u2disc_preflight(); }
'''),
}

def gen(name):
    j = JOBS[name]
    parts = [j['head'], '#include "tools/a2c/liftdev.h"\n']
    for ver, st, en, cname, sig, ret, cls, kinds, locs in j['bodies']:
        kd = {}
        for kv in [x for x in (kinds + ',' + KINDS_ALL).split(',') if x]:
            k, v = kv.split('=')
            kd[k if k.startswith('fn:') else 'msgSend:' + k] = v
        L = a2c.Lift(ver, st, en, cname, sig, ret, kd, cls)
        L.locals = dict(locs)
        head, fn = L.generate()
        for w in L.stats['warn']: sys.stderr.write('WARN %s: %s\n' % (cname, w))
        parts.append(head + '\n' + fn + '\n')
    parts.append(j['tail'])
    open(os.path.join(OUT, j['file']), 'w').write('\n'.join(parts))
    a2c.save_memo()
    print('wrote', j['file'])

if __name__ == '__main__':
    for n in (sys.argv[1:] or list(JOBS)): gen(n)
