with AUnit.Assertions;

with Pictlib;
with Pictlib.Decoding;
with Pictlib.Errors;
with Pictlib.Internal.Picture_Stream;
with Pictlib.Limits;
with Pictlib.Pictures;
with Pictlib.Results;
with Pictlib.Streams;
with Pictlib_Testing.Builders;
with Pictlib_Testing.Canvases;
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
   --  A reserved opcode whose data is skipped, longer than the reader's lookahead.
   Skipped : aliased constant Bytes :=
     V2_Prefix (0, 0, 4, 8) & W (16#8100#) & L (10_000) & Zeros (10_000) & W (16#00FF#);

   procedure Wrong_State_Calls (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Visitor_Stops (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Failure_Is_Terminal (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Cancellation (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Meddling_Visitors (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Reset_Reuses_The_Decoder (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Finalize_Is_Idempotent (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Source_Failure (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Overreporting_Source (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Source_Offsets (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  A source that delivers honestly but reports offsets from near the largest there is.
   type Far_Offset is limited new Pictlib.Streams.Source with record
      Inner : Pictlib.Streams.Memory_Source;
   end record;
   overriding function Read
     (Object : in out Far_Offset; Buffer : out Pictlib.Streams.Byte_Array) return Pictlib.Streams.Source_Result
   is (Object.Inner.Read (Buffer));
   overriding function Offset (Object : Far_Offset) return Pictlib.Source_Offset is
     (Pictlib."-" (Pictlib.Source_Offset'Last, 3));
   overriding function Skip
     (Object : in out Far_Offset; Count : Pictlib.Byte_Count) return Pictlib.Streams.Source_Result
   is (Object.Inner.Skip (Count));

   --  A source that delivers honestly but claims one byte more than it skipped, or with On_Read than it read.
   type Overreporting is limited new Pictlib.Streams.Source with record
      Inner : Pictlib.Streams.Memory_Source;
      On_Read : Boolean := False;
   end record;
   overriding function Read
     (Object : in out Overreporting; Buffer : out Pictlib.Streams.Byte_Array) return Pictlib.Streams.Source_Result;
   overriding function Offset (Object : Overreporting) return Pictlib.Source_Offset is (Object.Inner.Offset);
   overriding function Skip
     (Object : in out Overreporting; Count : Pictlib.Byte_Count) return Pictlib.Streams.Source_Result;

   --  What a meddling source does once it has delivered After bytes.
   type Source_Move is (Raises, Reenters, Cancels, Resets, Finalizes);

   --  A source that, once it has delivered After bytes, raises, or calls into or cancels Target.
   type Raising is limited new Pictlib.Streams.Source with record
      Inner : Pictlib.Streams.Memory_Source;
      After : Pictlib.Byte_Count := 0;
      Move : Source_Move := Raises;
      Target : access Decoding.Decoder;
      --  The source Resets rebinds Target to.
      Again : access Pictlib.Streams.Source'Class;
      Done : Boolean := False;
      Nested : Pictlib.Results.Result := Pictlib.Results.Success;
   end record;
   overriding function Read
     (Object : in out Raising; Buffer : out Pictlib.Streams.Byte_Array) return Pictlib.Streams.Source_Result;
   overriding function Offset (Object : Raising) return Pictlib.Source_Offset is (Object.Inner.Offset);
   overriding function Skip
     (Object : in out Raising; Count : Pictlib.Byte_Count) return Pictlib.Streams.Source_Result
   is (Object.Inner.Skip (Count));

   Source_Raised : exception;

   --  What a meddling visitor does to its decoder at its first opcode.
   type Meddle is (Cancels, Enumerates, Reads_Header, Renders, Resets, Resets_And_Reads_Header, Finalizes, Raises);

   Visitor_Failure : exception;

   --  A visitor that, at one opcode, calls into the decoder it is visiting.
   type Meddling is new Decoding.Opcode_Visitor with record
      Target : access Decoding.Decoder;
      Move : Meddle := Cancels;
      --  The visit Move is made at: 1 and 2 are Picture's version opcode and HeaderOp, 3 its first opcode after.
      At_Visit : Positive := 1;
      --  The source Resets rebinds.
      Input : access Pictlib.Streams.Source'Class;
      Visits : Natural := 0;
      --  The result of the call Move makes, when it returns one.
      Nested : Pictlib.Results.Result := Pictlib.Results.Success;
   end record;
   overriding function Visit (Object : in out Meddling; Event : Pictlib.Pictures.Opcode_Event)
     return Decoding.Visit_Action;

   overriding function Visit (Object : in out Meddling; Event : Pictlib.Pictures.Opcode_Event)
     return Decoding.Visit_Action
   is
      pragma Unreferenced (Event);
      Inner : Recorders.Null_Visitor;
      Storage : aliased Bytes := [1 .. 3 * 8 * 4 => 0];
   begin
      Object.Visits := Object.Visits + 1;
      if Object.Visits = Object.At_Visit then
         case Object.Move is
            when Cancels => Decoding.Cancel (Object.Target.all);
            when Enumerates => Object.Nested := Decoding.Enumerate (Object.Target.all, Inner);
            when Reads_Header => Object.Nested := Decoding.Read_Header (Object.Target.all);
            when Renders =>
               Object.Nested := Decoding.Render (Object.Target.all, Canvases.View (Storage'Access, 8, 4));
            when Resets => Decoding.Reset (Object.Target.all, Object.Input);
            when Resets_And_Reads_Header =>
               Decoding.Reset (Object.Target.all, Object.Input);
               Object.Nested := Decoding.Read_Header (Object.Target.all);
            when Finalizes => Decoding.Finalize (Object.Target.all);
            when Raises => raise Visitor_Failure;
         end case;
      end if;
      return Decoding.Continue;
   end Visit;

   overriding function Skip
     (Object : in out Overreporting; Count : Pictlib.Byte_Count) return Pictlib.Streams.Source_Result
   is
      use type Pictlib.Byte_Count;
      Step : constant Pictlib.Streams.Source_Result := Object.Inner.Skip (Count);
   begin
      return (Step with delta Count => Step.Count + (if Object.On_Read then 0 else 1));
   end Skip;

   overriding function Read
     (Object : in out Raising; Buffer : out Pictlib.Streams.Byte_Array) return Pictlib.Streams.Source_Result
   is
      use type Pictlib.Byte_Count;
   begin
      if Pictlib.Byte_Count (Object.Inner.Offset) >= Object.After and then not Object.Done then
         case Object.Move is
            when Raises => raise Source_Raised;
            when Reenters =>
               Object.Done := True;
               Object.Nested := Decoding.Read_Header (Object.Target.all);
            when Cancels =>
               Object.Done := True;
               Decoding.Cancel (Object.Target.all);
            when Resets =>
               Object.Done := True;
               Decoding.Reset (Object.Target.all, Object.Again);
            when Finalizes =>
               Object.Done := True;
               Decoding.Finalize (Object.Target.all);
         end case;
      end if;
      return Object.Inner.Read (Buffer);
   end Read;

   overriding function Read
     (Object : in out Overreporting; Buffer : out Pictlib.Streams.Byte_Array) return Pictlib.Streams.Source_Result
   is
      use type Pictlib.Byte_Count;
      Step : constant Pictlib.Streams.Source_Result := Object.Inner.Read (Buffer);
   begin
      return (Step with delta Count => Step.Count + (if Object.On_Read then 1 else 0));
   end Read;

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
      Register_Routine (T, Meddling_Visitors'Access, "decoder.state.meddling_visitors");
      Register_Routine (T, Reset_Reuses_The_Decoder'Access, "decoder.state.reset_reuse");
      Register_Routine (T, Finalize_Is_Idempotent'Access, "decoder.state.finalize");
      Register_Routine (T, Source_Failure'Access, "decoder.source_failure");
      Register_Routine (T, Overreporting_Source'Access, "decoder.source_overreports");
      Register_Routine (T, Source_Offsets'Access, "decoder.source_offsets");
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

      --  Cancelled from inside a visit: enumeration stops there, and the decoder stays cancelled.
      declare
         Inside : aliased Decoding.Decoder;
         Canceller : Meddling := (Target => Inside'Unchecked_Access, others => <>);
         Storage : aliased Bytes := [1 .. 3 * 8 * 4 => 0];
      begin
         Pictlib.Streams.Open (Source, Picture'Access);
         Decoding.Initialize (Inside, Source'Access);
         Outcome := Decoding.Read_Header (Inside);
         Assert (Pictlib.Results.Succeeded (Outcome), "the header was not read");
         Outcome := Decoding.Enumerate (Inside, Canceller);
         Assert (Outcome.First_Error.Code = Pictlib.Errors.Operation_Cancelled and then Canceller.Visits = 1
                 and then Decoding.State (Inside) = Decoding.Cancelled,
                 "a decoder cancelled by its visitor read on, or forgot it was cancelled");
         Outcome := Decoding.Render (Inside, Canvases.View (Storage'Access, 8, 4));
         Assert (Outcome.First_Error.Code = Pictlib.Errors.Operation_Cancelled,
                 "a decoder cancelled by its visitor rendered");
      end;
      --  Enumerating again from inside a visit is refused; the outer enumeration goes on to the end.
      declare
         Inside : aliased Decoding.Decoder;
         Reenterer : Meddling := (Target => Inside'Unchecked_Access, Move => Enumerates, others => <>);
      begin
         Pictlib.Streams.Open (Source, Picture'Access);
         Decoding.Initialize (Inside, Source'Access);
         Outcome := Decoding.Read_Header (Inside);
         Assert (Pictlib.Results.Succeeded (Outcome), "the header was not read");
         Outcome := Decoding.Enumerate (Inside, Reenterer);
         Assert (Reenterer.Nested.First_Error.Code = Pictlib.Errors.Invalid_State,
                 "a visitor enumerated its decoder again");
         Assert (Pictlib.Results.Succeeded (Outcome) and then Decoding.State (Inside) = Decoding.Finished,
                 "a refused nested enumeration disturbed the outer one");
      end;
   end Cancellation;

   --  At a header event and at an opcode after it: a visitor's nested Read_Header, Enumerate and Render are
   --  refused; one that resets or finalizes its decoder ends the enumeration in the state it left, and a reset
   --  decoder reads no header under its visitor; one that raises leaves the decoder Stopped until Reset.
   procedure Meddling_Visitors (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Source : aliased Pictlib.Streams.Memory_Source;
      Again : aliased Pictlib.Streams.Memory_Source;
      Outcome : Pictlib.Results.Result;
      Storage : aliased Bytes := [1 .. 3 * 8 * 4 => 0];

      procedure Start (Inside : in out Decoding.Decoder) is
      begin
         Pictlib.Streams.Open (Source, Picture'Access);
         Pictlib.Streams.Open (Again, Other'Access);
         Decoding.Initialize (Inside, Source'Access);
         Outcome := Decoding.Read_Header (Inside);
         Assert (Pictlib.Results.Succeeded (Outcome), "the header was not read");
      end Start;
   begin
      for At_Visit in 1 .. 3 loop
         declare
            Where : constant String := " at visit" & At_Visit'Image;
         begin
            for Move in Enumerates .. Renders loop
               declare
                  Inside : aliased Decoding.Decoder;
                  Visitor : Meddling :=
                    (Target => Inside'Unchecked_Access, Move => Move, At_Visit => At_Visit, others => <>);
               begin
                  Start (Inside);
                  Outcome := Decoding.Enumerate (Inside, Visitor);
                  Assert (Visitor.Nested.First_Error.Code = Pictlib.Errors.Invalid_State,
                          "a visitor's nested " & Move'Image & " was not refused" & Where);
                  Assert (Pictlib.Results.Succeeded (Outcome) and then Decoding.State (Inside) = Decoding.Finished,
                          "a refused nested " & Move'Image & " disturbed the enumeration" & Where);
               end;
            end loop;

            for Move in Meddle range Resets .. Finalizes loop
               declare
                  Inside : aliased Decoding.Decoder;
                  Visitor : Meddling :=
                    (Target => Inside'Unchecked_Access, Move => Move, At_Visit => At_Visit,
                     Input => Again'Unchecked_Access, others => <>);
               begin
                  Start (Inside);
                  Outcome := Decoding.Enumerate (Inside, Visitor);
                  Assert (Outcome.First_Error.Code = Pictlib.Errors.Invalid_State and then Visitor.Visits = At_Visit,
                          "a decoder its visitor ran " & Move'Image & " on read on" & Where);
                  Assert (Decoding.State (Inside) = (if Move = Finalizes then Decoding.Created else Decoding.Ready),
                          "the state " & Move'Image & " left did not stand" & Where);
                  if Move = Resets_And_Reads_Header then
                     Assert (Visitor.Nested.First_Error.Code = Pictlib.Errors.Invalid_State,
                             "a decoder reset by its visitor read a header under it" & Where);
                  end if;
                  if Move /= Finalizes then
                     --  The source the visitor bound, Other, a version 1 picture.
                     Outcome := Decoding.Read_Header (Inside);
                     Assert (Pictlib.Results.Succeeded (Outcome)
                             and then Decoding.Header (Inside).Version = Pictlib.Version_1,
                             "a decoder reset by its visitor did not read the new source" & Where);
                     Outcome := Decoding.Enumerate (Inside, Visitor);
                     Assert (Pictlib.Results.Succeeded (Outcome) and then Decoding.State (Inside) = Decoding.Finished,
                             "a decoder reset by its visitor did not enumerate the new source" & Where);
                  end if;
               end;
            end loop;

            declare
               Inside : aliased Decoding.Decoder;
               Visitor : Meddling :=
                 (Target => Inside'Unchecked_Access, Move => Raises, At_Visit => At_Visit, others => <>);
               Events : Recorders.Recorder;
               Raised : Boolean := False;
            begin
               Start (Inside);
               begin
                  Outcome := Decoding.Enumerate (Inside, Visitor);
               exception
                  when Visitor_Failure => Raised := True;
               end;
               Assert (Raised, "a visitor's exception did not propagate" & Where);
               Assert (Decoding.State (Inside) = Decoding.Stopped,
                       "a decoder whose visitor raised was not stopped" & Where);
               Outcome := Decoding.Render (Inside, Canvases.View (Storage'Access, 8, 4));
               Assert (Outcome.First_Error.Code = Pictlib.Errors.Invalid_State,
                       "a decoder whose visitor raised rendered the rest of its stream" & Where);
               Outcome := Decoding.Enumerate (Inside, Events);
               Assert (Outcome.First_Error.Code = Pictlib.Errors.Invalid_State,
                       "a decoder whose visitor raised enumerated the rest of its stream" & Where);
               Pictlib.Streams.Open (Source, Picture'Access);
               Decoding.Reset (Inside, Source'Access);
               Outcome := Decoding.Read_Header (Inside);
               Assert (Pictlib.Results.Succeeded (Outcome),
                       "a decoder whose visitor raised read no header after Reset" & Where);
               Outcome := Decoding.Enumerate (Inside, Events);
               Assert (Pictlib.Results.Succeeded (Outcome) and then Events.Count > 0,
                       "a decoder whose visitor raised did not enumerate after Reset" & Where);
            end;
         end;
      end loop;

      --  A source that raises: in Read_Header, and in Render once the header is read. The exception propagates
      --  and leaves the decoder Stopped, refusing the rest of a stream it read part of, until Reset.
      for In_Render in Boolean loop
         declare
            Inside : aliased Decoding.Decoder;
            Faulty : aliased Raising;
            Raised : Boolean := False;
            Storage : aliased Bytes := [1 .. 3 * 8 * 4 => 0];
         begin
            Pictlib.Streams.Open (Faulty.Inner, Skipped'Access);
            --  In Render: past the header, which the look-ahead reads at once, so Render's next read raises.
            Faulty.After := (if In_Render then 528 else 0);
            Decoding.Initialize (Inside, Faulty'Access);
            begin
               Outcome := Decoding.Read_Header (Inside);
               if In_Render then
                  Assert (Pictlib.Results.Succeeded (Outcome), "the header was not read");
                  Outcome := Decoding.Render (Inside, Canvases.View (Storage'Access, 8, 4));
               end if;
            exception
               when Source_Raised => Raised := True;
            end;
            Assert (Raised, "a source's exception did not propagate, in Render: " & In_Render'Image);
            Assert (Decoding.State (Inside) = Decoding.Stopped,
                    "a decoder whose source raised was left " & Decoding.State (Inside)'Image);
            Outcome := Decoding.Render (Inside, Canvases.View (Storage'Access, 8, 4));
            Assert (Outcome.First_Error.Code = Pictlib.Errors.Invalid_State,
                    "a decoder whose source raised rendered the rest of its stream");
            Pictlib.Streams.Open (Source, Picture'Access);
            Decoding.Reset (Inside, Source'Access);
            Outcome := Decoding.Read_Header (Inside);
            Assert (Pictlib.Results.Succeeded (Outcome), "a decoder whose source raised read no header after Reset");
         end;
      end loop;

      --  A source that resets or finalizes its decoder mid-read leaves it as it chose, in Read_Header and in Render:
      --  what it read for the old binding is dropped, and a reset decoder reads its new source from the start.
      for Move in Source_Move range Resets .. Finalizes loop
         for In_Render in Boolean loop
            declare
               Inside : aliased Decoding.Decoder;
               Faulty : aliased Raising;
               Fresh : aliased Pictlib.Streams.Memory_Source;
               Storage : aliased Bytes := [1 .. 3 * 8 * 4 => 0];
               Where : constant String := Move'Image & (if In_Render then " in Render" else " in Read_Header");
            begin
               Pictlib.Streams.Open (Faulty.Inner, Skipped'Access);
               Pictlib.Streams.Open (Fresh, Other'Access);
               Faulty.After := (if In_Render then 528 else 0);
               Faulty.Move := Move;
               Faulty.Target := Inside'Unchecked_Access;
               Faulty.Again := Fresh'Unchecked_Access;
               Decoding.Initialize (Inside, Faulty'Access);
               Outcome := Decoding.Read_Header (Inside);
               if In_Render then
                  Assert (Pictlib.Results.Succeeded (Outcome), "the header was not read, " & Where);
                  Outcome := Decoding.Render (Inside, Canvases.View (Storage'Access, 8, 4));
               end if;
               Assert (Outcome.First_Error.Code = Pictlib.Errors.Invalid_State
                       and then Decoding.State (Inside)
                                = (if Move = Resets then Decoding.Ready else Decoding.Created),
                       "a source's " & Where & " did not stand: " & Decoding.State (Inside)'Image);
               if Move = Resets then
                  Outcome := Decoding.Read_Header (Inside);
                  Assert (Pictlib.Results.Succeeded (Outcome)
                          and then Decoding.Header (Inside).Version = Pictlib.Version_1,
                          "a decoder its source reset did not read the new source, " & Where);
               end if;
            end;
         end loop;
      end loop;

      --  A source that calls into its decoder is refused; one that cancels it mid-render leaves it cancelled.
      for Move in Reenters .. Cancels loop
         declare
            Inside : aliased Decoding.Decoder;
            Faulty : aliased Raising;
            Storage : aliased Bytes := [1 .. 3 * 8 * 4 => 0];
         begin
            Pictlib.Streams.Open (Faulty.Inner, Skipped'Access);
            Faulty.After := 528;
            Faulty.Move := Move;
            Faulty.Target := Inside'Unchecked_Access;
            Decoding.Initialize (Inside, Faulty'Access);
            Outcome := Decoding.Read_Header (Inside);
            Assert (Pictlib.Results.Succeeded (Outcome), "the header was not read");
            Outcome := Decoding.Render (Inside, Canvases.View (Storage'Access, 8, 4));
            if Move = Reenters then
               Assert (Faulty.Nested.First_Error.Code = Pictlib.Errors.Invalid_State,
                       "a source called into the decoder rendering through it");
            else
               Assert (Outcome.First_Error.Code = Pictlib.Errors.Operation_Cancelled
                       and then Decoding.State (Inside) = Decoding.Cancelled,
                       "a source's Cancel mid-render was overwritten: " & Decoding.State (Inside)'Image);
            end if;
         end;
      end loop;
   end Meddling_Visitors;

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

   procedure Overreporting_Source (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Source : aliased Overreporting;
      Decoder : Decoding.Decoder;
      Visitor : Recorders.Null_Visitor;
      Outcome : Pictlib.Results.Result;
   begin
      Pictlib.Streams.Open (Source.Inner, Skipped'Access);
      --  The picture byte budget ends inside the skipped data, so the reader asks the source for less than the
      --  opcode's length and the extra byte claimed still lies within that length.
      Decoding.Initialize
        (Decoder, Source'Access,
         Decode_Limits => (Pictlib.Limits.Default_Limits with delta Max_Picture_Bytes => 5_000));
      Outcome := Decoding.Read_Header (Decoder);
      Assert (Pictlib.Results.Succeeded (Outcome), "the header did not read");
      Outcome := Decoding.Enumerate (Decoder, Visitor);
      Assert (Outcome.First_Error.Code = Pictlib.Errors.Internal_Invariant_Failed,
              "a source claiming more than it skipped was trusted: " & Outcome.First_Error.Code'Image);

      --  One claiming more than it read: a claim within the request cannot be told from the truth, but the first
      --  read it fills claims more than was asked.
      declare
         Reader : aliased Overreporting;
         Other_Decoder : Decoding.Decoder;
      begin
         Reader.On_Read := True;
         Pictlib.Streams.Open (Reader.Inner, Skipped'Access);
         Decoding.Initialize (Other_Decoder, Reader'Access);
         Outcome := Decoding.Read_Header (Other_Decoder);
         if Pictlib.Results.Succeeded (Outcome) then
            Outcome := Decoding.Enumerate (Other_Decoder, Visitor);
         end if;
         Assert (Outcome.First_Error.Code = Pictlib.Errors.Internal_Invariant_Failed
                 and then Decoding.State (Other_Decoder) = Decoding.Failed,
                 "a source claiming more than it read was trusted: " & Outcome.First_Error.Code'Image);
      end;
   end Overreporting_Source;

   procedure Source_Offsets (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      use type Pictlib.Byte_Count;
      use type Pictlib.Source_Offset;
      Far : aliased Far_Offset;
      Decoder : Decoding.Decoder;
      Visitor : Recorders.Null_Visitor;
      Outcome : Pictlib.Results.Result;
   begin
      --  Offsets past the largest a source can report saturate instead of overflowing.
      Pictlib.Streams.Open (Far.Inner, Broken'Access);
      Decoding.Initialize (Decoder, Far'Access);
      Outcome := Decoding.Read_Header (Decoder);
      if Pictlib.Results.Succeeded (Outcome) then
         Outcome := Decoding.Enumerate (Decoder, Visitor);
      end if;
      Assert (not Pictlib.Results.Succeeded (Outcome)
              and then Outcome.First_Error.Context.Source = Pictlib.Source_Offset'Last,
              "a failure past the largest offset did not saturate: " & Outcome.First_Error.Code'Image);

      --  The reader defines only the bytes it delivers: what a short read leaves is the caller's, untouched.
      declare
         Source : aliased Pictlib.Streams.Memory_Source;
         Reader : Pictlib.Internal.Picture_Stream.Reader;
         Buffer : Bytes (1 .. 10) := [others => 16#EE#];
         Step : Pictlib.Streams.Source_Result;
      begin
         Pictlib.Streams.Open (Source, Picture'Access, Max_Transfer => 2);
         Pictlib.Internal.Picture_Stream.Bind (Reader, Source'Access, Max_Bytes => 1_000);
         Step := Reader.Read (Buffer);
         Assert (Step.Count = 2 and then Buffer (3 .. 10) = [3 .. 10 => 16#EE#],
                 "a short read cleared the bytes it did not deliver");
      end;
   end Source_Offsets;
end Pictlib_Testing.Test_Decoder;
