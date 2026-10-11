# AUDIT-DEFSIZE-0.6.9: port of the 16.2 default window size computation (written incrementally)

Disassembly source: 16.2 20C65 `-[SBSwitcherChamoisSettings layoutAttributesForContainerBounds:nativeContainerReferencePixelBounds:interfaceOrientation:floatingDockHeight:statusBarHeight:requiresFullScreen:prefersStripHidden:prefersDockHidden:isEmbeddedDisplay:]` 0x1c78c0f50..0x1c78c18fc (619 insns, read in full).

## S1. 16.2 builder 0x1c78c0f50: register map and flow (decoded by hand, constants read from the cache)
Args: bounds B=(bx,by,W,H)=d0..d3; native reference pixel bounds N=d4..d7 (cache key only); orientation x2; stack: floatingDockHeight dock (d13), statusBarHeight sb (d12); w3 requiresFullScreen rfs; w4 prefersStripHidden psh; w5 prefersDockHidden pdh; w6 isEmbeddedDisplay emb.
* 0x1c78c0fb8..0x1c78c10d8 CACHE: ivars (settings object) 0x7cc orientation, 0x7d0 result object, 0x7d4 bounds, 0x7d8 native bounds, 0x7dc dock, 0x7e0 statusBar, 0x7e4 rfs, 0x7e8 psh, 0x7ec pdh, 0x7f0 emb.
  Hit (returns cached object) only if bounds equal, native bounds equal, dock equal, sb equal, rfs/psh/pdh/emb equal and (isPortrait(orient) XOR isPortrait(cachedOrient)) == 0 and cached object non-nil. Orientation 1,2 = portrait.
* persp = W > 1681.0 ? 3000.0 : 2000.0   (0x1c78c10e8/0x1c78c1164: table 0x1c7a93530 = {2000,3000})
* E (screenEdgePadding) = W > 1920.0 ? 36.0 : sb   (0x1c78c1170..0x1c78c1188)
* rows = emb ? [self numberOfRowsWhileInAppOnEmbeddedDisplay] : (H < (double)[self externalDisplayHighResVerticalResolution] ? numberOfRowsWhileInAppOnExternalDisplay : ...HighRes)  (0x1c78c1190..0x1c78c11bc)
* SVES (stripVerticalEdgeSpacing) = rows > 4 ? 64 : 32; SIIS (stripInterItemSpacing) = rows > 4 ? 64 : 44   (0x1c78c11c4..0x1c78c11e4)
* CS (stripCardScale) = [self _stripCardScaleForContainerBounds:B screenEdgePadding:E stripVerticalEdgeSpacing:SVES stripInterItemSpacing:SIIS floatingDockHeight:dock numberOfRows:rows]  (0x1c78c1210; helper 0x1c78c203c)
* S (stripWidth) = [self _stripWidthForContainerBounds:B screenEdgePadding:E stripStackDistance:60 stripCardScale:CS stripTiltAngle:1.1344640137963142 (65 deg) containerPerspective:persp]  (0x1c78c1250; helper 0x1c78c1dd0)
* (minDW,minDH) = [self _minimumDefaultWindowSizeForContainerBounds:B stripWidth:S]  (0x1c78c1278; helper 0x1c78c207c)
* Hd = H - dock; E2 = 2E; sb2 = 2 sb; minWinW = W > 1920 ? 414 : 320   (0x1c78c1284..0x1c78c12ac)
* gridWidths (NSMutableArray, sorted ascending with compare: at 0x1c78c143c):
  - psh && pdh: [_gridWidthsForSafeWidth:W minimumWidth:minWinW stageInterItemSpacing:10]
  - psh only (pdh == 0): same with safeWidth = W - E2
  - !psh: S' = min(S, (W - minDW)*0.5); safe = emb ? W - E2 : W - S' - E; widths = [_gridWidths(safe, minWinW, 10)]; if S' != S: removeLastObject and addObject:@(W - 2*S'); then always addObject:@(W - E2)   (0x1c78c1344..0x1c78c1410)
