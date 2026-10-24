with Pictlib.Internal.Rendering;
with Pictlib.Internal.Sessions;
with Pictlib.Pictures;
with Pictlib.Results;

--  CompressedQuickTime (16#8200#): an image compressed by a QuickTime codec, drawn through a matrix. JPEG images
--  are decoded by jpeglib, read straight from the picture.
package Pictlib.Internal.QuickTime is
   --  Draw.
   --  @param P Painter.
   --  @param S Session positioned after the opcode's 32-bit length.
   --  @param Event The opcode, for diagnostics.
   --  @param Length The opcode's data length after the length field; all of it is consumed on success.
   --  @return Success; Unsupported_Feature strictly for codecs other than 'jpeg', mattes and matrices other
   --  than translation and scaling; Embedded_Image_Failed for a JPEG jpeglib rejects; Limit_Exceeded above the
   --  embedded image budgets; Opcode_Length_Invalid when the parts do not fit the opcode.
   function Draw
     (P : in out Rendering.Painter;
      S : in out Sessions.Session;
      Event : Pictures.Opcode_Event;
      Length : Byte_Count) return Results.Result;
end Pictlib.Internal.QuickTime;
