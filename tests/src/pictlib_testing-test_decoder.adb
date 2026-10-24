with AUnit.Assertions;

with Pictlib;
with Pictlib.Decoding;
with Pictlib.Errors;
with Pictlib.Results;
with Pictlib.Streams;
with Pictlib_Testing.Builders;
with Pictlib_Testing.Recorders;

package body Pictlib_Testing.Test_Decoder is
   use AUnit.Assertions;
   use Pictlib_Testing.Builders;
   use type Pictlib.Decoding.Decoder_State;
   use type Pictlib.Errors.Error_Code;
   use type Pictlib.Opcode;
   use type Pictlib.Opcode_Ordinal;
   use type Pictlib.PICT_Version;
   use type Pictlib.Streams.Byte_Array;

   package Decoding renames Pictlib.Decoding;

   Picture : aliased constant Bytes :=
     V2_Prefix (0, 0, 4, 8) & W (16#001E#) & W (16#00A0#) & W (7) & W (16#0030#) & Rect (0, 0, 1, 1) & W (16#00FF#);
   Other : aliased constant Bytes := V1_Prefix (0, 0, 2, 2) & B (16#A0#) & W (9) & B (16#FF#);
   Broken : aliased constant Bytes := V2_Prefix (0, 0, 4, 8) & W (16#0001#) & W (2) & W (16#00FF#);

   procedure Wrong_State_Calls (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Visitor_Stops (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Failure_Is_Terminal (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Cancellation (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Reset_Reuses_The_Decoder (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Finalize_Is_Idempotent (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Source_Failure (T : in out AUnit.Test_Cases.Test_Case'Class);

   overriding function Name (T : Test) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("decoder");
   end Name;

   overriding procedure Register_Tests (T : in out Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Wrong_State_Calls'Access, "decoder.state.wrong_state");
      Register_Routine (T, Visitor_Stops'Access, "decoder.state.visitor_stop");
      Register_Routine (T, Failure_Is_Terminal'Access, "decoder.state.failure_terminal");
      Register_Routine (T, Cancellation'Access, "decoder.state.cancel");
      Register_Routine (T, Reset_Reuses_The_Decoder'Access, "decoder.state.reset_reuse");
      Register_Routine (T, Finalize_Is_Idempotent'Access, "decoder.state.finalize");
      Register_Routine (T, Source_Failure'Access, "decoder.source_failure");
   end Register_Tests;

   procedure Wrong_State_Calls (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Decoder : Decoding.Decoder;
      Source : aliased Pictlib.Streams.Memory_Source;
      Events : Recorders.Recorder;
      Outcome : Pictlib.Results.Result;
   begin
      Assert (Decoding.State (Decoder) = Decoding.Created, "a new decoder is not Created");
      Outcome := Decoding.Read_Header (Decoder);
      Assert (Outcome.First_Error.Code = Pictlib.Errors.Invalid_State, "an uninitialized decoder read a header");
      Assert (Decoding.State (Decoder) = Decoding.Created, "a wrong-state call changed the state");

      Pictlib.Streams.Open (Source, Picture'Access);
      Decoding.Initialize (Decoder, Source'Access);
      Assert (Decoding.State (Decoder) = Decoding.Ready, "an initialized decoder is not Ready");
      Outcome := Decoding.Enumerate (Decoder, Events);
      Assert (Outcome.First_Error.Code = Pictlib.Errors.Invalid_State, "enumeration ran before the header");
      Assert (Decoding.State (Decoder) = Decoding.Ready and then Events.Count = 0,
              "a wrong-state enumeration had effects");

      Outcome := Decoding.Read_Header (Decoder);
      Assert (Pictlib.Results.Succeeded (Outcome) and then Decoding.State (Decoder) = Decoding.Header_Read,
              "the header was not read");
      Outcome := Decoding.Read_Header (Decoder);
      Assert (Outcome.First_Error.Code = Pictlib.Errors.Invalid_State
              and then Decoding.State (Decoder) = Decoding.Header_Read,
              "the header was read twice");

      Outcome := Decoding.Enumerate (Decoder, Events);
      Assert (Pictlib.Results.Succeeded (Outcome) and then Decoding.State (Decoder) = Decoding.Finished,
              "enumeration did not finish");
      Assert (Events.Count = 6, "enumeration saw" & Events.Count'Image & " opcodes");
      Outcome := Decoding.Enumerate (Decoder, Events);
      Assert (Outcome.First_Error.Code = Pictlib.Errors.Invalid_State
              and then Decoding.State (Decoder) = Decoding.Finished and then Events.Count = 6,
              "a finished picture was enumerated again");
      Assert (not Pictlib.Errors.Is_Fatal (Decoding.Last_Error (Decoder)), "a wrong-state call set the last error");
   end Wrong_State_Calls;

   procedure Visitor_Stops (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Decoder : Decoding.Decoder;
      Outcome : Pictlib.Results.Result;
   begin
      for Stop_After in 1 .. 5 loop
         declare
            Events : Recorders.Recorder := (Stop_After => Stop_After, others => <>);
         begin
            Recorders.Decode (Picture, Decoder, Events, Outcome);
            Assert (Pictlib.Results.Succeeded (Outcome) and then Decoding.State (Decoder) = Decoding.Stopped,
                    "the visitor did not stop after" & Stop_After'Image);
            Assert (Events.Count = Stop_After, "the visitor saw opcodes after stopping");
            Outcome := Decoding.Enumerate (Decoder, Events);
            Assert (Outcome.First_Error.Code = Pictlib.Errors.Invalid_State, "a stopped decoder resumed");
         end;
      end loop;
      declare
         Events : Recorders.Recorder := (Stop_After => 6, others => <>);
      begin
         Recorders.Decode (Picture, Decoder, Events, Outcome);
         Assert (Decoding.State (Decoder) = Decoding.Finished, "stopping at the end opcode is finishing");
      end;
   end Visitor_Stops;

   procedure Failure_Is_Terminal (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Decoder : Decoding.Decoder;
      Events : Recorders.Recorder;
      Outcome : Pictlib.Results.Result;
   begin
      Recorders.Decode (Broken, Decoder, Events, Outcome);
      Assert (Outcome.First_Error.Code = Pictlib.Errors.Region_Invalid, "the broken region was accepted");
      Assert (Decoding.State (Decoder) = Decoding.Failed, "the decoder did not fail");
      Assert (Decoding.Last_Error (Decoder).Code = Pictlib.Errors.Region_Invalid
              and then Decoding.Last_Error (Decoder).Context.Op = 16#0001#
              and then Decoding.Last_Error (Decoder).Context.Ordinal = 2,
              "the last error lost its context");
      Assert (Events.Count = 2, "opcodes after the failure were reported");
      Outcome := Decoding.Enumerate (Decoder, Events);
      Assert (Outcome.First_Error.Code = Pictlib.Errors.Invalid_State, "a failed decoder resumed");
      Assert (Decoding.Last_Error (Decoder).Code = Pictlib.Errors.Region_Invalid,
              "a wrong-state call replaced the last error");
   end Failure_Is_Terminal;

   procedure Cancellation (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Decoder : Decoding.Decoder;
      Source : aliased Pictlib.Streams.Memory_Source;
      Events : Recorders.Recorder;
      Outcome : Pictlib.Results.Result;
   begin
      Pictlib.Streams.Open (Source, Picture'Access);
      Decoding.Initialize (Decoder, Source'Access);
      Decoding.Cancel (Decoder);
      Assert (Decoding.State (Decoder) = Decoding.Cancelled, "a ready decoder was not cancelled");
      Outcome := Decoding.Read_Header (Decoder);
      Assert (Outcome.First_Error.Code = Pictlib.Errors.Operation_Cancelled, "a cancelled decoder read a header");

      Pictlib.Streams.Open (Source, Picture'Access);
      Decoding.Initialize (Decoder, Source'Access);
      Outcome := Decoding.Read_Header (Decoder);
      Assert (Pictlib.Results.Succeeded (Outcome), "the header was not read");
      Decoding.Cancel (Decoder);
      Outcome := Decoding.Enumerate (Decoder, Events);
      Assert (Outcome.First_Error.Code = Pictlib.Errors.Operation_Cancelled and then Events.Count = 0,
              "a cancelled decoder enumerated");

      Recorders.Decode (Picture, Decoder, Events, Outcome);
      Decoding.Cancel (Decoder);
      Assert (Decoding.State (Decoder) = Decoding.Finished, "cancelling a finished decoder changed its state");
   end Cancellation;

   procedure Reset_Reuses_The_Decoder (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Decoder : Decoding.Decoder;
      First_Events : Recorders.Recorder;
      Second_Events : Recorders.Recorder;
      Second : aliased Pictlib.Streams.Memory_Source;
      Outcome : Pictlib.Results.Result;
   begin
      Recorders.Decode (Broken, Decoder, First_Events, Outcome, (Strictness => Pictlib.Compatible, others => <>));
      Assert (Decoding.State (Decoder) = Decoding.Failed, "the first picture did not fail");

      Pictlib.Streams.Open (Second, Other'Access);
      Decoding.Reset (Decoder, Second'Access);
      Assert (Decoding.State (Decoder) = Decoding.Ready, "reset did not make the decoder ready");
      Assert (not Pictlib.Errors.Is_Fatal (Decoding.Last_Error (Decoder)), "reset kept the last error");
      Assert (Decoding.Metadata_Count (Decoder) = 0 and then Decoding.Warning_Count (Decoder) = 0,
              "reset kept metadata or warnings");
      Outcome := Decoding.Read_Header (Decoder);
      if Pictlib.Results.Succeeded (Outcome) then
         Outcome := Decoding.Enumerate (Decoder, Second_Events);
      end if;
      Assert (Pictlib.Results.Succeeded (Outcome), "the reset decoder failed the second picture");
      Assert (Decoding.Header (Decoder).Version = Pictlib.Version_1, "the second header is stale");
      Assert (Second_Events.Count = 3 and then Second_Events.Events (1).Ordinal = 0,
              "ordinals did not restart");
      Assert (Decoding.Metadata_Count (Decoder) = 1, "the second picture's comment was not retained");

      --  Reset keeps the options: the first decode was compatible, so a missing end opcode is accepted.
      declare
         Truncated : aliased constant Bytes := V1_Prefix (0, 0, 2, 2);
         Third : aliased Pictlib.Streams.Memory_Source;
         Events : Recorders.Recorder;
      begin
         Pictlib.Streams.Open (Third, Truncated'Unchecked_Access);
         Decoding.Reset (Decoder, Third'Unchecked_Access);
         Outcome := Decoding.Read_Header (Decoder);
         if Pictlib.Results.Succeeded (Outcome) then
            Outcome := Decoding.Enumerate (Decoder, Events);
         end if;
         Assert (Pictlib.Results.Succeeded (Outcome), "reset lost the options");
      end;
   end Reset_Reuses_The_Decoder;

   procedure Finalize_Is_Idempotent (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Decoder : Decoding.Decoder;
      Events : Recorders.Recorder;
      Outcome : Pictlib.Results.Result;
   begin
      Decoding.Finalize (Decoder);
      Assert (Decoding.State (Decoder) = Decoding.Created, "finalizing a new decoder changed it");
      Recorders.Decode (Picture, Decoder, Events, Outcome);
      Assert (Decoding.Metadata_Count (Decoder) = 1, "the comment was not retained");
      Decoding.Finalize (Decoder);
      Decoding.Finalize (Decoder);
      Assert (Decoding.State (Decoder) = Decoding.Created, "a finalized decoder is not Created");
      Assert (Decoding.Metadata_Count (Decoder) = 0, "finalize kept metadata");
      Outcome := Decoding.Read_Header (Decoder);
      Assert (Outcome.First_Error.Code = Pictlib.Errors.Invalid_State, "a finalized decoder read a header");
   end Finalize_Is_Idempotent;

   procedure Source_Failure (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Decoder : Decoding.Decoder;
      Unopened : aliased Pictlib.Streams.Memory_Source;
      Stalled : aliased Pictlib.Streams.Memory_Source;
      Outcome : Pictlib.Results.Result;
   begin
      Decoding.Initialize (Decoder, Unopened'Access);
      Outcome := Decoding.Read_Header (Decoder);
      Assert (Outcome.First_Error.Code = Pictlib.Errors.Source_Read_Failed, "a source failure was not propagated");

      Pictlib.Streams.Open (Stalled, Picture'Access, Max_Transfer => 0);
      Decoding.Initialize (Decoder, Stalled'Access);
      Outcome := Decoding.Read_Header (Decoder);
      Assert (Outcome.First_Error.Code = Pictlib.Errors.Source_Zero_Progress, "a stalled source was not rejected");
   end Source_Failure;
end Pictlib_Testing.Test_Decoder;
