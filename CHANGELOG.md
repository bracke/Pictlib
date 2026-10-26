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
  - `Max_Drawing_Work` (default 2^30, one to three minutes of work) for all
    rendering work, drawn or not: see the specification, section 9.
- Coordinates stay within ±2^24, so no coordinate arithmetic overflows.
- Constructs a release cannot render (other QuickTime codecs, mattes,
  skewing matrices, outline and shadow text, color tiles of more than
  2^31 − 1 pixels) fail with `Unsupported_Feature` in `Strict` and are
  skipped with a warning otherwise.
- `hostile.*` tests hold the cases that once overflowed or worked without
  bound, asserting their cost through budgets, never the clock.

### Fixed

- A copied pixmap or pattern is charged work for each row's unpacked bytes
  as well as its pixels: a row whose rowBytes is far wider than the picture
  drew a thousand bytes of PackBits for one unit.
- `Limits.Max_Canvas_Bytes` and `Canvas_Byte_Limit` are gone: they were
  never enforced, the renderer allocating no canvas.
- An exception from a source in `Read_Header` or `Render`, as from a
  visitor in `Enumerate`, propagates and leaves the decoder `Stopped`, its
  stream partly read: a second `Render` could draw the rest of a picture
  without its first opcodes. One from a destination once writing began
  leaves the encoder `Failed` with `Destination_Write_Failed`, so a retried
  `Encode` cannot append a second picture to part of the first.
- A `srcRect` clamped to a bits opcode's bounds keeps its mapping: the
  whole `srcRect` is sampled over the whole `dstRect` and only the part
  that samples the bounds is painted, as QuickTime images do. The clamped
  source used to be stretched over the whole destination, and then, for a
  while, over the part it maps to, which samples differently when the
  scale is not whole.
- While `Read_Header`, `Enumerate` or `Render` runs the source, a nested
  call of any of them is refused, and a `Cancel` the source makes stands;
  while `Encode` or `Finish` runs the destination, a nested `Encode` or
  `Finish` is refused, and a flush that fails or raises fails the encoder.
- A payload longer than the picture byte limit can still hold fails on
  that limit before anything is allocated for it, as the specification
  says; a wrong version the limit leaves in view is `Version_Invalid`, not
  the limit.
- The encoder frees its row buffers when the destination raises.
- Region framing charges each intersection by the rows it walks, before it
  is made, rather than by its result; pictures near the drawing limit may
  now reach it.
- A source that resets, initializes or finalizes its decoder mid-read, or a
  destination that does so to its encoder mid-write, leaves it as it chose:
  what the source delivered for the old binding is dropped, the call
  returns what one in the new state gets, and nothing reads a cleared
  stream. A source's `Finalize` used to make the look-ahead read through a
  null source and raise, and a `Reset` during `Read_Header` used to be
  undone. A destination's `Cancel` or `Finalize` is no longer overwritten.
- The decoder frees its row buffers, payloads and embedded-JPEG pixels when
  the source raises, as the specification promises for every failure.
- `Encoding.Reset` binds another destination and keeps the options and
  limits, as the decoder's does.
- `Pictlib.Font_ID` is one type: `Fonts.Font_ID` is a subtype of it and
  `Metadata.Item_Info.Font_ID` has it, so a font name read back can be
  given to a font table without a conversion.
- Diagnostic offsets follow one rule the specification now states: a field
  found wrong while reading names where reading stood, a verdict on the
  whole opcode names its offset.
- The warning log's suppression record keeps the context of the first
  warning suppressed, as documented, not the latest's.
- `lineJustify` with extra space is unsupported (strictly a failure,
  leniently drawn unjustified with a warning); it was skipped silently.
- Shape building charges a line's row buffers, a polygon's edges and an
  arc's spans before it makes or tests them, and the region walk charges
  the active inversion set and the line's points before it inverts.
- Framing a region erodes its rows by doubling, in log2 of the pen height
  passes instead of one row a pass, so a tall pen no longer spends the
  whole default budget on one opcode.
- A color table's entries past 255 warn once, as the specification says,
  not once each, which could fill the warning log.
- DHText and DVText move the text origin only once it is in reach.
- An invalid view of the frame's size reports the bytes a valid one holds
  against its own; `Encoding.Finalize` forgets the last layout.
- The zero-progress identifiers are `pict.source.zero_progress` and
  `pict.destination.zero_progress`, like the other stream codes.
- `Pack_Type` is internal: no public subprogram used it.
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
  their share name the share they had.
- The picture reader no longer clears the rest of a caller's buffer on
  every short read, which made long payloads from a source that delivers in
  small pieces quadratic in work no budget counted; nor does the source
  jpeglib reads QuickTime images through.
