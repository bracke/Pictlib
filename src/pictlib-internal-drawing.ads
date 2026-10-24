with Pictlib.Internal.Rendering;
with Pictlib.Internal.Sessions;
with Pictlib.Pictures;
with Pictlib.Results;

--  While a picture renders, every opcode that changes the port state or draws goes through here: the opcode
--  reader frames each opcode and, rendering, hands it to Consume before skipping or retaining what is left.
package Pictlib.Internal.Drawing is
   --  Consume: the drawing side of one opcode, which changes the port state or draws.
   --  @param P Painter.
   --  @param S Session positioned at the opcode's data.
   --  @param Event The opcode.
   --  @param Handled True when the opcode was one of these and its data was consumed; False leaves its data to
   --  the reader.
   --  @return Operation result.
   function Consume
     (P : in out Rendering.Painter;
      S : in out Sessions.Session;
      Event : Pictures.Opcode_Event;
      Handled : out Boolean) return Results.Result;

   --  Register font name: a fontName opcode the reader parsed, which text drawn later resolves by.
   --  @param P Painter.
   --  @param Font The font ID.
   --  @param Name Its family name.
   procedure Register_Font_Name (P : in out Rendering.Painter; Font : Natural; Name : String);
end Pictlib.Internal.Drawing;