* gridHeights (sorted):
  - psh && pdh: [_gridHeightsForSafeHeight:H minimumHeight:600 stageInterItemSpacing:10]
  - pdh only: safe = H - E2
  - !pdh: [_gridHeights(safe = Hd - E2 = H - dock - E2, 600, 10)] and addObject:@(H - E2)   (0x1c78c1450..0x1c78c14f0)
  (the psh && pdh case needs care: the code tests `cbz w23` where w23 = psh & pdh, then `cbz w21` (pdh))
* Hs = H - dock - E2  (d10 after 0x1c78c1420)
* INDEX: idx = count(gridHeights) + (pdh ? -1 : (count == 1 ? -1 : -2));  hSel = gridHeights[idx]   (0x1c78c1524..0x1c78c1560).
  NOTE (correction of the brief): the second-largest grid entry comes from the HEIGHT list, selected by prefersDockHidden; the default WIDTH is not taken from the width list but from the formula below.
* Wd = (psh && emb) ? W - (pdh ? 0 : E2) : max(minDW, min(W - 2S, max(0.65*W, 1590.0)))   (0x1c78c1568..0x1c78c15a8; 0.65 at 0x1c7a91c98, 1590 at 0x1c7a934b8)
* defW = min(Wd, 1590);  ovlW = Wd > 1590 ? 1590 : 0.8*Wd    (BSFloatGreaterThanFloat, 0x1c78c15b0..0x1c78c15cc)
* defaultWindowSize = [self _nearestGridSizeForSize:(defW, hSel) gridWidths gridHeights bounds:B]  -> setDefaultWindowSize:   (0x1c78c15f8)
* maximumWindowWidthForOverlapping = [self _nearestGridSizeForSize:(ovlW, H) ...].width   (0x1c78c1628)
* other setters (0x1c78c1654..0x1c78c1898): containerBounds=B, requiresFullScreen=rfs, minimumDefaultWindowSize=(minDW,minDH), maximumWindowHeightWithDock=Hs, minimumWindowWidth=minWinW, containerPerspective=persp,
  screenEdgePadding=E, stripWidth=S, stripVerticalEdgeSpacing=SVES, stripInterItemSpacing=SIIS, stripTiltAngle=65deg, stripIconLength = W>1681 ? 40 : 30, stripStackDistance=60, stripCardScale=CS, stripCornerRaddii=10,
  stageCornerRaddii=20, stageInterItemSpacing=10, stageOccludedAppScale=1-32/H, stageStatusBarClearingAppScale=1-2sb/H, stageOcclusionDodgingPeekLength=44, PeekScale=0.9, numberOfRowsWhileInApp=rows,
  prefersStripHidden=psh, prefersDockHidden=pdh, usesStripAreaForOverlapping=emb, gridWidths, gridHeights,
  switcherHorizontalEdgeSpacing=round(H/16) [x1.5 rounded if W>1920], switcherVerticalEdgeSpacing=round(H*0.10546875) [x1.5], switcherHorizontalInterItemSpacing=same as HES (before x1.5), switcherVerticalInterItemSpacing=round(H*0.0859375),
  + copies of switcherHeightForIconAndLabelsUnderEachPile, switcherPileCardMinimumPeekAmount, switcherPileCompactingFactor from the settings.

## S2. 16.2 helpers (decoded)
* `_gridWidthsForSafeWidth:Ws minimumWidth:minW stageInterItemSpacing:sp` 0x1c78c18fc: if (minW+sp) <= 0 -> empty (log). q = (Ws+sp)/(minW+sp); nmax = floor(q) (fcvtmu). Loop n = nmax..1 (0x1c78c1984):
  n==1: add Ws; n==2: add floor((Ws-sp)/2); n>=3: w = floor((Ws-(n-1)*sp)/n); add w; add floor(Ws-sp-w); and if n == nmax additionally add floor(Ws - w/2). After the loop (n==0): if floor(q) > 2 done, else add minW and, if (Ws-sp-minW) > 0, add (Ws-sp-minW).
  (the fadd/fmul pairs around frintm are floor-to-0.5 sequences that reduce to plain floor of the value, identity otherwise)
