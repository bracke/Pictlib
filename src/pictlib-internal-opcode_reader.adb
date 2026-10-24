with Interfaces;
with Pictlib.Errors;
with Pictlib.Internal.Bytes;
with Pictlib.Internal.Drawing;
with Pictlib.Internal.Metadata_Store;
with Pictlib.Internal.Picture_Stream;
with Pictlib.Internal.Pixmaps;
with Pictlib.Internal.Region_Reader;
with Pictlib.Internal.Regions;
with Pictlib.Metadata;
with Pictlib.Opcodes;
with Pictlib.Streams;

package body Pictlib.Internal.Opcode_Reader is
   use type Interfaces.Unsigned_16;
   use type Errors.Error_Code;
   use type Opcodes.Data_Rule;

   subtype Session is Sessions.Session;

   function Item_For (Kind : Metadata.Item_Kind; Event : Pictures.Opcode_Event) return Metadata.Item_Info is
     ((Kind => Kind, Ordinal => Event.Ordinal, Offset => Event.Offset, Op => Event.Op, others => <>));

   function Skip_Polygon (S : in out Session) return Results.Result is
      Points : Natural;
      Outcome : constant Results.Result := Sessions.Read_Polygon_Size (S, Points);
   begin
      if not Results.Succeeded (Outcome) then
         return Outcome;
      end if;
      return Sessions.Skip_Data (S, Sessions.Smallest_Polygon - 2 + 4 * Byte_Count (Points));
   end Skip_Polygon;

   function Skip_Pixel_Pattern (S : in out Session) return Results.Result is
      Pattern_Type : Interfaces.Unsigned_16;
      --  The rows are laid out, and checked, as rendering decodes them, so both agree where the opcode ends.
      Header : Pixmaps.Bits_Header;
      Outcome : Results.Result := Sessions.Read_Word (S, Pattern_Type);
   begin
      if Results.Succeeded (Outcome) then
         Outcome := Sessions.Skip_Data (S, 8);  --  pat1Data, the 1-bit fallback pattern
      end if;
      if not Results.Succeeded (Outcome) then
         return Outcome;
      end if;
      case Pattern_Type is
         when 1 =>
            Outcome := Pixmaps.Read_Pattern_Header (S, Header, For_Decoding => False);
            if not Results.Succeeded (Outcome) then
               return Outcome;
            end if;
            return Pixmaps.Skip_Pixels (S, Header);
         when 2 =>
            return Sessions.Skip_Data (S, 6);  --  an RGB color to dither
         when others =>
            return Sessions.Fail (S, Errors.Pattern_Invalid, 2, Byte_Count (Pattern_Type));
      end case;
   end Skip_Pixel_Pattern;

   --  A bits opcode enumerated: its header read, its rows skipped. Rendering copies it in Drawing instead.
   function Skip_Bits (S : in out Session; Event : Pictures.Opcode_Event) return Results.Result is
      Header : Pixmaps.Bits_Header;
      Mask : Regions.Region;
      Outcome : constant Results.Result :=
        Pixmaps.Read_Bits_Header (S, Event.Op, Header, Mask, Read_Mask => False, For_Decoding => False);
   begin
      if not Results.Succeeded (Outcome) then
         return Outcome;
      end if;
      return Pixmaps.Skip_Pixels (S, Header);
   end Skip_Bits;

   function Consume_Short_Comment (S : in out Session; Event : Pictures.Opcode_Event) return Results.Result is
      Kind : Interfaces.Unsigned_16;
      Keep : Boolean;
      Outcome : Results.Result := Sessions.Read_Word (S, Kind);
   begin
      if Results.Succeeded (Outcome) and then S.Retention.Comments then
         Outcome := Sessions.Admit_Item (S, 0, Keep);
         if Results.Succeeded (Outcome) and then Keep then
            Metadata_Store.Append
              (S.Store, (Item_For (Metadata.Short_Comment, Event) with delta Comment_Kind => Kind), [1 .. 0 => 0]);
         end if;
      end if;
      return Outcome;
   end Consume_Short_Comment;

   function Consume_Long_Comment (S : in out Session; Event : Pictures.Opcode_Event) return Results.Result is
      Kind, Size : Interfaces.Unsigned_16;
      Outcome : Results.Result := Sessions.Read_Word (S, Kind);
   begin
      if Results.Succeeded (Outcome) then
         Outcome := Sessions.Read_Word (S, Size);
      end if;
      if not Results.Succeeded (Outcome) then
         return Outcome;
      elsif S.Retention.Comments then
         return Sessions.Retain
           (S, (Item_For (Metadata.Long_Comment, Event) with delta Comment_Kind => Kind), Byte_Count (Size));
      end if;
      return Sessions.Skip_Data (S, Byte_Count (Size));
   end Consume_Long_Comment;

   --  fontName data: a font ID, then the name as a Pascal string.
   function Consume_Font_Name
     (S : in out Session;
      Event : Pictures.Opcode_Event;
      Length : Byte_Count;
      Paint : access Rendering.Painter) return Results.Result
   is
      Data : Streams.Byte_Array_Access;
      Keep : Boolean;
      Outcome : Results.Result := Sessions.Read_Payload (S, Length, Data);
   begin
      if not Results.Succeeded (Outcome) then
         return Outcome;
      end if;
      if Data'Length < 3 or else Natural (Data (3)) > Data'Length - 3 then
         Sessions.Free (Data);
         return Sessions.Reject_Or_Warn
           (S, Errors.Opcode_Length_Invalid, Errors.Data_Loss, Errors.Data_Loss,
            (Sessions.Context_Of (Event) with delta Source => 0, Expected => 3, Actual => Length));
      end if;
      declare
         Name_Length : constant Natural := Natural (Data (3));
         Font : constant Interfaces.Unsigned_16 :=
           Interfaces.Shift_Left (Interfaces.Unsigned_16 (Data (1)), 8) or Interfaces.Unsigned_16 (Data (2));
      begin
         if Paint /= null then
            Outcome := Sessions.Admit_Aggregate (S, Byte_Count (Name_Length) + Sessions.Item_Overhead_Bytes);
            if not Results.Succeeded (Outcome) then
               Sessions.Free (Data);
               return Outcome;
            end if;
            declare
               Name : String (1 .. Name_Length);
            begin
               for Index in Name'Range loop
                  Name (Index) := Character'Val (Data (3 + Index));
               end loop;
               Drawing.Register_Font_Name (Paint.all, Natural (Font), Name);
            end;
         end if;
         if S.Retention.Font_Names then
            Outcome := Sessions.Admit_Item (S, Byte_Count (Name_Length), Keep);
         else
            Keep := False;
         end if;
         if Results.Succeeded (Outcome) and then Keep then
            Metadata_Store.Append
              (S.Store, (Item_For (Metadata.Font_Name, Event) with delta Font_ID => Font), Data (4 .. 3 + Name_Length));
         end if;
      end;
      Sessions.Free (Data);
      return Outcome;
   end Consume_Font_Name;

   function Consume_Length_Prefixed
     (S : in out Session;
      Event : Pictures.Opcode_Event;
      Length : Byte_Count;
      Paint : access Rendering.Painter) return Results.Result
   is
      Outcome : constant Results.Result := Sessions.Admit_Data (S, Length);
   begin
      if not Results.Succeeded (Outcome) then
         return Outcome;
      elsif Event.Op = Opcodes.Font_Name then
         --  Its structure is checked whatever the retention policy, so the policy never changes which pictures
         --  are malformed.
         return Consume_Font_Name (S, Event, Length, Paint);
      elsif Event.Op in Opcodes.Compressed_QuickTime | Opcodes.Uncompressed_QuickTime
        and then S.Retention.QuickTime_Payloads and then Paint = null
      then
         --  Only enumeration retains QuickTime payloads; rendering skips an uncompressed one.
         return Sessions.Retain (S, Item_For (Metadata.QuickTime_Payload, Event), Length);
      elsif Event.Reserved and then S.Retention.Reserved_Payloads then
         return Sessions.Retain (S, Item_For (Metadata.Reserved_Payload, Event), Length);
      end if;
      return Sessions.Skip_Data (S, Length);
   end Consume_Length_Prefixed;

   function Consume_Text (S : in out Session; Prefix : Natural) return Results.Result is
      Count : Byte;
      Outcome : Results.Result := Sessions.Skip_Data (S, Byte_Count (Prefix));
   begin
      if Results.Succeeded (Outcome) then
         Outcome := Sessions.Read_Count_Byte (S, Count);
      end if;
      if Results.Succeeded (Outcome) then
         Outcome := Sessions.Skip_Data (S, Byte_Count (Count));
      end if;
      return Outcome;
   end Consume_Text;

   function Consume_Data
     (S : in out Session;
      Event : Pictures.Opcode_Event;
      Paint : access Rendering.Painter) return Results.Result
   is
      Rule : constant Opcodes.Length_Rule := Opcodes.Rule_For (Event.Op);
      Outcome : Results.Result;
   begin
      case Rule.Rule is
         when Opcodes.Fixed_Data =>
            if Event.Op = Opcodes.Short_Comment then
               return Consume_Short_Comment (S, Event);
            end if;
            return Sessions.Skip_Data (S, Byte_Count (Rule.Fixed_Length));
         when Opcodes.Word_Length_Data =>
            declare
               Length : Interfaces.Unsigned_16;
            begin
               Outcome := Sessions.Read_Word (S, Length);
               if Results.Succeeded (Outcome) then
                  Outcome := Consume_Length_Prefixed (S, Event, Byte_Count (Length), Paint);
               end if;
               return Outcome;
            end;
         when Opcodes.Long_Length_Data =>
            declare
               Length : Interfaces.Unsigned_32;
            begin
               Outcome := Sessions.Read_Long (S, Length);
               if Results.Succeeded (Outcome) then
                  Outcome := Consume_Length_Prefixed (S, Event, Byte_Count (Length), Paint);
               end if;
               return Outcome;
            end;
         when Opcodes.Region_Data =>
            return Region_Reader.Skip (S);
         when Opcodes.Polygon_Data =>
            return Skip_Polygon (S);
         when Opcodes.Pixel_Pattern_Data =>
            return Skip_Pixel_Pattern (S);
         when Opcodes.Text_Data =>
            return Consume_Text (S, Rule.Fixed_Length);
         when Opcodes.Long_Comment_Data =>
            return Consume_Long_Comment (S, Event);
         when Opcodes.Bits_Data =>
            return Skip_Bits (S, Event);
         when Opcodes.Version_Data =>
            return Sessions.Skip_Data (S, (if S.Version = Version_1 then 1 else 2));
         when Opcodes.End_Of_Picture =>
            return Results.Success;
      end case;
   end Consume_Data;


   function Next
     (S : in out Session;
      Event : out Pictures.Opcode_Event;
      At_End_Of_Input : out Boolean;
      Paint : access Rendering.Painter := null) return Results.Result
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
         if Sessions.Is_Boundary_End (Outcome) then
            At_End_Of_Input := True;
            return Results.Success;
         elsif not Results.Succeeded (Outcome) then
            return Outcome;
         end if;
      end if;

      Event.Op := Op;
      Event.Reserved := Opcodes.Is_Reserved (Op);
      Outcome := Sessions.Claim_Ordinal (S, Event.Ordinal);
      if Results.Succeeded (Outcome) then
         S.Data_Start := Picture_Stream.Picture_Offset (S.Stream);
         declare
            Handled : Boolean := False;
         begin
            --  Rendering, every opcode goes to Drawing first; what it leaves is skipped or retained here.
            if Paint /= null then
               Outcome := Drawing.Consume (Paint.all, S, Event, Handled);
            end if;
            if Results.Succeeded (Outcome) and then not Handled then
               Outcome := Consume_Data (S, Event, Paint);
            end if;
         end;
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
         Sessions.Warn (S, Errors.Reserved_Opcode_Skipped, Errors.Informational,
                        (Source => Event.Offset, Op => Op, Has_Opcode => True, Ordinal => Event.Ordinal,
                         Actual => Event.Data_Length, others => <>));
      end if;
      return Results.Success;
   end Next;
end Pictlib.Internal.Opcode_Reader;
