# Reverse-engineering tools used for the 16.0 -> 16.2 comparison

These scripts expect a scratchpad directory laid out like the one they were written in (paths are hard-coded as `S=` near the top of each file; edit them).
They are small and only here so the work can be resumed if the session's container is reset.

Needed in the scratchpad (not committed, large):

* `bin/ipsw` (blacktop/ipsw built from source).
* `dsc/com.apple.dyld/dyld_shared_cache_arm64e`: the 16.0 (20A8372) dyld shared cache for iPad13,x (extracted from the IPSW with `ipsw extract --dyld --dyld-arch arm64e`, using apfs-fuse for the rootfs DMG; `IPSW_APFS_FUSE_PATH`).
* `dsc162/20C65__iPad13,4_5_6_7_8_9_10_11/dyld_shared_cache_arm64e`: the 16.2 (20C65) cache (`ipsw extract --dyld --dyld-arch arm64e --remote`, add `-V`).
* `sb_syms.txt` / `sb162_syms.txt`: `ipsw dsc macho <cache> SpringBoard --symbols`; `sb160n_objc.txt` / `sb162_objc.txt`: `ipsw dsc macho <cache> SpringBoard --objc -V`.
* `tp/selmap_160.pkl`, `tp/selmap_162.pkl`: built by `selmap.py` (selector-stub to selector-name maps).
* `tp/common_meths.json`: built by `bodydiff_list.py`; `bodydiff3.py` then writes `tp/bodydiff3.json` (the data behind `../WORKLIST.md`).

`annot3.py <16.0 cache> <hex addr> <insn count>` and `annot162.py <16.2 cache> ...` print annotated disassembly (selector names for objc_msgSend$ stubs).