* `_gridHeightsForSafeHeight:Hs minimumHeight:minH stageInterItemSpacing:sp` 0x1c78c1b54: if Hs < minH -> empty. step = ((Hs + (-0.5)*(Hs - sp)) * 0.25) = (Hs+sp)/8. do { add floor(Hs); Hs -= step } while (Hs >= minH).
* So for the dock-visible case the height list = {floor(H-E2) [extra], floor(H-dock-E2), then steps of (H-dock-E2+10)/8 down to >= 600}; index count-2 = the full height that clears the floating dock (NOT a grid step below full height); with prefersDockHidden the index is count-1 = H-E2.

## S3. 16.2 `_nearestGridSizeForSize:gridWidths:gridHeights:bounds:` 0x1c78c1c24 (decoded)
nearestW = the entry of gridWidths with minimal |v - w| (strict `<`, first minimal wins; list is sorted ascending), nearestH likewise for heights (init CGSizeZero). If nearestW == [gridWidths lastObject] (BSFloatEqualToFloat) AND nearestH == [gridHeights lastObject] -> returns the BOUNDS size (W, H) (args d4,d5), else (nearestW, nearestH). Empty lists -> (W,H).

## S4. 16.0 builder 0x1c6413524 and `_defaultAppSizeForContainerBounds:...` 0x1c641391c (decoded, for the diff)
16.0 has NO gridWidths/gridHeights/_nearestGridSize/containerBounds on the settings/attributes; it computes (same arg layout as 16.2):
* persp = W > 1681 ? 3000 : 2000; E = **W > 1681** ? 36 : sb (16.2: W > 1920; only matters for external 1681 < W <= 1920); rows, SVES, SIIS, CS, S: same formulas and SAME helper bodies (`_stripWidth...` 16.0 0x1c6413a28 == 16.2 0x1c78c1dd0 instruction by instruction; `_stripCardScale...` 16.0 0x1c6413c94 == 16.2 0x1c78c203c; both constants 876 / 65 deg).
* minimumWindowWidth = emb ? 320 : 414 (16.2: W > 1920 ? 414 : 320). `_minimumDefaultWindowSizeForContainerBounds:` 16.0 0x1c6413cd4 = hard-coded table by container size ((1389,970)->(1194,834), (1590,1192)->(1366,1024), (1192,1590)->(1024,1366), (1681,1260)->(1444,1082), (1366,1024)->(1158,858), (1194,834)->(1024,683)); 16.2 0x1c78c207c = same table but the width entries are W - stripWidth (1366 - S, 1194 - S...).
* default size = `_defaultAppSize...` 0x1c641391c (UNSNAPPED): rfs -> (W-2E, H-2E); **emb && nativeBounds.width < 2048 -> the FULL container (W,H)** (0x1c6413960..0x1c641396c); else width = min(max(minDW, min(W-2S, max(0.65 W, 1600))), 1600) (if psh: pdh ? W : W-2E), height = pdh ? H : H-2E-dock.
  maximumWindowWidthForOverlapping (out param) = Wd > 1600 ? 1600 : 0.8*Wd.
* The 16.0 `_SBDisplayItemFlexibleGrid _buildGridWithScreenScale:` 0x1c6468f0c builds the SAME width/height lists as 16.2's settings (from attrs stripWidth, screenEdgePadding, minimumWindowWidth, minimumDefaultWindowSize, maximumWindowHeightWithDock, prefersStripHidden/DockHidden; helpers 0x1c64691b4/0x1c6469374 identical to 16.2 0x1c78c18fc/0x1c78c1b54 except that 16.2 adds a tail (minW, Ws-sp-minW) when floor(q) <= 2) ; 16.2's flexible grid `_buildGridWithScreenScale:` 0x1c791e5d4 just takes attrs.gridWidths/gridHeights (callers of gridWidths: 0x1c791e5ec/0x1c791e604).
=> ON THE STOCK 16.0 the full-screen default of a never-windowed app comes from the emb && native.width < 2048 quirk (11-inch iPads: UIScreen nativeBounds is portrait based, 1668 < 2048), and for 12.9 inch (2048) from nothing (16.0 and 16.2 agree there up to the 1600/1590 cap).

