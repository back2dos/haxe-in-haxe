# Code generation and optimizations

The pipeline as built: [docs/hxmc.md](../hxmc.md), "Pipeline".

## Escape analysis

Allocate objects that never escape their function on the stack, or
replace them by their fields in registers (scalar replacement): temporary
iterators, small structs and anonymous objects, closures called in place,
boxed values. Go relies on this to keep short-lived objects off its heap.
It removes allocation, write barriers and GC pressure at once, and is
likely the largest remaining gain for allocation-heavy code (alloc,
binarytrees, closure-heavy code, the port's own temporaries), more than
any tuning of the collector. hxmc's SSA IR and inliner make it practical:
inlining first exposes most non-escaping allocations, and scalar
replacement of frame slots already exists for struct values (`Sroa.hx`).
Stack-allocated objects must stay visible to the GC when they hold
references (as roots, via the shadow stack), and must never be stored
where a heap object or another thread can see them.

## Frame pointers, unwind tables, debug info

Frame pointers are built (docs/hxmc.md, "Pipeline": always on arm64,
`-D hxmc.frame-pointers` on x86-64; `perf record -g` works). Measured as a
default on Linux x86-64 (as Fedora and Ubuntu now build): 0.8% more code
and no difference beyond noise in time.

Not built on main: unwind tables (the debug-info branch is on it).

- ELF `.eh_frame` CFI and macOS `__unwind_info` (or `__eh_frame`), for
  `perf --call-graph dwarf`, gdb/lldb backtraces without frame-pointer
  heuristics and profilers that do not walk frame pointers. The prologues
  are regular (push rbp / pushes of the callee-saved registers / sub rsp;
  stp x29, x30 / sub sp / stores), so one CIE and an FDE per function with
  a few instructions each would do; the emitters know every offset. With
  frame pointers on, the FDEs reduce to "CFA = rbp + 16" after the
  prologue.
- Windows `.pdata`/`.xdata`: nothing needs them while setjmp/longjmp do
  not unwind, but debuggers and SEH-based tools do.
- Source lines (DWARF) for debuggers.

## Smaller items

- Thread-locals: inline macOS's TLV thunk call (a call per function
  today) and trim Windows arm64's three loads per function.
- From the math work ([math.md](math.md)): a switch on small integers as a
  jump table (sin/cos/tan's quadrant), if-conversion (cmov), splitting
  live ranges around rare calls.
