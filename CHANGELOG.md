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
- `Pictlib.Opcodes` names every opcode pictlib draws, and
  `Pictlib.Encoding.Default_Mono_Threshold` the default Mono_1 threshold.
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

### Fixed

- Text after `HiliteMode` draws in the hilite mode, and the flag no longer
  carries over to the drawing after the text.
- An encoder frame taller than `Max_Frame_Height` reports the height limit
  and height, not the width's.
- A per-opcode size that overflows reports the size that saturated, not 0.
- Every strict failure and its lenient warning carry the same context: a
  wrong or missing HeaderOp, a dropped metadata item, a bad color index and
  an oversized pattern tile now name their offset, opcode and ordinal both
  ways, and every failure inside an opcode names its ordinal.
- The encoder checks `Max_Allocation_Bytes` against the row buffers of the
  layout it writes, not always against 32-bit rows.
- Copying a metadata item reads it in place instead of copying it to the
  stack first, and a too-short buffer reports its size as the expected
  value and the item's size as the actual one.
- A framed polygon stops working once its shape's allowance is spent,
  instead of sizing and clearing row buffers for every later segment.
- The decoder fails with `Internal_Invariant_Failed` when a source claims
  more bytes than it was asked for after the picture byte budget capped the
  request, instead of trusting the count.
- Going over `Max_Total_Allocation_Bytes` while retaining metadata always
  fails, as every limit does; a lenient decoder drops an item only when the
  metadata budgets have no room for it.
- Text is painted row by row across the whole string, so a complex clip
  region is walked once per opcode, not once per glyph.
- A QuickTime image's matte and mask that leave no room for the image
  description fail before the description is read.
- A missing end opcode finishes with a `Compatibility_Issue` warning in
  both lenient modes; the specification no longer also lists it among the
  partial pictures of `Recover_When_Safe`.
- An oversized `PixPat` tile's `Approximated_Rendering` warning is recorded
  only once its rows are skipped and the pattern is charged.
- An indexed PixMap allows pack types 0 and 1, as the specification now
  says; any other is `Pixmap_Invalid`, as for direct pixmaps.
- HeaderOp's own warnings and failures name its offset and ordinal; an
  origin moved out of reach names the origin's bound; the picture byte and
  metadata budgets name the amount that crossed them.
- The encoder writes nothing more to a destination after it fails once, so
  a destination that recovers never holds a picture with a gap in it, and
  `Bytes_Written` counts what the destination took of a cut-short write.
- An invert verb after `HiliteMode` highlights its shape instead of
  inverting it, as the specification now says.
- A shape stopped by `Max_Total_Allocation_Bytes` reports that limit, not
  `Max_Drawing_Work`.
- A retained comment is checked against `Max_Opcode_Bytes` before the
  metadata budgets, so the retention policy never changes which limit a
  picture crosses.
- The version opcode's data and HeaderOp's 24 bytes count against
  `Max_Opcode_Bytes`, as they would anywhere in a picture.
- A frame over `Max_Canvas_Pixels` leaves the decoder `Failed` with that
  error, since no view can render it; a rejected view still leaves it
  `Header_Read`, as the specification now says of both.
- A font that fails to load no longer evicts a loaded font: a new font
  loads into a spare renderer, and the least recently used of the eight is
  evicted only once it has loaded.
- Text keeps every glyph when the font atlas empties part-way through a
  string: a string is painted in runs of glyphs that share one atlas
  generation, and the glyphs a request displaced are taken again, charged
  as glyph work, and painted one by one.
- A jpeglib limit is `Limit_Exceeded` on pictlib's matching limit, a JPEG
  feature jpeglib does not decode is `Unsupported_Feature` (skipped with a
  warning in the lenient modes, like another codec), and jpeglib's own
  invariants are `Internal_Invariant_Failed`; only malformed JPEG data is
  `Embedded_Image_Failed` and recovered. jpeglib's code is kept underneath.
- With the file header on, an encoder over `Max_Output_Bytes` reports that
  limit as set, the header counted, at the file offset.
- `Warnings_Suppressed` carries the number of warnings suppressed.
- A text opcode ends at the first failure while the glyphs an atlas
  eviction displaced are painted again; a later, smaller charge no longer
  lets drawing go on past the work limit.
