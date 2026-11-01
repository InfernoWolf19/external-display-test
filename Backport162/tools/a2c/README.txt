a2c : static recompiler arm64e machine code (dyld shared cache of iPadOS 16.2 20C65 / 16.0 20A8372) -> C.   Used by the Y34 / Y35 ports that need a LARGE or numerically fiddly 16.2 body
(Y34LazyTypes.c is 1244 instructions of nested device / screen size tests) to be the 16.2 code itself instead of a hand copy.

  python3 a2c.py <160|162> <start-hex> <end-hex> <cname> <sig> [--ret v|x|d|size|rect] > body.gen.c
      sig: argument registers in ABI order, x = integer register, d = double register (self and _cmd are the first two x)
      one machine instruction = one C statement (registers X[], VR[][2], flags N Z C V, the stack frame as a byte array);
      adrp / add / ldr of the constants are resolved at translation time (ivar offsets -> IVOFF, selector refs -> SEL, class refs -> CLS, CFString -> CFSTR_,
      the immutable SBDisplayMetrics table -> baked doubles through a flow analysis of the constant registers, stack guard -> a cell);
      every call passes x0..x7 + d0..d7 through a typed function pointer (the ARM64 ABI hands exactly those registers to any callee), the return kind
      (x, v, d, size = CGSize, rect = CGRect) is derived from the instructions after the call; the objc_retain / release / claim stubs map to the runtime.
  liftcommon.h  shared macros (loads / stores, FP compare, conversions)
  liftdev.h     device side (plain C, no ObjC headers, runtime functions bound through asm labels); NAME_preflight() reports the first symbol / class / ivar the process cannot resolve
  liftest.h     Linux test side (every call / selector / ivar goes to a python callback)
  tests/        lzt.py (ctypes harness), lazy_test.py (lifted 16.0 / 16.2 lazy type calculation vs the Unicorn emulation of the original code, 22704 inputs per device class),
                splash_test.py + splash_unicorn_test.py (Y34SplashTypes.h vs lifted and emulated code)
Needs python3, capstone, unicorn, the ipsw tool and the two dyld shared caches of the analysis machine (paths in ../y26_classic_tree/emu_lib.py); the committed outputs are the Y34*.c files.
