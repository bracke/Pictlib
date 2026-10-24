# pictlib — Native Ada QuickDraw PICT Codec

**Status:** authoritative implementation contract  
**Version:** 0.1.0-dev  
**Plan:** [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md)  
**Reference architecture:** https://github.com/bracke/jpeglib (`../jpeglib`)

Normative words: **shall** is a requirement, **should** is a recommendation, **may** is permitted.

## 1. Purpose and scope

`pictlib` is a native Ada 2022 library that reads and writes Apple QuickDraw pictures (`PICT`).

- **Decode** PICT version 1, version 2 and extended version 2 pictures, from files (with the
  512-byte application header) and from bare picture data (resources, clipboard, embedded).
- **Render** the whole picture into a caller-owned RGBA canvas: bitmap and pixmap opcodes,
  QuickDraw vector primitives (lines, rectangles, rounded rectangles, ovals, arcs, polygons,
  regions), patterns, pen state, clipping, transfer modes and text.
- **Enumerate** the opcode stream without rendering, and retain picture comments, font names
  and other non-pixel content as bounded metadata.
- **Decode embedded JPEG** carried by the QuickTime compressed-image opcode (`16#8200#`) through
  the public API of `jpeglib`.
- **Draw text** with TrueType fonts the caller supplies, through the public API of `textrender`.
- **Encode** raster PICT version 2 (extended header) from caller pixel views.

Out of scope: rendering the QuickDraw GX or QuickDraw 3D payloads that pictures may carry in
comments; QuickTime codecs other than JPEG; encoding vector opcodes (the opcode writer layer
may emit them internally but no public vector-encoding API is promised); PostScript comments
are retained, never interpreted.

## 2. Normative behavior

- Expected invalid input never raises: every public operation reports an `Errors.Error` inside a
  `Results.Result`. An exception escaping the public API is a defect.
- Default strictness is `Strict`. `Compatible` accepts documented deviations seen in real files
  (wrong `picSize`, missing end opcode at EOF, odd padding). `Recover_When_Safe` additionally
  renders what was decoded before a recoverable failure and reports `Partial_Picture`. Each
  accepted deviation records a `Warning`.
- Behavior is deterministic: the same bytes, options and limits produce the same pixels,
  warnings and errors on every platform.

## 3. Format requirements

### 3.1 Container

- A PICT **file** begins with a 512-byte application header whose contents are ignored but may be
  retained as metadata. Picture data in resources or embedded streams has no header.
  `Header_Policy` is `Auto` (default), `Has_File_Header` or `No_File_Header`. `Auto` accepts the
  header when a valid version opcode follows `picSize` and `picFrame` at offset 512, otherwise at
  offset 0 (a file header is preferred when both match); it shall not require seeking. The first
  528 bytes are held in a look-ahead buffer, which never reads beyond the picture byte limit.
  When the policy names a header the version opcode must be where it says, otherwise the result is
  `Version_Invalid`.
- `picSize` (16 bits) is the low word of the picture length; for version 2 it is unreliable and
  shall be retained but never used to bound parsing. `picFrame` is a `Rect`.
- **Version 1:** version opcode `16#11#` followed by `16#01#`. Opcodes are one byte; data is not
  aligned; end opcode `16#FF#`.
- **Version 2:** `16#0011#` followed by `16#02FF#`, then `HeaderOp` `16#0C00#` with 24 data bytes.
  Header version `-1` (a long) carries fixed-point picture bounds stored left, top, right,
  bottom — the order Netpbm's `ppmtopict` writes — and four reserved bytes (version 2); `-2` carries `hRes`, `vRes`
  (Fixed, 72 dpi default) and an integer source rectangle (extended version 2). Opcodes are two
  bytes and every opcode starts on an even offset from the start of the opcode stream, so odd
  data lengths are followed by one pad byte. End opcode `16#00FF#`.
- Every opcode shall be parsed against the length rules of Inside Macintosh: *Imaging With
  QuickDraw*, Appendix A, including the reserved ranges, which shall be skipped by their defined
  lengths. Reserved opcodes inside a shape group take the data length of that group (for example
  `16#0035#..16#0037#` take a rect, `16#0065#..16#0067#` take an arc, `16#0075#..16#0077#` a
  polygon, `16#0085#..16#0087#` a region; `16#003D#..16#003F#` take none), `16#0017#..16#0019#`
  carry no data; `16#0024#..16#0027#`,
  `16#002F#`, `16#0092#..16#0097#`, `16#009C#..16#009F#`, `16#00A2#..16#00AF#` carry a 16-bit
  length then data; `16#00B0#..16#00CF#` carry no data; `16#00D0#..16#00FE#` carry a 32-bit length
  then data; `16#0100#..16#7FFF#` carry `2 * (opcode / 256)` bytes; `16#8000#..16#80FF#` carry no
  data; `16#8100#..16#FFFF#` carry a 32-bit length then data. Reserved opcodes record a
  `Reserved_Opcode_Skipped` warning; in `Strict` mode they are still accepted (they are legal).
