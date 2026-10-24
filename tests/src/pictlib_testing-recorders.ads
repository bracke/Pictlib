with Pictlib.Decoding;
with Pictlib.Errors;
with Pictlib.Limits;
with Pictlib.Pictures;
with Pictlib.Results;
with Pictlib.Streams;

package Pictlib_Testing.Recorders is
   type Event_Array is array (Positive range 1 .. 64) of Pictlib.Pictures.Opcode_Event;

   --  Records every opcode; stops after Stop_After opcodes when it is positive.
   type Recorder is new Pictlib.Decoding.Opcode_Visitor with record
      Events : Event_Array := [others => (others => <>)];
      Count : Natural := 0;
      Stop_After : Natural := 0;
   end record;

   overriding function Visit
     (Object : in out Recorder; Event : Pictlib.Pictures.Opcode_Event) return Pictlib.Decoding.Visit_Action;

   --  Bind Input to Decoder through the shared memory source and initialize it.
   procedure Start
     (Input : aliased Pictlib.Streams.Byte_Array;
      Decoder : in out Pictlib.Decoding.Decoder;
      Options : Pictlib.Decoding.Options := (others => <>);
      Budget : Pictlib.Limits.Limit_Set := Pictlib.Limits.Default_Limits;
      Max_Transfer : Pictlib.Byte_Count := Pictlib.Byte_Count'Last);

   --  Read the header and enumerate Input with a fresh decoder.
   procedure Decode
     (Input : aliased Pictlib.Streams.Byte_Array;
      Decoder : in out Pictlib.Decoding.Decoder;
      Events : in out Recorder;
      Outcome : out Pictlib.Results.Result;
      Options : Pictlib.Decoding.Options := (others => <>);
      Budget : Pictlib.Limits.Limit_Set := Pictlib.Limits.Default_Limits;
      Max_Transfer : Pictlib.Byte_Count := Pictlib.Byte_Count'Last);

   --  Has warning.
   --  @return True when Decoder recorded a warning with Code.
   function Has_Warning (Decoder : Pictlib.Decoding.Decoder; Code : Pictlib.Errors.Warning_Code) return Boolean;
end Pictlib_Testing.Recorders;
