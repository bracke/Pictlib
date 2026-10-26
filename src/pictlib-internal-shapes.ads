with Pictlib.Internal.Rendering;
with Pictlib.Internal.Sessions;
with Pictlib.Opcodes;
with Pictlib.Pictures;
with Pictlib.Results;

--  The shape opcodes: rects, round rects, ovals, arcs, polygons and regions, framed, painted, erased, inverted
--  and filled, with their "same" forms, as coverage painted through the port.
package Pictlib.Internal.Shapes is
   --  Has verb.
   --  @param Op A shape opcode.
   --  @return True when its verb is one QuickDraw draws: verbs 5 .. 7 are reserved.
   function Has_Verb (Op : Opcode) return Boolean;

   --  Draw.
   --  @param P Painter.
   --  @param S Session positioned at the opcode's data.
   --  @param Event A shape opcode whose verb is drawn.
   --  @return Success, or the failure reading or drawing it.
   function Draw
     (P : in out Rendering.Painter;
      S : in out Sessions.Session;
      Event : Pictures.Opcode_Event) return Results.Result
     with Pre => Event.Op in Opcodes.First_Shape .. Opcodes.Last_Shape and then Has_Verb (Event.Op);
end Pictlib.Internal.Shapes;
