with Pictlib.Streams;

--  Hand-assembled PICT bytes, written from the layouts in Inside Macintosh: Imaging With QuickDraw, Appendix A.
--  Nothing here comes from pictlib's own writer.
package Pictlib_Testing.Builders is
   subtype Bytes is Pictlib.Streams.Byte_Array;

   --  One byte.
   function B (Value : Natural) return Bytes with Pre => Value <= 16#FF#;
   --  A big-endian 16-bit word; negative values are two's complement.
   function W (Value : Integer) return Bytes with Pre => Value in -16#8000# .. 16#FFFF#;
   --  A big-endian 32-bit long.
   function L (Value : Long_Long_Integer) return Bytes with Pre => Value in 0 .. 16#FFFF_FFFF#;
   --  A QuickDraw Rect: top, left, bottom, right.
   function Rect (Top, Left, Bottom, Right : Integer) return Bytes;
   --  Count zero bytes.
   function Zeros (Count : Natural) return Bytes;
   --  Characters as bytes.
   function Text (Item : String) return Bytes;
   --  A rectangular region.
   function Region (Top, Left, Bottom, Right : Integer) return Bytes;

   --  picSize (Size), picFrame and the version 1 version opcode.
   function V1_Prefix (Top, Left, Bottom, Right : Integer; Size : Natural := 0) return Bytes;
   --  picSize, picFrame, the version 2 version opcode and an extended version 2 HeaderOp at 72 dpi
   --  whose source rectangle is the frame.
   function V2_Prefix (Top, Left, Bottom, Right : Integer; Size : Natural := 0) return Bytes;
   --  V2_Prefix (Top, Left, Bottom, Right), Body, then the end opcode. Body must keep version 2 alignment.
   function V2_Picture (Top, Left, Bottom, Right : Integer; Body_Bytes : Bytes) return Bytes;
   --  A color table header: seed 0, Flags, and Entries entries (ctSize = Entries - 1).
   function Table_Header (Flags, Entries : Natural) return Bytes;
   --  One color table entry, 16-bit components.
   function Table_Entry (Value, Red, Green, Blue : Natural) return Bytes;
   --  A CompressedQuickTime opcode (16#8200#), from Inside Macintosh: QuickTime: version 0, the matrix
   --  [Scale_H 0 0 / 0 Scale_V 0 / Move_H Move_V 1] (16.16, the last column 2.30), the matte, the transfer
   --  mode, srcRect, accuracy, the mask region, an 86-byte ImageDescription and the compressed data, padded to
   --  an even length.
   function QuickTime
     (Codec : String;
      Width, Height : Natural;
      Data : Bytes;
      Scale_H : Long_Long_Integer := 16#1_0000#;
      Scale_V : Long_Long_Integer := 16#1_0000#;
      Move_H : Long_Long_Integer := 0;
      Move_V : Long_Long_Integer := 0;
      Skew : Long_Long_Integer := 0;
      Mode : Natural := 16#40#;
      Source : Bytes := [1 .. 0 => 0];
      Matte : Bytes := [1 .. 0 => 0];
      Mask : Bytes := [1 .. 0 => 0];
      Description_Size : Natural := 86) return Bytes
     with Pre => Codec'Length = 4;
   --  The 36 PixMap bytes after rowBytes and bounds.
   function Pixmap_Tail (Pack_Type, Pixel_Size, Component_Count, Component_Size : Natural) return Bytes;

   --  A version 2 picture of a Width x Height frame at the origin holding Body_Bytes, then the end opcode.
   function Pic (Width, Height : Natural; Body_Bytes : Bytes) return Bytes;
   --  An opcode followed by a Rect.
   function Op_Rect (Op, Top, Left, Bottom, Right : Integer) return Bytes;
   --  Origin (16#0C#): move the local system by Dh, Dv.
   function Origin (Dh, Dv : Integer) return Bytes;
   --  PnSize (16#07#): the pen V high and H wide.
   function Pen_Size (V, H : Integer) return Bytes;
   --  PnMode (16#08#).
   function Pen_Mode (Mode : Natural) return Bytes;
   --  An RGB color opcode (RGBFgCol 16#1A#, RGBBkCol 16#1B#, ...) with 16-bit components.
   function RGB (Op, Red, Green, Blue : Natural) return Bytes;
   --  Item, Count times over.
   function Repeat (Item : Bytes; Count : Natural) return Bytes;

   --  A checkerboard bit pattern: 10101010 / 01010101, four times.
   Checker : constant Bytes := [16#AA#, 16#55#, 16#AA#, 16#55#, 16#AA#, 16#55#, 16#AA#, 16#55#];
   --  A 2 x 8 BitMap copied with Mode, rowBytes 2 < 8 so unpacked: 10100101 and 00001111.
   function Bitmap_2x8
     (Mode : Natural := 0; Source, Destination : Bytes := Rect (0, 0, 2, 8)) return Bytes;
end Pictlib_Testing.Builders;
