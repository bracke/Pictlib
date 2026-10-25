with Pictlib.Internal.Container;
with Pictlib.Internal.Sessions;
with Pictlib.Internal.Failures;
with Pictlib.Internal.Opcode_Reader;
with Pictlib.Geometry;
with Pictlib.Internal.Picture_Stream;
with Pictlib.Internal.Rendering;
with Pictlib.Opcodes;

package body Pictlib.Decoding is
   use type Errors.Error_Code;

   --  Everything known about the last picture goes; the options and limits stay.
   procedure Discard_Picture (Object : in out Decoder) is
   begin
      Object.Inner.Info := (others => <>);
      Object.Inner.Header_Events := [others => (others => <>)];
      Object.Inner.Header_Event_Count := 0;
      Object.First_Error := Errors.Make (Errors.No_Error);
   end Discard_Picture;

   procedure Bind (Object : in out Decoder; Input : not null access Streams.Source'Class) is
   begin
      Internal.Sessions.Start
        (Object.Inner.Session, Input, Object.Decode_Options.Strictness, Object.Decode_Options.Retention);
      Discard_Picture (Object);
      Object.Current_State := Ready;
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

   function Read_Header (Object : in out Decoder) return Results.Result is
   begin
      if Object.Visiting then
         return Results.Failure (Errors.Invalid_State);
      elsif Object.Current_State /= Ready then
         return Wrong_State (Object);
      end if;
      declare
         Outcome : constant Results.Result :=
           Internal.Container.Read_Header
             (Object.Inner.Session, Object.Decode_Options.File_Header, Object.Inner.Info, Object.Inner.Header_Events,
              Object.Inner.Header_Event_Count);
      begin
         if Results.Succeeded (Outcome) then
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

   --  Enumerate while Visiting is set. A visitor may cancel, reset or finalize the decoder: the state it leaves
   --  stands, and enumeration ends with what a call in that state gets.
   function Enumerate_Opcodes (Object : in out Decoder; Visitor : in out Opcode_Visitor'Class)
     return Results.Result
   is
      Action : Visit_Action;
   begin
      for Index in 1 .. Object.Inner.Header_Event_Count loop
         Action := Visitor.Visit (Object.Inner.Header_Events (Index));
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
            if not Results.Succeeded (Outcome) then
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
                  if Results.Succeeded (Trailing) then
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
      if Object.Visiting then
         return Results.Failure (Errors.Invalid_State);
      elsif Object.Current_State /= Header_Read then
         return Wrong_State (Object);
      end if;
      Object.Visiting := True;
      declare
         Outcome : constant Results.Result := Enumerate_Opcodes (Object, Visitor);
      begin
         Object.Visiting := False;
         return Outcome;
      end;
   exception
      --  A visitor's exception is the caller's: it propagates, but leaves the decoder usable.
      when others =>
         Object.Visiting := False;
         raise;
   end Enumerate;

   --  Malformed picture data, after which what was drawn so far may stand as a partial picture.
   function Is_Recoverable (Code : Errors.Error_Code) return Boolean is
     (Code in Errors.Source_Unexpected_End | Errors.Opcode_Invalid | Errors.Opcode_Length_Invalid
            | Errors.Region_Invalid | Errors.Polygon_Invalid | Errors.Pixmap_Invalid | Errors.PackBits_Invalid
            | Errors.Color_Table_Invalid | Errors.Pattern_Invalid | Errors.Transfer_Mode_Invalid
            | Errors.Embedded_Image_Failed);

   function Check_View (Object : Decoder; Output : Images.Mutable_Image_View) return Results.Result is
      Frame : constant Geometry.Rect := Object.Inner.Info.Frame;
      Budget : Limits.Limit_Set renames Object.Inner.Session.Budget;
      Pixels : constant Pixel_Count :=
        Pixel_Count (Geometry.Width (Frame)) * Pixel_Count (Geometry.Height (Frame));
   begin
      --  The frame first: no view can render a frame over the canvas limit, so no view is worth correcting.
      if Pixels > Budget.Max_Canvas_Pixels then
         return Internal.Failures.Over_Limit
           (Canvas_Pixel_Limit, Byte_Count (Budget.Max_Canvas_Pixels), Byte_Count (Pixels));
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
      if Object.Visiting then
         return Results.Failure (Errors.Invalid_State);
      elsif Object.Current_State /= Header_Read then
         return Wrong_State (Object);
      end if;
      declare
         Checked : constant Results.Result := Check_View (Object, Output);
      begin
         if not Results.Succeeded (Checked) and then Checked.First_Error.Context.Limit = Canvas_Pixel_Limit then
            --  The frame, not the view, is over the limit: no view can render this picture.
            return Finish (Object, Checked);
         elsif not Results.Succeeded (Checked) then
            --  A bad view is the caller's mistake: the picture is untouched and can still be rendered.
            return Checked;
         end if;
      end;

      declare
         Paint : aliased Internal.Rendering.Painter;
         Outcome : Results.Result := Results.Success;
      begin
         --  Each render has the whole drawing budget.
         Internal.Sessions.Start_Drawing (Object.Inner.Session);
         Internal.Rendering.Start
           (Paint, Output, Object.Inner.Info.Frame, Object.Decode_Options.Background, Object.Decode_Options.Fonts);
         loop
            declare
               Event : Pictures.Opcode_Event;
               Kind : Step_Kind;
            begin
               Outcome := Step (Object, Event, Kind, Paint'Access);
               exit when not Results.Succeeded (Outcome) or else Kind = Ended_By_Input;
               if Kind = Ended_By_End_Opcode then
                  Outcome := Check_Trailing_Data (Object);
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
     (Internal.Sessions.Metadata_Count (Object.Inner.Session));

   function Metadata_Item (Object : Decoder; Index : Positive) return Metadata.Item_Info is
     (Internal.Sessions.Metadata_Item (Object.Inner.Session, Index));

   function Copy_Metadata
     (Object : Decoder;
      Index : Positive;
      Buffer : out Streams.Byte_Array;
      Count : out Byte_Count) return Results.Result is
     (Internal.Sessions.Copy_Metadata (Object.Inner.Session, Index, Buffer, Count));

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
   end Finalize;
end Pictlib.Decoding;
