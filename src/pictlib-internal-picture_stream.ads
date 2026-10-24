with Pictlib.Results;
with Pictlib.Streams;

--  The decoder's view of its borrowed source: a bounded look-ahead buffer that lets the container
--  detect the 512-byte file header without seeking, and a byte budget for the whole picture.
package Pictlib.Internal.Picture_Stream is
   --  The file header, picSize, picFrame and both version opcode forms.
   Lookahead_Capacity : constant := 512 + 16;

   type Reader is limited new Streams.Source with private;

   --  Bind.
   --  @param Object Reader to bind; any earlier state is discarded.
   --  @param Input Borrowed source; the caller keeps it alive while Object is used.
   --  @param Max_Bytes Largest number of bytes the reader may consume.
   procedure Bind (Object : in out Reader; Input : not null access Streams.Source'Class; Max_Bytes : Byte_Count);
   --  Unbind.
   --  @param Object Reader to release; it reads nothing until bound again.
   procedure Unbind (Object : in out Reader);

   --  Fill lookahead.
   --  @param Object Reader whose look-ahead buffer is filled.
   --  @param Count Bytes wanted ahead of the current position; fewer are buffered at end of input.
   --  @return Success, or the source failure or zero progress.
   function Fill_Lookahead (Object : in out Reader; Count : Positive) return Results.Result
     with Pre => Count <= Lookahead_Capacity;
   --  Lookahead length.
   --  @param Object Reader to inspect.
   --  @return Bytes buffered ahead of the current position.
   function Lookahead_Length (Object : Reader) return Natural;
   --  Lookahead at.
   --  @param Object Reader to inspect.
   --  @param Index 1-based position ahead of the current position.
   --  @return The buffered byte.
   function Lookahead_At (Object : Reader; Index : Positive) return Byte
     with Pre => Index <= Lookahead_Length (Object);

   --  Start picture.
   --  @param Object Reader whose current position becomes picture offset 0.
   procedure Start_Picture (Object : in out Reader);
   --  Picture offset.
   --  @param Object Reader to inspect.
   --  @return Bytes consumed since Start_Picture; version 2 opcodes align on even picture offsets.
   function Picture_Offset (Object : Reader) return Byte_Count;

   overriding function Read (Object : in out Reader; Buffer : out Streams.Byte_Array) return Streams.Source_Result;
   overriding function Offset (Object : Reader) return Source_Offset;
   overriding function Skip (Object : in out Reader; Count : Byte_Count) return Streams.Source_Result;

private
   type Source_Access is access all Streams.Source'Class;

   type Reader is limited new Streams.Source with record
      Input : Source_Access := null;
      Buffer : Streams.Byte_Array (1 .. Lookahead_Capacity) := [others => 0];
      First : Positive := 1;
      Last : Natural := 0;
      Input_Ended : Boolean := False;
      Base : Source_Offset := 0;
      Consumed : Byte_Count := 0;
      Picture_Origin : Byte_Count := 0;
      Max_Bytes : Byte_Count := 0;
   end record;
end Pictlib.Internal.Picture_Stream;
