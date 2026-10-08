# Generational GC experiment (HL/C)

A sticky-mark-bit generational mode for libhl with a write barrier emitted by
hl2c. It works and passes the conformance suite, but it makes the port
slower, so it is kept here for reference and is not part of the benchmark
build.

Patches, applied on top of the benchmark ones:

- `libhl.patch` on top of `bench/libhl-allocator.patch`
- `hl2c.patch` on top of `bench/hl2c-virtual-field-cast.patch`

## Design

- **Sticky mark bits.** Each page keeps its mark bitmap for its whole
  lifetime instead of sharing one buffer that is cleared at every collection.
  A major collection clears the bits. A minor one keeps them, so a marked
  block is old and marking stops at it. New blocks are allocated unmarked.
- **Arena.** All GC pages come from one 8 GB virtual region aligned on its
  size. The page-map hash cannot collide inside it, and the barrier only
  needs a range check. Freed pages are returned with `MADV_DONTNEED` and
  reused for pages of the same size.
- **Remembered set.** `hl_gc_rem` has one byte per 8-byte granule of the
  arena. The barrier sets the byte of the written object's start:
  `if (o - arena < 8GB) rem[(o - arena) >> 3] = 1`. Marking sets the same
  byte in an "old" map for every marked block. A minor collection rescans the
  blocks in `rem & old` and then clears `rem`.
- **Barriers.**
  - hl2c emits `HL_WB(obj)` after every pointer store into an object field,
    array element or enum field, and `HL_WB_V(obj, field)` after a virtual
    field store. When the runtime's `hlc.h` does not define them they compile
    to nothing.
  - libhl calls `hl_gc_wb` / `hl_gc_wb_interior` after its own stores: the
    dynamic setters, `hl_to_virtual` caches, dynobj field tables, maps, string
    buffers, `hl_array_blit` and deques.
- **C runtime safety net.** Blocks first marked through a stack word are
  rescanned at the next collection. They cover fresh objects that C code is
  still filling in without barriers across an allocation.
- **Policy** (environment variables):
  - `HL_GC_GEN=1` enables the mode. Run with `HAXE_IN_HAXE_GC_FACTOR=0` so
    the port leaves collection to libhl.
  - A minor collection runs every `HL_GC_NURSERY` MB allocated (default 8).
  - A major runs when the estimated old generation exceeds `HL_GC_OLD_MIN`
    MB (default 32) and `HL_GC_OLD_FACTOR` (default 2) times the live size
    after the last major.
- **Verification.** `HL_GC_VERIFY=1` re-marks from the roots after each
  minor collection and reports live blocks the minor collection left
  unmarked, together with the old blocks pointing to them.

## Results (`stdlib` workload, 2026-10-08)

Correctness:

- With `HL_GC_NURSERY=1` (hundreds of minor collections) all 282
  conformance cases still produce identical HXB.
- The verifier's only remaining reports in that stress run (7, in 4 cases)
  are dead `UnificationContext` objects that a stale stack word once marked:
  their `applyParamsStack` field points at reused memory. This is an artifact
  of conservative stack scanning; nothing live is lost.

The barrier runs 10.5M times per run. It is emitted at 13.7k field, array and
enum store sites plus 4.5k virtual-field sites, and adds 174M instructions
(1.565G → 1.739G). An earlier card-marking version through the two-level page
map cost about 17 instructions per store, and its 512-byte cards made minor
collections rescan most old objects: initialising stores to new objects dirty
the cards they share with old ones.

Marking. The current policy runs three major collections 64–90 MB of
allocation apart; together with three tiny startup collections they mark
0.92M blocks. A minor collection promotes about 10% of its nursery, much of
which dies before the next major would have run:

| Mode | Collections | Blocks marked | Peak pages |
| --- | ---: | ---: | ---: |
| current (non-generational) | 6 major | 0.92M | 105 MB |
| generational, 16 MB nursery | 16 minor + 1 major | 1.08M | 46 MB |
| generational, 64 MB nursery | 4 minor | 0.59M | 94 MB |

CPU time in seconds, minimum (and median) of 21 runs, with 4 mark threads:

| Build | User | User + system |
| --- | ---: | ---: |
| reference (OCaml) | 0.205 | 0.238 (0.256) |
| HL/C as benchmarked | 0.323 | 0.361 (0.518) |
| arena, no barrier | 0.343 | 0.407 (0.439) |
| arena + barrier, not generational | 0.373 | 0.432 (0.478) |
| generational, 48 MB nursery | 0.446 | 0.559 (0.605) |
| generational, 64 MB nursery | 0.420 | 0.539 (0.587) |

With a single mark thread the generational runs were 0.53s (16 MB nursery)
and 0.46s (32 MB) of user time.

## Why it does not pay off

- **Small live set.** The live heap is 6–12 MB while 260 MB is allocated.
  Majors 64 MB of allocation apart therefore mark little, and a minor
  collection can save at most part of that (about 0.02s here). The barrier
  alone costs about 0.03s.
- **Fragmentation.** Small nurseries promote a lot of short-lived data, which
  then fragments the non-moving heap. The allocator then refills slices from
  tiny free runs, and its slow path, free-list rebuilds and mark-bit clearing
  cost more than the marking saved.
- **What remains is not marking.** The GC overhead left in HL/C is
  allocation and the zeroing of recycled memory. OCaml's advantage there is a
  copying, cache-resident minor heap, which needs moving objects. That is
  incompatible with HashLink's conservative stack scanning unless it pins the
  pages referenced from stacks (mostly-copying collection).
- **The arena on its own.** It makes system time steadier (median
  0.44s against 0.52s), but its best runs are slower, so it was not adopted
  either.