- Source offsets saturate, so a source reporting offsets near the largest
  there is cannot make the decoder raise.
- A lossless JPEG is `Unsupported_Feature` once its header is read: jpeglib
  decodes one through stack buffers sized by the image, which no budget
  bounds, so a large one could overflow the stack. So is a progressive or
  hierarchical JPEG of more than 8192 blocks (about 175,000 pixels at
  4:2:0), whose progressive decode keeps a map of 64 bytes a block on the
  stack.
- A hierarchical JPEG is held to twice its coefficients against jpeglib's
  share, since jpeglib keeps a continuation frame's beside the first's.
- jpeglib's `Invalid_State`, which only malformed data makes when pictlib
  drives it, is `Embedded_Image_Failed`.
- A JPEG whose height a later DNL marker gives is `Unsupported_Feature`:
  jpeglib reports neither its height nor the coefficients it needs, so it
  slipped past the bounds on progressive and hierarchical images.
- A QuickTime image costs a unit of drawing work for every byte of its
  compressed data besides its pixels and rows; jpeglib now finds each
  Huffman code without scanning its table, which made a crafted JPEG cost
  thousands of steps a byte.
- jpeglib's metadata limits are raised to what the embedded data can hold,
  so a valid JPEG's metadata is never refused; pictlib keeps none of it.
- A round rect whose corner oval holds no pixel centre in a row keeps that
  row's straight edge between the corners; a narrow corner oval (2 wide,
  10 high) used to drop the rect's top and bottom rows, and a framed round
  rect's inner shape with them.
- Clearing a decoder releases the storage its metadata and warnings held,
  as the specification says, rather than keeping the emptied vectors'
  capacity.
- jpeglib's share is sized over the image's extent rounded up to 32-pixel
  MCUs, the largest jpeglib's sampling factors make, so narrow subsampled
  JPEGs decode: `quicktime.narrow_image` renders a 1 × 16000 progressive
  4:2:0 JPEG written by jpeglib's encoder, which the unpadded share refused.
  Its coefficient and output limits are that share and the image's pixels,
  so none of jpeglib's own defaults is reported as pictlib's allocation
  limit.
- A filled polygon's edges count against `Max_Total_Allocation_Bytes`
  besides its points, 104 bytes an edge, so a filled polygon can now cross
  that limit where it did not.
- A source's stall or over-reported count names the offset the reader
  reached and the counts involved, wherever it happens; a stall in the
  look-ahead used to name the source's own offset and no counts.
- A QuickTime image's pixel buffer is admitted like every other allocation,
  so its failure names `Max_Allocation_Bytes`, and the pixels and jpeglib's
  share are charged to the session's total separately.
- A visitor that cancels, resets or finalizes its decoder from inside
  `Enumerate` ends the enumeration there, and the state it leaves stands,
  so a cancelled decoder answers `Operation_Cancelled` until `Reset`; a
  visitor that calls `Read_Header`, `Enumerate` or `Render` from inside is
  refused with `Invalid_State` instead of draining the stream under it.
  An exception the visitor raises, or an abort, propagates and leaves the
  decoder `Stopped`, its stream partly read, until `Reset` or `Initialize`;
  it used to leave every later `Read_Header`, `Enumerate` and `Render`
  refused for good, and then, once that was fixed, `Header_Read`, so a
  `Render` could draw the rest of the picture without its first opcodes.
  The specification and `Enumerate`'s documentation state these rules, and
  each is tested at a header opcode and at one after it.
- textrender's renderers are created and destroyed under the textrender lock
  as well as used under it: textrender promises nothing about initializing
  or finalizing one while another task renders.
- `Render` judges the frame against `Max_Canvas_Pixels` before the view, so
  a frame no view can render fails the decoder however wrong the view.
- A malformed fontName names the length its name needs; an empty or
  inverted frame names the one pixel each way it needs.
- ChExtra is read as the 4.12 fixed-point value QuickDraw records, and
  widens every character but the space, as Inside Macintosh says; it was
  read as whole pixels and widened spaces too.
- An encoder stays `Ready`, its last error unset, after a failure found
  before anything is written (an invalid view or resolution, too wide an
  image, too many colors, a frame, allocation or output limit), so another
  image can be tried; only a failure while writing leaves it `Failed`. An
  invalid view's failure names the bytes a valid one holds against its own.
- A full `Fixed_Buffer_Destination` fails with `Destination_Write_Failed`,
  expecting its length, and a short `Copy_Metadata` buffer with
  `Invalid_Argument`: both were reported as crossing `Max_Output_Bytes`.