- A length that would cross the configured opcode, region, polygon or picture byte limits fails
  with `Limit_Exceeded` before any allocation.

### 3.2 State and drawing opcodes

- The renderer keeps a QuickDraw graphics port state: origin (`16#000C#`), clip region
  (`16#0001#`), pen size/mode/pattern/location (`16#0007#`, `16#0008#`, `16#0009#`, `16#0015#`),
  fill and background patterns (`16#000A#`, `16#0002#`) and pixel patterns (`16#0012#..16#0014#`),
  oval size (`16#000B#`), foreground/background/op/hilite colors (`16#000E#`, `16#000F#`,
  `16#001A#`, `16#001B#`, `16#001D#`, `16#001F#`), and text state (`16#0003#..16#0006#`,
  `16#000D#`, `16#0010#`, `16#0016#`, `16#002C#..16#002E#`).
- Version 1 colors (`16#000E#`, `16#000F#`) map the eight QuickDraw planar colors to RGB as
  Color QuickDraw shows them (whiteColor 30, blackColor 33, yellowColor 69 `FC F3 05`,
  magentaColor 137 `F2 08 84`, redColor 205 `DD 08 06`, cyanColor 273 `02 AB EA`, greenColor
  341 `00 80 11`, blueColor 409 `00 00 D4`); any other value is `Unsupported_Feature` in
  `Strict` and leaves the color unchanged with a warning otherwise. RGB colors keep the high byte
  of each 16-bit component.
- Coordinates read from the picture are local. `Origin` (`dh`, `dv`) moves the local system and
  accumulates; a local point `p` is picture point `p − origin`. The clip region keeps its local
  coordinates when the origin moves, as `SetOrigin` leaves `clipRgn` alone. Pen location is kept
  in picture coordinates.
- Pixel model: pixel `(x, y)` is the unit square from `(x, y)` to `(x + 1, y + 1)`; a rectangle
  covers columns `left .. right − 1` and rows `top .. bottom − 1`. The pen is `pnSize`
  (`v`, `h` = height, width) and hangs below and right of its location. A zero or negative pen
  dimension draws no lines and no frames.
