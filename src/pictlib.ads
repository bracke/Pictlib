with Interfaces;

package Pictlib is
   pragma Pure;

   type Byte is new Interfaces.Unsigned_8;
   type Byte_Count is range 0 .. 2 ** 63 - 1;
   type Source_Offset is range 0 .. 2 ** 63 - 1;
   type Destination_Offset is range 0 .. 2 ** 63 - 1;

   --  QuickDraw coordinates are signed 16-bit values; a picture frame spans at most 32_767 units.
   type Coordinate is range -32_768 .. 32_767;
   type Image_Width is range 1 .. 32_767;
   type Image_Height is range 1 .. 32_767;
   type Pixel_Count is range 0 .. 2 ** 63 - 1;
   type Row_Stride is range 0 .. 2 ** 63 - 1;

   type Opcode is range 0 .. 16#FFFF#;
   type Opcode_Ordinal is range 0 .. 2 ** 63 - 1;
   type Pixel_Depth is range 1 .. 32
     with Static_Predicate => Pixel_Depth in 1 | 2 | 4 | 8 | 16 | 32;
   type Pack_Type is range 0 .. 4;
   type Row_Index is range 0 .. 2 ** 31 - 1;

   type Strictness_Mode is (Strict, Compatible, Recover_When_Safe);
   type PICT_Version is (Version_1, Version_2, Extended_Version_2);
   type Header_Policy is (Auto, Has_File_Header, No_File_Header);
   type Pixel_Format is (RGB_24, BGR_24, RGBA_32, BGRA_32, ARGB_32);

   --  The limit a Limit_Exceeded failure crossed. Warning_Record_Limit names Max_Warning_Records, which caps the
   --  warning log and is never crossed.
   type Limit_Kind is
     (No_Limit,
      Frame_Width_Limit,
      Frame_Height_Limit,
      Canvas_Pixel_Limit,
      Picture_Byte_Limit,
      Opcode_Count_Limit,
      Opcode_Byte_Limit,
      Region_Byte_Limit,
      Polygon_Point_Limit,
      Drawing_Work_Limit,
      Retained_Metadata_Byte_Limit,
      Metadata_Item_Limit,
      Allocation_Byte_Limit,
      Total_Allocation_Byte_Limit,
      Output_Byte_Limit,
      Embedded_Image_Byte_Limit,
      Embedded_Image_Pixel_Limit,
      Warning_Record_Limit);
end Pictlib;
