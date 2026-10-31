Generator of Y26ClassicTables.h (see the header of Y26Classic.x).  Needs: python3 + unicorn (pip install unicorn), the ipsw tool and the two dyld shared caches of the analysis machine
(paths at the top of emu_lib.py), and the raw listings cm160.raw / cm162.raw (annotated disassembly of -[SBApplication(Classic_Internal) _classicModeFromSupportedTypes], used only to name
the call targets).  Steps: genvar.py <160|162> <homeButtonType 0|2>  (explores all paths, writes varleaves_*.pkl), cmpdag.py <hb> (16.0 vs 16.2 differences), emit.py (writes the header).
