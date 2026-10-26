with Ada.Finalization;
with Pictlib.Geometry;
with Pictlib.Internal.Container;
with Pictlib.Internal.Failures;
with Pictlib.Internal.Opcode_Reader;
with Pictlib.Internal.Picture_Stream;
with Pictlib.Internal.Rendering;
with Pictlib.Internal.Sessions.Accounting;
with Pictlib.Internal.Sessions.Retained;
with Pictlib.Opcodes;

package body Pictlib.Decoding is
   package Accounting renames Pictlib.Internal.Sessions.Accounting;
   package Retained renames Pictlib.Internal.Sessions.Retained;
   use type Errors.Error_Code;
   use type Internal.Generation;

   --  Everything known about the last picture goes; the options and limits stay.
   procedure Discard_Picture (Object : in out Decoder) is
   begin
      Internal.Decoder_Core.Discard (Object.Inner);
      Object.First_Error := Errors.Make (Errors.No_Error);
   end Discard_Picture;

   procedure Bind (Object : in out Decoder; Input : not null access Streams.Source'Class) is
   begin
      --  First, so a source whose Offset raises below leaves no picture behind.
      Discard_Picture (Object);
      Internal.Sessions.Start
        (Object.Inner.Session, Input, Object.Decode_Options.Strictness, Object.Decode_Options.Retention);
      Object.Current_State := Ready;
      Object.Binds := Object.Binds + 1;
   exception
      --  The source's exception, from its Offset, passes through: the picture is gone and the decoder bound to
      --  nothing, Stopped until Reset or Initialize, and a call it was made under is told it was rebound.
      when others =>
         Object.Current_State := Stopped;
         Object.Binds := Object.Binds + 1;
         raise;
   end Bind;

   procedure Initialize
     (Object : in out Decoder;
      Input : not null access Streams.Source'Class;
      Decode_Options : Options := (others => <>);
      Decode_Limits : Limits.Limit_Set := Limits.Default_Limits) is
   begin
      Object.Decode_Options := Decode_Options;
      Internal.Sessions.Set_Budget (Object.Inner.Session, Decode_Limits);
      Bind (Object, Input);
   end Initialize;

   procedure Reset (Object : in out Decoder; Input : not null access Streams.Source'Class) is
   begin
      Bind (Object, Input);
   end Reset;

   function State (Object : Decoder) return Decoder_State is (Object.Current_State);

   function Wrong_State (Object : Decoder) return Results.Result is
     (Results.Failure
        (if Object.Current_State = Cancelled then Errors.Operation_Cancelled else Errors.Invalid_State));

   function Finish (Object : in out Decoder; Outcome : Results.Result) return Results.Result is
   begin
      if not Results.Succeeded (Outcome) then
         Object.First_Error := Outcome.First_Error;
         Object.Current_State := Failed;
      end if;
      return Outcome;
   end Finish;

   --  Guards a call that reads the picture: caller code it runs (a visitor, the source) may raise, or the task be
   --  aborted. However the call ends, Busy, when given, is cleared; a call that leaves the decoder in From,
   --  the state it began in, did not return, since every return moves it on, and leaves it Stopped, its stream
   --  partly read, until Reset or Initialize.
   --  A call whose caller code rebound the decoder (Binds moved) left it as that code chose.
   type Call_Guard
     (From : Decoder_State;
      State : not null access Decoder_State;
      Busy : not null access Boolean;
      Binds : not null access constant Internal.Generation) is new Ada.Finalization.Limited_Controlled with record
      Binds_At_Start : Internal.Generation := 0;
   end record;

   --  Caller code the guarded call ran rebound the decoder.
   function Rebound (Guard : Call_Guard'Class) return Boolean is (Guard.Binds.all /= Guard.Binds_At_Start);

   overriding procedure Initialize (Guard : in out Call_Guard);
   overriding procedure Finalize (Guard : in out Call_Guard);

   overriding procedure Initialize (Guard : in out Call_Guard) is
   begin
      Guard.Busy.all := True;
      Guard.Binds_At_Start := Guard.Binds.all;
   end Initialize;

   overriding procedure Finalize (Guard : in out Call_Guard) is
   begin
      Guard.Busy.all := False;
      if Guard.State.all = Guard.From and then not Rebound (Guard) then
         Guard.State.all := Stopped;
      end if;
   end Finalize;

   function Read_Header (Object : in out Decoder) return Results.Result is
   begin
      if Object.Busy then
         return Results.Failure (Errors.Invalid_State);
      elsif Object.Current_State /= Ready then
         return Wrong_State (Object);
      end if;
      declare
         Guard : Call_Guard (Ready, Object.Current_State'Access, Object.Busy'Access, Object.Binds'Access);
         Outcome : constant Results.Result :=
           Internal.Container.Read_Header
             (Object.Inner.Session, Object.Decode_Options.File_Header, Object.Inner.Info, Object.Inner.Header_Events,
              Object.Inner.Header_Event_Count);
      begin
         --  The source cancelled, reset or finalized the decoder under it: that stands.
         if Object.Current_State /= Ready or else Rebound (Guard) then
            return Wrong_State (Object);
         elsif Results.Succeeded (Outcome) then
            Object.Current_State := Header_Read;
         end if;
         return Finish (Object, Outcome);
      end;
   end Read_Header;

   function Header (Object : Decoder) return Pictures.Header_Info is (Object.Inner.Info);

   --  After the end opcode: by default the rest of the input is not read.
   function Check_Trailing_Data (Object : in out Decoder) return Results.Result is
      Step : Streams.Source_Result;
   begin
      if not Object.Decode_Options.Require_End_Of_Input then
         return Results.Success;
      end if;
      --  A trailing byte is not picture data: a picture that used its whole byte budget still has it found.
      --  The reader judges the source's reply, a stall included.
      Step := Internal.Picture_Stream.Probe_Past_End (Object.Inner.Session.Stream.all);
      if Errors.Is_Fatal (Step.Error) then
         return Results.Failure (Step.Error);
      elsif Step.Count = 0 then
         return Results.Success;
      end if;
      return Internal.Sessions.Reject_Or_Warn
        (Object.Inner.Session, Errors.Trailing_Data, Errors.Compatibility_Issue, Errors.Compatibility,
         (Source => Object.Inner.Session.Offset - 1, others => <>));
   end Check_Trailing_Data;

   --  How a picture goes on after an opcode.
   type Step_Kind is (More, Ended_By_End_Opcode, Ended_By_Input);

   --  Read the next opcode, rendering it when Paint is given. Input that ends at an opcode boundary is the
   --  missing end opcode: strictly a failure, otherwise a warning. Enumerate and Render share this.
   function Step
     (Object : in out Decoder;
      Event : out Pictures.Opcode_Event;
      Kind : out Step_Kind;
      Paint : access Internal.Rendering.Painter := null) return Results.Result
   is
      At_End : Boolean;
      Outcome : constant Results.Result := Internal.Opcode_Reader.Next (Object.Inner.Session, Event, At_End, Paint);
   begin
      Kind := More;
      if not Results.Succeeded (Outcome) then
         return Outcome;
      elsif At_End then
         Kind := Ended_By_Input;
         return Internal.Sessions.Reject_Or_Warn
           (Object.Inner.Session, Errors.Missing_End_Opcode, Errors.Compatibility_Issue, Errors.Compatibility,
            (Ordinal => Internal.Sessions.Opcodes_Read (Object.Inner.Session), others => <>));
      elsif Event.Op = Opcodes.End_Picture then
         Kind := Ended_By_End_Opcode;
      end if;
      return Results.Success;
   end Step;

   --  Enumerate while Busy is set. A visitor may cancel, reset or finalize the decoder: the state it leaves
   --  stands, and enumeration ends with what a call in that state gets.
   function Enumerate_Opcodes (Object : in out Decoder; Visitor : in out Opcode_Visitor'Class)
     return Results.Result
   is
      Action : Visit_Action;
   begin
      for Index in 1 .. Object.Inner.Header_Event_Count loop
         declare
            --  A copy: a visitor that resets or finalizes the decoder clears the header events.
            Event : constant Pictures.Opcode_Event := Object.Inner.Header_Events (Index);
         begin
            Action := Visitor.Visit (Event);
         end;
         if Object.Current_State /= Header_Read then
            return Wrong_State (Object);
         elsif Action = Stop then
            Object.Current_State := Stopped;
            return Results.Success;
         end if;
      end loop;

      loop
         declare
            Event : Pictures.Opcode_Event;
            Kind : Step_Kind;
            Outcome : constant Results.Result := Step (Object, Event, Kind);
         begin
            --  The source cancelled the decoder under it: that stands.
            if Object.Current_State /= Header_Read then
               return Wrong_State (Object);
            elsif not Results.Succeeded (Outcome) then
               return Finish (Object, Outcome);
            elsif Kind = Ended_By_Input then
               Object.Current_State := Finished;
               return Results.Success;
            end if;
            Action := Visitor.Visit (Event);
            if Object.Current_State /= Header_Read then
               return Wrong_State (Object);
            elsif Action = Stop and then Kind = More then
               Object.Current_State := Stopped;
               return Results.Success;
            elsif Kind = Ended_By_End_Opcode then
               declare
                  Trailing : constant Results.Result := Check_Trailing_Data (Object);
               begin
                  if Object.Current_State /= Header_Read then
                     return Wrong_State (Object);
                  elsif Results.Succeeded (Trailing) then
                     Object.Current_State := Finished;
                  end if;
                  return Finish (Object, Trailing);
               end;
            end if;
         end;
      end loop;
   end Enumerate_Opcodes;

   function Enumerate (Object : in out Decoder; Visitor : in out Opcode_Visitor'Class) return Results.Result is
   begin
      if Object.Busy then
         return Results.Failure (Errors.Invalid_State);
      elsif Object.Current_State /= Header_Read then
         return Wrong_State (Object);
      end if;
      declare
         Guard : Call_Guard (Header_Read, Object.Current_State'Access, Object.Busy'Access, Object.Binds'Access);
         pragma Unreferenced (Guard);
      begin
         return Enumerate_Opcodes (Object, Visitor);
      end;
   end Enumerate;

   --  Malformed picture data, after which what was drawn so far may stand as a partial picture: the
   --  specification's list, section 6. An unknown transfer mode is not there: it fails only strictly.
   function Is_Recoverable (Code : Errors.Error_Code) return Boolean is
     (Code in Errors.Source_Unexpected_End | Errors.Opcode_Invalid | Errors.Opcode_Length_Invalid
            | Errors.Region_Invalid | Errors.Polygon_Invalid | Errors.Pixmap_Invalid | Errors.PackBits_Invalid
            | Errors.Color_Table_Invalid | Errors.Pattern_Invalid | Errors.Embedded_Image_Failed);

   function Frame_Pixels (Object : Decoder) return Pixel_Count is
     (Pixel_Count (Geometry.Width (Object.Inner.Info.Frame)) * Pixel_Count (Geometry.Height (Object.Inner.Info.Frame)));

   --  The frame against the canvas limit: a frame over it no view can render.
   function Check_Frame (Object : Decoder) return Results.Result is
      Budget : Limits.Limit_Set renames Object.Inner.Session.Budget;
      Pixels : constant Pixel_Count := Frame_Pixels (Object);
   begin
      if Pixels > Budget.Max_Canvas_Pixels then
         return Internal.Failures.Over_Limit
           (Canvas_Pixel_Limit, Byte_Count (Budget.Max_Canvas_Pixels), Byte_Count (Pixels));
      end if;
      return Results.Success;
   end Check_Frame;

   --  The view against the frame and the output limit: a caller's mistake, which another view can correct.
   function Check_View (Object : Decoder; Output : Images.Mutable_Image_View) return Results.Result is
      Frame : constant Geometry.Rect := Object.Inner.Info.Frame;
      Budget : Limits.Limit_Set renames Object.Inner.Session.Budget;
      Pixels : constant Pixel_Count := Frame_Pixels (Object);
   begin
      if Integer (Output.Descriptor.Width) = Geometry.Width (Frame)
        and then Integer (Output.Descriptor.Height) = Geometry.Height (Frame)
        and then not Images.Is_Valid (Output)
      then
         --  The frame's size, but not a valid view: the least a valid view of its size and format holds, against
         --  what it holds.
         return Internal.Failures.Invalid_View (Output.Descriptor);
      elsif not Images.Is_Valid (Output)
        or else Integer (Output.Descriptor.Width) /= Geometry.Width (Frame)
        or else Integer (Output.Descriptor.Height) /= Geometry.Height (Frame)
      then
         return Results.Failure
           (Errors.Make
              (Errors.Invalid_Argument,
               (Expected => Byte_Count (Pixels),
                Actual => Byte_Count (Output.Descriptor.Width) * Byte_Count (Output.Descriptor.Height),
                others => <>)));
      elsif Output.Descriptor.Accessible_Bytes > Budget.Max_Output_Bytes then
         return Internal.Failures.Over_Limit
           (Output_Byte_Limit, Budget.Max_Output_Bytes, Output.Descriptor.Accessible_Bytes);
      end if;
      return Results.Success;
   end Check_View;

   function Render (Object : in out Decoder; Output : Images.Mutable_Image_View) return Results.Result is
   begin
      if Object.Busy then
         return Results.Failure (Errors.Invalid_State);
      elsif Object.Current_State /= Header_Read then
         return Wrong_State (Object);
      end if;
      --  The frame first: no view can render a frame over the canvas limit, so no view is worth correcting.
      declare
         Frame_Checked : constant Results.Result := Check_Frame (Object);
         View_Checked : constant Results.Result :=
           (if Results.Succeeded (Frame_Checked) then Check_View (Object, Output) else Results.Success);
      begin
         if not Results.Succeeded (Frame_Checked) then
            return Finish (Object, Frame_Checked);
         elsif not Results.Succeeded (View_Checked) then
            --  The picture is untouched and can still be rendered.
            return View_Checked;
         end if;
      end;

      declare
         --  Before the painter, so the painter is finalized first.
         Guard : Call_Guard (Header_Read, Object.Current_State'Access, Object.Busy'Access, Object.Binds'Access);
         pragma Unreferenced (Guard);
         Paint : aliased Internal.Rendering.Painter;
         Outcome : Results.Result := Results.Success;
      begin
         --  Each render has the whole drawing budget.
         Accounting.Start_Drawing (Object.Inner.Session);
         Internal.Rendering.Start
           (Paint, Output, Object.Inner.Info.Frame, Object.Decode_Options.Background, Object.Decode_Options.Fonts);
         loop
            declare
               Event : Pictures.Opcode_Event;
               Kind : Step_Kind;
            begin
               Outcome := Step (Object, Event, Kind, Paint'Access);
               --  The source cancelled the decoder under it: that stands.
               if Object.Current_State /= Header_Read then
                  return Wrong_State (Object);
               end if;
               exit when not Results.Succeeded (Outcome) or else Kind = Ended_By_Input;
               if Kind = Ended_By_End_Opcode then
                  Outcome := Check_Trailing_Data (Object);
                  if Object.Current_State /= Header_Read then
                     return Wrong_State (Object);
                  end if;
                  exit;
               end if;
            end;
         end loop;

         if not Results.Succeeded (Outcome)
           and then Object.Inner.Session.Strictness = Recover_When_Safe
           and then Is_Recoverable (Outcome.First_Error.Code)
         then
            Internal.Sessions.Warn
              (Object.Inner.Session, Errors.Partial_Picture, Errors.Data_Loss, Outcome.First_Error.Context);
            Outcome := Results.Success;
         end if;
         if Results.Succeeded (Outcome) then
            Object.Current_State := Finished;
         end if;
         return Finish (Object, Outcome);
      end;
   end Render;

   function Last_Error (Object : Decoder) return Errors.Error is (Object.First_Error);

   function Warning_Count (Object : Decoder) return Natural is
     (Internal.Sessions.Warning_Count (Object.Inner.Session));

   function Warning_At (Object : Decoder; Index : Positive) return Errors.Warning is
     (Internal.Sessions.Warning_At (Object.Inner.Session, Index));

   function Metadata_Count (Object : Decoder) return Natural is
     (Retained.Metadata_Count (Object.Inner.Session));

   function Metadata_Item (Object : Decoder; Index : Positive) return Metadata.Item_Info is
     (Retained.Metadata_Item (Object.Inner.Session, Index));

   function Copy_Metadata
     (Object : Decoder;
      Index : Positive;
      Buffer : out Streams.Byte_Array;
      Count : out Byte_Count) return Results.Result is
     (Retained.Copy_Metadata (Object.Inner.Session, Index, Buffer, Count));

   procedure Cancel (Object : in out Decoder) is
   begin
      if Object.Current_State in Ready | Header_Read then
         Object.Current_State := Cancelled;
      end if;
   end Cancel;

   procedure Finalize (Object : in out Decoder) is
   begin
      Internal.Sessions.Clear (Object.Inner.Session);
      Discard_Picture (Object);
      Object.Current_State := Created;
      Object.Binds := Object.Binds + 1;
   end Finalize;
end Pictlib.Decoding;
