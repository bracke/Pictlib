# pictlib — Implementation Plan

**Status:** M0–M7 implemented; open items are listed under M7  
**Contract:** [SPECIFICATION.md](SPECIFICATION.md) (authoritative)  
**Reference:** https://github.com/bracke/jpeglib

## Operating rules

- Implement in Ada 2022, using Alire with `gnat_native = "^15"`. The production dependencies are
  `jpeglib`, for QuickTime JPEG images, and `textrender`, for TrueType text, both through their
  public APIs. No C libraries.
- Read the specification and the relevant `jpeglib` package interfaces before changing a public API.
  Any design conflict is resolved in the specification first.
- For each task, implement its public contract, internal implementation, positive and adversarial
  AUnit tests, and documentation together. Keep tasks small enough for one focused session.
- Build after each task (`alr build`, `alr --chdir tests build`) and run the tests. Do not claim
  completion without verified results.
- Never suppress corrupt input or exceed configured limits to make a test pass. Error reporting is
  non-raising and deterministic.
- Unimplemented public capabilities report `Unsupported_Feature` explicitly; no stub returns success.
- Tasks below are ordered; tasks within a milestone may be subdivided while preserving dependencies.

## M0 — Skeleton and test harness

**Completed (2026-10-24):** Tasks 1–6 and Gate M0. The GNAT 15 Alire library and
test crates, public foundation API, diagnostics, limits, stream adapters, checked
big-endian bytes, compile-only consumer and AUnit runner are
implemented and verified with the day-to-day gate (then `scripts/check_all.sh`, since
replaced by the Ada tool `pictlib_check`).

1. Create Alire library crate `pictlib` (GNAT 15 pin, MIT, `jpeglib` path pin, `src/`) and the child
   Alire crate `tests` depending on `pictlib`, `aunit` and `project_tools`.
2. Public root `Pictlib` scalar types, `Version`, `Capabilities`; compile-only API consumer.
3. `Errors`, `Results`, `Limits` with explicit diagnostics (offsets, opcode, opcode ordinal, row,
   expected/actual, limit kind). Test each code's identifier and the default limits.
4. `Streams` interfaces, memory source and fixed-buffer destination with transfer caps; exact
   read/skip/write helpers. Test partial reads/writes, EOF, zero progress, offsets, failures.
5. `Internal.Checked_Arithmetic` and `Internal.Bytes` (big-endian 16/32-bit, signed coordinates).
6. `AGENTS.md`, README, CHANGELOG, AUnit runner, a day-to-day gate (now `pictlib_check`).

**Gate M0:** clean root and tests builds; API consumer compiles; foundation, stream and byte tests pass.

## M1 — Container and opcode stream

**Completed (2026-10-24):** Tasks 7–12 and Gate M1. Geometry, the opcode
length-rule table, file-header detection without seeking, v1/v2/extended-v2
headers, the bounded opcode reader with structural skipping of regions,
polygons, pixel patterns and pixmaps, the decoder state machine with
enumeration, metadata retention and the invariant and limits documents are
covered by hand-assembled fixtures and malformed streams.

7. `Geometry` (Point, Rect, Fixed) with checked validation; `Opcodes` length-rule table for every
   opcode and reserved range (SPARK-friendly pure function), exhaustively tested.
8. Container: 512-byte header policy (`Auto` via bounded look-ahead), `picSize`, `picFrame`,
   v1/v2/extended-v2 version detection, `HeaderOp` parsing and resolution.
9. `Internal.Opcode_Reader`: v1 byte and v2 word opcodes, alignment padding, bounded skipping,
   end opcode, trailing data and missing-end policy per strictness mode.
10. `Decoding` state machine with `Read_Header`, `Enumerate`, `Cancel`, `Reset`, `Finalize`.
11. `Metadata`: comments, font names, file header, reserved payload retention under budgets.
12. `docs/invariants.md`, `docs/limits_and_safety.md`.

**Gate M1:** every opcode of hand-assembled v1, v2 and extended v2 fixtures is enumerated with
correct offsets and lengths; malformed containers fail deterministically on forward-only sources.

## M2 — Raster decode

**Completed (2026-10-24):** Tasks 13–16 and Gate M2. Caller image views with
overflow-safe validation, PackBits for bytes and words, region parsing with a
top-to-bottom row walker, BitMap and PixMap decoding at every depth and pack
type, nearest-neighbor copies with clip and mask regions, and `Render` are
covered by hand-built fixtures and by four PICTs from two independent writers
(Netpbm `ppmtopict`, ImageMagick) that render pixel-exactly. Native
resolution rendering moved to task 19a.

13. `Images` views and validators (descriptor arithmetic SPARK-ready).
14. `Internal.Canvas` (heap, budgeted), `Internal.Regions` (parse + scanline mask), clip region.
15. `Internal.PackBits` (byte and word variants) and `Internal.Pixmaps`: BitMap/PixMap headers,
    color tables, rows for 1/2/4/8/16/32 bpp and pack types 1–4.
16. `BitsRect/Rgn`, `PackBitsRect/Rgn`, `DirectBitsRect/Rgn`: scaling, clip, mask, `srcCopy`;
    `Render` into the caller view.

**Gate M2:** raster fixtures (hand-built and external) render to the reference rasters exactly.

## M3 — QuickDraw rasterizer

**Completed (2026-10-24):** Tasks 17–19 and Gate M3. Port state (origin, clip,
pen, bit and pixel patterns, planar and RGB colors, oval size, highlight),
transfer modes for patterns and copies with colorizing, and every shape verb for
lines, rects, round rects, ovals, arcs, polygons and regions, with the "same"
variants, render to hand-computed rasters. No QuickDraw reference
renderer was available: the geometry follows QuickDraw where it is documented
and the integer rules of the specification elsewhere; checking those against a
real QuickDraw rendering is added to task 26. Task 19a stays open.

