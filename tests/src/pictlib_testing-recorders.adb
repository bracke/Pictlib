package body Pictlib_Testing.Recorders is
   use type Pictlib.Errors.Warning_Code;

   overriding function Visit
     (Object : in out Recorder; Event : Pictlib.Pictures.Opcode_Event) return Pictlib.Decoding.Visit_Action is
   begin
      if Object.Count < Object.Events'Last then
         Object.Count := Object.Count + 1;
         Object.Events (Object.Count) := Event;
      end if;
      if Object.Stop_After > 0 and then Object.Count >= Object.Stop_After then
         return Pictlib.Decoding.Stop;
      end if;
      return Pictlib.Decoding.Continue;
   end Visit;

   --  The source must outlive the decoder's use of it, so it lives at library level.
   Source : aliased Pictlib.Streams.Memory_Source;

   procedure Start
     (Input : aliased Pictlib.Streams.Byte_Array;
      Decoder : in out Pictlib.Decoding.Decoder;
      Options : Pictlib.Decoding.Options := (others => <>);
      Budget : Pictlib.Limits.Limit_Set := Pictlib.Limits.Default_Limits;
      Max_Transfer : Pictlib.Byte_Count := Pictlib.Byte_Count'Last) is
   begin
      Pictlib.Streams.Open (Source, Input'Unchecked_Access, Max_Transfer);
      Pictlib.Decoding.Initialize (Decoder, Source'Access, Options, Budget);
   end Start;

   procedure Decode
     (Input : aliased Pictlib.Streams.Byte_Array;
      Decoder : in out Pictlib.Decoding.Decoder;
      Events : in out Recorder;
      Outcome : out Pictlib.Results.Result;
      Options : Pictlib.Decoding.Options := (others => <>);
      Budget : Pictlib.Limits.Limit_Set := Pictlib.Limits.Default_Limits;
      Max_Transfer : Pictlib.Byte_Count := Pictlib.Byte_Count'Last) is
   begin
      Start (Input, Decoder, Options, Budget, Max_Transfer);
      Outcome := Pictlib.Decoding.Read_Header (Decoder);
      if Pictlib.Results.Succeeded (Outcome) then
         Outcome := Pictlib.Decoding.Enumerate (Decoder, Events);
      end if;
   end Decode;

   function Has_Warning (Decoder : Pictlib.Decoding.Decoder; Code : Pictlib.Errors.Warning_Code) return Boolean is
   begin
      for Index in 1 .. Pictlib.Decoding.Warning_Count (Decoder) loop
         if Pictlib.Decoding.Warning_At (Decoder, Index).Code = Code then
            return True;
         end if;
      end loop;
      return False;
   end Has_Warning;
end Pictlib_Testing.Recorders;
