with Interfaces;
with Pictlib.Errors;
with Pictlib.Geometry;
with Pictlib.Internal.Bytes;
with Pictlib.Internal.Picture_Stream;
with Pictlib.Metadata;
with Pictlib.Opcodes;
with Pictlib.Streams;

package body Pictlib.Internal.Container is
   use type Interfaces.Unsigned_16;
   use type Geometry.Fixed;

   File_Header_Bytes : constant := 512;
   --  picSize and picFrame precede the version opcode.
   Version_Offset : constant := 10;
   Header_Op_Bytes : constant := 24;

   type Detected_Version is (None, Detected_1, Detected_2);

   --  The version opcode a picture starting Base bytes ahead would carry.
   function Version_At (S : Opcode_Reader.Session; Base : Natural) return Detected_Version is
      Available : constant Natural := Picture_Stream.Lookahead_Length (S.Stream);
      First : constant Positive := Base + Version_Offset + 1;

      function At_Index (Index : Positive) return Byte is (Picture_Stream.Lookahead_At (S.Stream, Index));
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

   function Fail (S : Opcode_Reader.Session; Code : Errors.Error_Code; Op : Opcode := 0; Has_Op : Boolean := False)
     return Results.Result is
     (Results.Failure (Errors.Make (Code, (Source => S.Stream.Offset, Op => Op, Has_Opcode => Has_Op, others => <>))));

   function Read_File_Header (S : in out Opcode_Reader.Session) return Results.Result is
   begin
      if S.Retention.File_Headers then
         return Opcode_Reader.Retain
           (S, (Kind => Metadata.File_Header, Offset => S.Stream.Offset, others => <>), File_Header_Bytes);
      end if;
      return Streams.Skip_Exact (S.Stream, File_Header_Bytes);
   end Read_File_Header;

   function Check_Frame (S : Opcode_Reader.Session; Frame : Geometry.Rect) return Results.Result is
   begin
      if Geometry.Is_Empty (Frame) then
         return Results.Failure
           (Errors.Make
              (Errors.Header_Invalid,
               (Source => S.Stream.Offset,
                Actual => Byte_Count (Integer'Max (0, Integer'Min (Geometry.Width (Frame), Geometry.Height (Frame)))),
                others => <>)));
      elsif Geometry.Width (Frame) > Integer (S.Budget.Max_Frame_Width) then
         return Results.Failure
           (Errors.Make
              (Errors.Limit_Exceeded,
               (Source => S.Stream.Offset,
                Expected => Byte_Count (S.Budget.Max_Frame_Width),
                Actual => Byte_Count (Geometry.Width (Frame)),
                Limit => Frame_Width_Limit,
                others => <>)));
      elsif Geometry.Height (Frame) > Integer (S.Budget.Max_Frame_Height) then
         return Results.Failure
           (Errors.Make
              (Errors.Limit_Exceeded,
               (Source => S.Stream.Offset,
                Expected => Byte_Count (S.Budget.Max_Frame_Height),
                Actual => Byte_Count (Geometry.Height (Frame)),
                Limit => Frame_Height_Limit,
                others => <>)));
      end if;
      return Results.Success;
   end Check_Frame;

   --  The 24 bytes of HeaderOp data. Version -1 (a long) carries fixed-point bounds; version -2 (a word)
   --  carries the resolution and an integer source rectangle.
   function Read_Header_Op_Data
     (S : in out Opcode_Reader.Session;
      Info : in out Pictures.Header_Info) return Results.Result
   is
      Context : constant Bytes.Opcode_Context := Bytes.Within (Opcodes.Header_Op);
      First, Second : Interfaces.Unsigned_16;
      Outcome : Results.Result := Bytes.Read_U16_BE (S.Stream, First, Context);
   begin
      if Results.Succeeded (Outcome) then
         Outcome := Bytes.Read_U16_BE (S.Stream, Second, Context);
      end if;
      if not Results.Succeeded (Outcome) then
         return Outcome;
      end if;

      if First = 16#FFFF# and then Second = 16#FFFF# then
         Info.Version := Version_2;
         Outcome := Bytes.Read_Fixed (S.Stream, Info.Fixed_Bounds.Top, Context);
         if Results.Succeeded (Outcome) then
            Outcome := Bytes.Read_Fixed (S.Stream, Info.Fixed_Bounds.Left, Context);
         end if;
         if Results.Succeeded (Outcome) then
            Outcome := Bytes.Read_Fixed (S.Stream, Info.Fixed_Bounds.Bottom, Context);
         end if;
         if Results.Succeeded (Outcome) then
            Outcome := Bytes.Read_Fixed (S.Stream, Info.Fixed_Bounds.Right, Context);
         end if;
         if Results.Succeeded (Outcome) then
            Outcome := Streams.Skip_Exact (S.Stream, 4);
         end if;
         return Outcome;
      elsif First = 16#FFFE# then
         Info.Version := Extended_Version_2;
         Outcome := Bytes.Read_Fixed (S.Stream, Info.Horizontal_Resolution, Context);
         if Results.Succeeded (Outcome) then
            Outcome := Bytes.Read_Fixed (S.Stream, Info.Vertical_Resolution, Context);
         end if;
         if Results.Succeeded (Outcome) then
            Outcome := Bytes.Read_Rect (S.Stream, Info.Source_Rect, Context);
         end if;
         if Results.Succeeded (Outcome) then
            Outcome := Streams.Skip_Exact (S.Stream, 4);
         end if;
         if Results.Succeeded (Outcome)
           and then (Info.Horizontal_Resolution <= 0 or else Info.Vertical_Resolution <= 0)
         then
            if not Opcode_Reader.Is_Lenient (S) then
               return Fail (S, Errors.Header_Invalid, Opcodes.Header_Op, True);
            end if;
            Opcode_Reader.Warn (S, Errors.Compatibility_Issue, Errors.Compatibility,
                                (Op => Opcodes.Header_Op, Has_Opcode => True, others => <>));
            Info.Horizontal_Resolution := Geometry.Fixed_72;
            Info.Vertical_Resolution := Geometry.Fixed_72;
         end if;
         return Outcome;
      end if;

      if not Opcode_Reader.Is_Lenient (S) then
         return Fail (S, Errors.Header_Invalid, Opcodes.Header_Op, True);
      end if;
      Opcode_Reader.Warn (S, Errors.Compatibility_Issue, Errors.Compatibility,
                          (Op => Opcodes.Header_Op, Has_Opcode => True, others => <>));
      Info.Version := Version_2;
      return Streams.Skip_Exact (S.Stream, Header_Op_Bytes - 4);
   end Read_Header_Op_Data;

   function Read_Header
     (S : in out Opcode_Reader.Session;
      Policy : Header_Policy;
      Info : out Pictures.Header_Info;
      Events : out Header_Events;
      Event_Count : out Natural) return Results.Result
   is
      Outcome : Results.Result;
      Detected : Detected_Version;
      File_Header_Present : Boolean;
      Word : Interfaces.Unsigned_16;
   begin
      Info := (others => <>);
      Events := [others => (others => <>)];
      Event_Count := 0;

      Outcome := Picture_Stream.Fill_Lookahead (S.Stream, Picture_Stream.Lookahead_Capacity);
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
      if Detected = None then
         return Fail (S, Errors.Version_Invalid);
      end if;

      Info.Has_File_Header := File_Header_Present;
      if File_Header_Present then
         Outcome := Read_File_Header (S);
         if not Results.Succeeded (Outcome) then
            return Outcome;
         end if;
      end if;

      Picture_Stream.Start_Picture (S.Stream);
      Outcome := Bytes.Read_U16_BE (S.Stream, Info.Picture_Size);
      if Results.Succeeded (Outcome) then
         Outcome := Bytes.Read_Rect (S.Stream, Info.Frame);
      end if;
      if Results.Succeeded (Outcome) then
         Outcome := Check_Frame (S, Info.Frame);
      end if;
      if not Results.Succeeded (Outcome) then
         return Outcome;
      end if;
      Info.Source_Rect := Info.Frame;

      --  The version opcode; its bytes were checked in the look-ahead.
      Event_Count := 1;
      Events (1).Offset := S.Stream.Offset;
      Events (1).Op := Opcodes.Version_Op;
      Outcome := Opcode_Reader.Claim_Ordinal (S, Events (1).Ordinal);
      if not Results.Succeeded (Outcome) then
         return Outcome;
      end if;
      if Detected = Detected_1 then
         S.Version := Version_1;
         Info.Version := Version_1;
         Events (1).Data_Length := 1;
         return Streams.Skip_Exact (S.Stream, 2);
      end if;
      S.Version := Version_2;
      Info.Version := Version_2;
      Events (1).Data_Length := 2;
      Outcome := Streams.Skip_Exact (S.Stream, 4);
      if not Results.Succeeded (Outcome) then
         return Outcome;
      end if;

      --  Version 2 continues with the HeaderOp at an even offset.
      declare
         Header_Offset : constant Source_Offset := S.Stream.Offset;
      begin
         Outcome := Bytes.Read_U16_BE (S.Stream, Word);
         if not Results.Succeeded (Outcome) then
            return Outcome;
         elsif Opcode (Word) /= Opcodes.Header_Op then
            if not Opcode_Reader.Is_Lenient (S) then
               return Fail (S, Errors.Header_Invalid, Opcode (Word), True);
            end if;
            Opcode_Reader.Warn (S, Errors.Compatibility_Issue, Errors.Compatibility,
                                (Source => Header_Offset, Op => Opcode (Word), Has_Opcode => True, others => <>));
            S.Has_Pending := True;
            S.Pending_Op := Opcode (Word);
            S.Pending_Offset := Header_Offset;
            return Results.Success;
         end if;

         Event_Count := 2;
         Events (2) := (Offset => Header_Offset, Op => Opcodes.Header_Op, Data_Length => Header_Op_Bytes, others => <>);
         Outcome := Opcode_Reader.Claim_Ordinal (S, Events (2).Ordinal);
         if Results.Succeeded (Outcome) then
            Outcome := Read_Header_Op_Data (S, Info);
         end if;
         if Results.Succeeded (Outcome) then
            Info.Has_Header_Opcode := True;
            S.Version := Info.Version;
            if Info.Version /= Extended_Version_2 then
               Info.Source_Rect := Info.Frame;
            end if;
         end if;
         return Outcome;
      end;
   end Read_Header;
end Pictlib.Internal.Container;
