# Limits And Safety Boundaries

PICT input is hostile input. Every size the picture states is checked before it
bounds a read, a skip, an allocation or a loop.

## Budgets enforced from M1

| Limit | Enforced where | On excess |
| --- | --- | --- |
| `Max_Frame_Width`, `Max_Frame_Height` | after `picFrame`, before any opcode | `Limit_Exceeded` |
| `Max_Picture_Bytes` | every byte the decoder takes from its source, the look-ahead included | `Limit_Exceeded` |
| `Max_Opcodes` | each opcode, the version opcode and `HeaderOp` included | `Limit_Exceeded` |
| `Max_Opcode_Bytes` | each opcode's data, checked before every skip or read inside it | `Limit_Exceeded` |
| `Max_Region_Bytes`, `Max_Polygon_Points` | each region and polygon size word | `Limit_Exceeded` |
| `Max_Metadata_Items`, `Max_Retained_Metadata_Bytes` | before an item is retained | strict: `Limit_Exceeded`; lenient: dropped, `Data_Loss` warning |
| `Max_Allocation_Bytes` | each heap buffer for a retained payload | `Limit_Exceeded` |
| `Max_Warning_Records` | the warning log | last slot becomes `Warnings_Suppressed` |

| `Max_Canvas_Pixels` | the frame, when `Render` starts | `Limit_Exceeded` |
| `Max_Output_Bytes` | the view's accessible bytes, when `Render` starts | `Limit_Exceeded` |
| `Max_Drawing_Work` | every pixel painted, every pixel converted from a copied row, every unit of region, polygon, line and shape-building work, checked while a shape is built | `Limit_Exceeded` |
| `Max_Polygon_Points` | each polygon, also while rendering | `Limit_Exceeded` |
| `Max_Allocation_Bytes` | each opcode's row buffers, each font's glyph atlas | `Limit_Exceeded` |

| `Max_Embedded_Image_Bytes` | a QuickTime image's dataSize, before decoding | `Limit_Exceeded` |
| `Max_Embedded_Image_Pixels` | a QuickTime image's width × height, before decoding, and jpeglib's pixel limit | `Limit_Exceeded` |
| `Max_Allocation_Bytes` | a QuickTime image's RGB buffer, which is also never above 2^31 − 1 bytes | `Limit_Exceeded` |

Coordinates are bounded rather than budgeted: the origin, line ends and the
text origin stay within ±2^24, and an opcode that moves one further fails with
`Opcode_Invalid`. Moving the origin costs nothing, since the clip region stays
in local coordinates; copying a region for a "same" opcode is charged as
drawing work.

The encoder applies `Max_Frame_Width` and `Max_Frame_Height` to the image,
`Max_Allocation_Bytes` to its row buffers and `Max_Output_Bytes` to the whole
picture, measured by a dry run before anything is written.

The renderer draws into the caller's view and allocates no canvas, so there is
no canvas byte limit: `Max_Output_Bytes` bounds the view.

## Fuzzing and the real-world corpus

`pictlib_fuzz` mutates the fixture pictures and fresh encoder output and runs
every mutant through enumeration and both lenient renders under tight limits:
a 1024 x 1024 frame, 2^20 canvas and embedded pixels, 2^26 units of drawing
work, 64 MiB of allocation. Besides flipping, replacing, truncating, deleting
and inserting bytes, it plants opcodes, writes extreme points (±32 768) and
repeats short chunks up to 64 KiB, as runaway origins, pens and text do.
`hostile.*` in the AUnit suite holds the cases that once overflowed or
worked without bound. Any exception, or any input taking more than two
seconds, is saved for replay and fails the run. `pictlib_real_world` holds
LibreOffice's PICT filter test files, CVE reproductions among them, to their
recorded outcomes.

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
