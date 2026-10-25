with Interfaces;
with Pictlib.Errors;
with Pictlib.Geometry;
with Pictlib.Internal.Bytes;
with Pictlib.Internal.Failures;
with Pictlib.Internal.Picture_Stream;
with Pictlib.Metadata;
with Pictlib.Opcodes;
with Pictlib.Streams;

package body Pictlib.Internal.Container is
   use type Interfaces.Unsigned_16;
   use type Geometry.Fixed;
   use type Errors.Error_Code;

   --  picSize and picFrame precede the version opcode.
   Version_Offset : constant := 10;
   Header_Op_Bytes : constant := 24;

   type Detected_Version is (None, Detected_1, Detected_2);

   --  The version opcode a picture starting Base bytes ahead would carry.
   function Version_At (S : in out Sessions.Session; Base : Natural) return Detected_Version is
      Available : constant Natural := Picture_Stream.Lookahead_Length (S.Stream.all);
      First : constant Positive := Base + Version_Offset + 1;

      function At_Index (Index : Positive) return Byte is (Picture_Stream.Lookahead_At (S.Stream.all, Index));
   begin
      if Available >= First + 3
        and then At_Index (First) = 16#00# and then At_Index (First + 1) = 16#11#
        and then At_Index (First + 2) = 16#02# and then At_Index (First + 3) = 16#FF#
      then
         return Detected_2;
      elsif Available >= First + 1 and then At_Index (First) = 16#11# and then At_Index (First + 1) = 16#01# then
         return Detected_1;
      end if;
      return None;
   end Version_At;

   --  The file header is not an opcode: retained or skipped, the per-opcode byte budget does not apply to it.
   function Read_File_Header (S : in out Sessions.Session) return Results.Result is
     (if S.Retention.File_Headers
      then Sessions.Retain
             (S, (Kind => Metadata.File_Header, Offset => S.Offset, others => <>), File_Header_Bytes,
              In_Opcode => False)
      else Streams.Skip_Exact (S.Stream.all, File_Header_Bytes));

   --  A frame needs a pixel each way; an empty or inverted side counts as none, since counts are not signed.
   function Check_Frame (S : Sessions.Session; Frame : Geometry.Rect) return Results.Result is
     (if Geometry.Is_Empty (Frame)
      then Sessions.Fail (S, Errors.Header_Invalid, Expected => 1, Actual => 0)
      else Failures.Check_Frame_Size (Geometry.Width (Frame), Geometry.Height (Frame), S.Budget, S.Offset));

   --  The 24 bytes of HeaderOp data. Version -1 (a long) carries fixed-point bounds; version -2 (a word)
   --  carries the resolution and an integer source rectangle.

   --  Its diagnostics name the HeaderOp Event: its offset, opcode and ordinal.
   function Read_Header_Op_Data
     (S : in out Sessions.Session;
      Event : Pictures.Opcode_Event;
      Info : in out Pictures.Header_Info) return Results.Result
   is
      Header_Op_Context : constant Errors.Diagnostic_Context := Sessions.Context_Of (Event);
      First, Second : Interfaces.Unsigned_16;
      Outcome : Results.Result := Bytes.Read_U16_BE (S.Stream.all, First);
   begin
      if Results.Succeeded (Outcome) then
         Outcome := Bytes.Read_U16_BE (S.Stream.all, Second);
      end if;
      if not Results.Succeeded (Outcome) then
         return Outcome;
      end if;

      if First = 16#FFFF# and then Second = 16#FFFF# then
         Info.Version := Version_2;
         --  The fixed-point bounds are stored x before y: left, top, right, bottom (as Netpbm writes them).
         Outcome := Bytes.Read_Fixed (S.Stream.all, Info.Fixed_Bounds.Left);
         if Results.Succeeded (Outcome) then
            Outcome := Bytes.Read_Fixed (S.Stream.all, Info.Fixed_Bounds.Top);
         end if;
         if Results.Succeeded (Outcome) then
            Outcome := Bytes.Read_Fixed (S.Stream.all, Info.Fixed_Bounds.Right);
         end if;
         if Results.Succeeded (Outcome) then
            Outcome := Bytes.Read_Fixed (S.Stream.all, Info.Fixed_Bounds.Bottom);
         end if;
         if Results.Succeeded (Outcome) then
            Outcome := Streams.Skip_Exact (S.Stream.all, 4);
         end if;
         return Outcome;
      elsif First = Extended_Header_Version then
         Info.Version := Extended_Version_2;
         Outcome := Bytes.Read_Fixed (S.Stream.all, Info.Horizontal_Resolution);
         if Results.Succeeded (Outcome) then
            Outcome := Bytes.Read_Fixed (S.Stream.all, Info.Vertical_Resolution);
         end if;
         if Results.Succeeded (Outcome) then
            Outcome := Bytes.Read_Rect (S.Stream.all, Info.Source_Rect);
         end if;
         if Results.Succeeded (Outcome) then
            Outcome := Streams.Skip_Exact (S.Stream.all, 4);
         end if;
         if Results.Succeeded (Outcome)
           and then (Info.Horizontal_Resolution <= 0 or else Info.Vertical_Resolution <= 0)
         then
            --  Leniently the resolution is 72 dpi.
            Info.Horizontal_Resolution := Geometry.Fixed_72;
            Info.Vertical_Resolution := Geometry.Fixed_72;
            return Sessions.Reject_Or_Warn
              (S, Errors.Header_Invalid, Errors.Compatibility_Issue, Errors.Compatibility, Header_Op_Context);
         end if;
         return Outcome;
      end if;

      --  An unknown HeaderOp version: leniently version 2, its fields skipped.
      Info.Version := Version_2;
      Outcome := Sessions.Reject_Or_Warn
        (S, Errors.Header_Invalid, Errors.Compatibility_Issue, Errors.Compatibility, Header_Op_Context);
      return (if Results.Succeeded (Outcome) then Streams.Skip_Exact (S.Stream.all, Header_Op_Bytes - 4) else Outcome);
   end Read_Header_Op_Data;

   --  Which version the look-ahead shows, after a file header or not as the policy decides.
   function Detect_Layout
     (S : in out Sessions.Session;
      Policy : Header_Policy;
      File_Header_Present : out Boolean;
      Detected : out Detected_Version) return Results.Result
   is
      Outcome : constant Results.Result :=
        Picture_Stream.Fill_Lookahead (S.Stream.all, Picture_Stream.Lookahead_Capacity);
   begin
      File_Header_Present := False;
      Detected := None;
      if not Results.Succeeded (Outcome) then
         return Outcome;
      end if;
      case Policy is
         when Auto =>
            File_Header_Present := Version_At (S, File_Header_Bytes) /= None;
         when Has_File_Header =>
            File_Header_Present := True;
         when No_File_Header =>
            File_Header_Present := False;
      end case;
      Detected := Version_At (S, (if File_Header_Present then File_Header_Bytes else 0));
      if Detected = None
        and then Byte_Count (Picture_Stream.Lookahead_Length (S.Stream.all)) >= S.Budget.Max_Picture_Bytes
        and then Picture_Stream.Lookahead_Length (S.Stream.all) < Picture_Stream.Lookahead_Capacity
        and then not Picture_Stream.Input_Ended (S.Stream.all)
      then
         --  The picture byte budget cut the look-ahead short of the version: the limit, not a bad version.
         return Sessions.Over_Limit
           (S, Picture_Byte_Limit, S.Budget.Max_Picture_Bytes, S.Budget.Max_Picture_Bytes + 1);
      elsif Detected = None then
         return Sessions.Fail (S, Errors.Version_Invalid);
      end if;
      return Results.Success;
   end Detect_Layout;

   --  picSize and picFrame.
   function Read_Frame (S : in out Sessions.Session; Info : in out Pictures.Header_Info) return Results.Result is
      Outcome : Results.Result := Bytes.Read_U16_BE (S.Stream.all, Info.Picture_Size);
   begin
      if Results.Succeeded (Outcome) then
         Outcome := Bytes.Read_Rect (S.Stream.all, Info.Frame);
      end if;
      if Results.Succeeded (Outcome) then
         Outcome := Check_Frame (S, Info.Frame);
      end if;
      Info.Source_Rect := Info.Frame;
      return Outcome;
   end Read_Frame;

   --  The version opcode, the picture's first event; its bytes were checked in the look-ahead.
   function Read_Version_Opcode
     (S : in out Sessions.Session;
      Detected : Detected_Version;
      Info : in out Pictures.Header_Info;
      Event : out Pictures.Opcode_Event) return Results.Result
   is
      Outcome : Results.Result;
   begin
      Event := (Offset => S.Offset, Op => Opcodes.Version_Op, others => <>);
      Outcome := Sessions.Claim_Ordinal (S, Event.Ordinal);
      if not Results.Succeeded (Outcome) then
         return Outcome;
      end if;
      Info.Version := (if Detected = Detected_1 then Version_1 else Version_2);
      Sessions.Set_Version (S, Info.Version);
      --  The opcode and its data, each Opcode_Bytes long; the data counts against the per-opcode budget, as
      --  every opcode's does.
      Event.Data_Length := Byte_Count (Opcode_Bytes (Info.Version));
      Outcome := Streams.Skip_Exact (S.Stream.all, Event.Data_Length);
      if Results.Succeeded (Outcome) then
         Sessions.Begin_Opcode_Data (S);
         Outcome := Sessions.Skip_Data (S, Event.Data_Length);
      end if;
      return Sessions.Attributed (Outcome, Event);
   end Read_Version_Opcode;

   --  Version 2 continues with the HeaderOp at an even offset.
   function Read_Header_Op
     (S : in out Sessions.Session;
      Info : in out Pictures.Header_Info;
      Version_Event : Pictures.Opcode_Event;
      Event : out Pictures.Opcode_Event;
      Found : out Boolean) return Results.Result
   is
      Header_Offset : constant Source_Offset := S.Offset;
      Word : Interfaces.Unsigned_16;
      Outcome : Results.Result := Bytes.Read_U16_BE (S.Stream.all, Word);

      --  The opcode where HeaderOp belongs, with the ordinal HeaderOp would have had.
      function In_Place_Of_Header_Op (Op : Opcode) return Errors.Diagnostic_Context is
        ((Source => Header_Offset, Op => Op, Has_Opcode => True, Ordinal => Version_Event.Ordinal + 1,
          others => <>));
   begin
      Event := (others => <>);
      Found := False;
      if Sessions.Is_Boundary_End (Outcome) then
         --  The input ends right after the version opcode, at an opcode boundary: the picture has no
         --  HeaderOp, and leniently it then ends without its end opcode, as the opcode reader reports.
         return Sessions.Reject_Or_Warn
           (S, Errors.Header_Invalid, Errors.Compatibility_Issue, Errors.Compatibility,
            In_Place_Of_Header_Op (Opcodes.Header_Op));
      elsif not Results.Succeeded (Outcome) then
         return Outcome;
      elsif Opcode (Word) /= Opcodes.Header_Op then
         --  Leniently the opcode found is the first one the opcode reader reads.
         Outcome := Sessions.Reject_Or_Warn
           (S, Errors.Header_Invalid, Errors.Compatibility_Issue, Errors.Compatibility,
            In_Place_Of_Header_Op (Opcode (Word)));
         if Results.Succeeded (Outcome) then
            Sessions.Defer_Opcode (S, Opcode (Word), Header_Offset);
         end if;
         return Outcome;
      end if;

      Found := True;
      Event := (Offset => Header_Offset, Op => Opcodes.Header_Op, Data_Length => Header_Op_Bytes, others => <>);
      Outcome := Sessions.Claim_Ordinal (S, Event.Ordinal);
      if Results.Succeeded (Outcome) then
         --  Its data counts against the per-opcode budget, as it would anywhere in the picture.
         Sessions.Begin_Opcode_Data (S);
         Outcome := Sessions.Attributed (Sessions.Admit_Data (S, Header_Op_Bytes), Event);
      end if;
      if Results.Succeeded (Outcome) then
         Outcome := Sessions.Attributed (Read_Header_Op_Data (S, Event, Info), Event);
      end if;
      if Results.Succeeded (Outcome) then
         Info.Has_Header_Opcode := True;
         Sessions.Set_Version (S, Info.Version);
      end if;
      return Outcome;
   end Read_Header_Op;

   function Read_Header
     (S : in out Sessions.Session;
      Policy : Header_Policy;
      Info : out Pictures.Header_Info;
      Events : out Header_Events;
      Event_Count : out Natural) return Results.Result
   is
      Outcome : Results.Result;
      Detected : Detected_Version;
      File_Header_Present : Boolean;
      Found : Boolean;
   begin
      Info := (others => <>);
      Events := [others => (others => <>)];
      Event_Count := 0;

      Outcome := Detect_Layout (S, Policy, File_Header_Present, Detected);
      if not Results.Succeeded (Outcome) then
         return Outcome;
      end if;
      Info.Has_File_Header := File_Header_Present;
      if File_Header_Present then
         Outcome := Read_File_Header (S);
         if not Results.Succeeded (Outcome) then
            return Outcome;
         end if;
      end if;

      Picture_Stream.Start_Picture (S.Stream.all);
      Outcome := Read_Frame (S, Info);
      if not Results.Succeeded (Outcome) then
         return Outcome;
      end if;

      Event_Count := 1;
      Outcome := Read_Version_Opcode (S, Detected, Info, Events (1));
      if not Results.Succeeded (Outcome) or else Detected = Detected_1 then
         return Outcome;
      end if;

      Outcome := Read_Header_Op (S, Info, Events (1), Events (2), Found);
      if Found then
         Event_Count := 2;
      end if;
      return Outcome;
   end Read_Header;
end Pictlib.Internal.Container;
