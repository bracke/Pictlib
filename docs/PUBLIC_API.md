# Public API notes

Only `Pictlib.*` packages outside `Pictlib.Internal` are supported public API.
`tests/src/pictlib_api_consumer.ads` consumes the public surface the way an
outside crate does and must keep compiling.

## Foundation availability

Available since Gate M0:

- `Pictlib` — scalar types (`Byte`, counts and offsets, QuickDraw `Coordinate`,
  `Image_Width`/`Image_Height`, `Opcode`, `Pixel_Depth`), `Strictness_Mode`,
  `PICT_Version`, `Header_Policy`, `Pixel_Format`, `Limit_Kind`.
- `Pictlib.Version`, `Pictlib.Capabilities`.
- `Pictlib.Errors` — `Error_Code`, `Warning_Code`, `Diagnostic_Context`
  (offsets, opcode, opcode ordinal, row, expected/actual counts, limit kind,
  underlying code), stable `pict.*` identifiers.
- `Pictlib.Results`, `Pictlib.Limits`.
- `Pictlib.Streams` — `Source`/`Destination` interfaces, `Memory_Source`,
  `Fixed_Buffer_Destination`, `Read_Exact`, `Skip_Exact`, `Write_All`.

Decoding, rendering, metadata and encoding packages arrive with Gates M1–M6.
