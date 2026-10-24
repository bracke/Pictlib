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
   --  The 36 PixMap bytes after rowBytes and bounds.
   function Pixmap_Tail (Pack_Type, Pixel_Size, Component_Count, Component_Size : Natural) return Bytes;
end Pictlib_Testing.Builders;
