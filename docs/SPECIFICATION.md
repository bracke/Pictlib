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
  Header version `-1` carries fixed-point picture bounds (version 2); `-2` carries `hRes`, `vRes`
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
- Version 1 colors (`16#000E#`, `16#000F#`) map the eight QuickDraw planar colors to RGB.
- Shapes: `frame`, `paint`, `erase`, `invert`, `fill` for rect (`16#0030#..`), rounded rect
  (`16#0040#..`), oval (`16#0050#..`), arc (`16#0060#..`), polygon (`16#0070#..`) and region
  (`16#0080#..`), plus each "same" variant reusing the last shape of that kind. Lines:
  `16#0020#..16#0023#`. Pixel coverage follows QuickDraw's pen-hangs-below-right model; tests
  compare against reference rasters, not antialiased approximations. QuickDraw draws without
  antialiasing and so shall the renderer.
- Transfer modes: the 16 boolean modes (`srcCopy` .. `notPatBic`), the arithmetic modes
  (`blend`, `addPin`, `addOver`, `subPin`, `transparent`, `addMax`, `subOver`, `adMin`),
  `hilite` and `ditherCopy` (rendered as `srcCopy`, with a warning). Unknown modes fail in
  `Strict`, render as `srcCopy` with a warning otherwise.
- Regions: 16-bit size, bounding rect, then the inversion-point scanline encoding terminated by
  `16#7FFF#`. Rectangular regions have size 10. Malformed region data fails with `Region_Invalid`.
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
- The source rectangle is scaled to the destination rectangle with nearest-neighbor sampling,
  then clipped by the clip region and the mask region, then composited with the transfer mode.
- `hRes`/`vRes`, `pixelType`, `planeBytes` and `pmReserved` are validated for consistency and
  retained.

### 3.4 Text

- Text opcodes `LongText`, `DHText`, `DVText`, `DHDVText` (`16#0028#..16#002B#`) render through
  the `Pictlib.Fonts.Glyph_Source` interface. The library ships one built-in bitmap face (from a
  public-domain source, provenance recorded in `docs/`) used for every font ID, scaled by integer
  replication to the nearest size; text face bits bold/italic/underline are synthesized.
  Callers may supply their own `Glyph_Source` for higher fidelity.
- Mac Roman text bytes are mapped to Unicode code points before glyph lookup. Font names
  (`16#002C#`) and IDs are retained as metadata.
- Exact Macintosh glyph fidelity is not a requirement; tests compare text placement, advance and
  coverage against the built-in face's own reference rasters.

### 3.5 Comments and QuickTime

- `ShortComment` (`16#00A0#`) and `LongComment` (`16#00A1#`) are retained in order under the
  metadata budget, with kind, data and opcode ordinal. They never change rendering.
- `CompressedQuickTime` (`16#8200#`): the 32-bit-length payload is parsed (version, matrix, matte,
  mode, source rect, accuracy, mask region, `ImageDescription`, image data). When the codec type
  is `'jpeg'` the image data is decoded by `jpeglib` into a library-owned bounded buffer and drawn
  through the matrix (translation and positive axis-aligned scale; any other matrix is
  `Unsupported_Feature` in `Strict`, a skipped image with a warning otherwise), the matte and the
  mask region. Other codec types are `Unsupported_Feature` in `Strict`; otherwise skipped with a
  warning. The raw payload may be retained as metadata.
