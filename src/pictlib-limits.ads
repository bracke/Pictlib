package Pictlib.Limits is
   pragma Preelaborate;

   --  Hostile-input budgets. Every input-derived size is checked against these before allocation,
   --  indexing or a loop bound.
   type Limit_Set is record
      Max_Frame_Width : Image_Width := 16_384;
      Max_Frame_Height : Image_Height := 16_384;
      Max_Canvas_Pixels : Pixel_Count := 268_435_456;
      Max_Picture_Bytes : Byte_Count := 1_073_741_824;
      Max_Opcodes : Opcode_Ordinal := 16_777_216;
      Max_Opcode_Bytes : Byte_Count := 268_435_456;
      Max_Region_Bytes : Byte_Count := 16 * 1024 * 1024;
      Max_Polygon_Points : Natural := 1_048_576;
      Max_Drawing_Work : Pixel_Count := 2 ** 34;
      Max_Retained_Metadata_Bytes : Byte_Count := 64 * 1024 * 1024;
      Max_Metadata_Items : Natural := 65_536;
      Max_Allocation_Bytes : Byte_Count := 1_073_741_824;
      Max_Output_Bytes : Byte_Count := 1_073_741_824;
      Max_Embedded_Image_Bytes : Byte_Count := 268_435_456;
      Max_Embedded_Image_Pixels : Pixel_Count := 268_435_456;
      Max_Warning_Records : Natural := 256;
   end record;

   Default_Limits : constant Limit_Set := (others => <>);
end Pictlib.Limits;
