with Pictlib.Internal.Diagnostics;
with Pictlib.Internal.Opcode_Reader;
with Pictlib.Internal.Metadata_Store;
with Pictlib.Geometry;
with Pictlib.Internal.Picture_Stream;
with Pictlib.Internal.Rendering;
with Pictlib.Opcodes;

package body Pictlib.Decoding is
   use type Errors.Error_Code;

   procedure Bind (Object : in out Decoder; Input : not null access Streams.Source'Class) is
   begin
      Internal.Sessions.Clear (Object.Session);
      Internal.Picture_Stream.Bind (Object.Session.Stream, Input, Object.Session.Budget.Max_Picture_Bytes);
      Object.Session.Strictness := Object.Decode_Options.Strictness;
      Object.Session.Retention := Object.Decode_Options.Retention;
      Object.Info := (others => <>);
      Object.Header_Events := [others => (others => <>)];
      Object.Header_Event_Count := 0;
      Object.First_Error := Errors.Make (Errors.No_Error);
      Object.Current_State := Ready;
   end Bind;

   procedure Initialize
     (Object : in out Decoder;
      Input : not null access Streams.Source'Class;
      Decode_Options : Options := (others => <>);
      Decode_Limits : Limits.Limit_Set := Limits.Default_Limits) is
   begin
      Object.Decode_Options := Decode_Options;
      Object.Session.Budget := Decode_Limits;
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
      if Object.Current_State /= Ready then
         return Wrong_State (Object);
      end if;
      declare
         Outcome : constant Results.Result :=
           Internal.Container.Read_Header
             (Object.Session, Object.Decode_Options.File_Header, Object.Info, Object.Header_Events,
              Object.Header_Event_Count);
      begin
         if Results.Succeeded (Outcome) then
            Object.Current_State := Header_Read;
         end if;
         return Finish (Object, Outcome);
      end;
   end Read_Header;

   function Header (Object : Decoder) return Pictures.Header_Info is (Object.Info);

   --  After the end opcode: by default the rest of the input is not read.
   function Check_Trailing_Data (Object : in out Decoder) return Results.Result is
      Probe : Streams.Byte_Array (1 .. 1);
      Step : Streams.Source_Result;
   begin
      if not Object.Decode_Options.Require_End_Of_Input then
         return Results.Success;
      end if;
      Step := Object.Session.Stream.Read (Probe);
      if Errors.Is_Fatal (Step.Error) then
         return Results.Failure (Step.Error);
      elsif Step.Count = 0 and then not Step.End_Of_Input then
         return Results.Failure
           (Errors.Make (Errors.Source_Zero_Progress, (Source => Object.Session.Stream.Offset, others => <>)));
      elsif Step.Count = 0 then
         return Results.Success;
      elsif not Internal.Sessions.Is_Lenient (Object.Session) then
         return Results.Failure
           (Errors.Make (Errors.Trailing_Data, (Source => Object.Session.Stream.Offset - 1, others => <>)));
      end if;
      Internal.Sessions.Warn
        (Object.Session, Errors.Compatibility_Issue, Errors.Compatibility,
         (Source => Object.Session.Stream.Offset - 1, others => <>));
      return Results.Success;
   end Check_Trailing_Data;

   function Enumerate (Object : in out Decoder; Visitor : in out Opcode_Visitor'Class) return Results.Result is
   begin
      if Object.Current_State /= Header_Read then
         return Wrong_State (Object);
      end if;

      for Index in 1 .. Object.Header_Event_Count loop
         if Visitor.Visit (Object.Header_Events (Index)) = Stop then
            Object.Current_State := Stopped;
            return Results.Success;
         end if;
      end loop;

      loop
         declare
            Event : Pictures.Opcode_Event;
            At_End : Boolean;
            Outcome : constant Results.Result := Internal.Opcode_Reader.Next (Object.Session, Event, At_End);
         begin
            if not Results.Succeeded (Outcome) then
               return Finish (Object, Outcome);
            elsif At_End then
               if not Internal.Sessions.Is_Lenient (Object.Session) then
                  return Finish
                    (Object,
                     Results.Failure
                       (Errors.Make
                          (Errors.Missing_End_Opcode,
                           (Source => Object.Session.Stream.Offset,
                            Ordinal => Object.Session.Next_Ordinal,
                            others => <>))));
               end if;
               Internal.Sessions.Warn
                 (Object.Session, Errors.Compatibility_Issue, Errors.Compatibility,
                  (Ordinal => Object.Session.Next_Ordinal, others => <>));
               Object.Current_State := Finished;
               return Results.Success;
            end if;

            if Visitor.Visit (Event) = Stop and then Event.Op /= Opcodes.End_Picture then
               Object.Current_State := Stopped;
               return Results.Success;
            elsif Event.Op = Opcodes.End_Picture then
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
   end Enumerate;

   --  Malformed picture data, after which what was drawn so far may stand as a partial picture.
   function Is_Recoverable (Code : Errors.Error_Code) return Boolean is
     (Code in Errors.Source_Unexpected_End | Errors.Opcode_Invalid | Errors.Opcode_Length_Invalid
            | Errors.Region_Invalid | Errors.Polygon_Invalid | Errors.Pixmap_Invalid | Errors.PackBits_Invalid
            | Errors.Color_Table_Invalid | Errors.Pattern_Invalid | Errors.Transfer_Mode_Invalid
            | Errors.Missing_End_Opcode | Errors.Embedded_Image_Failed);

   function Check_View (Object : Decoder; Output : Images.Mutable_Image_View) return Results.Result is
      Frame : constant Geometry.Rect := Object.Info.Frame;
      Budget : Limits.Limit_Set renames Object.Session.Budget;
      Pixels : constant Pixel_Count :=
        Pixel_Count (Geometry.Width (Frame)) * Pixel_Count (Geometry.Height (Frame));
   begin
      if not Images.Is_Valid (Output)
        or else Integer (Output.Descriptor.Width) /= Geometry.Width (Frame)
        or else Integer (Output.Descriptor.Height) /= Geometry.Height (Frame)
      then
         return Results.Failure
           (Errors.Make
              (Errors.Invalid_Argument,
               (Expected => Byte_Count (Pixels),
                Actual => Byte_Count (Output.Descriptor.Width) * Byte_Count (Output.Descriptor.Height),
                others => <>)));
      elsif Pixels > Budget.Max_Canvas_Pixels then
         return Results.Failure
           (Errors.Make
              (Errors.Limit_Exceeded,
               (Expected => Byte_Count (Budget.Max_Canvas_Pixels), Actual => Byte_Count (Pixels),
                Limit => Canvas_Pixel_Limit, others => <>)));
      elsif Output.Descriptor.Accessible_Bytes > Budget.Max_Output_Bytes then
         return Results.Failure
           (Errors.Make
              (Errors.Limit_Exceeded,
               (Expected => Budget.Max_Output_Bytes, Actual => Output.Descriptor.Accessible_Bytes,
                Limit => Output_Byte_Limit, others => <>)));
      end if;
      return Results.Success;
   end Check_View;

   function Render (Object : in out Decoder; Output : Images.Mutable_Image_View) return Results.Result is
   begin
      if Object.Current_State /= Header_Read then
         return Wrong_State (Object);
      end if;
      declare
         Checked : constant Results.Result := Check_View (Object, Output);
      begin
         if not Results.Succeeded (Checked) then
            --  A bad view is the caller's mistake: the picture is untouched and can still be rendered.
            return Checked;
         end if;
      end;

      declare
         Paint : aliased Internal.Rendering.Painter;
         Outcome : Results.Result := Results.Success;
      begin
         Internal.Rendering.Start
           (Paint, Output, Object.Info.Frame, Object.Decode_Options.Background, Object.Decode_Options.Fonts);
         loop
            declare
               Event : Pictures.Opcode_Event;
               At_End : Boolean;
            begin
               Outcome := Internal.Opcode_Reader.Next (Object.Session, Event, At_End, Paint'Access);
               if Results.Succeeded (Outcome) and then At_End then
                  if not Internal.Sessions.Is_Lenient (Object.Session) then
                     Outcome := Results.Failure
                       (Errors.Make
                          (Errors.Missing_End_Opcode,
                           (Source => Object.Session.Stream.Offset, Ordinal => Object.Session.Next_Ordinal,
                            others => <>)));
                  else
                     Internal.Sessions.Warn (Object.Session, Errors.Compatibility_Issue, Errors.Compatibility,
                                             (Ordinal => Object.Session.Next_Ordinal, others => <>));
                  end if;
                  exit;
               end if;
               exit when not Results.Succeeded (Outcome);
               if Event.Op = Opcodes.End_Picture then
                  Outcome := Check_Trailing_Data (Object);
                  exit;
               end if;
            end;
         end loop;

         if not Results.Succeeded (Outcome)
           and then Object.Session.Strictness = Recover_When_Safe
           and then Is_Recoverable (Outcome.First_Error.Code)
         then
            Internal.Sessions.Warn
              (Object.Session, Errors.Partial_Picture, Errors.Data_Loss, Outcome.First_Error.Context);
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
     (Internal.Diagnostics.Count (Object.Session.Log));

   function Warning_At (Object : Decoder; Index : Positive) return Errors.Warning is
     (Internal.Diagnostics.Element (Object.Session.Log, Index));

   function Metadata_Count (Object : Decoder) return Natural is
     (Internal.Metadata_Store.Count (Object.Session.Store));

   function Metadata_Item (Object : Decoder; Index : Positive) return Metadata.Item_Info is
     (Internal.Metadata_Store.Info (Object.Session.Store, Index));

   function Copy_Metadata
     (Object : Decoder;
      Index : Positive;
      Buffer : out Streams.Byte_Array;
      Count : out Byte_Count) return Results.Result is
     (Internal.Metadata_Store.Copy_Data (Object.Session.Store, Index, Buffer, Count));

   procedure Cancel (Object : in out Decoder) is
   begin
      if Object.Current_State in Ready | Header_Read then
         Object.Current_State := Cancelled;
      end if;
   end Cancel;

   procedure Finalize (Object : in out Decoder) is
   begin
      Internal.Sessions.Clear (Object.Session);
      Object.Info := (others => <>);
      Object.Header_Event_Count := 0;
      Object.First_Error := Errors.Make (Errors.No_Error);
      Object.Current_State := Created;
   end Finalize;
end Pictlib.Decoding;
