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
| `Max_Drawing_Work` | every pixel painted, every unit of region, polygon, line and shape-building work | `Limit_Exceeded` |
| `Max_Polygon_Points` | each polygon, also while rendering | `Limit_Exceeded` |
| `Max_Allocation_Bytes` | each opcode's row buffers | `Limit_Exceeded` |

The embedded image limits take effect with M5. `Max_Canvas_Bytes` is reserved:
the renderer draws into the caller's view and allocates no canvas.

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
