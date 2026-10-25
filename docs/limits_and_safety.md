# Limits And Safety Boundaries

PICT input is hostile input. Every size the picture states is checked before it
bounds a read, a skip, an allocation or a loop.

## Where each budget is checked

| Limit | Checked | On excess |
| --- | --- | --- |
| `Max_Frame_Width`, `Max_Frame_Height` | after `picFrame`, before any opcode; the encoder's image | `Limit_Exceeded` |
| `Max_Canvas_Pixels` | the frame, when `Render` starts | `Limit_Exceeded` |
| `Max_Output_Bytes` | the view's accessible bytes, when `Render` starts; the encoder's whole picture, measured by a dry run | `Limit_Exceeded` |
| `Max_Picture_Bytes` | every byte taken from the source, the look-ahead included; a look-ahead it cuts short of the version is this limit, not a bad version | `Limit_Exceeded` |
| `Max_Opcodes` | each opcode, the version opcode and `HeaderOp` included | `Limit_Exceeded` |
| `Max_Opcode_Bytes` | each opcode's data, before every read or skip inside it; not the file header | `Limit_Exceeded` |
| `Max_Region_Bytes`, `Max_Polygon_Points` | each region and polygon size word, enumerating and rendering | `Limit_Exceeded` |
| `Max_Metadata_Items`, `Max_Retained_Metadata_Bytes` | before an item is retained | strict: `Limit_Exceeded`; lenient: dropped, `Data_Loss` warning |
| `Max_Allocation_Bytes` | each allocation before it is made: a retained payload, an opcode's row buffers (with a PixPat's tile), a font's atlas and file, a QuickTime image's pixels (never above 2^31 − 1 bytes, set aside only once the JPEG header agrees); jpeglib gets the rest for its own buffers, at most 8 times the RGB bytes of the image rounded up to 32-pixel MCUs, plus 1 MiB (its coefficient and output limits too); the encoder's row buffers | `Limit_Exceeded` |
| `Max_Total_Allocation_Bytes` | every allocation of a session, counted when admitted and never given back; unlimited by default | `Limit_Exceeded` |
| `Max_Drawing_Work` | all rendering work, drawn or not, before or as it is done: the specification, section 9, lists what each piece costs | `Limit_Exceeded` |
| `Max_Embedded_Image_Bytes` | a QuickTime image's dataSize, before decoding | `Limit_Exceeded` |
| `Max_Embedded_Image_Pixels` | a QuickTime image's width × height, before decoding, and jpeglib's pixel limit | `Limit_Exceeded` |
| `Max_Warning_Records` | the warning log | the last slot becomes `Warnings_Suppressed`; no warning is otherwise dropped |

Coordinates are bounded rather than budgeted: line ends and the text origin
stay within ±2^24, and the origin within ±(2^24 − 2^15), so that any 16-bit
point read after it is still within ±2^24. An opcode that would move one
further fails with `Opcode_Invalid`. Moving the origin costs nothing, since
the clip region stays in local coordinates.

The renderer draws into the caller's view and allocates no canvas, so there
is no canvas byte limit: `Max_Output_Bytes` bounds the view.

## The drawing budget's unit

A unit is meant to be about one pixel's work; measured, it is between about
50 and 150 ns. The default `Max_Drawing_Work` of 2^30 is about four paints of
the largest default canvas and bounds a hostile picture to a minute or two of
work. Callers that render very large pictures raise it; callers that need a
tighter bound lower it.

## Fuzzing and the real-world corpus

`pictlib_fuzz` mutates the fixture pictures and fresh encoder output and runs
every mutant through enumeration and both lenient renders under tight limits:
a 1024 x 1024 frame, 2^20 canvas and embedded pixels, 2^26 units of drawing
work, 64 MiB of allocation. Besides flipping, replacing, truncating, deleting
and inserting bytes, it plants opcodes, writes extreme points (±32 768) and
repeats short chunks up to 64 KiB, as runaway origins, pens and text do.

- An exception escaping pictlib is saved for replay and fails the run.
- An input taking more than two seconds (slow) or a minute (stuck) is saved
  and reported; it fails the run only with `--fail-stuck`, since a loaded
  machine can be that slow.
- Seeds are taken in file-name order, so a run's arguments reproduce it on
  any machine.
- `pictlib_fuzz --replay FILE...` runs saved inputs through the same checks
  and prints how long each took.

`hostile.*` in the AUnit suite holds the cases that once overflowed or worked
without bound; they assert what work costs through the budgets, never the
clock. `pictlib_real_world` holds LibreOffice's PICT filter test files, CVE
reproductions among them, to their recorded outcomes, and fails on a recorded
picture that has gone missing.

## Tasks

Decoders and encoders share no state and may run in different tasks.
textrender's rasterizer shares scratch buffers between all renderers, so pictlib
calls it only under one process-wide lock: text drawn in parallel tasks takes
turns; everything else runs in parallel.

## Memory

The decoder holds a fixed 528-byte look-ahead buffer. Retained metadata is
copied into library-owned heap storage that `Reset`, `Initialize` and
`Finalize` release. A payload is read into a heap buffer only after the
per-opcode and allocation budgets admit it. Rendering decodes pixel data one
row at a time through three buffers per opcode (stored row, unpacked row,
row of colors), at most 64 KiB plus two rows, and frees them when the opcode
ends. Regions keep their scanline data and the current inversion set only.

## Caller views

`Render` writes only into a view that `Images.Is_Valid` accepts and whose size
is the frame's. The descriptor check is overflow-safe: the stride is compared
before `stride * (height - 1)` is formed. Row padding beyond each row's pixels
is never written.

## Caller buffers and `Unchecked_Access`

The decoder borrows its source: the caller keeps it alive until `Reset`,
`Initialize` or `Finalize`. `Copy_Metadata` writes into a caller buffer and
fails with `Limit_Exceeded` rather than truncating. Tests use
`Unchecked_Access` only to bind stack objects that outlive the decoder's use.
