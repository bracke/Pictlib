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

The canvas, drawing work, output and embedded image limits take effect with
the milestones that use them.

## Memory

The decoder holds a fixed 528-byte look-ahead buffer. Retained metadata is
copied into library-owned heap storage that `Reset`, `Initialize` and
`Finalize` release. A payload is read into a heap buffer only after the
per-opcode and allocation budgets admit it; pixel data is skipped by its
structure, never buffered, until rendering arrives in M2.

## Caller buffers and `Unchecked_Access`

The decoder borrows its source: the caller keeps it alive until `Reset`,
`Initialize` or `Finalize`. `Copy_Metadata` writes into a caller buffer and
fails with `Limit_Exceeded` rather than truncating. Tests use
`Unchecked_Access` only to bind stack objects that outlive the decoder's use.
