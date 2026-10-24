with Pictlib.Internal.Rendering;
with Pictlib.Internal.Sessions;
with Pictlib.Pictures;
with Pictlib.Results;

--  Steps through a picture's opcode stream: reads each opcode, consumes its data by the opcode's length
--  rule within the session's budgets, aligns version 2 opcodes and retains the metadata the policy asks for.
--  With a painter, the opcodes that draw are rendered as their data is read.
package Pictlib.Internal.Opcode_Reader is
   --  Next.
   --  @param S Session positioned at an opcode boundary.
   --  @param Event The opcode read, after its data was consumed.
   --  @param At_End_Of_Input True when the input ended at the boundary; Event is then not meaningful.
   --  @param Paint Painter to render onto, or null to enumerate only.
   --  @return Success, or the failure with the opcode and ordinal in its context.
   function Next
     (S : in out Sessions.Session;
      Event : out Pictures.Opcode_Event;
      At_End_Of_Input : out Boolean;
      Paint : access Rendering.Painter := null) return Results.Result;
end Pictlib.Internal.Opcode_Reader;
