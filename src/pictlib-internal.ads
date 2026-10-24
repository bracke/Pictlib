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
end Pictlib.Internal;
