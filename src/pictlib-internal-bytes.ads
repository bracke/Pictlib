with Interfaces;
with Pictlib.Results;
with Pictlib.Streams;

--  Checked big-endian readers and writers. PICT stores every multi-byte value most significant byte first.
package Pictlib.Internal.Bytes is
   pragma Preelaborate;

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

   --  To coordinate.
   --  @param Value Raw 16-bit word.
   --  @return Value interpreted as two's complement.
   function To_Coordinate (Value : Interfaces.Unsigned_16) return Coordinate;
   --  From coordinate.
   --  @param Value Coordinate.
   --  @return Two's-complement 16-bit word of Value.
   function From_Coordinate (Value : Coordinate) return Interfaces.Unsigned_16;

   --  Write byte.
   --  @param Object Destination to write to.
   --  @param Value Byte to write.
   --  @param Context Opcode recorded on failure.
   --  @return Operation result.
   function Write_Byte
     (Object : in out Streams.Destination'Class;
      Value : Byte;
      Context : Opcode_Context := No_Opcode) return Results.Result;

   --  Write U16 BE.
   --  @param Object Destination to write to.
   --  @param Value Value written most significant byte first.
   --  @param Context Opcode recorded on failure.
   --  @return Operation result.
   function Write_U16_BE
     (Object : in out Streams.Destination'Class;
      Value : Interfaces.Unsigned_16;
      Context : Opcode_Context := No_Opcode) return Results.Result;

   --  Write U32 BE.
   --  @param Object Destination to write to.
   --  @param Value Value written most significant byte first.
   --  @param Context Opcode recorded on failure.
   --  @return Operation result.
   function Write_U32_BE
     (Object : in out Streams.Destination'Class;
      Value : Interfaces.Unsigned_32;
      Context : Opcode_Context := No_Opcode) return Results.Result;

   --  Write coordinate.
   --  @param Object Destination to write to.
   --  @param Value Coordinate written as a two's-complement big-endian word.
   --  @param Context Opcode recorded on failure.
   --  @return Operation result.
   function Write_Coordinate
     (Object : in out Streams.Destination'Class;
      Value : Coordinate;
      Context : Opcode_Context := No_Opcode) return Results.Result;
end Pictlib.Internal.Bytes;
