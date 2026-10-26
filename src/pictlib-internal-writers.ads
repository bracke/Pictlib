with Interfaces;
with Pictlib.Geometry;
with Pictlib.Results;
with Pictlib.Streams;

--  Picture bytes out: big-endian values, rectangles and version 2 alignment, either to a destination or, for
--  a dry run that measures the picture, nowhere.
package Pictlib.Internal.Writers is
   type Writer is limited private;

   --  Start.
   --  @param Object Writer to prepare.
   --  @param Output Destination, or null for a dry run that only counts.
   --  @param Max_Bytes Most bytes the writer may produce.
   procedure Start (Object : out Writer; Output : access Streams.Destination'Class; Max_Bytes : Byte_Count);
   --  Watch: once Counter moves from its value now, every later Put fails with Invalid_State and writes nothing,
   --  so a destination that rebinds or cancels what it writes for does not receive the rest of the picture.
   --  @param Object Writer.
   --  @param Counter The generation of what the writer writes for.
   procedure Watch (Object : in out Writer; Counter : not null access constant Generation);
   --  Count.
   --  @param Object Writer.
   --  @return Bytes produced so far: after a destination failure, what the destination took.
   function Count (Object : Writer) return Byte_Count;
   --  Start picture.
   --  @param Object Writer whose current count becomes picture offset 0, for alignment.
   procedure Start_Picture (Object : in out Writer);
   --  Picture count.
   --  @param Object Writer.
   --  @return Bytes produced since Start_Picture.
   function Picture_Count (Object : Writer) return Byte_Count;

   --  Put. The first failure is kept: every later Put returns it and writes nothing, so a destination that fails
   --  once never receives the rest of the picture after a gap.
   --  @param Object Writer.
   --  @param Data Bytes to produce.
   --  @return Success, Limit_Exceeded beyond Max_Bytes, or the destination's failure.
   function Put (Object : in out Writer; Data : Streams.Byte_Array) return Results.Result;
   --  Put byte.
   --  @param Object Writer.
   --  @param Value Byte to produce.
   --  @return As Put.
   function Put_Byte (Object : in out Writer; Value : Natural) return Results.Result with Pre => Value <= 255;
   --  Put word: a big-endian 16-bit value; negative values are two's complement.
   --  @param Object Writer.
   --  @param Value Word to produce.
   --  @return As Put.
   function Put_Word (Object : in out Writer; Value : Integer) return Results.Result
     with Pre => Value in -16#8000# .. 16#FFFF#;
   --  Put long: a big-endian 32-bit value.
   --  @param Object Writer.
   --  @param Value Long to produce.
   --  @return As Put.
   function Put_Long (Object : in out Writer; Value : Interfaces.Unsigned_32) return Results.Result;
   --  Put rect: top, left, bottom, right.
   --  @param Object Writer.
   --  @param Value Rectangle to produce.
   --  @return As Put.
   function Put_Rect (Object : in out Writer; Value : Geometry.Rect) return Results.Result;
   --  Align: a pad byte when the picture offset is odd, so the next version 2 opcode starts even.
   --  @param Object Writer.
   --  @return As Put.
   function Align (Object : in out Writer) return Results.Result;

private
   type Destination_Access is access all Streams.Destination'Class;
   type Generation_Access is access constant Generation;

   type Writer is limited record
      Output : Destination_Access := null;
      Total : Byte_Count := 0;
      Origin : Byte_Count := 0;
      Max_Bytes : Byte_Count := 0;
      --  The destination's offset at Start, to count a transfer a failure cut short.
      Base : Destination_Offset := 0;
      Failure : Results.Result := Results.Success;
      Watched : Generation_Access := null;
      Watched_At : Generation := 0;
   end record;
end Pictlib.Internal.Writers;
