with Pictlib.Internal.Rendering;
with Pictlib.Internal.Sessions;
with Pictlib.Pictures;
with Pictlib.Results;

--  The opcodes that change the port state or draw shapes, while a picture renders.
package Pictlib.Internal.Drawing is
   --  Consume.
   --  @param P Painter.
   --  @param S Session positioned at the opcode's data.
   --  @param Event The opcode.
   --  @param Handled True when the opcode was one of these and its data was consumed.
   --  @return Operation result.
   function Consume
     (P : in out Rendering.Painter;
      S : in out Sessions.Session;
      Event : Pictures.Opcode_Event;
      Handled : out Boolean) return Results.Result;
end Pictlib.Internal.Drawing;