- A short fontName expects the opcode's length against what its name
  needs, the convention the specification now states for expected and
  actual counts, and names the opcode's offset.
- Warnings raised while an opcode's data is read name that opcode and its
  ordinal, as failures do: dropped metadata and color recoveries named none.
- Unsupported-feature diagnostics name the text size, planar color, matte
  size, codec or jpeglib's counts that make them unsupported.
- A payload past the most one buffer holds names `Max_Allocation_Bytes` when
  that budget is the smaller bound, in the session and for QuickTime pixels.
- `Diagnostic_Context.Has_Row` tells row 0 from no row.
- Malformed polygons and coordinates beyond reach are recovered as partial
  pictures, as the specification now lists; the dead `Transfer_Mode_Invalid`
  entry of the recoverable list is gone, it being only ever a warning
  leniently.

### Documentation

- The specification describes text cells stretched to their ink, the work
  of copying a region shape, the font file bytes a load is charged, and
  `Font_Unavailable`; `Warning_Record_Limit` is documented as never crossed.
- The specification says the encoder's resolution only labels a picture,
  every rectangle staying in pixels, and names its two departures from
  QuickDraw: patterns tiled from the picture's origin, the pen kept in
  picture coordinates.
- The specification tabulates what `Max_Total_Allocation_Bytes` counts at
  fixed rates, lists embedded JPEG data among what `Recover_When_Safe`
  recovers, and the invariant registry names the units and tests that
  enforce RENDER-002 and TASK-001.
- The specification states a retained item's real charge (its bytes twice,
  read and kept, plus 128), that truncation is recovered as a partial
  picture under `Recover_When_Safe` like any malformed data, and lists
  `pictlib_example` among the tools.
- The specification no longer promises a caller-chosen render rectangle or a
  public transfer-mode type; `Decoding.Render`, `Decoding.Initialize` and
  `Encoding.Layout_Kind` describe what they do now.
- The README shows how to encode and decode, in the words of
  `pictlib_example`, which the tests crate builds and `pictlib_check` runs
  and holds the README to, line for line; `pictlib_api_consumer` renames
  every public subprogram, so a change to a parameter's or result's type, a
  parameter's mode or the number of parameters breaks the build (Ada does not
  compare a renaming's subtypes, names or defaults).
- The invariant registry no longer calls overflow freedom proved where only
  the helpers are, names `Sessions` for retention, the stream and writer
  units for exact transfers, the encoder for states and allocations, and
  every unit that charges drawing work; it cites the tests that cover them,
  among them new ones for descending region scanlines and points outside a
  region's box, and lists text sizes above 512 as unsupported.
- The specification tabulates every warning, its severity and what records
  it; STATE-001 gives the encoder its own terminal states; LIMIT-001 no
  longer counts `Warning_Record_Limit` among the limits reported;
  BYTES-001 names `Sessions` for attribution; `docs/proof_profile.md` says
  where `gnatprove` comes from.

- The specification says which limits enumeration enforces, that all
  retained metadata shares one count and one byte budget, what `Cancel`
  does in each state, that visitors may read the metadata retained so far
  (the promised callback does not exist), that `PnLocHFrac` and
  `glyphState` are read and ignored, how a non-positive resolution is
  read, how the counts of a bad view and resolution read, and lists
  `Internal.Replies`, `Internal.Divisions`, `proof_profile.md` and the CI
  workflow; the drawing budget's time is one to three minutes everywhere;
  `SECURITY.md` says where to report.

- The specification records that ImageMagick and LibreOffice read a
  144 dpi picture at its pixels, and the re-entry and flush rules;
  `Bytes_Written`, `Finish`, `Item_Info`'s fields, the stale
  `Copy_Metadata` comments and `Retain`'s claim are corrected;
  `PUBLIC_API.md` records that `Pack_Type` is internal;
  `tests/fixtures/README.md` says where provenance is actually kept.

- The specification names the new units and the rules for rebinding from
  caller code; the fixture READMEs record the Netpbm version and the check
  that reproduces them.

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
- A shape opcode builds its coverage in one function per kind, and the
  reserved verbs are those its verb list leaves out, not a second table.
- `PackBits.Pack` packs bytes, the only rows the encoder writes, and states
  its output size in its precondition.
- A clip and a mask cut a row through one helper, which charges the region
  walk before cutting.
- `Pictlib.Fonts` keys font IDs by `Font_ID`.
- The byte readers carry no opcode of their own: the session attributes
  every failure to its opcode in one place. The container uses the one
  opcode-boundary test, and the encoder surveys colors only for `Auto` and
  `Indexed_8`.
