package Pictlib.Limits is
   pragma Preelaborate;

   --  Hostile-input budgets. Every input-derived size is checked against these before allocation,
   --  indexing or a loop bound; docs/limits_and_safety.md says where each is checked.
   type Limit_Set is record
      --  The widest and tallest frame decoded, and image encoded.
      Max_Frame_Width : Image_Width := 16_384;
      Max_Frame_Height : Image_Height := 16_384;
      --  The pixels of a frame rendered.
      Max_Canvas_Pixels : Pixel_Count := 268_435_456;
      --  The bytes taken from the source, the look-ahead included.
      Max_Picture_Bytes : Byte_Count := 1_073_741_824;
      --  The opcodes read, the version opcode and HeaderOp included.
      Max_Opcodes : Opcode_Ordinal := 16_777_216;
      --  The data of one opcode.
      Max_Opcode_Bytes : Byte_Count := 268_435_456;
      --  The bytes of one region.
      Max_Region_Bytes : Byte_Count := 16 * 1024 * 1024;
      --  The points of one polygon.
      Max_Polygon_Points : Natural := 1_048_576;
      --  The drawing work of one Render, about a pixel a unit; Spec section 9 gives the units.
      Max_Drawing_Work : Pixel_Count := 2 ** 30;
      --  The bytes of all metadata kept.
      Max_Retained_Metadata_Bytes : Byte_Count := 64 * 1024 * 1024;
      --  The metadata items kept.
      Max_Metadata_Items : Natural := 65_536;
      --  Monotonic aggregate admission for decoder-owned storage during one
      --  Initialize/Reset session. Released storage does not replenish it.
      Max_Total_Allocation_Bytes : Byte_Count := Byte_Count'Last;
      --  One allocation.
      Max_Allocation_Bytes : Byte_Count := 1_073_741_824;
      --  The bytes of a view rendered into, and of a picture encoded.
      Max_Output_Bytes : Byte_Count := 1_073_741_824;
      --  The compressed data of one embedded image.
      Max_Embedded_Image_Bytes : Byte_Count := 268_435_456;
      --  The pixels of one embedded image.
      Max_Embedded_Image_Pixels : Pixel_Count := 268_435_456;
      --  The warnings recorded; later ones are counted in a Warnings_Suppressed warning.
      Max_Warning_Records : Natural := 256;
   end record;

   Default_Limits : constant Limit_Set := (others => <>);
end Pictlib.Limits;
