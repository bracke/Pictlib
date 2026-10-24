with Ada.Unchecked_Deallocation;
with Pictlib.Errors;
with Pictlib.Internal.PackBits;
with Pictlib.Opcodes;

package body Pictlib.Internal.Pixmaps is
   use type Interfaces.Unsigned_16;
   use type PackBits.Unpack_Status;

   --  Bytes of a PixMap after pixelSize: cmpCount, cmpSize, planeBytes, pmTable, pmReserved.
   Pixmap_Rest_Bytes : constant := 2 + 2 + 4 + 4 + 4;
   Color_Entry_Bytes : constant := 8;

   procedure Free is new Ada.Unchecked_Deallocation (Color_Row, Color_Row_Access);

   function Read_Pixmap_Tail (S : in out Sessions.Session; Fields : out Pixmap_Fields) return Results.Result is
      Version, Pack, Pixel_Type, Pixel_Size, Component_Count : Interfaces.Unsigned_16 := 0;
      Ignored : Interfaces.Unsigned_32;
      Outcome : Results.Result := Sessions.Read_Word (S, Version);
   begin
      Fields := (others => <>);
      if Results.Succeeded (Outcome) then
         Outcome := Sessions.Read_Word (S, Pack);
      end if;
      for Index in 1 .. 3 loop  --  packSize, hRes, vRes
         exit when not Results.Succeeded (Outcome);
         Outcome := Sessions.Read_Long (S, Ignored);
      end loop;
      if Results.Succeeded (Outcome) then
         Outcome := Sessions.Read_Word (S, Pixel_Type);
      end if;
      if Results.Succeeded (Outcome) then
         Outcome := Sessions.Read_Word (S, Pixel_Size);
      end if;
      if Results.Succeeded (Outcome) then
         Outcome := Sessions.Read_Word (S, Component_Count);
      end if;
      if Results.Succeeded (Outcome) then
         Outcome := Sessions.Skip_Data (S, Pixmap_Rest_Bytes - 2);
      end if;
      if not Results.Succeeded (Outcome) then
         return Outcome;
      elsif Pixel_Size not in 1 | 2 | 4 | 8 | 16 | 32 then
         return Sessions.Fail (S, Errors.Pixmap_Invalid, 32, Byte_Count (Pixel_Size));
      elsif Pack > Interfaces.Unsigned_16 (Pack_Type'Last) then
         return Sessions.Fail (S, Errors.Pixmap_Invalid, Byte_Count (Pack_Type'Last), Byte_Count (Pack));
      end if;
      Fields :=
        (Pack => Natural (Pack), Pixel_Size => Natural (Pixel_Size), Component_Count => Natural (Component_Count));
      return Results.Success;
   end Read_Pixmap_Tail;

   function Read_Table_Header
     (S : in out Sessions.Session;
      Flags : out Interfaces.Unsigned_16;
      Entries : out Natural) return Results.Result
   is
      Seed : Interfaces.Unsigned_32;
      Size : Interfaces.Unsigned_16 := 0;
      Outcome : Results.Result := Sessions.Read_Long (S, Seed);
   begin
      Flags := 0;
      Entries := 0;
      if Results.Succeeded (Outcome) then
         Outcome := Sessions.Read_Word (S, Flags);
      end if;
      if Results.Succeeded (Outcome) then
         Outcome := Sessions.Read_Word (S, Size);
      end if;
      if not Results.Succeeded (Outcome) then
         return Outcome;
      elsif Size = 16#FFFF# then
         --  ctSize is the entry count minus one; -1 is an empty table.
         return Results.Success;
      elsif Size > 255 then
         return Sessions.Fail (S, Errors.Color_Table_Invalid, 255, Byte_Count (Size));
      end if;
      Entries := Natural (Size) + 1;
      return Results.Success;
   end Read_Table_Header;

   function Skip_Color_Table (S : in out Sessions.Session) return Results.Result is
      Flags : Interfaces.Unsigned_16;
      Entries : Natural;
      Outcome : constant Results.Result := Read_Table_Header (S, Flags, Entries);
   begin
      if not Results.Succeeded (Outcome) then
         return Outcome;
      end if;
      return Sessions.Skip_Data (S, Byte_Count (Entries) * Color_Entry_Bytes);
   end Skip_Color_Table;

   function Read_Color_Table (S : in out Sessions.Session; Table : out Color_Table) return Results.Result is
      Device : constant Interfaces.Unsigned_16 := 16#8000#;
      Flags : Interfaces.Unsigned_16;
      Entries : Natural;
      Outcome : Results.Result := Read_Table_Header (S, Flags, Entries);
   begin
      Table := (others => <>);
      if not Results.Succeeded (Outcome) then
         return Outcome;
      end if;
      for Position in 0 .. Entries - 1 loop
         declare
            Item : Streams.Byte_Array (1 .. Color_Entry_Bytes);
            Value : Interfaces.Unsigned_16;
            Index : Natural;
         begin
            Outcome := Sessions.Read_Into (S, Item);
            if not Results.Succeeded (Outcome) then
               return Outcome;
            end if;
            Value := Interfaces.Shift_Left (Interfaces.Unsigned_16 (Item (1)), 8) or Interfaces.Unsigned_16 (Item (2));
            Index := (if (Flags and Device) /= 0 then Position else Natural (Value));
            if Index > 255 then
               if not Sessions.Is_Lenient (S) then
                  return Sessions.Fail (S, Errors.Color_Table_Invalid, 255, Byte_Count (Index));
               end if;
               Sessions.Warn
                 (S, Errors.Recovery_Applied, Errors.Recovery, (Actual => Byte_Count (Index), others => <>));
            else
               --  The high byte of each 16-bit component.
               Table.Colors (Index) := (Red => Item (3), Green => Item (5), Blue => Item (7));
               Table.Defined (Index) := True;
            end if;
         end;
      end loop;
      return Results.Success;
   end Read_Color_Table;

   function Decide_Layout (S : Sessions.Session; Header : in out Bits_Header; For_Decoding : Boolean)
     return Results.Result
   is
      Packed : constant Boolean := Header.Op not in Opcodes.Bits_Rect | Opcodes.Bits_Region;
      Depth : constant Natural := Header.Fields.Pixel_Size;
      Pack : constant Natural := Header.Fields.Pack;

      function Invalid (Expected, Actual : Natural) return Results.Result is
        (Sessions.Fail (S, Errors.Pixmap_Invalid, Byte_Count (Expected), Byte_Count (Actual)));
   begin
      if not Header.Is_Pixmap then
         Header.Encoding := Bitmap_Bits;
      elsif Depth <= 8 then
         Header.Encoding := Indexed_Bits;
      elsif Depth = 16 then
         Header.Encoding := RGB_555;
      else
         Header.Encoding := XRGB_Chunky;
      end if;

      --  The pack types and component counts a direct pixmap allows, whether or not its rows are packed.
      if Header.Is_Pixmap and then Depth = 16 and then Pack not in 0 | 1 | 3 then
         return Invalid (3, Pack);
      elsif Header.Is_Pixmap and then Depth = 32 and then Pack not in 0 | 1 | 2 | 4 then
         return Invalid (4, Pack);
      elsif Header.Is_Pixmap and then Depth = 32 and then Header.Fields.Component_Count not in 3 | 4 then
         return Invalid (3, Header.Fields.Component_Count);
      end if;

      if not Packed or else Header.Row_Bytes < Smallest_Packed_Row_Bytes or else (Header.Is_Pixmap and then Pack = 1)
      then
         Header.Layout := Unpacked;
         Header.Raw_Length := Header.Row_Bytes;
         Header.Unpacked_Length := Header.Row_Bytes;
      elsif Header.Is_Pixmap and then Pack = 2 then
         --  32-bit pixels with the pad byte dropped, unpacked.
         if Depth /= 32 then
            return Invalid (32, Depth);
         end if;
         Header.Layout := Unpacked;
         Header.Encoding := RGB_Triplets;
         Header.Raw_Length := 3 * Header.Width;
         Header.Unpacked_Length := Header.Raw_Length;
      elsif Depth = 16 then
         if Pack not in 0 | 3 then
            return Invalid (3, Pack);
         elsif Header.Row_Bytes mod 2 /= 0 then
            return Invalid (Header.Row_Bytes + 1, Header.Row_Bytes);
         end if;
         Header.Layout := Packed_Words;
         Header.Unpacked_Length := Header.Row_Bytes;
      elsif Depth = 32 then
         if Pack not in 0 | 4 then
            return Invalid (4, Pack);
         end if;
         Header.Layout := Packed_Bytes;
         Header.Encoding := Planar;
         --  The planes are counted from cmpCount, so where the opcode ends depends on it too.
         if Header.Fields.Component_Count not in 3 | 4 then
            return Invalid (3, Header.Fields.Component_Count);
         end if;
         Header.Unpacked_Length := Header.Fields.Component_Count * Header.Width;
      else
         Header.Layout := Packed_Bytes;
         Header.Unpacked_Length := Header.Row_Bytes;
      end if;

      --  A chunky row must hold the bounds width.
      if For_Decoding and then Header.Encoding not in RGB_Triplets | Planar
        and then Long_Long_Integer (Header.Unpacked_Length) * 8
                 < Long_Long_Integer (Header.Width) * Long_Long_Integer (Depth)
      then
         return Invalid ((Header.Width * Depth + 7) / 8, Header.Unpacked_Length);
      end if;
      return Results.Success;
   end Decide_Layout;

   function Read_Bits_Header
     (S : in out Sessions.Session;
      Op : Opcode;
      Header : out Bits_Header;
      Mask : out Regions.Region;
      Read_Mask : Boolean;
      For_Decoding : Boolean) return Results.Result
   is
      Direct : constant Boolean := Op in Opcodes.Direct_Bits_Rect | Opcodes.Direct_Bits_Region;
      Raw_Row_Bytes : Interfaces.Unsigned_16 := 0;
      Outcome : Results.Result := Results.Success;
   begin
      Header := (Op => Op, others => <>);
      Header.Masked := Op in Opcodes.Bits_Region | Opcodes.Pack_Bits_Region | Opcodes.Direct_Bits_Region;
      Mask := Regions.Rectangle ((others => 0));
      if Direct then
         Outcome := Sessions.Skip_Data (S, 4);  --  baseAddr
      end if;
      if Results.Succeeded (Outcome) then
         Outcome := Sessions.Read_Word (S, Raw_Row_Bytes);
      end if;
      if Results.Succeeded (Outcome) then
         Outcome := Sessions.Read_Bounds (S, Header.Bounds);
      end if;
      if not Results.Succeeded (Outcome) then
         return Outcome;
      end if;

      Header.Is_Pixmap := Direct or else (Raw_Row_Bytes and 16#8000#) /= 0;
      Header.Row_Bytes :=
        Natural (Raw_Row_Bytes and (if Header.Is_Pixmap then Pixmap_Row_Bytes_Mask else Bitmap_Row_Bytes_Mask));
      if Header.Is_Pixmap then
         Outcome := Read_Pixmap_Tail (S, Header.Fields);
         if Results.Succeeded (Outcome) then
            if Direct and then Header.Fields.Pixel_Size not in 16 | 32 then
               Outcome := Sessions.Fail (S, Errors.Pixmap_Invalid, 32, Byte_Count (Header.Fields.Pixel_Size));
            elsif not Direct and then Header.Fields.Pixel_Size > 8 then
               Outcome := Sessions.Fail (S, Errors.Pixmap_Invalid, 8, Byte_Count (Header.Fields.Pixel_Size));
            elsif not Direct then
               Outcome :=
                 (if For_Decoding then Read_Color_Table (S, Header.Table) else Skip_Color_Table (S));
            end if;
         end if;
      end if;
      if Results.Succeeded (Outcome) then
         Outcome := Sessions.Read_Bounds (S, Header.Source);
      end if;
      if Results.Succeeded (Outcome) then
         Outcome := Sessions.Read_Bounds (S, Header.Destination);
      end if;
      if Results.Succeeded (Outcome) then
         Outcome := Sessions.Read_Word (S, Header.Mode);
      end if;
      if Results.Succeeded (Outcome) and then Header.Masked then
         Outcome := (if Read_Mask then Regions.Read (S, Mask) else Regions.Skip (S));
      end if;
      if Results.Succeeded (Outcome) then
         Outcome := Sessions.Extent (S, Header.Bounds, Header.Width, Header.Height);
      end if;
      if Results.Succeeded (Outcome) then
         Outcome := Decide_Layout (S, Header, For_Decoding);
      end if;
      return Outcome;
   end Read_Bits_Header;

   function Skip_Pixels (S : in out Sessions.Session; Header : Bits_Header) return Results.Result is
     (if Header.Layout = Unpacked
      then Sessions.Skip_Rows (S, Header.Row_Bytes, Header.Height, False, Byte_Count (Header.Raw_Length))
      else Sessions.Skip_Rows (S, Header.Row_Bytes, Header.Height, True, 0));

   function Stored_Length (Header : Bits_Header) return Natural is
     (if Header.Layout = Unpacked then Header.Raw_Length
      elsif Header.Row_Bytes > Byte_Count_Row_Bytes then 16#FFFF# else 16#FF#);

   function Unpacked_Length (Header : Bits_Header) return Natural is
     (if Header.Layout = Unpacked then 0 else Header.Unpacked_Length);

   function Buffer_Bytes (Header : Bits_Header) return Byte_Count is
     (Byte_Count (Stored_Length (Header)) + Byte_Count (Unpacked_Length (Header)) + 3 * Byte_Count (Header.Width));

   function Read_Pattern_Header
     (S : in out Sessions.Session;
      Header : out Bits_Header;
      For_Decoding : Boolean) return Results.Result
   is
      Raw_Row_Bytes : Interfaces.Unsigned_16 := 0;
      Outcome : Results.Result := Sessions.Read_Word (S, Raw_Row_Bytes);
   begin
      Header := (Op => Opcodes.Pack_Bits_Rect, Is_Pixmap => True, others => <>);
      if Results.Succeeded (Outcome) then
         Header.Row_Bytes := Natural (Raw_Row_Bytes and Pixmap_Row_Bytes_Mask);
         Outcome := Sessions.Read_Bounds (S, Header.Bounds);
      end if;
      if Results.Succeeded (Outcome) then
         Outcome := Read_Pixmap_Tail (S, Header.Fields);
      end if;
      if Results.Succeeded (Outcome) and then Header.Fields.Pixel_Size > 8 then
         Outcome := Sessions.Fail (S, Errors.Pattern_Invalid, 8, Byte_Count (Header.Fields.Pixel_Size));
      end if;
      if Results.Succeeded (Outcome) then
         Outcome := (if For_Decoding then Read_Color_Table (S, Header.Table) else Skip_Color_Table (S));
      end if;
      if Results.Succeeded (Outcome) then
         Outcome := Sessions.Extent (S, Header.Bounds, Header.Width, Header.Height);
      end if;
      if Results.Succeeded (Outcome) and then (Header.Width = 0 or else Header.Height = 0) then
         Outcome := Sessions.Fail (S, Errors.Pattern_Invalid, 1, 0);
      end if;
      if Results.Succeeded (Outcome) then
         Outcome := Decide_Layout (S, Header, For_Decoding);
      end if;
      return Outcome;
   end Read_Pattern_Header;

   function Start
     (S : in out Sessions.Session;
      Decoder : in out Row_Decoder;
      Header : Bits_Header;
      Extra : Byte_Count := 0) return Results.Result
   is
      Buffers : constant Byte_Count := Buffer_Bytes (Header);
      Total : constant Byte_Count := (if Extra > Byte_Count'Last - Buffers then Byte_Count'Last else Buffers + Extra);
   begin
      Finish (Decoder);
      declare
         Admission : constant Results.Result :=
           Sessions.Admit_Allocation (S, Total);
      begin
         if not Results.Succeeded (Admission) then
            return Admission;
         end if;
      end;
      Decoder.Header := Header;
      Decoder.Stored := new Streams.Byte_Array (1 .. Stored_Length (Header));
      Decoder.Unpacked := new Streams.Byte_Array (1 .. Unpacked_Length (Header));
      Decoder.Colors := new Color_Row (0 .. Header.Width - 1);
      Decoder.Bad_Index_Reported := False;
      return Results.Success;
   end Start;

   function Expand_5 (Value : Interfaces.Unsigned_16) return Byte is
     (Byte (Interfaces.Shift_Left (Value, 3) or Interfaces.Shift_Right (Value, 2)));

   function Convert
     (S : in out Sessions.Session;
      Decoder : in out Row_Decoder;
      Data : Streams.Byte_Array;
      Row : Natural) return Results.Result
   is
      Header : Bits_Header renames Decoder.Header;
      Width : constant Natural := Header.Width;
      First : constant Positive := Data'First;
   begin
      case Header.Encoding is
         when Bitmap_Bits | Indexed_Bits =>
            declare
               Depth : constant Natural := Header.Fields.Pixel_Size;
               Mask : constant Natural := 2 ** Depth - 1;
            begin
               for X in 0 .. Width - 1 loop
                  declare
                     Bit : constant Natural := X * Depth;
                     Value : constant Natural := Natural (Data (First + Bit / 8));
                     Index : constant Natural := (Value / 2 ** (8 - Depth - Bit mod 8)) mod (Mask + 1);
                  begin
                     if Header.Encoding = Bitmap_Bits then
                        Decoder.Colors (X) := (if Index = 1 then Images.Black else Images.White);
                     elsif Header.Table.Defined (Index) then
                        Decoder.Colors (X) := Header.Table.Colors (Index);
                     elsif not Sessions.Is_Lenient (S) then
                        return Results.Failure
                          (Errors.Make
                             (Errors.Color_Table_Invalid,
                              (Source => S.Stream.Offset, Row => Row_Index (Row), Actual => Byte_Count (Index),
                               others => <>)));
                     else
                        if not Decoder.Bad_Index_Reported then
                           Sessions.Warn (S, Errors.Recovery_Applied, Errors.Recovery,
                                          (Row => Row_Index (Row), Actual => Byte_Count (Index), others => <>));
                           Decoder.Bad_Index_Reported := True;
                        end if;
                        Decoder.Colors (X) := Images.Black;
                     end if;
                  end;
               end loop;
            end;
         when RGB_555 =>
            for X in 0 .. Width - 1 loop
               declare
                  Word : constant Interfaces.Unsigned_16 :=
                    Interfaces.Shift_Left (Interfaces.Unsigned_16 (Data (First + 2 * X)), 8)
                    or Interfaces.Unsigned_16 (Data (First + 2 * X + 1));
               begin
                  Decoder.Colors (X) :=
                    (Red => Expand_5 (Interfaces.Shift_Right (Word, 10) and 31),
                     Green => Expand_5 (Interfaces.Shift_Right (Word, 5) and 31),
                     Blue => Expand_5 (Word and 31));
               end;
            end loop;
         when XRGB_Chunky =>
            for X in 0 .. Width - 1 loop
               Decoder.Colors (X) := (Data (First + 4 * X + 1), Data (First + 4 * X + 2), Data (First + 4 * X + 3));
            end loop;
         when RGB_Triplets =>
            for X in 0 .. Width - 1 loop
               Decoder.Colors (X) := (Data (First + 3 * X), Data (First + 3 * X + 1), Data (First + 3 * X + 2));
            end loop;
         when Planar =>
            declare
               Red_Plane : constant Natural := (if Header.Fields.Component_Count = 4 then Width else 0);
            begin
               for X in 0 .. Width - 1 loop
                  Decoder.Colors (X) :=
                    (Data (First + Red_Plane + X), Data (First + Red_Plane + Width + X),
                     Data (First + Red_Plane + 2 * Width + X));
               end loop;
            end;
      end case;
      return Results.Success;
   end Convert;

   function Read_Row (S : in out Sessions.Session; Decoder : in out Row_Decoder; Row : Natural) return Results.Result is
      Header : constant Bits_Header := Decoder.Header;
      Outcome : Results.Result;
   begin
      if Header.Layout = Unpacked then
         Outcome := Sessions.Read_Into (S, Decoder.Stored (1 .. Header.Raw_Length));
         if Results.Succeeded (Outcome) then
            Outcome := Convert (S, Decoder, Decoder.Stored (1 .. Header.Raw_Length), Row);
         end if;
      else
         declare
            Count : Natural := 0;
            Written : Natural;
            Status : PackBits.Unpack_Status;
         begin
            if Header.Row_Bytes > Byte_Count_Row_Bytes then
               declare
                  Word : Interfaces.Unsigned_16;
               begin
                  Outcome := Sessions.Read_Word (S, Word);
                  Count := Natural (Word);
               end;
            else
               declare
                  Small : Byte;
               begin
                  Outcome := Sessions.Read_Count_Byte (S, Small);
                  Count := Natural (Small);
               end;
            end if;
            if Results.Succeeded (Outcome) then
               Outcome := Sessions.Read_Into (S, Decoder.Stored (1 .. Count));
            end if;
            if Results.Succeeded (Outcome) then
               PackBits.Unpack
                 (Decoder.Stored (1 .. Count), (if Header.Layout = Packed_Words then 2 else 1),
                  Decoder.Unpacked (1 .. Header.Unpacked_Length), Written, Status);
               --  In every mode: Recover_When_Safe turns it into a partial picture.
               if Status /= PackBits.Exact then
                  Outcome := Results.Failure
                    (Errors.Make
                       (Errors.PackBits_Invalid,
                        (Source => S.Stream.Offset, Row => Row_Index (Row),
                         Expected => Byte_Count (Header.Unpacked_Length), Actual => Byte_Count (Written),
                         others => <>)));
               end if;
            end if;
            if Results.Succeeded (Outcome) then
               Outcome := Convert (S, Decoder, Decoder.Unpacked (1 .. Header.Unpacked_Length), Row);
            end if;
         end;
      end if;
      if not Results.Succeeded (Outcome) and then Outcome.First_Error.Context.Row = 0 then
         return Results.Failure
           ((Outcome.First_Error with delta
               Context => (Outcome.First_Error.Context with delta Row => Row_Index (Row))));
      end if;
      return Outcome;
   end Read_Row;

   function Pixel (Decoder : Row_Decoder; Column : Natural) return Images.RGB_Color is (Decoder.Colors (Column));

   procedure Finish (Decoder : in out Row_Decoder) is
   begin
      Sessions.Free (Decoder.Stored);
      Sessions.Free (Decoder.Unpacked);
      Free (Decoder.Colors);
   end Finish;
end Pictlib.Internal.Pixmaps;