- `UncompressedQuickTime` (`16#8201#`) is parsed and skipped; it carries no pixels that QuickDraw
  would draw.
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
Pictlib.Fonts                  -- Glyph_Source interface and the built-in face
Pictlib.Decoding               -- forward-only decoder: header, enumerate, render
Pictlib.Encoding               -- forward-only raster PICT 2 encoder
Pictlib.Internal.Bytes             -- checked big-endian readers and writers
Pictlib.Internal.Checked_Arithmetic
Pictlib.Internal.Picture_Stream    -- look-ahead source wrapper, picture byte budget
Pictlib.Internal.Container         -- file header, picSize, picFrame, version, HeaderOp
Pictlib.Internal.Opcode_Reader     -- bounded opcode stream, alignment, structural skipping
Pictlib.Internal.Diagnostics       -- bounded warning log
Pictlib.Internal.Metadata_Store    -- retained metadata under budgets
Pictlib.Internal.Regions           -- region parsing and scanline masks
Pictlib.Internal.Polygons
Pictlib.Internal.PackBits          -- unpack/pack byte and word runs
Pictlib.Internal.Pixmaps           -- BitMap/PixMap headers, color tables, rows
Pictlib.Internal.Patterns
Pictlib.Internal.Canvas            -- heap-held working canvas
Pictlib.Internal.Rasterizer        -- shapes, pen, clipping
Pictlib.Internal.Transfer_Modes
Pictlib.Internal.Text
Pictlib.Internal.QuickTime         -- 8200/8201 parsing, jpeglib bridge
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
into the view at 72 dpi or at the extended header's resolution when the caller asks.

### 5.4 Ownership rules

- Decoder and encoder objects are `limited private`; they borrow the Source/Destination for their
  active lifetime.
- Output pixels are caller-owned; their content is defined only on success or on a reported
  `Partial_Picture`.
- The working canvas, region masks, unpacked rows and embedded JPEG pixels are library-owned
  heap buffers accounted against `Max_Allocation_Bytes` and released on `Reset`/`Finalize`, also
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

The decoder reads nothing after the end opcode unless `Require_End_Of_Input` is set; then one more
byte fails with `Trailing_Data` in `Strict` and is a warning otherwise. Input that ends at an
opcode boundary without the end opcode fails with `Missing_End_Opcode` in `Strict` and finishes
with a warning otherwise; input that ends inside an opcode always fails with
`Source_Unexpected_End`. A version 2 picture without `HeaderOp` fails with `Header_Invalid` in
`Strict`; otherwise it is treated as version 2 at 72 dpi with a warning and the opcode read in its
place is enumerated. The warning log holds `Max_Warning_Records` entries; when it overflows, the
last entry becomes `Warnings_Suppressed`.

## 7. Encoder contract

`Initialize (Object, Output, Options, Limits)`, `Encode (Image_View)`, `Finish`, `Cancel`,
`Finalize`. Options: write the 512-byte zero header (default on), resolution (default 72 dpi),
`Layout`: `Direct_32` (`DirectBitsRect`, pack type 4, `cmpCount` 3 or 4 with alpha), `Indexed_8`
(`PackBitsRect` with an exact color table, fails with `Too_Many_Colors` above 256), `Mono_1`
(`PackBitsRect` BitMap, threshold policy explicit), and `Auto` (smallest exact layout). The
encoder writes extended version 2 headers, the `picSize` low word, `DefHilite`, `Clip` of the
frame and `OpEndPic`, with even alignment.

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

Root `alire.toml`: `name = "pictlib"`, `0.1.0-dev`, MIT, `gnat_native = "^15"`, `jpeglib` pinned
by path `../jpeglib`. Child crate `tests` depends on `pictlib`, `aunit ^26.0.0` and
`project_tools`. Test binaries: `pictlib_tests`, later `pictlib_check`, `pictlib_conformance`,
`pictlib_fuzz`, `pictlib_benchmark`.

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
| Text | each text opcode, face bits, sizes, custom `Glyph_Source` |
| QuickTime | JPEG with identity/translated/scaled matrix, matte, mask, non-JPEG codec, corrupt JPEG |
| I/O | fragmented reads/writes, EOF, zero progress, destination failure |
| Encoder | each layout, alpha, >256 colors, header on/off, decode by independent decoders |
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

- Native Ada 2022, GNAT 15 via Alire; `jpeglib` is the only production dependency.
- Full QuickDraw rendering of picture opcodes, without antialiasing.
- Text through a pluggable glyph source with one built-in public-domain bitmap face.
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