17. Port state: origin, pen, patterns (8×8 and pixel patterns), colors (v1 planar and RGB).
18. `Internal.Transfer_Modes`: boolean and arithmetic modes, for shapes and copies.
19. Lines, rects, rounded rects, ovals, arcs, polygons, regions × frame/paint/erase/invert/fill,
    "same" variants, drawing-work budget; colorized copies and the Origin opcode.
19a. Optional rendering at an extended header's native resolution.

**Gate M3:** vector fixtures render pixel-exactly to reviewed reference rasters.

## M4 — Text

**Completed (2026-10-24):** Tasks 20–21 and Gate M4. Text draws with TrueType
fonts through `textrender`; the caller's `Fonts.Font_Table` resolves families by
`fontName`, ID, classic name and default. The text state, the four text opcodes,
Mac Roman, face synthesis, text modes and spacing render exactly as textrender's
glyphs placed by the specification's layout rules (88 tests, with DejaVu test
fonts committed under their license).

20. `Fonts.Font_Table` of caller-supplied TrueType files; `textrender` as the glyph rasterizer.
21. Text state and the four text opcodes, Mac Roman mapping, face synthesis.

**Gate M4:** text fixtures match textrender's glyphs placed by the specification's layout rules;
font resolution and missing fonts behave as specified.

## M5 — QuickTime JPEG

**Completed (2026-10-24):** Tasks 22–23 and Gate M5. `CompressedQuickTime` is
parsed within its opcode and its JPEG decoded by jpeglib straight from the
picture, then drawn through the matrix (translation and scaling), srcRect, mask,
clip and transfer mode; the placeholder bitmap QuickTime writes after the image
is skipped. Two QuickTime PICTs written by ImageMagick render within two levels
of libjpeg's decoding of their JPEGs, and hand-built opcodes cover placement,
masks, modes, the placeholder, unsupported codecs, mattes and matrices, broken
JPEGs and the embedded budgets.

22. `Internal.QuickTime`: parse `16#8200#`/`16#8201#`, `ImageDescription`, matrix, matte, mask.
23. Bridge to `jpeglib` decoding with byte/pixel budgets; error mapping; drawing via the matrix.

**Gate M5:** QuickTime JPEG fixtures from independent producers render within the documented
tolerance of JPEG decoding; non-JPEG codecs and corrupt payloads fail or warn as specified.

## M6 — Raster encoding

**Completed (2026-10-24):** Tasks 24–25 and Gate M6. `Pictlib.Encoding` writes
`Direct_32`, `Indexed_8` and `Mono_1` pictures (and chooses with `Auto`) from
views in every pixel format, round-tripping exactly through pictlib.
`pictlib_conformance` has LibreOffice's own PICT import read all ten conformance
pictures exactly and ImageMagick the four it can read; ImageMagick 7 needs the
file header, misreads unpacked rows and draws BitMaps black, so those pictures
rest on LibreOffice. Netpbm `picttoppm` was not available as a third reader.

24. `Internal.Writers`: header, opcodes, alignment, PackBits packing, color tables.
25. `Encoding`: `Direct_32`, `Indexed_8`, `Mono_1`, `Auto`; header and resolution options.

**Gate M6 (first release):** encoder output decodes identically in pictlib and in independent
decoders (LibreOffice for every picture, ImageMagick where its reader applies); decode corpus
passes.

## M7 — Conformance, security and completeness

**Completed (2026-10-24):** Tasks 26–29 and the library-complete gate, with the
open items below. `pictlib_complete` runs every gate: the source policy
(`pictlib_check`), the AUnit suite, the real-world corpus
(`pictlib_real_world`: LibreOffice's PICT filter test files at a pinned commit,
pass and fail, CVE reproductions among them), mutation fuzzing (`pictlib_fuzz`;
300 000 inputs found no defect), the SPARK proof profile (`pictlib_prove`) and
encoder conformance (`pictlib_conformance`). The stress suite covers reset
reuse, independent decoders in four tasks and a matrix of every limit kind; the
concurrency test exposed textrender's shared rasterizer buffers, now behind a
lock. `pictlib_benchmark` reports throughput. CI mirrors jpeglib's.

Open:

- The shape and text rules (specification sections 3.2 and 3.4) have not been
  compared with real QuickDraw: that needs classic Mac OS under emulation, with
  its ROM and system software, which this environment lacks.
- Netpbm `picttoppm` was not available as a third independent reader.
- The CI workflow has not run on GitHub yet.
- Task 19a, rendering at an extended header's native resolution.

26. Real-world corpus with provenance, external oracle matrix, fuzz harness and seed corpus;
    compare shape rendering with a QuickDraw reference (classic Mac OS emulation or a reference
    implementation) and revise the specification's shape rules where they differ.
27. Stress and limit matrix, cancellation/reset reuse, benchmark tool.
28. `proof/pictlib_proof.gpr`: checked arithmetic, image descriptors and opcode length rules;
    `pictlib_prove` via `alr exec`. Region bounds remain open: regions are covered by tests and
    fuzzing, not proof.
29. CI workflow mirroring `jpeglib`'s; README capability matrix.

**Library-complete gate:** every `Capabilities` feature is tested, proofs pass, no required check
is waived.

## Cross-cutting acceptance checklist

- Clean build under `-gnatwa -gnatyM120`; all tests pass through `alr`.
- New input-derived sizes use checked arithmetic and limits before allocation or loops.
- Malformed-input tests accompany every parser.
- CHANGELOG entry and plan status updated.