## S5. Numerical check (hand evaluation, S taken from the 16.0 table: 1366-1158 = 208, 1194-1024 = 170; dock 90 assumed)
* 11 inch landscape B=1194x834, E=24: widths [375, 568, 761, 958, 1024, 1146]; heights [608, 696, 786]; Wd = 1024; default = nearest((1024, 696)) = **1024 x 696** (16.0 stock: 1194 x 834 = full container, because nativeBounds.width 1668 < 2048).
* 12.9 inch landscape B=1366x1024: widths [322, 432, 654, 876, 986, 1157, 1158, 1318]; heights [654, 765, 876, 976]; default = 1158 x 876 (16.0 stock identical, un-snapped value 1158 x 876).

## S6. Further 16.0 -> 16.2 differences found in the builder inputs (matter for the exact default width)
* stripVerticalEdgeSpacing: **16.0 = 64 always** (builder 0x1c6413608 `fmov d5` 64, stored [sp,#0x48] and passed as the card-scale argument), **16.2 = rows > 4 ? 64 : 32** (0x1c78c11c4..0x1c78c11d8). stripInterItemSpacing: both rows > 4 ? 64 : 44. => card scale and strip width S differ for rows <= 4, and since the known container sizes use minDW = W - S the default WIDTH of 16.2 depends on the 16.2 S. The port therefore recomputes CS and S with the (identical) 16.0 helper bodies and the 16.2 inputs and (sub-switch g2defsize_strip, default on) writes E, SVES, SIIS, CS, S back into the attributes so the 16.0 grid (which reads attrs.stripWidth / screenEdgePadding / minimumWindowWidth / minimumDefaultWindowSize) builds exactly the 16.2 lists.
* The ONLY consumer of requiresFullScreen is the calculator frame code (16.0 0x1c6119d14 / 16.2 0x1c75a3bf0: size = defaultWindowSize); 16.2's builder does not special-case rfs (stores it), 16.0's returned (W-2E, H-2E). rfs is real: 16.2 0x1c75a3450..0x1c75a3468: rfs = layout role valid for split view && !_appLayoutContainsOnlyResizableApps: (non-resizable apps). Faithful port applies the 16.2 default to them too; sub-switch g2defsize_rfs (default on) keeps the 16.0 value for rfs attributes if the non-resizable apps look wrong.
* Orientation and nativeBounds are cache-key only in 16.2 (portrait test 0x1c78c0fb8..0x1c78c0fdc); the computation uses only the container size (bx,by,W,H), dock, statusBar, psh, pdh, emb and the settings getters (numberOfRowsWhileInApp*, externalDisplayHighResVerticalResolution).
* 16.2 caches the attributes object in the settings (ivars 0x7cc..0x7f0); 16.0 builds a new object per call -> the port caches its numeric result per input key (8 entries) to avoid doubling the cost of the CATransform loop of _stripWidth.

## S7. Implementation (G2.x, switch `g2defsize`; sub-switches `g2defsize_strip`, `g2defsize_rfs`; all default on)
* `BP_G2_DSCompute` (G2.x, before `%group G2Settings`) = the S1..S3 arithmetic; `BP_G2_ApplyDefaultSize` is called at the end of the existing `%hook SBSwitcherChamoisSettings layoutAttributesForContainerBounds:...` (after %orig = the 16.0 builder). It caches the numeric result per input key (8 entries), writes into the 16.0 attributes: defaultWindowSize (not for rfs when g2defsize_rfs is off), minimumDefaultWindowSize, minimumWindowWidth, maximumWindowHeightWithDock, maximumWindowWidthForOverlapping, gridWidths/gridHeights (G2 extras), and with g2defsize_strip screenEdgePadding, containerPerspective, stripVerticalEdgeSpacing, stripInterItemSpacing, stripCardScale, stripWidth. Not touched: stage scales, peek values, icon length (16.0 values equal or out of scope).
* New hook `%hook _SBDisplayItemFlexibleGrid -_buildGridWithScreenScale:` (group G2Grid, 16.0 0x1c6468f0c): after %orig the grid adopts attrs.gridWidths/gridHeights into _widths/_heights, exactly what 16.2 0x1c791e5d4 does; this removes the only remaining list difference (16.2's narrow-container tail entries) so the frame code's grid snap of the new default is the identity. FixedAspect grids keep their own builder (as in 16.2).
* Mock-compiled (clang -fsyntax-only -Wall -Wextra -Werror with a stub Foundation header) for the whole block; logos.pl OK for G2.x and G3C.x. Python mirror of the arithmetic reproduces the hand numbers of S5 (11 inch: widths [375,568,761,958,1024,1146], default 1024 x 696).

## S8. Consumers checked
* Calculator frame code (16.0 0x1c6119d00..0x1c6119df4, wrapped by G2B gBP2B_Ctx): reads defaultWindowSize for (policy 0, Unspecified/size<=0, rfs); then grid snap = identity because default is a list entry (or the container if both list maxima).
* BP2B_AutoLayout / BP2B_FrameSkipAutoLayout / BP2B_PreferredSizingPolicy: default (1024x696) != container -> normalized (0.857, 0.835) -> `_SBPreferredDisplayItemSizingPolicy` keeps policy 0; write-back stores inferred size (semantic type 6 = follows default). maxW (maximumWindowWidthForOverlapping) now the 16.2 grid value; gridMax = grid.nearest((maxW, H)). Hand-resized windows: stored normalized sizes are untouched; only types 4/5/6 follow the default (16.2 semantics). If the default equals the container (small displays, both list maxima) the policy derives to 2 as before.
* G2.x controller (_widthThreshold, _stageArea, _columns, _dodge) reads stripWidth / minimumDefaultWindowSize / maximumWindowHeightWithDock / screenEdgePadding: now the 16.2 values they were ported against.
* G3C.x: kept. New early return: leaving maximized with an Unspecified size and a live default window < container -> request untouched (Zoom -> maximize, Zoom -> default window, like 16.2). Old paths (grid index 1) remain for g2defsize off, for stored full-size windows and when the default still fills the container. The "stay" branch only fires when the default fills the container, so it is dormant now.
* G1C.x (not edited): its drag-and-drop code reads defaultWindowSize from the attributes; it now gets the 16.2 value.

## S9. Exact vs approximated, confidence, log
* EXACT (decoded instruction by instruction): the whole default-size path incl. constants 1681/1920/1590/0.65/0.8/320/414/600/10/60/65 deg, height index count-2 / count-1 (dock hidden), width formula, list construction, nearest-grid with the "both maxima -> container" rule, minimum-default table, the cache-key irrelevance of orientation/native bounds.
* REUSED 16.0 bodies (verified identical): `_stripWidth...`, `_stripCardScale...`. REIMPLEMENTED: lists, nearest, minimum table, comparisons via BSFloat* when available.
* APPROXIMATED / deviations: (1) unconditional NSRangeException paths of 16.2 (empty list, bad index) -> we keep the 16.0 value and log "compute failed"; (2) widths loop capped at 256 columns; (3) 16.2 caches the attributes object, we cache numbers; (4) rfs: faithful (16.2 gives rfs apps the same default) but switchable; (5) strip geometry write-back (E threshold 1920, stripVerticalEdgeSpacing 32 for rows <= 4) changes strip look to 16.2's; switch g2defsize_strip off keeps 16.0 strip geometry and computes the default with the 16.0 S (then width is only approximately 16.2's).
* Confidence: HIGH that the formula is 16.2's (read in full, consistent with the 16.0 grid builder); MEDIUM that nothing else regresses (static, not run); S (stripWidth) value is live from the CATransform helper, not hand-checked.
* Log (Backport162.debug): `[defsize] bounds ...` then `[defsize]   E ... gridWidths ... gridHeights ...` then `[defsize]   DEFAULT WINDOW SIZE 16.2 = {w, h} (stock 16.0 builder gave {..}) -> applied`, once per distinct input set. Expect on an 11 inch iPad Pro landscape: 16.0 gave {1194, 834}; 16.2 about {1024, ~700}. Check the later `[g3c]` lines: "leaving full screen with an Unspecified size, the default window ... applies".
