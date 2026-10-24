with Pictlib.Internal.Opcode_Reader;
with Pictlib.Pictures;
with Pictlib.Results;

--  The picture container: the optional 512-byte file header, picSize, picFrame, the version opcode and,
--  for version 2, the HeaderOp.
package Pictlib.Internal.Container is
   type Header_Events is array (1 .. 2) of Pictures.Opcode_Event;

   --  Read header.
   --  @param S Session bound to a fresh source; on success it is positioned after the header opcodes.
   --  @param Policy Whether a 512-byte file header precedes the picture.
   --  @param Info The header.
   --  @param Events The version opcode and, when present, the HeaderOp, for enumeration.
   --  @param Event_Count Entries of Events that are meaningful.
   --  @return Success, or the failure.
   function Read_Header
     (S : in out Opcode_Reader.Session;
      Policy : Header_Policy;
      Info : out Pictures.Header_Info;
      Events : out Header_Events;
      Event_Count : out Natural) return Results.Result;
end Pictlib.Internal.Container;
