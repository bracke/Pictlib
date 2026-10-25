with Ada.Containers.Vectors;
with Pictlib.Decoding;
with Pictlib.Errors;
with Pictlib.Limits;
with Pictlib.Pictures;
with Pictlib.Results;
with Pictlib.Streams;

package Pictlib_Testing.Recorders is
   package Event_Vectors is new Ada.Containers.Vectors (Positive, Pictlib.Pictures.Opcode_Event, Pictlib.Pictures."=");

   --  Records every opcode, however many; stops after Stop_After opcodes when it is positive.
   type Recorder is new Pictlib.Decoding.Opcode_Visitor with record
      Events : Event_Vectors.Vector;
      Count : Natural := 0;
      Stop_After : Natural := 0;
   end record;

   overriding function Visit
     (Object : in out Recorder; Event : Pictlib.Pictures.Opcode_Event) return Pictlib.Decoding.Visit_Action;

   --  Visits every opcode and keeps nothing.
   type Null_Visitor is new Pictlib.Decoding.Opcode_Visitor with null record;

   overriding function Visit
     (Object : in out Null_Visitor; Event : Pictlib.Pictures.Opcode_Event) return Pictlib.Decoding.Visit_Action
   is (Pictlib.Decoding.Continue);

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
   --  Count warnings.
   --  @return How many warnings with Code Decoder recorded.
   function Count_Warnings (Decoder : Pictlib.Decoding.Decoder; Code : Pictlib.Errors.Warning_Code) return Natural;
   --  Warning with.
   --  @return The first warning with Code Decoder recorded.
   function Warning_With (Decoder : Pictlib.Decoding.Decoder; Code : Pictlib.Errors.Warning_Code)
     return Pictlib.Errors.Warning
     with Pre => Has_Warning (Decoder, Code);

   --  Expect failure: enumerating Input with a fresh decoder fails with Code, leaves the decoder Failed with
   --  Code as its last error, and names Op, Limit and Ordinal when they are given.
   procedure Expect_Failure
     (Input : aliased Pictlib.Streams.Byte_Array;
      Code : Pictlib.Errors.Error_Code;
      Label : String;
      Op : Expected_Opcode := Any_Opcode;
      Options : Pictlib.Decoding.Options := (others => <>);
      Budget : Pictlib.Limits.Limit_Set := Pictlib.Limits.Default_Limits;
      Limit : Pictlib.Limit_Kind := Pictlib.No_Limit;
      Ordinal : Integer := -1);
end Pictlib_Testing.Recorders;