- The font cache's operations that reach textrender take the textrender
  guard as a parameter, so a call without the process-wide lock does not
  compile.
- The encoder's pack type 0 is named for what it is, the default.
- `Internal.Sessions.Session` is private: its budget, version, strictness
  and retention are read through functions, and its reader is reached only
  for what lies outside an opcode's budget-checked data (the header, opcode
  words, pad bytes and the probe past the end).
- `Encode` reads as its steps: check the frame, choose the layout, check
  the plan, write; `Decide_Layout` keeps one check per pack type and
  component count.
- One judgement of a source's reply (`Internal.Replies`) serves the exact
  transfers and the picture stream; `Over_Limit` takes a destination offset,
  so the writer builds no limit failure of its own; enumeration and
  rendering classify a PixPat's type in one place; `Render` checks the frame
  and the view separately instead of telling them apart by limit kind.

- QuickTime's jpeglib failure mapping, header checks and admission are
  functions of their own, and the text cell geometry and advance rule are
  package-level; `Floor_Divide` and `Ceiling_Divide` live in
  `Internal.Divisions`; a shape's row is copied into place without a
  temporary.

- The encoder writes the file header and picture through one sequence
  for the dry run and the real one, and its color table in a procedure of
  its own; writes are judged by `Replies.Judged_Write` as reads are; the
  version bytes are named by their constants; misplaced comments are back
  above their declarations; region framing moves its rows instead of
  copying them.

- The jpeglib bridge (`Internal.JPEG_Bridge`), shape drawing
  (`Internal.Shapes`), a view's pixel accessors (`Internal.Pixels`) and the
  session's accounting and retained metadata (`Sessions.Accounting`,
  `Sessions.Retained`) are units of their own; `Read_Pair` is a session
  reader; failures over a limit in a context and invalid views are built by
  `Failures`; `Sessions.Context_Of` is gone in favour of
  `Failures.Context_Of`; `Visiting` is `Busy`; the font cache checks it is
  given a held textrender guard; `Text.File_Bytes` catches only file
  errors; polygon filling reuses its row vectors.

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
- `pictlib_check` runs `pictlib_example`, and `pictlib_benchmark` fails
  like the other tools when an encode or render fails.
- `pictlib_real_world` checks a picture against another decoder's raster
  when one is committed beside it: `tdf92789.pct` against ImageMagick's,
  within 2 of each component; its outcomes alone were pictlib's own record.
- The stress tests clear the view before each reused decoder's render and
  tie every limit-matrix call to the limit it targets; the spent-quota test
  is guarded from below too; the encoder tests anchor the byte offsets they
  read to where the bits opcode is.
- The tests crate has one seeded pseudo-random generator
  (`Pictlib_Testing.Random`) and one file loader; the encoder tests check
  the alpha plane's values byte for byte, independently of the decoder.
- `pictlib_conformance` has ImageMagick and LibreOffice read pictures that
  keep alpha and pictures `Auto` laid out; the test-side rowBytes rule lives
  in `Samples`, and every failing render test checks the decoder's state and
  last error.
- The suite tests the eleven transfer modes it skipped (notSrcOr, notSrcXor,
  notSrcBic, notPatOr, notPatXor, notPatBic, addPin, addOver, subPin,
  subOver, grayishTextOr) against hand-worked rasters, the PackBits count at
  rowBytes 250 and 251, Mono_1 at and around both thresholds with colors
  only Rec. 601's weights classify, the encoder's terminal states, a source
  over-reporting a read, the warning cap against a picture that warns,
  equal, descending and out-of-box region scanlines, and the limit kind of
  every work-budget failure.
- `pictlib_prove` captures gnatprove's standard error, where it reports
  unproved checks and skipped bodies.
- `pictlib_fuzz` takes `--fail-stuck` anywhere, refuses bad arguments and an
  empty seed set with a usage failure, reports a failed mutation or replay
  load instead of raising past its handler, and checks that every failure
  carries a fatal code and leaves the decoder `Failed` with it.
- `pictlib_check` also requires every test package to be added to the suite,
  every registry row to name covered tests, `Register_Routine` only as a
  call, textrender only through its root package, no `pragma Suppress`,
  `Unchecked_Conversion`, `'Address` or `'Unrestricted_Access` in the
  library, no shell or Python script, and single-command CI steps; it counts
  line lengths in characters.
- The tests share `L_Region`, `Canvases.Expect_Pixels`, `Frame_View` and
  `Files.Save_Path`; the recorder keeps every event; `Any_Opcode`, not 0,
  means a failure's opcode is not checked; `pictlib_benchmark` no longer
  leaks a buffer each round.
