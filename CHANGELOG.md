# Changelog

## 0.1.0-dev

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
