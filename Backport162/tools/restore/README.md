# Restoring the analysis machine after a container reset

Rebuilt on 2026-11-18 (the old scratchpad with the caches was lost). Both caches verified against the old specs:
16.2 0x1c744326c = `___70-[SBFluidSwitcherViewController _layoutAppLayout:roleMask:completion:]_block_invoke`,
0x1c7965d48 = `-[SBSystemUISceneController initWithSceneWorkspaceIdentifier:clientProcessIdentity:sceneVendingPolicy:traitsRole:jobLabel:level:]`;
16.0 0x1c5fca514 = the 16.0 `_layoutAppLayout` block.

* 16.0 (20A8372): the user supplies the cache folder (all 44 files `dyld_shared_cache_arm64e*`, UUID 92381BEE-55B3-36E3-B3AF-9709707638FC) -> `<scratchpad>/dsc/com.apple.dyld/`.
* 16.2 (20C65, UUID 4A17A992-DF1E-3A8D-849C-9F73C0662339): `extract_dsc.py` (this folder) from the iPad13,4 IPSW cryptex DMG -> `<scratchpad>/dsc162/20C65__iPad13,4_5_6_7_8_9_10_11/` (must be REAL files: ipsw does not follow absolute symlinks for subcaches).
* `bin/ipsw`: the module `github.com/blacktop/ipsw` @master from proxy.golang.org (`curl -L .../@v/<pseudo-version>.zip`, unzip, `go build ./cmd/ipsw` with GOFLAGS=-mod=mod). `ipsw extract --dyld` needs apfs-fuse (not available) so the cache comes from extract_dsc.py instead; `dsc info / a2s / disass / macho` work on the extracted caches.
* then the files listed in ../README.md (`sb_syms.txt`, `sb162_syms.txt`, `sb160n_objc.txt`, `sb162_objc.txt`: `ipsw dsc macho <cache> SpringBoard --symbols` / `--objc -V`).
