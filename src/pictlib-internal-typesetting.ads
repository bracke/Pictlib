with Pictlib.Internal.Rendering;
with Pictlib.Internal.Sessions;
with Pictlib.Pictures;
with Pictlib.Results;
with Pictlib.Streams;

--  Draws a text opcode's characters with the port's text state, from the text origin's baseline, through
--  TrueType fonts the caller supplies, without antialiasing.
package Pictlib.Internal.Typesetting is
   --  Draw.
   --  @param P Painter.
   --  @param S Session, for budgets and warnings.
   --  @param Event The text opcode, for diagnostics.
   --  @param Characters Mac Roman characters.
   --  @return Success; Font_Unavailable strictly when no font resolves or loads; Unsupported_Feature strictly for
   --  outline and shadow faces, text ratios other than 1:1 and sizes above 512.
   function Draw
     (P : in out Rendering.Painter;
      S : in out Sessions.Session;
      Event : Pictures.Opcode_Event;
      Characters : Streams.Byte_Array) return Results.Result;
end Pictlib.Internal.Typesetting;
