# Changelog

## 0.1.0-dev

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
