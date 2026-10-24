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

Available since Gate M1:

- `Pictlib.Geometry` — `Point`, `Rect`, 16.16 `Fixed`, `Fixed_Rect`.
- `Pictlib.Opcodes` — named opcodes, `Rule_For`, `Is_Reserved`, `Name`.
- `Pictlib.Pictures` — `Header_Info`, `Opcode_Event`.
- `Pictlib.Metadata` — `Item_Kind`, `Retention_Policy`, `Item_Info`.
- `Pictlib.Decoding` — `Decoder` with `Initialize`, `Reset`, `Read_Header`,
  `Header`, `Enumerate` through an `Opcode_Visitor`, metadata and warning
  queries, `Last_Error`, `Cancel`, `Finalize`.

Available since Gate M2:

- `Pictlib.Images` — `RGB_Color`, `Image_Descriptor`, `Image_View`,
  `Mutable_Image_View`, `Bytes_Per_Pixel`, `Minimum_Row_Bytes`,
  `Descriptor_Is_Valid`, `Is_Valid`.
- `Pictlib.Decoding.Render` and `Options.Background`.

Available since Gate M4:

- `Pictlib.Fonts` — `Font_ID`, `Font_Table` (`Add` by family or ID,
  `Set_Default`, `Resolve`), `Classic_Name`; `Decoding.Options.Fonts`.
- `Errors.Font_Unavailable`.

QuickTime JPEG and encoding arrive with Gates M5–M6.
