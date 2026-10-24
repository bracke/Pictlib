# Changelog

## 0.1.0-dev

- Specification and implementation plan: PICT version 1, version 2 and
  extended version 2 decoding with a full QuickDraw renderer, QuickTime JPEG
  through `jpeglib`, and raster PICT version 2 encoding, in milestones M0–M7.
- Gate M0: the `pictlib` Alire crate (GNAT 15, `jpeglib` path pin) and its
  `tests` crate; root scalar types, `Version`, `Capabilities`, `Errors` with
  stable `pict.*` identifiers and opcode-aware diagnostic context, `Results`,
  `Limits`, `Streams` with memory adapters and exact transfer helpers,
  `Internal.Checked_Arithmetic` and checked big-endian `Internal.Bytes`;
  15 AUnit tests covering them.