- Malformed JPEG metadata, a broken ICC chain among it, is
  `Embedded_Image_Failed` again, and a frame of more components than
  jpeglib decodes is `Unsupported_Feature`; jpeglib's buffers outgrowing
  their share name the share they had. That share is sized over the image's
  extent rounded up to 16-pixel MCUs, so narrow subsampled JPEGs decode:
  `quicktime.narrow_image` renders a 1 × 16000 progressive 4:2:0 JPEG
  written by jpeglib's encoder, which the unpadded share refused.
- The picture reader no longer clears the rest of a caller's buffer on
  every short read, which made long payloads from a source that delivers in
  small pieces quadratic in work no budget counted; nor does the source
  jpeglib reads QuickTime images through.
- Source offsets saturate, so a source reporting offsets near the largest
  there is cannot make the decoder raise.
- The specification describes text cells stretched to their ink, the work
  of copying a region shape, the font file bytes a load is charged, and
  `Font_Unavailable`; `Warning_Record_Limit` is documented as never crossed.

### Internal structure

No behaviour changes; what each part of the library does now lives in one
place:

- `Internal.Failures` builds the failures several units report: a crossed
  limit, a malformed opcode, a failure within a pixel row, and the frame
  size limits the decoder and the encoder share.
- `Rendering.Drawing_Mode` gives copies, QuickTime images and text their
  transfer mode, hilite included; `Rendering.Sampled` is the one
  nearest-neighbour scaling rule copies and images use.
- One reader for QuickDraw's (v, h) pairs, one heap buffer deallocator, and
  one test of whether the encoder keeps alpha.
- A session's counters (allocations, drawing work, opcodes, where an
  opcode's data begins) are private to `Internal.Sessions`, which every
  other unit reaches through its operations.
- A painter's port state is one record whose defaults are QuickDraw's; each
  render starts from it, so no field can keep a value from the last render.
- `Opcode_Bytes` gives the size of an opcode, and of the version opcode's
  data, for every version in one place.
- Retained metadata and warnings are private to `Internal.Sessions`: one
  `Retain` for data read from the stream, the file header included, and one
  `Retain_Bytes` for data already read.
- The encoder builds its plan once, with whether its rows are packed; the
  planar row layout (alpha, red, green, blue planes) is one definition the
  encoder and the decoder share, and both pixmap header readers share the
  PixMap fields and color table.
- A shape opcode builds its coverage in one function per kind. A filled
  polygon's edges count against `Max_Total_Allocation_Bytes` besides its
  points, and a shape opcode with a reserved verb is never drawn whatever
  the opcode table says.
- `PackBits.Pack` packs bytes, the only rows the encoder writes, and states
  its output size in its precondition.
- `Picture_Stream` judges every reply of a source in one place, so an
  over-reported count and a stall carry the same context wherever they
  happen; a clip and a mask cut a row through one helper, which charges
  the region walk before cutting.
- `Pictlib.Fonts` keys font IDs by `Font_ID`.
- The byte readers carry no opcode of their own: the session attributes
  every failure to its opcode in one place. The container uses the one
  opcode-boundary test, and the encoder surveys colors only for `Auto` and
  `Indexed_8`.
- `Internal.Sessions.Session` is private: its budget, version, strictness
  and retention are read through functions, and its reader is reached only
  for what lies outside an opcode's budget-checked data (the header, opcode
  words, pad bytes and the probe past the end).
- `Encode` reads as its steps: check the frame, choose the layout, check
  the plan, write. A QuickTime image's pixel buffer is admitted like every
  other allocation, and `Decide_Layout` keeps one check per pack type and
  component count.

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
- Every tool runs from anywhere below the pictlib tree and finds its
  fixtures itself.
- `pictlib_check` keeps `docs/invariants.md` true to the suite: every
  coverage name it cites must be a registered test or a tool, and its
  capability table must list every `Pictlib.Capabilities` constant.
- Every tool reports failures the same way, as `tool: message` on standard
  error with a failing exit status.
- CI steps are single commands.
- The library and the tests crate build with `-gnatwe`: a warning or style
  finding in any unit either compiles fails the build, so `pictlib_check`
  cannot pass with one.
- The tests crate has one seeded pseudo-random generator
  (`Pictlib_Testing.Random`) and one file loader; the encoder tests check
  the alpha plane's values byte for byte, independently of the decoder.
- `pictlib_conformance` has ImageMagick and LibreOffice read pictures that
  keep alpha and pictures `Auto` laid out; the test-side rowBytes rule lives
  in `Samples`, and every failing render test checks the decoder's state and
  last error.
