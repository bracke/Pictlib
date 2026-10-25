with Pictlib.Internal.Checked_Arithmetic;
with Ada.Unchecked_Deallocation;
with Pictlib.Errors;
with Pictlib.Internal.Bytes;
with Pictlib.Internal.Failures;
with Pictlib.Internal.Region_Reader;
with Pictlib.Internal.PackBits;
with Pictlib.Opcodes;

package body Pictlib.Internal.Pixmaps is
   use type Interfaces.Unsigned_16;
   use type PackBits.Unpack_Status;

   --  Bytes of a PixMap after pixelSize: cmpCount, cmpSize, planeBytes, pmTable, pmReserved.
   Pixmap_Rest_Bytes : constant := 2 + 2 + 4 + 4 + 4;
   Color_Entry_Bytes : constant := 8;

   procedure Free is new Ada.Unchecked_Deallocation (Color_Row, Color_Row_Access);

   --  Read pixmap tail.
   --  @param S Session positioned after a PixMap's rowBytes and bounds.
   --  @param Fields Pack type, pixel size and component count.
   --  @return Success, or Pixmap_Invalid for an unknown pixel size or pack type.
   function Read_Pixmap_Tail (S : in out Sessions.Session; Fields : out Pixmap_Fields) return Results.Result;
   --  Read color table.
   --  @param S Session positioned at a color table.
   --  @param Table The colors it defines, reduced to 8 bits.
   --  @return Success, or Color_Table_Invalid for more than 256 entries or (strictly) an index above 255.
   function Read_Color_Table (S : in out Sessions.Session; Table : out Color_Table) return Results.Result;
   --  Skip color table.
   --  @param S Session positioned at a color table.
   --  @return Success, or Color_Table_Invalid for more than 256 entries.
   function Skip_Color_Table (S : in out Sessions.Session) return Results.Result;

   --  Decide layout.
   --  @param S Session, for diagnostics.
   --  @param Header A header whose Op, Is_Pixmap, Row_Bytes, Width and Fields are set; its row layout and pixel
   --  encoding are filled in.
   --  @param For_Decoding True to also check that rows cover the width, as decoding needs.
   --  @return Success, or Pixmap_Invalid when depth, pack type, components and row length disagree.
   function Decide_Layout (S : Sessions.Session; Header : in out Bits_Header; For_Decoding : Boolean)
     return Results.Result;

   --  Read packed count: the byte count before a packed row, a byte when Row_Bytes is at most 250, else a word.
   --  @param S Session positioned at the count.
   --  @param Row_Bytes The pixmap's row length.
   --  @param Count The packed row's length.
   --  @return Operation result.
   function Read_Packed_Count (S : in out Sessions.Session; Row_Bytes : Natural; Count : out Natural)
     return Results.Result is
   begin
      if Row_Bytes > Byte_Count_Row_Bytes then
         declare
            Word : Interfaces.Unsigned_16;
            Outcome : constant Results.Result := Sessions.Read_Word (S, Word);
         begin
            Count := Natural (Word);
            return Outcome;
         end;
      end if;
      declare
         Small : Byte;
         Outcome : constant Results.Result := Sessions.Read_Count_Byte (S, Small);
      begin
         Count := Natural (Small);
         return Outcome;
      end;
   end Read_Packed_Count;

   --  Skip rows: unpacked rows of Raw_Row_Length bytes, or rows each prefixed by its packed count.
   --  A pixmap's extent: Pixmap_Invalid for inverted bounds.
   function Extent (S : Sessions.Session; Bounds : Geometry.Rect; Width, Height : out Natural) return Results.Result is
   begin
      Width := 0;
      Height := 0;
      if Geometry.Width (Bounds) < 0 or else Geometry.Height (Bounds) < 0 then
         return Sessions.Fail (S, Errors.Pixmap_Invalid);
      end if;
      Width := Geometry.Width (Bounds);
      Height := Geometry.Height (Bounds);
      return Results.Success;
   end Extent;

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
            Value := Bytes.Word_At (Item, 1);
            Index := (if (Flags and Device) /= 0 then Position else Natural (Value));
            if Index > 255 then
               --  Leniently the entry is dropped.
               declare
                  Outcome : constant Results.Result :=
                    Sessions.Reject_Or_Warn
                      (S, Errors.Color_Table_Invalid, Errors.Recovery_Applied, Errors.Recovery,
                       (Expected => 255, Actual => Byte_Count (Index), others => <>));
               begin
                  if not Results.Succeeded (Outcome) then
                     return Outcome;
                  end if;
               end;
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

      --  The pack types and component counts each depth allows, whether or not its rows are packed: an indexed
      --  pixmap is packed by default or not at all.
      if Header.Is_Pixmap and then Depth <= 8 and then Pack not in 0 | 1 then
         return Invalid (1, Pack);
      elsif Header.Is_Pixmap and then Depth = 16 and then Pack not in 0 | 1 | 3 then
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
         --  32-bit pixels with the pad byte dropped, unpacked: the checks above leave no other depth.
         Header.Layout := Unpacked;
         Header.Encoding := RGB_Triplets;
         Header.Raw_Length := 3 * Header.Width;
         Header.Unpacked_Length := Header.Raw_Length;
      elsif Depth = 16 then
         --  Pack type 0 or 3: the checks above leave no other.
         if Header.Row_Bytes mod 2 /= 0 then
            return Invalid (Header.Row_Bytes + 1, Header.Row_Bytes);
         end if;
         Header.Layout := Packed_Words;
         Header.Unpacked_Length := Header.Row_Bytes;
      elsif Depth = 32 then
         --  Pack type 0 or 4, with 3 or 4 components, as checked above. The planes are counted from cmpCount,
         --  so where the opcode ends depends on it too.
         Header.Layout := Packed_Bytes;
         Header.Encoding := Planar;
         Header.Unpacked_Length := Planar_Row_Length (Header.Fields.Component_Count, Header.Width);
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

   --  A PixMap's fields after its bounds: the PixMap tail, its depth checked, and an indexed pixmap's color table,
   --  read or skipped. A depth the opcode does not allow is Code.
   function Read_Pixmap_Fields
     (S : in out Sessions.Session;
      Header : in out Bits_Header;
      Direct : Boolean;
      Code : Errors.Error_Code;
      For_Decoding : Boolean) return Results.Result
   is
      Outcome : constant Results.Result := Read_Pixmap_Tail (S, Header.Fields);
   begin
      if not Results.Succeeded (Outcome) then
         return Outcome;
      elsif Direct and then Header.Fields.Pixel_Size not in 16 | 32 then
         return Sessions.Fail (S, Code, 32, Byte_Count (Header.Fields.Pixel_Size));
      elsif not Direct and then Header.Fields.Pixel_Size > 8 then
         return Sessions.Fail (S, Code, 8, Byte_Count (Header.Fields.Pixel_Size));
      elsif Direct then
         return Outcome;
      end if;
      return (if For_Decoding then Read_Color_Table (S, Header.Table) else Skip_Color_Table (S));
   end Read_Pixmap_Fields;

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

      Header.Is_Pixmap := Direct or else (Raw_Row_Bytes and Pixmap_Flag) /= 0;
      Header.Row_Bytes :=
        Natural (Raw_Row_Bytes and (if Header.Is_Pixmap then Pixmap_Row_Bytes_Mask else Bitmap_Row_Bytes_Mask));
      if Header.Is_Pixmap then
         Outcome := Read_Pixmap_Fields (S, Header, Direct, Errors.Pixmap_Invalid, For_Decoding);
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
         Outcome := (if Read_Mask then Region_Reader.Read (S, Mask) else Region_Reader.Skip (S));
      end if;
      if Results.Succeeded (Outcome) then
         Outcome := Extent (S, Header.Bounds, Header.Width, Header.Height);
      end if;
      if Results.Succeeded (Outcome) then
         Outcome := Decide_Layout (S, Header, For_Decoding);
      end if;
      return Outcome;
   end Read_Bits_Header;

   function Skip_Pixels (S : in out Sessions.Session; Header : Bits_Header) return Results.Result is
      Outcome : Results.Result;
      Count : Natural;
   begin
      if Header.Layout = Unpacked then
         --  A saturated product is refused by the per-opcode budget.
         return Sessions.Skip_Data
           (S, Checked_Arithmetic.Saturating_Multiply (Byte_Count (Header.Raw_Length), Byte_Count (Header.Height)));
      end if;
      for Row in 0 .. Header.Height - 1 loop
         Outcome := Read_Packed_Count (S, Header.Row_Bytes, Count);
         if Results.Succeeded (Outcome) then
            Outcome := Sessions.Skip_Data (S, Byte_Count (Count));
         end if;
         if not Results.Succeeded (Outcome) then
            return Failures.At_Row (Outcome, Row);
         end if;
      end loop;
      return Results.Success;
   end Skip_Pixels;

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
         Outcome := Read_Pixmap_Fields (S, Header, False, Errors.Pattern_Invalid, For_Decoding);
      end if;
      if Results.Succeeded (Outcome) then
         Outcome := Extent (S, Header.Bounds, Header.Width, Header.Height);
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
      Total : constant Byte_Count := Checked_Arithmetic.Saturating_Add (Buffers, Extra);
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
                     else
                        --  Leniently black, reported once per opcode.
                        if not Decoder.Bad_Index_Reported then
                           declare
                              Verdict : constant Results.Result := Sessions.Reject_Or_Warn
                                (S, Errors.Color_Table_Invalid, Errors.Recovery_Applied, Errors.Recovery,
                                 (Row => Row_Index (Row), Actual => Byte_Count (Index), others => <>));
                           begin
                              if not Results.Succeeded (Verdict) then
                                 return Verdict;
                              end if;
                           end;
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
                  Word : constant Interfaces.Unsigned_16 := Bytes.Word_At (Data, First + 2 * X);
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
               Components : constant Natural := Header.Fields.Component_Count;
               Red : constant Natural := First + Plane_Offset (Red_Plane, Components, Width);
               Green : constant Natural := First + Plane_Offset (Green_Plane, Components, Width);
               Blue : constant Natural := First + Plane_Offset (Blue_Plane, Components, Width);
            begin
               for X in 0 .. Width - 1 loop
                  Decoder.Colors (X) := (Data (Red + X), Data (Green + X), Data (Blue + X));
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
            Outcome := Read_Packed_Count (S, Header.Row_Bytes, Count);
            if Results.Succeeded (Outcome) then
               Outcome := Sessions.Read_Into (S, Decoder.Stored (1 .. Count));
            end if;
            if Results.Succeeded (Outcome) then
               PackBits.Unpack
                 (Decoder.Stored (1 .. Count), (if Header.Layout = Packed_Words then 2 else 1),
                  Decoder.Unpacked (1 .. Header.Unpacked_Length), Written, Status);
               --  In every mode: Recover_When_Safe turns it into a partial picture.
               if Status /= PackBits.Exact then
                  Outcome := Sessions.Fail
                    (S, Errors.PackBits_Invalid, Byte_Count (Header.Unpacked_Length), Byte_Count (Written));
               end if;
            end if;
            if Results.Succeeded (Outcome) then
               Outcome := Convert (S, Decoder, Decoder.Unpacked (1 .. Header.Unpacked_Length), Row);
            end if;
         end;
      end if;
      return Failures.At_Row (Outcome, Row);
   end Read_Row;

   function Pixel (Decoder : Row_Decoder; Column : Natural) return Images.RGB_Color is (Decoder.Colors (Column));

   procedure Finish (Decoder : in out Row_Decoder) is
   begin
      Bytes.Free (Decoder.Stored);
      Bytes.Free (Decoder.Unpacked);
      Free (Decoder.Colors);
   end Finish;
end Pictlib.Internal.Pixmaps;