- Shapes, where QuickDraw documents no exact rule, use these, with all arithmetic in integers:
  - oval: the pixels whose centres lie inside the ellipse inscribed in the rectangle;
  - round rect: the rectangle with each corner cut by a quarter of the `OvSize` oval (clamped to
    the rectangle); a zero oval size is a rectangle;
  - arc: the oval's pixels whose centres lie in the sweep from `startAngle` through `arcAngle`
    degrees (0 at 12 o'clock, clockwise, negative sweeps backward, 360 or more is the whole oval),
    the angles stretched so that 45° passes through the rectangle's corner; tested with a table
    of `sin (k°) × 2³⁰` and exact cross products, so results are identical on every platform;
  - polygon: even-odd at pixel centres, closed automatically;
  - line: the pen rectangle at every point of the Bresenham line between the endpoints, both
    included;
  - frame: the shape less the shape inset by the pen (`pnSize` width horizontally, height
    vertically); a framed round rect's inner oval is `OvSize` less twice the pen; `framePoly`
    draws the polygon's lines without closing it; `frameRgn` erodes the region by the pen,
    separably.
- Verbs: `frame` and `paint` use the pen pattern and pen mode (a source mode `0 .. 7` acts as the
  matching pattern mode), `erase` the background pattern with `patCopy`, `fill` the fill pattern
  with `patCopy`, and `invert` inverts each component. One last rectangle serves the "same"
  opcodes of rects, round rects, ovals and arcs; polygons and regions keep their own. Before any
  shape, "same" draws nothing.
- Patterns tile from picture coordinate (0, 0). A bit pattern's 1 bits are the foreground and its
  0 bits the background; a color `PixPat` (type 1) is drawn with its own colors and is not
  colorized; a dither `PixPat` (type 2) is drawn as its RGB color.
- Transfer modes act on 8-bit components. For the boolean modes, each source component `s` (a
  copied pixel, or a pattern's black-or-white sample) says how near to black the source is:
  `copy = mix (fg, bk, s)`, `or = mix (fg, dst, s)`, `bic = mix (bk, dst, s)`,
  `xor = dst xor (255 − s)`, the `not` modes use `255 − s`, where `mix (a, b, s)` is
  `(a (255 − s) + b s + 127) / 255`. With a black foreground and white background this is
  QuickDraw's black-and-white arithmetic and `copy` reproduces the source exactly; otherwise it is
  Color QuickDraw's colorizing, for copies of every depth. Arithmetic modes use `OpColor`: blend
  weights by it, `addPin`/`subPin` pin to it, `addOver`/`subOver` wrap, `addMax`/`adMin` take the
  larger or smaller component, `transparent` leaves pixels equal to the background color alone.
  `hilite` (and the drawing operation after `HiliteMode`) swaps the background and highlight
  colors under dark source pixels; `DefHilite` resets the highlight to black. `grayishTextOr`
  acts as `srcOr`. Unknown modes fail with `Transfer_Mode_Invalid` in `Strict` and act as copy
  with a warning otherwise.
- A real QuickDraw reference renderer was not available when these rules were written; comparing
  them against one is an M7 conformance task, and the rules change only through this document.
- Shapes: `frame`, `paint`, `erase`, `invert`, `fill` for rect (`16#0030#..`), rounded rect
  (`16#0040#..`), oval (`16#0050#..`), arc (`16#0060#..`), polygon (`16#0070#..`) and region
  (`16#0080#..`), plus each "same" variant. Lines: `16#0020#..16#0023#`. QuickDraw draws without
  antialiasing and so does the renderer.
- Regions: 16-bit size, bounding rect, then the inversion-point scanline encoding terminated by
  `16#7FFF#`. Rectangular regions have size 10. A pixel is inside when an odd number of inversion
  points lie at or above it and at or left of it. Scanline `y` values must increase strictly and
  lie within the bounding box, inversion points must increase strictly within a scanline, lie within
  the box and be even in number on every scanline, and the final terminator must end the data
  exactly; anything else fails with `Region_Invalid`. Rows are walked top to bottom holding only
  the current inversion set, and that work counts against the drawing budget.
- Polygons: 16-bit size, bounding rect, then points; the point count is `(size - 10) / 4`.

### 3.3 Bitmaps and pixmaps

- `BitsRect` / `BitsRgn` (`16#0090#`, `16#0091#`), `PackBitsRect` / `PackBitsRgn` (`16#0098#`,
  `16#0099#`): `rowBytes` with bit 15 set introduces a PixMap (then a color table follows),
  otherwise a 1-bit BitMap. Pixel sizes 1, 2, 4, 8 indexed; 16 and 32 direct for pixmaps.
  Then source rect, destination rect, transfer mode, optional mask region, then pixel data.
- `DirectBitsRect` / `DirectBitsRgn` (`16#009A#`, `16#009B#`): a 4-byte `baseAddr`
  (`16#000000FF#`), then the PixMap without a color table. 16-bit pixels are `x555`; 32-bit
  pixels are `xRGB` or `ARGB` (`cmpCount` 3 or 4).
- `rowBytes` keeps its flags in the high bits: bit 15 marks a PixMap and the PixMap row length is
  `rowBytes and 16#3FFF#`; a BitMap's is `rowBytes and 16#7FFF#`.
- `BitsRect`/`BitsRgn` data is always unpacked, `rowBytes` per row. Otherwise pixel data is
  unpacked when `rowBytes < 8` or `packType = 1`; `packType = 2` (32 bpp only) is unpacked at
  three bytes per pixel of the bounds width. Otherwise every row is prefixed
  by its packed byte count, one byte when `rowBytes <= 250` and two bytes otherwise. `packType`
  0/default uses PackBits on bytes (indexed) or on 16-bit words (16 bpp, pack type 3); 32 bpp uses
  pack type 2 (pad byte dropped, unpacked RGB) or 4 (PackBits over component planes, A plane first
  when `cmpCount = 4`). A row that unpacks to more or fewer than its row length fails with
  `PackBits_Invalid`.
- Color tables: seed, flags (`16#8000#` = device table, index is entry position), `ctSize`
  (count − 1, at most 255; `16#FFFF#` is an empty table) and entries of value plus 16-bit R, G, B. Entries are reduced to
  8 bits by taking the high byte. An index beyond the table fails with `Color_Table_Invalid` in
  `Strict`, maps to black with a warning otherwise.
- The source rectangle is scaled to the destination rectangle with nearest-neighbor sampling:
  destination column `k` (from the destination's left edge) takes source column
  `srcRect.left + floor (k * srcWidth / dstWidth)`, and rows likewise. The result is clipped by
  the clip region and, for the `Rgn` opcodes, by the mask region (both in destination
  coordinates), then composited with the transfer mode. Rows are decoded one at a time and never
  buffered whole.
- A `srcRect` reaching outside the bounds fails with `Pixmap_Invalid` in `Strict`; otherwise it is
  clamped to the bounds with a warning. An empty source or destination draws nothing.
- Indexed pixmaps (`BitsRect`, `PackBitsRect`) have 1, 2, 4 or 8 bits per pixel; direct pixmaps 16
  or 32. 16-bit pixels allow pack types 0, 1, 3; 32-bit pixels 0, 1, 2, 4 with `cmpCount` 3 or 4.
  A 5-bit component `v` expands to `v * 8 + v / 4`. Source alpha (`cmpCount = 4`) is ignored, as
  QuickDraw ignores it; every pixel written is opaque.
- A BitMap's 1 bits are black and 0 bits white before the transfer mode applies, so a copy made
  while the foreground is not black or the background not white is colorized (section 3.2).
- The transfer mode's `ditherCopy` flag (`16#40#`) makes no difference to true-color output and is
  ignored.
- `hRes`/`vRes`, `pixelType`, `planeBytes` and `pmReserved` are validated for consistency and
  retained.

### 3.4 Text

- Text opcodes `LongText`, `DHText`, `DVText`, `DHDVText` (`16#0028#..16#002B#`) draw with
  TrueType fonts through `textrender` (`../textrender`). pictlib ships no fonts: the caller's
  `Options.Fonts` (`Pictlib.Fonts.Font_Table`) maps Macintosh family names and font IDs to font
  files. The font for the current `TxFont` ID is, in order, the file for the family this picture
  named that ID (`fontName`, compared without regard to case), the file for the ID, the file for the
  family the classic Macintosh system gave the ID (`Fonts.Classic_Name`: 0 Chicago, 1 and 3 Geneva,
  2 New York, 4 Monaco, 20 Times, 21 Helvetica, 22 Courier, 23 Symbol, …), then the table's
  default. No file, or one that does not load, is `Font_Unavailable` in `Strict`; otherwise the text
  is skipped with an `Approximated_Rendering` warning.
- `LongText` sets the text origin to its point; `DHText`, `DVText` and `DHDVText` move the previous
  text origin by their unsigned offsets. Characters are drawn from the origin's baseline. Text state:
  `TxFont`, `TxFace`, `TxMode` (default `srcOr`), `TxSize` (0 is 12; points are pixels at 72 dpi;
  above 512 is unsupported), `SpExtra` (Fixed, added after each space), `ChExtra` (added after each
  character) and `TxRatio` (only 1:1 is supported).
- Characters are Mac Roman, mapped to Unicode; bytes below 16#20# draw nothing. A character the
  font lacks advances half the size and records one `Data_Loss` warning per opcode.
- Layout, per character: the glyph's left edge is `round (pen + bearing)`, its top is the baseline
  less its bearing, and the pen advances by the glyph's advance plus `ChExtra`, the face's width
  change and, after a space, `SpExtra`. There is no kerning and no antialiasing: coverage of 128 or
  more is ink. The character's cell — from its left edge or the pen, whichever is less, to its
  right edge or the advanced pen, and from the font's ascent above the baseline to its descent
  below — is drawn through the text mode with ink as a black source and the rest as a white one, so
  `srcOr` changes only ink and `srcCopy` paints the cell in the background color.
- Faces: bold smears ink one pixel right and widens the advance by one; italic is textrender's
  synthetic oblique; underline draws the row below the baseline under the whole string; condense and
  extend narrow and widen the advance by one. Outline and shadow are `Unsupported_Feature` in
  `Strict` and drawn plain with a warning otherwise.
- A font's renderer and atlas (a square of `max (256, 8 × size + 8)` pixels) count against
  `Max_Allocation_Bytes`; up to eight fonts stay loaded during one `Render`.

### 3.5 Comments and QuickTime

- `ShortComment` (`16#00A0#`) and `LongComment` (`16#00A1#`) are retained in order under the
  metadata budget, with kind, data and opcode ordinal. They never change rendering.
- `CompressedQuickTime` (`16#8200#`): after its 32-bit length come a version word, a 3 × 3 matrix
  (16.16 Fixed, the last column 2.30 Fract), `matteSize`, the matte rectangle, a transfer mode,
  `srcRect`, the accuracy and `maskSize` (68 bytes), then the matte (`matteSize` bytes), the mask
  region (`maskSize` bytes), an `ImageDescription` (`idSize`, at least 86 bytes: codec type at 4,
  width at 32, height at 34, `dataSize` at 44) and `dataSize` bytes of image data. Parts that do not
  fit the opcode fail with `Opcode_Length_Invalid`; a mask whose size disagrees with `maskSize`
  fails with `Region_Invalid`.
- Codec `'jpeg'` is decoded by `jpeglib`, which reads the data straight from the picture (never
  more than `dataSize` bytes); the decoded RGB image is held on the heap. A JPEG whose size is not
  the description's, or that `jpeglib` rejects, is `Embedded_Image_Failed`; `Recover_When_Safe`
  keeps what was drawn before it as a partial picture. Any other codec, a non-empty matte (an alpha
  image of its own), and a matrix other than positive scaling plus translation are
  `Unsupported_Feature` in `Strict`; otherwise the image is skipped (the matte ignored) with an
  `Approximated_Rendering` warning.
- The image's `srcRect` (in image coordinates, clamped to the image) is mapped through the matrix
  to a local destination rectangle (coordinates rounded to the nearest pixel), drawn nearest-
  neighbor like a copy with the opcode's transfer mode, clipped by the clip region and the mask
  region. Decompressed images are not colorized by the port's colors.
- QuickTime writes a bits opcode after the image as a placeholder for systems without the codec.
  After an image is drawn, the bits opcode immediately following is consumed without drawing; any
  other opcode in between ends that. An image that is skipped leaves its placeholder to be drawn.
- `UncompressedQuickTime` (`16#8201#`) is parsed and skipped; it carries no pixels that QuickDraw
  would draw.
- While rendering, QuickTime payloads are read by the decoder and are not retained as metadata;
  enumeration retains them when the policy asks.
- `jpeglib` errors are mapped to `Embedded_Image_Failed` with the `jpeglib` identifier kept as the
  underlying code.

## 4. Public package layout

```text
Pictlib                        -- shared scalar types and enums
Pictlib.Version                -- semantic crate version
Pictlib.Capabilities           -- implemented, tested features
Pictlib.Errors                 -- error codes, diagnostic context, warnings
Pictlib.Results                -- deterministic success/failure results
Pictlib.Limits                 -- processing, allocation and work bounds
Pictlib.Streams                -- Source/Destination, memory adapters
Pictlib.Geometry               -- QuickDraw Point, Rect, Fixed
Pictlib.Images                 -- RGB/RGBA views and stride checks
Pictlib.Pictures               -- header info and opcode events
Pictlib.Opcodes                -- opcode names, classification and length rules
Pictlib.Metadata               -- comments, font names, QuickTime payloads, retention
Pictlib.Fonts                  -- the caller's TrueType font table, classic font IDs
Pictlib.Decoding               -- forward-only decoder: header, enumerate, render
Pictlib.Encoding               -- forward-only raster PICT 2 encoder
Pictlib.Internal.Bytes             -- checked big-endian readers and writers
Pictlib.Internal.Checked_Arithmetic
Pictlib.Internal.Picture_Stream    -- look-ahead source wrapper, picture byte budget
Pictlib.Internal.Container         -- file header, picSize, picFrame, version, HeaderOp
Pictlib.Internal.Sessions          -- decoding session, budget-checked opcode data readers
Pictlib.Internal.Opcode_Reader     -- bounded opcode stream, alignment, structural skipping
Pictlib.Internal.Diagnostics       -- bounded warning log
Pictlib.Internal.Metadata_Store    -- retained metadata under budgets
Pictlib.Internal.Regions           -- region parsing and scanline masks
Pictlib.Internal.Polygons
Pictlib.Internal.PackBits          -- unpack/pack byte and word runs
Pictlib.Internal.Pixmaps           -- BitMap/PixMap headers, color tables, rows
Pictlib.Internal.Patterns
Pictlib.Internal.Canvas            -- the caller's view as a drawing surface
Pictlib.Internal.Rendering         -- painter and port state, fills, copies, clip and mask
Pictlib.Internal.Drawing           -- port state and shape opcodes
Pictlib.Internal.Coverage          -- shapes as per-row spans
Pictlib.Internal.Rasterizer        -- shapes, pen, clipping
Pictlib.Internal.Transfer_Modes
Pictlib.Internal.Text              -- text state, Mac Roman, loaded fonts
Pictlib.Internal.Typesetting       -- drawing text opcodes
Pictlib.Internal.QuickTime         -- 8200 parsing, jpeglib bridge, placement
Pictlib.Internal.Writers           -- opcode and pixmap emission
Pictlib.Internal.Ownership         -- allocation/budget accounting
```

Only non-`Internal` packages are the supported public API. Use `pragma Pure` / `Preelaborate`
where legal and SPARK for independently provable units (arithmetic, descriptors, opcode length
rules, region bounds), not indiscriminately.

## 5. Ada data and ownership model

### 5.1 Root types

`Byte` from `Interfaces.Unsigned_8`; 64-bit-capacity offsets and counts; QuickDraw `Coordinate`
(−32_768 .. 32_767); positive `Image_Width`/`Image_Height` bounded by QuickDraw's 16-bit space;
`Opcode` (0 .. 16#FFFF#); `Pixel_Depth`; `Transfer_Mode`; `Strictness_Mode`; `PICT_Version`.
All conversions from file values to Ada subtypes are checked before use; no huge stack arrays.

### 5.2 Streams

Mirror `jpeglib`: `Source` limited interface with `Read`, `Offset`, `Skip`; `Destination` with
`Write`, `Offset`, `Flush`; explicit counts and EOF; memory and fixed-buffer adapters with an
optional transfer cap for short-I/O testing. A zero-byte read without EOF or failure fails as
`Source_Zero_Progress`; a zero-byte write fails as `Destination_Zero_Progress`. No seek required.

### 5.3 Image views

Formats `RGB_24`, `BGR_24`, `RGBA_32`, `BGRA_32`, `ARGB_32`. A view is a descriptor (width,
height, stride, accessible bytes) plus a borrowed access to caller storage. Validators check
`stride >= width * bytes_per_pixel`, row-span overflow before `stride * (height - 1)`, and that
storage covers the accessible bytes. The decoder renders `picFrame` (or a caller-chosen rect)
into the view at 72 dpi; the view must be exactly the frame's size and canvas pixel (0, 0) is
the frame's top-left corner. The decoder draws directly into the view: there is no library-owned
canvas, and the view is first filled with `Options.Background` (white by default). Rendering at
an extended header's native resolution is a later task.

### 5.4 Ownership rules

- Decoder and encoder objects are `limited private`; they borrow the Source/Destination for their
  active lifetime.
- Output pixels are caller-owned; their content is defined only on success or on a reported
  `Partial_Picture`.
- Region data, row buffers and embedded JPEG pixels are library-owned heap buffers accounted against `Max_Allocation_Bytes` and released on `Reset`/`Finalize`, also
  after failure and cancellation. `Finalize` is idempotent.
- Metadata is copied into bounded library-owned storage valid until `Reset`/`Finalize`, or
  delivered through a caller callback during enumeration.

## 6. Decoder contract

States: `Created`, `Ready`, `Header_Read`, `Finished`, `Stopped`, `Failed`, `Cancelled`; the
renderer adds its state with M2. Operations: `Initialize (Object, Input, Options, Limits)`,
`Reset (Object, Input)` (keeps options and limits), `Read_Header` (container, version, frame,
resolution), `Header`, `Enumerate (Visitor)` (one callback per opcode, the version opcode and
`HeaderOp` included, with ordinal, source offset, opcode, data length excluding pad bytes and a
reserved flag; the visitor may return `Stop`, which ends in `Stopped` unless the opcode was the end
opcode), `Render (Output_View)` (from M2), `Metadata_Count`/`Metadata_Item`/`Copy_Metadata`,
`Warning_Count`/`Warning_At`, `Last_Error`, `Cancel`, `Finalize`. Calls in the wrong state fail
with `Invalid_State` (`Operation_Cancelled` after `Cancel`) and change neither the state nor the
last error. `Render` after `Enumerate` requires `Reset` (the stream is forward-only).

`Render` rejects an invalid view or one whose size is not the frame's with `Invalid_Argument`,
leaving the decoder in `Header_Read`; a frame above `Max_Canvas_Pixels` or a view above
`Max_Output_Bytes` fails with `Limit_Exceeded`. Drawing opcodes a release does not render yet
fail with `Unsupported_Feature` in `Strict` and are skipped with an `Approximated_Rendering`
warning otherwise; port state they depend on is tracked. In `Recover_When_Safe`, malformed
picture data (truncation, malformed regions, pixmaps, PackBits, color tables, patterns or opcode
lengths, a missing end opcode) ends rendering with success and a `Partial_Picture` warning: what
was drawn stands, the rest is background. Limits, stream failures and unsupported features are
never recovered.

The decoder reads nothing after the end opcode unless `Require_End_Of_Input` is set; then one more
byte fails with `Trailing_Data` in `Strict` and is a warning otherwise. Input that ends at an
opcode boundary without the end opcode fails with `Missing_End_Opcode` in `Strict` and finishes
with a warning otherwise; input that ends inside an opcode always fails with
`Source_Unexpected_End`. A version 2 picture without `HeaderOp` fails with `Header_Invalid` in
`Strict`; otherwise it is treated as version 2 at 72 dpi with a warning and the opcode read in its
place is enumerated. The warning log holds `Max_Warning_Records` entries; when it overflows, the
last entry becomes `Warnings_Suppressed`.

## 7. Encoder contract

States: `Created`, `Ready`, `Encoded`, `Finished`, `Failed`, `Cancelled`. `Initialize (Object,
Output, Options, Limits)`, `Encode (Image_View)` (Ready → Encoded), `Finish` (flushes; Encoded →
Finished), `Layout_Used`, `Bytes_Written`, `Last_Error`, `Cancel`, `Finalize` (idempotent). Calls
in the wrong state fail with `Invalid_State` (`Operation_Cancelled` after `Cancel`). An invalid
view or a non-positive resolution is `Invalid_Argument` and leaves the encoder `Ready`.

One image becomes one extended version 2 picture: the 512-byte zero file header (option, on by
default), `picSize` (the low 16 bits of the picture's length; the encoder measures the picture in a
dry run first, so the destination stays forward-only), `picFrame` `(0, 0, height, width)`,
`VersionOp`, `HeaderOp` (version −2, the options' resolution, the frame), `DefHilite`, a clip of the
frame, one bits opcode copied with `srcCopy` from and to the frame, and `OpEndPic`, with version 2
alignment.

Layouts:
- `Direct_32`: `DirectBitsRect`, pixel type 16, 32 bits, `rowBytes = 4 × width`, pack type 4 —
  PackBits over the red, green and blue planes, with the alpha plane first when `Keep_Alpha` asks
  for it on a 32-bit view (`cmpCount` 4).
- `Indexed_8`: `PackBitsRect`, an 8-bit PixMap with `rowBytes` the width rounded up to even, and a
  color table of the image's exact colors in the order they first appear (entry values are their
  indexes, components widened by × 257). More than 256 colors is `Too_Many_Colors`.
- `Mono_1`: `PackBitsRect`, a BitMap with `rowBytes` the bit width in bytes rounded up to even;
  a pixel is black when its luminance `(299 R + 587 G + 114 B) / 1000` is below `Mono_Threshold`.
- `Auto`: `Mono_1` when every pixel is black or white, `Indexed_8` for at most 256 colors,
  `Direct_32` otherwise or when alpha is kept.

Rows are stored as QuickDraw stores them: unpacked when `rowBytes < 8`, otherwise PackBits behind a
byte count (a word count when `rowBytes > 250`). `rowBytes` above `16#3FFE#` cannot be written
(`Invalid_Argument`): 4095 pixels wide for `Direct_32`, 16382 for `Indexed_8`. `Max_Frame_Width`,
`Max_Frame_Height`, `Max_Output_Bytes` (checked by the dry run before a byte is written) and
`Max_Allocation_Bytes` (row buffers) apply.

## 8. Metadata policy

Retained: file header bytes (optional), comments, font names, QuickTime payloads (optional),
unknown/reserved opcode payloads (optional, off by default). Each kind has a count and a byte
budget; overflow fails with `Limit_Exceeded` in `Strict` and drops with a `Data_Loss` warning
otherwise.

## 9. Resource limits and security

`Limits.Limit_Set` bounds: frame width/height, canvas pixels and bytes, opcode count, bytes per
opcode, region bytes, polygon points, total picture bytes, total drawing work (pixels touched,
counting every shape and scaled copy), retained metadata, allocation, output bytes, embedded image
bytes and pixels, warnings. Every input-derived size is checked with `Checked_Arithmetic` before
allocation, indexing or a loop bound. Drawing work is the guard against tiny pictures with huge
repeated fills.

## 10. Errors and diagnostics

`Error_Code` covers stream failures, `Header_Invalid`, `Version_Invalid`, `Opcode_Invalid`,
`Opcode_Length_Invalid`, `Region_Invalid`, `Polygon_Invalid`, `Pixmap_Invalid`,
`PackBits_Invalid`, `Color_Table_Invalid`, `Pattern_Invalid`, `Transfer_Mode_Invalid`,
`Embedded_Image_Failed`, `Too_Many_Colors`, `Missing_End_Opcode`, `Trailing_Data`,
`Unsupported_Feature`, `Invalid_State`, `Invalid_Argument`, `Integer_Overflow`, `Limit_Exceeded`,
`Operation_Cancelled`, `Internal_Invariant_Failed`. Identifiers are stable dotted strings
(`pict.*`). `Diagnostic_Context` carries source/destination offset, opcode, opcode ordinal, row,
expected/actual counts, limit kind and an underlying code.

## 11. Crate and project structure

```text
pictlib/
  alire.toml  pictlib.gpr  AGENTS.md  CLAUDE.md  README.md  LICENSE  CHANGELOG.md
  CONTRIBUTING.md  SECURITY.md  scripts/check_all.sh
  src/        pictlib.ads, pictlib-*.ads/.adb
  docs/       SPECIFICATION.md, IMPLEMENTATION_PLAN.md, PUBLIC_API.md,
              invariants.md, limits_and_safety.md (from M1)
  proof/      pictlib_proof.gpr (from M7)
  tests/      alire.toml, tests.gpr, src/ (AUnit suites, runner, tools), fixtures/
```

Root `alire.toml`: `name = "pictlib"`, `0.1.0-dev`, MIT, `gnat_native = "^15"`, `jpeglib` and
`textrender` pinned by path (`../jpeglib`, `../textrender`). Child crate `tests` depends on `pictlib`, `aunit ^26.0.0` and
`project_tools`. Test binaries: `pictlib_tests`, `pictlib_conformance` (encoder output read by ImageMagick and by
LibreOffice's own PICT import, exact), later `pictlib_check`, `pictlib_fuzz`, `pictlib_benchmark`.
ImageMagick 7 reads only pictures with the file header, misreads rows stored unpacked and draws
1-bit BitMaps black, so those pictures are judged by LibreOffice alone.

## 12. Testing matrix

| Area | Required cases |
|---|---|
| Container | with/without 512-byte header, v1, v2, extended v2, wrong `picSize`, missing end, trailing data, odd alignment |
| Opcodes | every defined opcode's length rule, each reserved range, truncated data, lengths crossing limits |
| Regions/polygons | rectangular, complex, empty, malformed scanlines, unterminated, size mismatch |
| PackBits | literal/run boundaries, 128 runs, byte vs word counts at `rowBytes` 250/251, `rowBytes < 8`, over/under-run |
| Pixmaps | 1/2/4/8 indexed, 16 and 32 direct, pack types 1–4, `cmpCount` 3/4, device color tables, index out of range |
| Copy | scaling up/down, clipping, mask regions, every transfer mode |
| Shapes | each verb × shape, "same" variants, pen sizes, patterns, oval size, arcs at all quadrants |
| Text | each text opcode, origins, font resolution by name, ID, classic name and default, Mac Roman, face bits, sizes, modes, spacing, clipping, missing fonts |
| QuickTime | JPEG with identity/translated/scaled matrix, srcRect, origin, matte, mask, clip, modes, placeholder bitmap, non-JPEG codec, skewing matrix, truncated/garbage/mis-sized JPEG, description and data sizes, embedded limits; independent QuickTime PICTs within decoder tolerance of libjpeg |
| I/O | fragmented reads/writes, EOF, zero progress, destination failure |
| Encoder | each layout and pixel format, alpha, thresholds, unpacked rows, byte and word counts, widest rows, >256 colors, header on/off, resolution, picSize, limits, short and full destinations, states; decode by independent decoders (`pictlib_conformance`) |
| Stress | huge frames with tight limits, many opcodes, repeated large fills, cancellation, reset |

Fixtures are independent: hand-assembled byte literals with documented provenance, real-world
PICT files with recorded origin and license, and expected rasters produced by an external
reference (ImageMagick, Netpbm `picttoppm`, macOS `sips` where available) and reviewed.
External tools are test-only oracles. Round trips complement, never replace, independent
expected data.

## 13. Phases and acceptance gates

Milestones M0–M7 in the implementation plan. First release: Gate M6 (raster and vector decode,
text, QuickTime JPEG, raster encode accepted by independent decoders). Library-complete: Gate M7.

## 14. Implementation discipline for coding agents

1. Read the current `../jpeglib` package specs before shaping a public API; adapt, do not copy
   JPEG-only abstractions.
2. Write specs (and invariants) before bodies; lock error policy, ownership, states and limits
   first.
3. One verifiable feature at a time, with positive and adversarial AUnit tests and fixtures.
4. All tooling through `alr` with the pinned GNAT 15.
5. Never catch programming errors to claim success; never mark a capability `True` untested.
6. Keep README, CHANGELOG and the plan's status lines accurate.

## 15. Decisions fixed by this specification

- Native Ada 2022, GNAT 15 via Alire; `jpeglib` and `textrender` are the only production
  dependencies.
- Full QuickDraw rendering of picture opcodes, without antialiasing.
- Text through `textrender` with caller-supplied TrueType fonts; no fonts ship with pictlib.
- QuickTime: JPEG decoded via `jpeglib`; other codecs unsupported.
- Encoding: raster PICT 2 only.
- Forward-only streaming; caller-owned output pixels; strict by default.

## 16. Source references

1. Apple, *Inside Macintosh: Imaging With QuickDraw* (1994), chapter 7 "Pictures" and Appendix A
   "Picture Opcodes".
2. Apple Technical Note QD 14 "Pictures and the Picture Utilities" / TN 1023 "PICT format".
3. Apple, *Inside Macintosh: QuickTime* — `ImageDescription` and compressed-picture opcodes.
4. `../jpeglib` public API: `src/jpeglib-streams.ads`, `jpeglib-images.ads`,
   `jpeglib-decoding.ads`, `jpeglib-errors.ads`, `jpeglib-results.ads`, `jpeglib-limits.ads`.
