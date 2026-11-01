# AUDIT: silent fallbacks, type mismatches, load-time code, armed overrides, signatures (0.7.9)

Why: bugs kept surfacing that needed device logs. Two found in one session show the class: (1) `G1C_WdDragging` / `G1C_WdProposedAll` accepted only `NSArray` but the coordinator answers an `NSCountedSet` copy and the VC an `NSMutableSet`, so the dragged layout was silently dropped (0efa07d); (2) `Y28Keyboard.x` constructor messaged `+[SBSceneManagerCoordinator mainDisplaySceneManager]` at dylib load, a boot hang (b6d6599). Earlier: a selector sent to the wrong receiver answered NO and caused unbounded re-entrancy. Common class: a ported body whose assumption fails and silently returns the stock / default value, nothing in the log.

Classes: A collection type mismatches, B silent fallbacks, C constructors / load-time code, D armed one-shot overrides, E wrong receiver / IMP signature, F caller / callee contract (card path first).

## 0. The anomaly channel (class B infrastructure)

* `BP_Anomaly(const char *tag, NSString *fmt, ...)` (BP.h, Tweak.x): appends `ANOMALY <tag>: <message>` to `<jbroot>/tmp/Backport162.log` always (no `Backport162.debug`). Cap 300 lines per process (+1 `ANOMALY (cap)` line), 40 per tag, a (tag, message) is written once, a (tag, format string pointer) is formatted at most 8 times (two table probes under a mutex before any allocation). Shares the file descriptor / rotation of `BP_Log` (`BP_LogLine`).
* `Y17_GuardOnce` (Y17Common.h) now hashes (tag, class name, what) into a lock-free table (no `NSString` per call; it runs on hot paths) and calls `BP_Anomaly`.
* every `GUARD...` `BP_Log` line (89 sites in 23 files) was turned into a `BP_Anomaly` with the GUARD(tag) as the tag (or `guard-<file>`); their `if (BP_LogEnabled())` guards were removed (the lines are rare by construction, and bounded by the cap otherwise).
* helpers that returned nil / 0 / NO for a missing selector (`BPX_*`, `BPY_*`, `G1B_Send*`): see section B.

## Findings table

Status: fixed / logged (now announces itself) / not-a-bug (proven) / unproven.
