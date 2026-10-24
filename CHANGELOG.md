# Changelog

## 0.1.0-dev

Nothing is released yet; this describes what the first release holds. The
specification (`docs/SPECIFICATION.md`) is the contract each item refers to.

### Added

- Containers: PICT version 1, version 2 and extended version 2, with or
  without the 512-byte file header, detected within a 528-byte look-ahead
  without seeking. `picSize` is retained, never checked.
- Enumeration (`Pictlib.Decoding.Enumerate`): every opcode with its ordinal,
  offset and data length, consumed by its Inside Macintosh Appendix A layout;
  comments, font names, file headers, QuickTime and reserved payloads
  retained on request under item and byte budgets.
- Raster rendering (`Pictlib.Decoding.Render`) into a caller-owned view in
  five pixel formats and any stride: BitMaps, indexed PixMaps (1, 2, 4, 8
  bits), direct PixMaps (16 and 32 bits) in every pack type, PackBits rows
  of bytes and words, nearest-neighbour scaling, clip regions and masks.
- Vector rendering: QuickDraw's port state and its lines, rects, round
  rects, ovals, arcs, polygons and regions, framed, painted, erased,
  inverted and filled, with the "same" opcodes, bit, color and dither
  patterns, and every boolean and arithmetic transfer mode. Shapes are
  computed in integers only, identically on every platform.
- Text through `textrender` (a production dependency): TrueType fonts the
  caller maps to Macintosh families and IDs (`Pictlib.Fonts`), Mac Roman,
  bold, italic, underline, condense, extend, sizes up to 512, `SpExtra` and
  `ChExtra`. pictlib ships no fonts.
- QuickTime: `CompressedQuickTime` JPEG images through `jpeglib`, placed by
  the matrix (translation, positive scaling), srcRect, mask, clip and
  transfer mode, `HiliteMode` included; the placeholder bitmap after an
  image is skipped.
- Encoding (`Pictlib.Encoding`): raster PICT version 2 as `Direct_32`,
  `Indexed_8`, `Mono_1` or `Auto`, with an extended header and an optional
  file header; picSize is measured by a dry run.
- Strictness modes `Strict`, `Compatible` and `Recover_When_Safe`, with
  structured, non-raising results, stable `pict.*` identifiers and warnings.

### Hostile input

- Every budget in `Pictlib.Limits` fails before it is crossed:
  - frame, canvas, output, picture, per-opcode, region, polygon, metadata,
    warning and embedded-image limits;
  - `Max_Allocation_Bytes` for each allocation and an optional monotonic
    `Max_Total_Allocation_Bytes` for a whole session;
  - `Max_Drawing_Work` (default 2^30, about a minute of work) for all
    rendering work, drawn or not: see the specification, section 9.
- Coordinates stay within ±2^24, so no coordinate arithmetic overflows.
- Constructs a release cannot render (other QuickTime codecs, mattes,
  skewing matrices, outline and shadow text, color tiles of more than
  2^31 − 1 pixels) fail with `Unsupported_Feature` in `Strict` and are
  skipped with a warning otherwise.
- `hostile.*` tests hold the cases that once overflowed or worked without
  bound, asserting their cost through budgets, never the clock.

### Tooling

All tooling is Ada, in the `tests` crate:

- `pictlib_check`: the day-to-day gate, which builds the library, enforces
  the source and dependency policy, and runs the AUnit suite.
- `pictlib_complete`: adds the LibreOffice real-world corpus
  (`pictlib_real_world`), deterministic mutation fuzzing (`pictlib_fuzz`),
  SPARK proofs at level 0 (`pictlib_prove`) and encoder conformance against
  ImageMagick and LibreOffice (`pictlib_conformance`).
- `pictlib_generate` regenerates the external fixtures.
- `pictlib_benchmark`.
- CI steps are single commands.
