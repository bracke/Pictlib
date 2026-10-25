package Pictlib.Internal is
   pragma Pure;

   --  PICT format constants shared by readers and the writer.

   --  rowBytes keeps its row length in the low bits: 14 for a PixMap, whose top bit marks it, 15 for a BitMap.
   Pixmap_Flag : constant := 16#8000#;
   Pixmap_Row_Bytes_Mask : constant := 16#3FFF#;
   Bitmap_Row_Bytes_Mask : constant := 16#7FFF#;
   --  A packed row's length is a byte up to this rowBytes and a word above it.
   Byte_Count_Row_Bytes : constant := 250;
   --  Rows shorter than this are stored unpacked.
   Smallest_Packed_Row_Bytes : constant := 8;

   --  A planar row, as 32-bit pack type 4 stores it: an alpha plane first when there are four components, then
   --  the red, green and blue planes, Width bytes each.
   type Color_Plane is (Red_Plane, Green_Plane, Blue_Plane);
   --  Plane offset.
   --  @param Plane A color plane.
   --  @param Components 3 or 4.
   --  @param Width Pixels per row.
   --  @return The plane's offset in the row; the alpha plane, when there is one, is at 0.
   function Plane_Offset (Plane : Color_Plane; Components, Width : Natural) return Natural is
     (((if Components = 4 then 1 else 0) + Color_Plane'Pos (Plane)) * Width)
     with Pre => Components in 3 | 4 and then Width <= 2 ** 16;
   --  Planar row length.
   --  @param Components 3 or 4.
   --  @param Width Pixels per row.
   --  @return The bytes of a planar row.
   function Planar_Row_Length (Components, Width : Natural) return Natural is (Components * Width)
     with Pre => Components in 3 | 4 and then Width <= 2 ** 16;

   --  Opcode bytes: an opcode is a byte in version 1 and a word after it, and so is the version opcode's data.
   --  @param Version A picture version.
   --  @return 1 for version 1, 2 otherwise.
   function Opcode_Bytes (Version : PICT_Version) return Positive is (if Version = Version_1 then 1 else 2);

   --  The version opcode's data in version 2, and the HeaderOp version of an extended version 2 picture (-2).
   Version_2_Word : constant := 16#02FF#;
   --  Version 1's version opcode carries this byte.
   Version_1_Number : constant := 1;
   Extended_Header_Version : constant := 16#FFFE#;

   --  The application header of a PICT file, before the picture.
   File_Header_Bytes : constant := 512;
   --  A polygon's or region's size word and bounding box, before its points or scanlines.
   Smallest_Polygon : constant := 10;
   Smallest_Region : constant := 10;
   --  A polygon point as stored: v, h.
   Polygon_Point_Bytes : constant := 4;
   --  A bit pattern, and the pat1Data of every PixPat.
   Bit_Pattern_Bytes : constant := 8;
   --  An RGBColor: three 16-bit components.
   RGB_Color_Bytes : constant := 6;
   --  The largest PixMap packType: 0 default, 1 unpacked, 2 pad byte dropped, 3 word runs, 4 component planes.
   Largest_Pack_Type : constant := 4;
   --  A PixPat's patType: a color tile, or an RGB color to dither.
   Color_Pattern_Type : constant := 1;
   Dither_Pattern_Type : constant := 2;
end Pictlib.Internal;
