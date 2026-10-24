with Ada.Unchecked_Deallocation;
with Interfaces;
with Pictlib.Geometry;
with Pictlib.Internal.Bytes;
with Pictlib.Internal.Checked_Arithmetic;
with Pictlib.Opcodes;
with Pictlib.Streams;

package body Pictlib.Internal.Opcode_Reader is
   use type Interfaces.Unsigned_16;
   use type Errors.Error_Code;

   procedure Free is new Ada.Unchecked_Deallocation (Streams.Byte_Array, Streams.Byte_Array_Access);

   --  Bytes of a PixMap after its rowBytes and bounds: pmVersion through pmReserved.
   Pixmap_Tail_Bytes : constant := 36;
   --  Bytes of one color table entry: value and 16-bit red, green and blue.
   Color_Entry_Bytes : constant := 8;
   Smallest_Region : constant := 10;

   procedure Clear (S : in out Session) is
   begin
      Picture_Stream.Unbind (S.Stream);
      S.Version := Version_1;
      Metadata_Store.Clear (S.Store);
      Diagnostics.Clear (S.Log);
      S.Next_Ordinal := 0;
      S.Data_Start := 0;
      S.Has_Pending := False;
      S.Pending_Op := 0;
      S.Pending_Offset := 0;
   end Clear;

   procedure Warn
     (S : in out Session;
      Code : Errors.Warning_Code;
      Severity : Errors.Warning_Severity;
      Context : Errors.Diagnostic_Context := (others => <>))
   is
      Item : Errors.Diagnostic_Context := Context;
   begin
      if Item.Source = 0 then
         Item.Source := S.Stream.Offset;
      end if;
      Diagnostics.Add (S.Log, Errors.Make_Warning (Code, Severity, Item), S.Budget.Max_Warning_Records);
   end Warn;

   function Fail (S : Session; Code : Errors.Error_Code; Expected, Actual : Byte_Count := 0) return Results.Result is
     (Results.Failure
        (Errors.Make (Code, (Source => S.Stream.Offset, Expected => Expected, Actual => Actual, others => <>))));

   function Over_Limit (S : Session; Limit : Limit_Kind; Expected, Actual : Byte_Count) return Results.Result is
     (Results.Failure
        (Errors.Make
           (Errors.Limit_Exceeded,
            (Source => S.Stream.Offset, Expected => Expected, Actual => Actual, Limit => Limit, others => <>))));

   function Claim_Ordinal (S : in out Session; Ordinal : out Opcode_Ordinal) return Results.Result is
   begin
      Ordinal := S.Next_Ordinal;
      if S.Next_Ordinal >= S.Budget.Max_Opcodes then
         return Over_Limit
           (S, Opcode_Count_Limit, Byte_Count (S.Budget.Max_Opcodes), Byte_Count (S.Next_Ordinal) + 1);
      end if;
      S.Next_Ordinal := S.Next_Ordinal + 1;
      return Results.Success;
   end Claim_Ordinal;

   --  Admit More bytes of the current opcode's data against the per-opcode budget.
   function Admit_Data (S : Session; More : Byte_Count) return Results.Result is
      Used : constant Byte_Count := Picture_Stream.Picture_Offset (S.Stream) - S.Data_Start;
      Sum : constant Checked_Arithmetic.Count_Result := Checked_Arithmetic.Add (Used, More);
   begin
      if not Results.Succeeded (Sum.Outcome) or else Sum.Value > S.Budget.Max_Opcode_Bytes then
         return Over_Limit (S, Opcode_Byte_Limit, S.Budget.Max_Opcode_Bytes, Sum.Value);
      end if;
      return Results.Success;
   end Admit_Data;

   function Skip_Data (S : in out Session; Count : Byte_Count) return Results.Result is
      Outcome : constant Results.Result := Admit_Data (S, Count);
   begin
      if not Results.Succeeded (Outcome) or else Count = 0 then
         return Outcome;
      end if;
      return Streams.Skip_Exact (S.Stream, Count);
   end Skip_Data;

   --  Read Length bytes into a heap buffer the caller frees.
   function Read_Payload
     (S : in out Session;
      Length : Byte_Count;
      Data : out Streams.Byte_Array_Access) return Results.Result
   is
      Outcome : Results.Result := Admit_Data (S, Length);
   begin
      Data := null;
      if not Results.Succeeded (Outcome) then
         return Outcome;
      elsif Length > Byte_Count (Natural'Last) then
         return Over_Limit (S, Allocation_Byte_Limit, Byte_Count (Natural'Last), Length);
      elsif Length > S.Budget.Max_Allocation_Bytes then
         return Over_Limit (S, Allocation_Byte_Limit, S.Budget.Max_Allocation_Bytes, Length);
      end if;
      Data := new Streams.Byte_Array (1 .. Natural (Length));
      Outcome := Streams.Read_Exact (S.Stream, Data.all);
      if not Results.Succeeded (Outcome) then
         Free (Data);
      end if;
      return Outcome;
   end Read_Payload;

   --  Decide whether an item of Length bytes may be kept: a strict session fails when it does not fit,
   --  a lenient one records Data_Loss and sets Keep to False.
   function Admit_Item (S : in out Session; Length : Byte_Count; Keep : out Boolean) return Results.Result is
      Admission : constant Results.Result := Metadata_Store.Admits (S.Store, Length, S.Budget);
   begin
      Keep := Results.Succeeded (Admission);
      if Keep then
         return Admission;
      elsif not Is_Lenient (S) then
         return Results.Failure
           ((Admission.First_Error with delta
               Context => (Admission.First_Error.Context with delta Source => S.Stream.Offset)));
      end if;
      Warn (S, Errors.Data_Loss, Errors.Data_Loss, Admission.First_Error.Context);
      return Results.Success;
   end Admit_Item;

   function Retain (S : in out Session; Info : Metadata.Item_Info; Length : Byte_Count) return Results.Result is
      Keep : Boolean;
      Outcome : Results.Result := Admit_Item (S, Length, Keep);
      Data : Streams.Byte_Array_Access;
   begin
      if not Results.Succeeded (Outcome) then
         return Outcome;
      elsif not Keep then
         return Skip_Data (S, Length);
      end if;
      Outcome := Read_Payload (S, Length, Data);
      if Results.Succeeded (Outcome) then
         Metadata_Store.Append (S.Store, Info, Data.all);
         Free (Data);
      end if;
      return Outcome;
   end Retain;

   function Item_For (Kind : Metadata.Item_Kind; Event : Pictures.Opcode_Event) return Metadata.Item_Info is
     ((Kind => Kind, Ordinal => Event.Ordinal, Offset => Event.Offset, Op => Event.Op, others => <>));

   function Read_Word (S : in out Session; Value : out Interfaces.Unsigned_16) return Results.Result is
      Outcome : constant Results.Result := Admit_Data (S, 2);
   begin
      Value := 0;
      if not Results.Succeeded (Outcome) then
         return Outcome;
      end if;
      return Bytes.Read_U16_BE (S.Stream, Value);
   end Read_Word;

   function Read_Count_Byte (S : in out Session; Value : out Byte) return Results.Result is
      Outcome : constant Results.Result := Admit_Data (S, 1);
   begin
      Value := 0;
      if not Results.Succeeded (Outcome) then
         return Outcome;
      end if;
      return Bytes.Read_Byte (S.Stream, Value);
   end Read_Count_Byte;

   function Read_Long (S : in out Session; Value : out Interfaces.Unsigned_32) return Results.Result is
      Outcome : constant Results.Result := Admit_Data (S, 4);
   begin
      Value := 0;
      if not Results.Succeeded (Outcome) then
         return Outcome;
      end if;
      return Bytes.Read_U32_BE (S.Stream, Value);
   end Read_Long;

   function Read_Bounds (S : in out Session; Value : out Geometry.Rect) return Results.Result is
      Outcome : constant Results.Result := Admit_Data (S, 8);
   begin
      Value := (others => 0);
      if not Results.Succeeded (Outcome) then
         return Outcome;
      end if;
      return Bytes.Read_Rect (S.Stream, Value);
   end Read_Bounds;

   function Skip_Region (S : in out Session) return Results.Result is
      Size : Interfaces.Unsigned_16;
      Outcome : constant Results.Result := Read_Word (S, Size);
   begin
      if not Results.Succeeded (Outcome) then
         return Outcome;
      elsif Size < Smallest_Region then
         return Fail (S, Errors.Region_Invalid, Smallest_Region, Byte_Count (Size));
      elsif Byte_Count (Size) > S.Budget.Max_Region_Bytes then
         return Over_Limit (S, Region_Byte_Limit, S.Budget.Max_Region_Bytes, Byte_Count (Size));
      end if;
      return Skip_Data (S, Byte_Count (Size) - 2);
   end Skip_Region;

   function Skip_Polygon (S : in out Session) return Results.Result is
      Size : Interfaces.Unsigned_16;
      Outcome : constant Results.Result := Read_Word (S, Size);
   begin
      if not Results.Succeeded (Outcome) then
         return Outcome;
      elsif Size < Smallest_Region or else (Size - Smallest_Region) mod 4 /= 0 then
         return Fail (S, Errors.Polygon_Invalid, Smallest_Region, Byte_Count (Size));
      elsif Natural (Size - Smallest_Region) / 4 > S.Budget.Max_Polygon_Points then
         return Over_Limit
           (S, Polygon_Point_Limit, Byte_Count (S.Budget.Max_Polygon_Points), Byte_Count (Size - Smallest_Region) / 4);
      end if;
      return Skip_Data (S, Byte_Count (Size) - 2);
   end Skip_Polygon;

   function Skip_Color_Table (S : in out Session) return Results.Result is
      Seed : Interfaces.Unsigned_32;
      Flags, Size : Interfaces.Unsigned_16;
      Outcome : Results.Result := Read_Long (S, Seed);
   begin
      if Results.Succeeded (Outcome) then
         Outcome := Read_Word (S, Flags);
      end if;
      if Results.Succeeded (Outcome) then
         Outcome := Read_Word (S, Size);
      end if;
      if not Results.Succeeded (Outcome) then
         return Outcome;
      elsif Size = 16#FFFF# then
         --  ctSize is the entry count minus one; -1 is an empty table.
         return Results.Success;
      elsif Size > 255 then
         return Fail (S, Errors.Color_Table_Invalid, 255, Byte_Count (Size));
      end if;
      return Skip_Data (S, (Byte_Count (Size) + 1) * Color_Entry_Bytes);
   end Skip_Color_Table;

   --  Pixel data: unpacked rows of Raw_Row_Length bytes, or rows each prefixed by its packed byte count,
   --  a byte when Row_Bytes <= 250 and a word otherwise.
   function Skip_Rows
     (S : in out Session;
      Row_Bytes : Natural;
      Height : Natural;
      Packed : Boolean;
      Raw_Row_Length : Byte_Count) return Results.Result
   is
      Outcome : Results.Result;
   begin
      if not Packed then
         declare
            Total : constant Checked_Arithmetic.Count_Result :=
              Checked_Arithmetic.Multiply (Raw_Row_Length, Byte_Count (Height));
         begin
            if not Results.Succeeded (Total.Outcome) then
               return Over_Limit (S, Opcode_Byte_Limit, S.Budget.Max_Opcode_Bytes, Byte_Count'Last);
            end if;
            return Skip_Data (S, Total.Value);
         end;
      end if;
      for Row in 0 .. Height - 1 loop
         declare
            Count : Byte_Count;
         begin
            if Row_Bytes > 250 then
               declare
                  Word : Interfaces.Unsigned_16;
               begin
                  Outcome := Read_Word (S, Word);
                  Count := Byte_Count (Word);
               end;
            else
               declare
                  Small : Byte;
               begin
                  Outcome := Read_Count_Byte (S, Small);
                  Count := Byte_Count (Small);
               end;
            end if;
            if Results.Succeeded (Outcome) then
               Outcome := Skip_Data (S, Count);
            end if;
            if not Results.Succeeded (Outcome) then
               return Results.Failure
                 ((Outcome.First_Error with delta
                     Context => (Outcome.First_Error.Context with delta Row => Row_Index (Row))));
            end if;
         end;
      end loop;
      return Results.Success;
   end Skip_Rows;

   type Pixmap_Fields is record
      Pack : Interfaces.Unsigned_16 := 0;
      Pixel_Size : Interfaces.Unsigned_16 := 0;
   end record;

   --  Read the PixMap fields after rowBytes and bounds, keeping the ones that delimit pixel data.
   function Read_Pixmap_Tail (S : in out Session; Fields : out Pixmap_Fields) return Results.Result is
      Version, Ignored_Word : Interfaces.Unsigned_16;
      Ignored_Long : Interfaces.Unsigned_32;
      Outcome : Results.Result := Read_Word (S, Version);
   begin
      Fields := (others => <>);
      if Results.Succeeded (Outcome) then
         Outcome := Read_Word (S, Fields.Pack);
      end if;
      for Index in 1 .. 3 loop  --  packSize, hRes, vRes
         exit when not Results.Succeeded (Outcome);
         Outcome := Read_Long (S, Ignored_Long);
      end loop;
      if Results.Succeeded (Outcome) then
         Outcome := Read_Word (S, Ignored_Word);  --  pixelType
      end if;
      if Results.Succeeded (Outcome) then
         Outcome := Read_Word (S, Fields.Pixel_Size);
      end if;
      if Results.Succeeded (Outcome) then
         Outcome := Skip_Data (S, Pixmap_Tail_Bytes - 20);  --  cmpCount through pmReserved
      end if;
      if not Results.Succeeded (Outcome) then
         return Outcome;
      elsif Fields.Pixel_Size not in 1 | 2 | 4 | 8 | 16 | 32 then
         return Fail (S, Errors.Pixmap_Invalid, 32, Byte_Count (Fields.Pixel_Size));
      elsif Fields.Pack > Interfaces.Unsigned_16 (Pack_Type'Last) then
         return Fail (S, Errors.Pixmap_Invalid, Byte_Count (Pack_Type'Last), Byte_Count (Fields.Pack));
      end if;
      return Results.Success;
   end Read_Pixmap_Tail;

   function Extent (S : Session; Bounds : Geometry.Rect; Width, Height : out Natural) return Results.Result is
   begin
      Width := 0;
      Height := 0;
      if Geometry.Width (Bounds) < 0 or else Geometry.Height (Bounds) < 0 then
         return Fail (S, Errors.Pixmap_Invalid);
      end if;
      Width := Geometry.Width (Bounds);
      Height := Geometry.Height (Bounds);
      return Results.Success;
   end Extent;

   function Skip_Pixel_Pattern (S : in out Session) return Results.Result is
      Pattern_Type, Raw_Row_Bytes : Interfaces.Unsigned_16;
      Bounds : Geometry.Rect;
      Fields : Pixmap_Fields;
      Width, Height : Natural;
      Outcome : Results.Result := Read_Word (S, Pattern_Type);
   begin
      if Results.Succeeded (Outcome) then
         Outcome := Skip_Data (S, 8);  --  pat1Data, the 1-bit fallback pattern
      end if;
      if not Results.Succeeded (Outcome) then
         return Outcome;
      end if;
      case Pattern_Type is
         when 1 =>
            Outcome := Read_Word (S, Raw_Row_Bytes);
            if Results.Succeeded (Outcome) then
               Outcome := Read_Bounds (S, Bounds);
            end if;
            if Results.Succeeded (Outcome) then
               Outcome := Read_Pixmap_Tail (S, Fields);
            end if;
            if Results.Succeeded (Outcome) then
               Outcome := Skip_Color_Table (S);
            end if;
            if Results.Succeeded (Outcome) then
               Outcome := Extent (S, Bounds, Width, Height);
            end if;
            if not Results.Succeeded (Outcome) then
               return Outcome;
            end if;
            declare
               Row_Bytes : constant Natural := Natural (Raw_Row_Bytes and 16#3FFF#);
            begin
               return Skip_Rows (S, Row_Bytes, Height, Row_Bytes >= 8, Byte_Count (Row_Bytes));
            end;
         when 2 =>
            return Skip_Data (S, 6);  --  an RGB color to dither
         when others =>
            return Fail (S, Errors.Pattern_Invalid, 2, Byte_Count (Pattern_Type));
      end case;
   end Skip_Pixel_Pattern;

   function Skip_Bits (S : in out Session; Op : Opcode) return Results.Result is
      Direct : constant Boolean := Op in Opcodes.Direct_Bits_Rect | Opcodes.Direct_Bits_Region;
      Packed : constant Boolean := Op not in Opcodes.Bits_Rect | Opcodes.Bits_Region;
      Masked : constant Boolean :=
        Op in Opcodes.Bits_Region | Opcodes.Pack_Bits_Region | Opcodes.Direct_Bits_Region;
      Raw_Row_Bytes : Interfaces.Unsigned_16;
      Is_Pixmap : Boolean;
      Row_Bytes, Width, Height : Natural;
      Bounds, Rect_Ignored : Geometry.Rect;
      Fields : Pixmap_Fields;
      Mode : Interfaces.Unsigned_16;
      Outcome : Results.Result := Results.Success;
   begin
      if Direct then
         Outcome := Skip_Data (S, 4);  --  baseAddr
      end if;
      if Results.Succeeded (Outcome) then
         Outcome := Read_Word (S, Raw_Row_Bytes);
      end if;
      if Results.Succeeded (Outcome) then
         Outcome := Read_Bounds (S, Bounds);
      end if;
      if not Results.Succeeded (Outcome) then
         return Outcome;
      end if;

      Is_Pixmap := Direct or else (Raw_Row_Bytes and 16#8000#) /= 0;
      Row_Bytes := Natural (Raw_Row_Bytes and (if Is_Pixmap then 16#3FFF# else 16#7FFF#));
      if Is_Pixmap then
         Outcome := Read_Pixmap_Tail (S, Fields);
         if Results.Succeeded (Outcome) and then Direct and then Fields.Pixel_Size not in 16 | 32 then
            Outcome := Fail (S, Errors.Pixmap_Invalid, 32, Byte_Count (Fields.Pixel_Size));
         end if;
         if Results.Succeeded (Outcome) and then not Direct then
            Outcome := Skip_Color_Table (S);
         end if;
      end if;
      for Index in 1 .. 2 loop  --  srcRect, dstRect
         exit when not Results.Succeeded (Outcome);
         Outcome := Read_Bounds (S, Rect_Ignored);
      end loop;
      if Results.Succeeded (Outcome) then
         Outcome := Read_Word (S, Mode);
      end if;
      if Results.Succeeded (Outcome) and then Masked then
         Outcome := Skip_Region (S);
      end if;
      if Results.Succeeded (Outcome) then
         Outcome := Extent (S, Bounds, Width, Height);
      end if;
      if not Results.Succeeded (Outcome) then
         return Outcome;
      end if;

      if not Packed or else Row_Bytes < 8 or else (Is_Pixmap and then Fields.Pack = 1) then
         return Skip_Rows (S, Row_Bytes, Height, False, Byte_Count (Row_Bytes));
      elsif Is_Pixmap and then Fields.Pack = 2 then
         --  32-bit pixels with the pad byte dropped, unpacked.
         if Fields.Pixel_Size /= 32 then
            return Fail (S, Errors.Pixmap_Invalid, 32, Byte_Count (Fields.Pixel_Size));
         end if;
         return Skip_Rows (S, Row_Bytes, Height, False, 3 * Byte_Count (Width));
      end if;
      return Skip_Rows (S, Row_Bytes, Height, True, 0);
   end Skip_Bits;

   function Consume_Short_Comment (S : in out Session; Event : Pictures.Opcode_Event) return Results.Result is
      Kind : Interfaces.Unsigned_16;
      Keep : Boolean;
      Outcome : Results.Result := Read_Word (S, Kind);
   begin
      if Results.Succeeded (Outcome) and then S.Retention.Comments then
         Outcome := Admit_Item (S, 0, Keep);
         if Results.Succeeded (Outcome) and then Keep then
            Metadata_Store.Append
              (S.Store, (Item_For (Metadata.Short_Comment, Event) with delta Comment_Kind => Kind), [1 .. 0 => 0]);
         end if;
      end if;
      return Outcome;
   end Consume_Short_Comment;

   function Consume_Long_Comment (S : in out Session; Event : Pictures.Opcode_Event) return Results.Result is
      Kind, Size : Interfaces.Unsigned_16;
      Outcome : Results.Result := Read_Word (S, Kind);
   begin
      if Results.Succeeded (Outcome) then
         Outcome := Read_Word (S, Size);
      end if;
      if not Results.Succeeded (Outcome) then
         return Outcome;
      elsif S.Retention.Comments then
         return Retain (S, (Item_For (Metadata.Long_Comment, Event) with delta Comment_Kind => Kind), Byte_Count (Size));
      end if;
      return Skip_Data (S, Byte_Count (Size));
   end Consume_Long_Comment;

   --  fontName data: a font ID, then the name as a Pascal string.
   function Consume_Font_Name
     (S : in out Session;
      Event : Pictures.Opcode_Event;
      Length : Byte_Count) return Results.Result
   is
      Data : Streams.Byte_Array_Access;
      Keep : Boolean;
      Outcome : Results.Result := Read_Payload (S, Length, Data);
   begin
      if not Results.Succeeded (Outcome) then
         return Outcome;
      end if;
      if Data'Length < 3 or else Natural (Data (3)) > Data'Length - 3 then
         Free (Data);
         if not Is_Lenient (S) then
            return Fail (S, Errors.Opcode_Length_Invalid, 3, Length);
         end if;
         Warn (S, Errors.Data_Loss, Errors.Data_Loss,
               (Op => Event.Op, Has_Opcode => True, Ordinal => Event.Ordinal, Actual => Length, others => <>));
         return Results.Success;
      end if;
      declare
         Name_Length : constant Natural := Natural (Data (3));
         Font : constant Interfaces.Unsigned_16 :=
           Interfaces.Shift_Left (Interfaces.Unsigned_16 (Data (1)), 8) or Interfaces.Unsigned_16 (Data (2));
      begin
         Outcome := Admit_Item (S, Byte_Count (Name_Length), Keep);
         if Results.Succeeded (Outcome) and then Keep then
            Metadata_Store.Append
              (S.Store, (Item_For (Metadata.Font_Name, Event) with delta Font_ID => Font), Data (4 .. 3 + Name_Length));
         end if;
      end;
      Free (Data);
      return Outcome;
   end Consume_Font_Name;

   function Consume_Length_Prefixed
     (S : in out Session;
      Event : Pictures.Opcode_Event;
      Length : Byte_Count) return Results.Result
   is
      Outcome : constant Results.Result := Admit_Data (S, Length);
   begin
      if not Results.Succeeded (Outcome) then
         return Outcome;
      elsif Event.Op = Opcodes.Font_Name and then S.Retention.Font_Names then
         return Consume_Font_Name (S, Event, Length);
      elsif Event.Op in Opcodes.Compressed_QuickTime | Opcodes.Uncompressed_QuickTime
        and then S.Retention.QuickTime_Payloads
      then
         return Retain (S, Item_For (Metadata.QuickTime_Payload, Event), Length);
      elsif Event.Reserved and then S.Retention.Reserved_Payloads then
         return Retain (S, Item_For (Metadata.Reserved_Payload, Event), Length);
      end if;
      return Skip_Data (S, Length);
   end Consume_Length_Prefixed;

   function Consume_Text (S : in out Session; Prefix : Natural) return Results.Result is
      Count : Byte;
      Outcome : Results.Result := Skip_Data (S, Byte_Count (Prefix));
   begin
      if Results.Succeeded (Outcome) then
         Outcome := Read_Count_Byte (S, Count);
      end if;
      if Results.Succeeded (Outcome) then
         Outcome := Skip_Data (S, Byte_Count (Count));
      end if;
      return Outcome;
   end Consume_Text;

   function Consume_Data (S : in out Session; Event : Pictures.Opcode_Event) return Results.Result is
      Rule : constant Opcodes.Length_Rule := Opcodes.Rule_For (Event.Op);
      Outcome : Results.Result;
   begin
      case Rule.Rule is
         when Opcodes.Fixed_Data =>
            if Event.Op = Opcodes.Short_Comment then
               return Consume_Short_Comment (S, Event);
            end if;
            return Skip_Data (S, Byte_Count (Rule.Fixed_Length));
         when Opcodes.Word_Length_Data =>
            declare
               Length : Interfaces.Unsigned_16;
            begin
               Outcome := Read_Word (S, Length);
               if Results.Succeeded (Outcome) then
                  Outcome := Consume_Length_Prefixed (S, Event, Byte_Count (Length));
               end if;
               return Outcome;
            end;
         when Opcodes.Long_Length_Data =>
            declare
               Length : Interfaces.Unsigned_32;
            begin
               Outcome := Read_Long (S, Length);
               if Results.Succeeded (Outcome) then
                  Outcome := Consume_Length_Prefixed (S, Event, Byte_Count (Length));
               end if;
               return Outcome;
            end;
         when Opcodes.Region_Data =>
            return Skip_Region (S);
         when Opcodes.Polygon_Data =>
            return Skip_Polygon (S);
         when Opcodes.Pixel_Pattern_Data =>
            return Skip_Pixel_Pattern (S);
         when Opcodes.Text_Data =>
            return Consume_Text (S, Rule.Fixed_Length);
         when Opcodes.Long_Comment_Data =>
            return Consume_Long_Comment (S, Event);
         when Opcodes.Bits_Data =>
            return Skip_Bits (S, Event.Op);
         when Opcodes.Version_Data =>
            return Skip_Data (S, (if S.Version = Version_1 then 1 else 2));
         when Opcodes.End_Of_Picture =>
            return Results.Success;
      end case;
   end Consume_Data;

   function Next
     (S : in out Session;
      Event : out Pictures.Opcode_Event;
      At_End_Of_Input : out Boolean) return Results.Result
   is
      Outcome : Results.Result := Results.Success;
      Op : Opcode := 0;
   begin
      Event := (others => <>);
      At_End_Of_Input := False;

      if S.Has_Pending then
         Op := S.Pending_Op;
         Event.Offset := S.Pending_Offset;
         S.Has_Pending := False;
      else
         if S.Version /= Version_1 and then Picture_Stream.Picture_Offset (S.Stream) mod 2 = 1 then
            Outcome := Streams.Skip_Exact (S.Stream, 1);
         end if;
         Event.Offset := S.Stream.Offset;
         if Results.Succeeded (Outcome) then
            if S.Version = Version_1 then
               declare
                  Value : Byte;
               begin
                  Outcome := Bytes.Read_Byte (S.Stream, Value);
                  Op := Opcode (Value);
               end;
            else
               declare
                  Value : Interfaces.Unsigned_16;
               begin
                  Outcome := Bytes.Read_U16_BE (S.Stream, Value);
                  Op := Opcode (Value);
               end;
            end if;
         end if;
         if Is_Boundary_End (Outcome) then
            At_End_Of_Input := True;
            return Results.Success;
         elsif not Results.Succeeded (Outcome) then
            return Outcome;
         end if;
      end if;

      Event.Op := Op;
      Event.Reserved := Opcodes.Is_Reserved (Op);
      Outcome := Claim_Ordinal (S, Event.Ordinal);
      if Results.Succeeded (Outcome) then
         S.Data_Start := Picture_Stream.Picture_Offset (S.Stream);
         Outcome := Consume_Data (S, Event);
         Event.Data_Length := Picture_Stream.Picture_Offset (S.Stream) - S.Data_Start;
      end if;
      if not Results.Succeeded (Outcome) then
         declare
            Item : Errors.Error := Outcome.First_Error;
         begin
            if not Item.Context.Has_Opcode then
               Item.Context.Op := Op;
               Item.Context.Has_Opcode := True;
               Item.Context.Ordinal := Event.Ordinal;
            end if;
            return Results.Failure (Item);
         end;
      end if;
      if Event.Reserved then
         Warn (S, Errors.Reserved_Opcode_Skipped, Errors.Informational,
               (Source => Event.Offset, Op => Op, Has_Opcode => True, Ordinal => Event.Ordinal,
                Actual => Event.Data_Length, others => <>));
      end if;
      return Results.Success;
   end Next;
end Pictlib.Internal.Opcode_Reader;
