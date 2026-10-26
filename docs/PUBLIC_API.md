# Public API notes

Only `Pictlib.*` packages outside `Pictlib.Internal` are supported public API.
This file lists each package and its headline entities, by the gate that made them
available; the package specs are the complete reference, every public subprogram
documented there.
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
  queries, `State` and its `Decoder_State`, `Last_Error`, `Cancel`,
  `Finalize`.

Available since Gate M2:

- `Pictlib.Images` — `RGB_Color`, `Image_Descriptor`, `Image_View`,
  `Mutable_Image_View`, `Bytes_Per_Pixel`, `Minimum_Row_Bytes`,
  `Descriptor_Is_Valid`, `Is_Valid`.
- `Pictlib.Decoding.Render` and `Options.Background`.

Available since Gate M4:

- `Pictlib.Font_ID` (0 .. 16#FFFF#), the one font ID type: `Pictlib.Fonts.Font_ID` is a subtype
  of it and `Metadata.Item_Info.Font_ID` has it. Code that named `Fonts.Font_ID` as a type of its
  own still compiles; code that converted between it and the metadata's ID no longer needs to.
- `Pictlib.Fonts` — `Font_ID`, `Font_Table` (`Add` by family or ID,
  `Set_Default`, `Resolve`), `Classic_Name`; `Decoding.Options.Fonts`.
- `Errors.Font_Unavailable`.

Gate M5 adds no public API: QuickTime JPEG images render through `Render`.

Available since Gate M6:

- `Pictlib.Encoding` — `Layout_Kind`, `Options`, `Default_Mono_Threshold`,
  `Encoder` with `Initialize`, `Reset`, `Encode`, `Finish`, `Layout_Used`,
  `Bytes_Written`, `State` and its `Encoder_State`, `Last_Error`, `Cancel`,
  `Finalize`.

Changed at Gate M7: `Limits.Max_Canvas_Bytes` and `Limit_Kind'(Canvas_Byte_Limit)`
were removed; they were never enforced (the renderer allocates no canvas). `Pack_Type`
was moved into the library's internals: no public subprogram used it.