- `foundation.capabilities` probes each advertised feature through the
  public API (a header, an enumeration, a copied bitmap, a painted rect,
  text, an embedded JPEG, a retained comment, an encode read back) and
  requires each capability to be advertised exactly when its probe works;
  it used to check only that the constants were `True`.
- The small progressive JPEG test checks the frame shows jpeglib's own
  decoding of the image's corner, not only that rendering succeeded.
- The task-safe render the stress tests use is `Canvases.Rendered`.
- `text.eviction_over_budget` requires a budget of its sweep to lie in the
  window the bug lived in, computed from the glyph, font-load and clip
  costs, so a drift in them cannot leave it testing nothing; both eviction
  tests check pictlib's own atlas geometry.
- `text.font_cache` tells least-recently-used eviction from first-in,
  first-out; `text.faces` covers the shadow face; `text.work` searches its
  least budgets below a ceiling worked out from its fonts and glyphs; the
  JPEG decoders' tolerance and the jpeglib encoding helper are shared.
- `pictlib_fuzz` takes `--replay` anywhere, refuses it with no file, tells
  an unreadable file from a defect, and reports a defect before saving its
  input.
- `pictlib_check` skips escaped bars in registry cells, finds a suite's test
  case declared without `constant`, and checks CI steps written `- run:`
  and steps continued on the next line.
- The capability probes render into one canvas and the progressive JPEG
  check frees its buffers; new tests cover raising sources and
  destinations, clamped srcRects on either side, lineJustify, region frames
  with pens up to 4 x 3 against a rectangle and an L, one warning for a
  table's bad entries, and the counts of bad views.
- `encoding.golden_bytes` holds the encoder to hand-assembled bytes for
  tiny Indexed_8, Mono_1 and Direct_32 pictures (the color table's ×257
  widening and order included) and picSize past 64 KiB; the encoder tests
  cover rowBytes 250 against 252 in the bytes, Indexed_8 at its widest and
  past it, `Cancel` in every state, a flush that fails or raises, and the
  unpacked green byte; the PackBits tests pin runs and literals of 128,
  129, 130 and 300 and the `Worst_Case` bound.
- `pictlib_conformance` adds the rowBytes boundary, the widest rows, a
  picture past 64 KiB, a raised Mono_1 threshold, BGR and BGRA sources and
  a 144 dpi picture: 24 pictures.
- New tests cover a non-whole-ratio and a vertical srcRect clamp, a source
  that calls into or cancels its decoder, a destination that calls Encode,
  the early picture byte check, a wrong version under a small budget, and
  the suppression record's context; the Direct pixmap builder is shared.
- `pictlib.gpr` takes Alire's build profile: `-O2` for release, `-Og -g`
  otherwise, every check kept; the tests crate builds with `-g` and binds
  with `-Es`, so defects carry a traceback; the proof profile uses the
  library's switches.
- `pictlib_generate --check` regenerates the external fixtures and
  compares them with the committed ones byte for byte; it clears stale
  staging first and reports a failure partway. `pictlib_conformance`,
  `pictlib_generate` and `pictlib_prove` print the versions of the external
  programs they run; CI installs `gnatprove^15`, fuzzes from its run number
  (`pictlib_complete --fuzz-seed`) and keeps the fuzzer's inputs when it
  fails.
- `pictlib_fuzz` fails without its fixture seeds and refuses seed 0 and no
  iterations; the generator draws from its high bits. `pictlib_check` runs
  every policy step and the suite whatever one of them raises, requires the
  CI workflow, and bans PowerShell, batch and Perl scripts and Makefiles;
  `pictlib_real_world` and `pictlib_complete` refuse unknown arguments, and
  the tools walk directories through one sorted walker.
- `Samples.Encode` and the benchmark free their buffers, the benchmark
  reports a rate it cannot time instead of raising, and conformance reads
  SVGs on the heap; `direct_large` is past 64 KiB, and checked to be.
- `pictlib_prove` prints what gnatprove said whenever a unit is not proved
  cleanly, so a failure can be read in CI's log; CI passes its fuzz seed in
  `PICTLIB_FUZZ_SEED`, which `pictlib_complete` reads when `--fuzz-seed` is
  not given, rather than in an argument holding a space.
- Every `alr --chdir` names its directory attached (`--chdir=tests`): alr
  2.1.1, which CI installs, refuses the directory as a separate argument, and
  so failed every proof. CI runs `pictlib_complete` through `alr exec`, as
  `alr run` reports it "not built by this release" on Windows.
