with AUnit.Assertions;

package body Pictlib_Testing.Recorders is
   use type Pictlib.Errors.Warning_Code;

   overriding function Visit
     (Object : in out Recorder; Event : Pictlib.Pictures.Opcode_Event) return Pictlib.Decoding.Visit_Action is
   begin
      Object.Events.Append (Event);
      Object.Count := Natural (Object.Events.Length);
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

   function Count_Warnings (Decoder : Pictlib.Decoding.Decoder; Code : Pictlib.Errors.Warning_Code) return Natural is
      Count : Natural := 0;
   begin
      for Index in 1 .. Pictlib.Decoding.Warning_Count (Decoder) loop
         if Pictlib.Decoding.Warning_At (Decoder, Index).Code = Code then
            Count := Count + 1;
         end if;
      end loop;
      return Count;
   end Count_Warnings;

   function Warning_With (Decoder : Pictlib.Decoding.Decoder; Code : Pictlib.Errors.Warning_Code)
     return Pictlib.Errors.Warning is
   begin
      for Index in 1 .. Pictlib.Decoding.Warning_Count (Decoder) loop
         if Pictlib.Decoding.Warning_At (Decoder, Index).Code = Code then
            return Pictlib.Decoding.Warning_At (Decoder, Index);
         end if;
      end loop;
      raise Program_Error with "no warning " & Code'Image;
   end Warning_With;

   procedure Expect_Failure
     (Input : aliased Pictlib.Streams.Byte_Array;
      Code : Pictlib.Errors.Error_Code;
      Label : String;
      Op : Expected_Opcode := Any_Opcode;
      Options : Pictlib.Decoding.Options := (others => <>);
      Budget : Pictlib.Limits.Limit_Set := Pictlib.Limits.Default_Limits;
      Limit : Pictlib.Limit_Kind := Pictlib.No_Limit;
      Ordinal : Integer := -1)
   is
      use AUnit.Assertions;
      use type Pictlib.Errors.Error_Code;
      use type Pictlib.Limit_Kind;
      use type Pictlib.Decoding.Decoder_State;
      Decoder : Pictlib.Decoding.Decoder;
      Events : Recorder;
      Outcome : Pictlib.Results.Result;
   begin
      Decode (Input, Decoder, Events, Outcome, Options, Budget);
      Assert (Outcome.First_Error.Code = Code,
              Label & ": expected " & Code'Image & ", got " & Outcome.First_Error.Code'Image);
      Assert (Pictlib.Decoding.State (Decoder) = Pictlib.Decoding.Failed, Label & ": the decoder did not fail");
      Assert (Pictlib.Decoding.Last_Error (Decoder).Code = Code, Label & ": the last error is wrong");
      if Op /= Any_Opcode then
         Assert (Outcome.First_Error.Context.Has_Opcode and then Integer (Outcome.First_Error.Context.Op) = Op,
                 Label & ": the failing opcode was not recorded");
      end if;
      if Limit /= Pictlib.No_Limit then
         Assert (Outcome.First_Error.Context.Limit = Limit,
                 Label & ": wrong limit " & Outcome.First_Error.Context.Limit'Image);
      end if;
      if Ordinal >= 0 then
         Assert (Long_Long_Integer (Outcome.First_Error.Context.Ordinal) = Long_Long_Integer (Ordinal),
                 Label & ": wrong ordinal" & Outcome.First_Error.Context.Ordinal'Image);
      end if;
   end Expect_Failure;
end Pictlib_Testing.Recorders;
