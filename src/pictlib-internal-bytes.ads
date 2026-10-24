with Interfaces;
with Pictlib.Geometry;
with Pictlib.Results;
with Pictlib.Streams;

--  Checked big-endian readers. PICT stores every multi-byte value most significant byte first.
package Pictlib.Internal.Bytes is
   pragma Preelaborate;
   use type Interfaces.Unsigned_16;
   use type Interfaces.Unsigned_32;

   --  The opcode whose data is being transferred, recorded in the diagnostic context on failure.
   type Opcode_Context is record
      Present : Boolean := False;
      Op : Opcode := 0;
   end record;

   No_Opcode : constant Opcode_Context := (others => <>);

   --  Within.
   --  @param Op Opcode whose data is being transferred.
   --  @return Context naming Op.
   function Within (Op : Opcode) return Opcode_Context is ((Present => True, Op => Op));

   --  Read byte.
   --  @param Object Source to read from.
   --  @param Value Byte read; 0 on failure.
   --  @param Context Opcode recorded on failure.
   --  @return Operation result.
   function Read_Byte
     (Object : in out Streams.Source'Class;
      Value : out Byte;
      Context : Opcode_Context := No_Opcode) return Results.Result;

   --  Read U16 BE.
   --  @param Object Source to read from.
   --  @param Value Big-endian 16-bit value read; 0 on failure.
   --  @param Context Opcode recorded on failure.
   --  @return Operation result.
   function Read_U16_BE
     (Object : in out Streams.Source'Class;
      Value : out Interfaces.Unsigned_16;
      Context : Opcode_Context := No_Opcode) return Results.Result;

   --  Read U32 BE.
   --  @param Object Source to read from.
   --  @param Value Big-endian 32-bit value read; 0 on failure.
   --  @param Context Opcode recorded on failure.
   --  @return Operation result.
   function Read_U32_BE
     (Object : in out Streams.Source'Class;
      Value : out Interfaces.Unsigned_32;
      Context : Opcode_Context := No_Opcode) return Results.Result;

   --  Read coordinate.
   --  @param Object Source to read from.
   --  @param Value Two's-complement big-endian 16-bit coordinate; 0 on failure.
   --  @param Context Opcode recorded on failure.
   --  @return Operation result.
   function Read_Coordinate
     (Object : in out Streams.Source'Class;
      Value : out Coordinate;
      Context : Opcode_Context := No_Opcode) return Results.Result;

   --  Read fixed.
   --  @param Object Source to read from.
   --  @param Value Two's-complement big-endian 16.16 value; 0 on failure.
   --  @param Context Opcode recorded on failure.
   --  @return Operation result.
   function Read_Fixed
     (Object : in out Streams.Source'Class;
      Value : out Geometry.Fixed;
      Context : Opcode_Context := No_Opcode) return Results.Result;

   --  Read rect.
   --  @param Object Source to read from.
   --  @param Value Rectangle read as top, left, bottom, right; all zero on failure.
   --  @param Context Opcode recorded on failure.
   --  @return Operation result.
   function Read_Rect
     (Object : in out Streams.Source'Class;
      Value : out Geometry.Rect;
      Context : Opcode_Context := No_Opcode) return Results.Result;

   --  To coordinate.
   --  @param Value Raw 16-bit word.
   --  @return Value interpreted as two's complement.
   function To_Coordinate (Value : Interfaces.Unsigned_16) return Coordinate;
   --  From coordinate.
   --  @param Value Coordinate.
   --  @return Two's-complement 16-bit word of Value.
   function From_Coordinate (Value : Coordinate) return Interfaces.Unsigned_16;

   --  To signed 32.
   --  @param Value Raw 32-bit long.
   --  @return Value interpreted as two's complement.
   function To_Signed_32 (Value : Interfaces.Unsigned_32) return Long_Long_Integer is
     (if Value >= 16#8000_0000# then Long_Long_Integer (Value) - 16#1_0000_0000# else Long_Long_Integer (Value));

   --  Word at.
   --  @param Data Bytes already read.
   --  @param Position Index of the word's first byte.
   --  @return The big-endian word there.
   function Word_At (Data : Streams.Byte_Array; Position : Natural) return Interfaces.Unsigned_16 is
     (Interfaces.Shift_Left (Interfaces.Unsigned_16 (Data (Position)), 8)
      or Interfaces.Unsigned_16 (Data (Position + 1)))
     with Pre => Position >= Data'First and then Position < Data'Last;
   --  Long at.
   --  @param Data Bytes already read.
   --  @param Position Index of the long's first byte.
   --  @return The big-endian long there.
   function Long_At (Data : Streams.Byte_Array; Position : Natural) return Interfaces.Unsigned_32 is
     (Interfaces.Shift_Left (Interfaces.Unsigned_32 (Word_At (Data, Position)), 16)
      or Interfaces.Unsigned_32 (Word_At (Data, Position + 2)))
     with Pre => Position >= Data'First and then Position <= Data'Last - 3;
end Pictlib.Internal.Bytes;
