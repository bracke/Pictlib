--  PICT opcode names and data-length rules (Inside Macintosh: Imaging With QuickDraw, Appendix A).
--  Version 1 pictures use the opcodes 16#00# .. 16#FF# with the same data layouts as version 2.
package Pictlib.Opcodes is
   pragma Pure;

   type Data_Rule is
     (Fixed_Data,          --  exactly Fixed_Length bytes
      Word_Length_Data,    --  a 16-bit byte count, then that many bytes
      Long_Length_Data,    --  a 32-bit byte count, then that many bytes
      Region_Data,         --  a region: 16-bit size counting itself, then the rest
      Polygon_Data,        --  a polygon: 16-bit size counting itself, then the rest
      Pixel_Pattern_Data,  --  a PixPat: type, 8-byte pattern, then a pixmap or an RGB color
      Text_Data,           --  Fixed_Length position bytes, a count byte, then that many text bytes
      Long_Comment_Data,   --  a 16-bit kind, a 16-bit byte count, then that many bytes
      Bits_Data,           --  a BitMap or PixMap copy (BitsRect .. DirectBitsRgn)
      Version_Data,        --  one byte in version 1, two bytes in version 2
      End_Of_Picture);     --  no data; the picture ends

   type Length_Rule is record
      Rule : Data_Rule := Fixed_Data;
      Fixed_Length : Natural := 0;
   end record;

   NOP : constant Opcode := 16#0000#;
   Clip : constant Opcode := 16#0001#;
   Background_Pixel_Pattern : constant Opcode := 16#0012#;
   Pen_Pixel_Pattern : constant Opcode := 16#0013#;
   Fill_Pixel_Pattern : constant Opcode := 16#0014#;
   Version_Op : constant Opcode := 16#0011#;
   Default_Hilite : constant Opcode := 16#001E#;
   Long_Text : constant Opcode := 16#0028#;
   Font_Name : constant Opcode := 16#002C#;
   Bits_Rect : constant Opcode := 16#0090#;
   Bits_Region : constant Opcode := 16#0091#;
   Pack_Bits_Rect : constant Opcode := 16#0098#;
   Pack_Bits_Region : constant Opcode := 16#0099#;
   Direct_Bits_Rect : constant Opcode := 16#009A#;
   Direct_Bits_Region : constant Opcode := 16#009B#;
   Short_Comment : constant Opcode := 16#00A0#;
   Long_Comment : constant Opcode := 16#00A1#;
   End_Picture : constant Opcode := 16#00FF#;
   Header_Op : constant Opcode := 16#0C00#;
   Compressed_QuickTime : constant Opcode := 16#8200#;
   Uncompressed_QuickTime : constant Opcode := 16#8201#;

   --  Rule for.
   --  @param Op Opcode.
   --  @return How the data that follows Op is delimited.
   function Rule_For (Op : Opcode) return Length_Rule;
   --  Is reserved.
   --  @param Op Opcode.
   --  @return True when Apple reserves Op; reserved opcodes are legal and skipped by their length rule.
   function Is_Reserved (Op : Opcode) return Boolean;
   --  Name.
   --  @param Op Opcode.
   --  @return Apple's name for Op, or "Reserved".
   function Name (Op : Opcode) return String;
end Pictlib.Opcodes;
