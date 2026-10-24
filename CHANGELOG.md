# Changelog

## 0.1.0-dev

- Tooling fixes from code review. `pictlib_generate` makes everything in a
  staging directory and copies it into place only when every step succeeded,
  refuses `--output` without a value, and no longer raises on a missing
  picture after an earlier failure. ImageMagick, gnatprove and the
  executable suffix are looked up in one place (`Pictlib_Testing.Tools`):
  ImageMagick 6's `convert` is taken only when it reports itself as
  ImageMagick (never Windows' convert.exe), and the Alire-installed gnatprove
  wins over one on `PATH`. `pictlib_check` builds and `pictlib_prove` runs
  `alr exec` non-interactively, and the AUnit suite runs even when the source
  policy finds something, so a policy finding cannot hide a failing test.
- All tooling and scripting is Ada. `scripts/check_all.sh` is replaced by
  `pictlib_check`, now the day-to-day gate (library build, source policy,
  AUnit suite; `--policy-only` for the policy alone), which `alr test` runs.
  `tests/fixtures/external/generate.sh` and its embedded Python are replaced
  by `pictlib_generate`, which reproduces the committed fixtures byte for
  byte. CI steps are single commands: `pictlib_complete` gained
  `--without-conformance` and finds its tools' executable suffix,
  `pictlib_conformance` falls back to ImageMagick 6's `convert`, and
  `pictlib_prove` finds an Alire-installed gnatprove off `PATH`.
- Gate M7, library-complete. New tools in the tests crate: `pictlib_check`
  (line length, GNATdoc tags on the public API, production dependencies),
  `pictlib_real_world` (LibreOffice's PICT filter test files at a pinned
  commit, MPL-2.0, held to recorded outcomes), `pictlib_fuzz` (deterministic
  mutation fuzzing; 300 000 inputs, no defects), `pictlib_prove` (SPARK:
  checked arithmetic, image descriptors, opcode rules and PackBits `Unpack`
  proved at level 0), `pictlib_benchmark` and `pictlib_complete` (every
  gate). A stress suite covers reset reuse, decoders in concurrent tasks and
  every limit kind. Fixes found on the way: textrender's rasterizer shares
  scratch buffers between renderers, so concurrent text failed -- textrender
  is now called under one process-wide lock; a 205-megapixel real-world
  picture took 16 s -- uniform fills whose result does not depend on the
  destination are now span writes, polygons use an active edge list, and the
  background fill copies rows (1.1 s); eight over-long source lines that
  incremental builds had hidden. `PackBits.Unpack` became a procedure, for
  SPARK. `Limits.Max_Canvas_Bytes` and `Canvas_Byte_Limit`, never enforced,
  are removed. A CI workflow mirrors jpeglib's. 107 AUnit tests.
- Gate M6: `Pictlib.Encoding` writes raster PICT version 2. `Direct_32`
  (DirectBitsRect, PackBits over component planes, alpha optional),
  `Indexed_8` (PackBitsRect with an exact color table), `Mono_1` (a BitMap
  under a luminance threshold) or `Auto`; extended version 2 header with the
  chosen resolution, optional 512-byte file header, picSize measured by a dry
  run so the destination stays forward-only, rows stored as QuickDraw stores
  them. The new `pictlib_conformance` tool has LibreOffice's PICT import read
  every conformance picture exactly and ImageMagick every one its reader
  handles. 103 AUnit tests.
- Gate M5: `CompressedQuickTime` images with JPEG data render. jpeglib
  reads the JPEG straight from the picture, at most the stated data size,
  under the embedded byte, pixel and allocation budgets; the image is drawn
  through the matrix (translation and positive scaling), srcRect, mask
  region, clip and transfer mode, without colorizing. The placeholder bitmap
  QuickTime writes after an image for systems without the codec is skipped,
  as QuickTime skips it. Other codecs, mattes and skewing matrices are
  unsupported; corrupt JPEGs are `Embedded_Image_Failed` and recoverable.
  Two QuickTime PICTs from ImageMagick match libjpeg within two levels.
  95 AUnit tests.
- Gate M4: text renders with TrueType fonts through `textrender`, a new
  production dependency. `Pictlib.Fonts.Font_Table`, in the decode options,
  maps Macintosh families and font IDs to font files; a picture's `fontName`,
  the ID, the classic Macintosh name of the ID and a default are tried in
  turn, and a missing font is `Font_Unavailable` strictly. `LongText`,
  `DHText`, `DVText` and `DHDVText` draw Mac Roman text from the text origin
  in the port's font, face (bold, italic, underline, condense, extend), size,
  mode and colors, with `SpExtra` and `ChExtra`, without antialiasing.
  DejaVu fonts are committed as test fixtures under their license. 88 AUnit
  tests.
- Gate M3: the renderer draws QuickDraw's vector opcodes. Port state — origin,
  clip, pen size, mode and location, bit patterns, color and dither pixel
  patterns, planar and RGB foreground and background, OpColor, highlight,
  oval size — follows the picture; lines, rects, round rects, ovals, arcs,
  polygons and regions are framed, painted, erased, inverted and filled,
  with the "same" opcodes. Transfer modes, boolean and arithmetic, apply to
  shapes and copies alike; copies are colorized by the foreground and
  background colors and move with the origin. Shapes are computed in
  integers only, identically on every platform, under the drawing budget.
  Text and QuickTime images remain unsupported until M4 and M5. 80 AUnit
  tests.
- Gate M2: `Pictlib.Decoding.Render` draws a picture's bitmaps and pixmaps
  into a caller-owned view (`Pictlib.Images`, five pixel formats, any stride),
  filled first with a background color. BitMaps and 1-, 2-, 4- and 8-bit
  indexed PixMaps with sparse or device color tables, 16-bit and 32-bit direct
  PixMaps in every pack type, PackBits rows of bytes and words, nearest-
  neighbor scaling from srcRect to dstRect, clip regions and the masks of the
  `Rgn` opcodes. Rows stream one at a time; regions keep only their current
  inversion set. Drawing not yet rendered fails strictly and warns otherwise;
  `Recover_When_Safe` keeps what was drawn before malformed data. Four PICTs
  written by Netpbm and ImageMagick render pixel-exactly against their
  sources. The version -1 HeaderOp's fixed-point bounds are now read left,
  top, right, bottom, as Netpbm writes them. 68 AUnit tests.
- Gate M1: `Pictlib.Decoding` reads PICT version 1, version 2 and extended
  version 2 containers — the 512-byte file header detected within a 528-byte
  look-ahead, without seeking — and enumerates every opcode with its ordinal,
  offset and data length. Each opcode's data is consumed by its Appendix A
  layout: regions, polygons, pixel patterns, color tables and BitMap/PixMap
  rows in every pack type, with version 2 alignment. Comments, font names,
  file headers, QuickTime and reserved payloads are retained under item and
  byte budgets. Strict, compatible and recovering modes differ only where the
  specification says so; every budget fails before it is crossed. New public
  packages `Geometry`, `Opcodes`, `Pictures`, `Metadata`, `Decoding`; new
  error code `Invalid_Argument`; `docs/invariants.md` and
  `docs/limits_and_safety.md`. 49 AUnit tests.
- Specification and implementation plan: PICT version 1, version 2 and
  extended version 2 decoding with a full QuickDraw renderer, QuickTime JPEG
  through `jpeglib`, and raster PICT version 2 encoding, in milestones M0–M7.
- Gate M0: the `pictlib` Alire crate (GNAT 15, `jpeglib` path pin) and its
  `tests` crate; root scalar types, `Version`, `Capabilities`, `Errors` with
  stable `pict.*` identifiers and opcode-aware diagnostic context, `Results`,
  `Limits`, `Streams` with memory adapters and exact transfer helpers,
  `Internal.Checked_Arithmetic` and checked big-endian `Internal.Bytes`;
  15 AUnit tests covering them.
