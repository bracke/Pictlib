package Pictlib.Internal is
   pragma Pure;

   --  PICT format constants shared by readers and the writer.

   --  rowBytes keeps its row length in the low bits: 14 for a PixMap, whose top bit marks it, 15 for a BitMap.
   Pixmap_Row_Bytes_Mask : constant := 16#3FFF#;
   Bitmap_Row_Bytes_Mask : constant := 16#7FFF#;
   --  A packed row's length is a byte up to this rowBytes and a word above it.
   Byte_Count_Row_Bytes : constant := 250;
   --  Rows shorter than this are stored unpacked.
   Smallest_Packed_Row_Bytes : constant := 8;

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
   --  A PixPat's patType: a color tile, or an RGB color to dither.
   Color_Pattern_Type : constant := 1;
   Dither_Pattern_Type : constant := 2;
end Pictlib.Internal;
