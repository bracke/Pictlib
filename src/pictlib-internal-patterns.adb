with Interfaces;
with Pictlib.Errors;
with Pictlib.Internal.Pixmaps;
with Pictlib.Opcodes;
with Pictlib.Streams;

package body Pictlib.Internal.Patterns is
   use type Interfaces.Unsigned_16;

   function From_Bits (Rows : Bit_Rows) return Pattern is ((Kind => Bit_Pattern, Bits => Rows, others => <>));

   function Kind (Item : Pattern) return Pattern_Kind is (Item.Kind);

   function Sample (Item : Pattern; X, Y : Integer) return Images.RGB_Color is
   begin
      case Item.Kind is
         when Bit_Pattern =>
            declare
               Row : constant Natural := Natural (Item.Bits (Y mod 8));
               Bit : constant Natural := (Row / 2 ** (7 - X mod 8)) mod 2;
            begin
               return (if Bit = 1 then Images.Black else Images.White);
            end;
         when Solid_Color =>
            return Item.Color;
         when Color_Pattern =>
            return Item.Tile ((Y mod Item.Height) * Item.Width + X mod Item.Width);
      end case;
   end Sample;

   function Uniform (Item : Pattern; Color : out Images.RGB_Color) return Boolean is
   begin
      Color := Sample (Item, 0, 0);
      case Item.Kind is
         when Bit_Pattern =>
            return (for all Row of Item.Bits => Row = Item.Bits (0) and then Row in 0 | 16#FF#);
         when Solid_Color =>
            return True;
         when Color_Pattern =>
            return False;
      end case;
   end Uniform;

   function Read_Bit_Pattern (S : in out Sessions.Session; Item : out Pattern) return Results.Result is
      Data : Streams.Byte_Array (1 .. 8);
      Outcome : constant Results.Result := Sessions.Read_Into (S, Data);
   begin
      Item := (others => <>);
      if Results.Succeeded (Outcome) then
         for Row in Bit_Rows'Range loop
            Item.Bits (Row) := Data (Row + 1);
         end loop;
      end if;
      return Outcome;
   end Read_Bit_Pattern;

   --  A type 1 PixPat: rowBytes, bounds, the PixMap tail, a color table, then rows packed as PackBitsRect packs
   --  them.
   function Read_Color_Tile
     (S : in out Sessions.Session;
      Item : in out Pattern;
      Allowance : Pixel_Count;
      Work : in out Pixel_Count) return Results.Result
   is
      Raw_Row_Bytes : Interfaces.Unsigned_16 := 0;
      Header : Pixmaps.Bits_Header;
      Decoder : Pixmaps.Row_Decoder;
      Outcome : Results.Result := Sessions.Read_Word (S, Raw_Row_Bytes);
   begin
      Header.Op := Opcodes.Pack_Bits_Rect;
      Header.Is_Pixmap := True;
      Header.Row_Bytes := Natural (Raw_Row_Bytes and 16#3FFF#);
      if Results.Succeeded (Outcome) then
         Outcome := Sessions.Read_Bounds (S, Header.Bounds);
      end if;
      if Results.Succeeded (Outcome) then
         Outcome := Pixmaps.Read_Pixmap_Tail (S, Header.Fields);
      end if;
      if Results.Succeeded (Outcome) and then Header.Fields.Pixel_Size > 8 then
         Outcome := Sessions.Fail (S, Errors.Pattern_Invalid, 8, Byte_Count (Header.Fields.Pixel_Size));
      end if;
      if Results.Succeeded (Outcome) then
         Outcome := Pixmaps.Read_Color_Table (S, Header.Table);
      end if;
      if Results.Succeeded (Outcome) then
         Outcome := Sessions.Extent (S, Header.Bounds, Header.Width, Header.Height);
      end if;
      if Results.Succeeded (Outcome) and then (Header.Width = 0 or else Header.Height = 0) then
         Outcome := Sessions.Fail (S, Errors.Pattern_Invalid, 1, 0);
      end if;
      --  The tile grows with the rows that arrive, so a short picture holds little; while it grows it can hold
      --  its old and new storage at once, twice its final size.
      if Results.Succeeded (Outcome)
        and then 6 * Byte_Count (Header.Width) * Byte_Count (Header.Height) > S.Budget.Max_Allocation_Bytes
      then
         Outcome := Sessions.Over_Limit
           (S, Allocation_Byte_Limit, S.Budget.Max_Allocation_Bytes,
            6 * Byte_Count (Header.Width) * Byte_Count (Header.Height));
      end if;
      if Results.Succeeded (Outcome) then
         Outcome := Pixmaps.Decide_Layout (S, Header, For_Decoding => True);
      end if;
      if Results.Succeeded (Outcome) then
         Outcome := Pixmaps.Start (S, Decoder, Header);
      end if;
      if not Results.Succeeded (Outcome) then
         return Outcome;
      end if;
      Item.Kind := Color_Pattern;
      Item.Width := Header.Width;
      Item.Height := Header.Height;
      Item.Tile.Clear;
      for Row in 0 .. Header.Height - 1 loop
         --  Decoding a row is drawing work, like converting a copied row.
         if Pixel_Count (Header.Width + 1) > Allowance - Pixel_Count'Min (Work, Allowance) then
            Outcome := Sessions.Over_Limit
              (S, Drawing_Work_Limit, Byte_Count (S.Budget.Max_Drawing_Work),
               Byte_Count (S.Budget.Max_Drawing_Work - Pixel_Count'Min (Allowance, S.Budget.Max_Drawing_Work))
               + Byte_Count (Work) + Byte_Count (Header.Width + 1));
            exit;
         end if;
         Work := Work + Pixel_Count (Header.Width + 1);
         Outcome := Pixmaps.Read_Row (S, Decoder, Row);
         exit when not Results.Succeeded (Outcome);
         declare
            use type Ada.Containers.Count_Type;
            Length : constant Ada.Containers.Count_Type := Item.Tile.Length;
            Width : constant Ada.Containers.Count_Type := Ada.Containers.Count_Type (Header.Width);
         begin
            if Item.Tile.Capacity < Length + Width then
               Item.Tile.Reserve_Capacity
                 (Ada.Containers.Count_Type'Min
                    (Ada.Containers.Count_Type (Header.Width) * Ada.Containers.Count_Type (Header.Height),
                     Ada.Containers.Count_Type'Max (2 * Length, Length + Width)));
            end if;
         end;
         for Column in 0 .. Header.Width - 1 loop
            Item.Tile.Append (Pixmaps.Pixel (Decoder, Column));
         end loop;
      end loop;
      Pixmaps.Finish (Decoder);
      return Outcome;
   end Read_Color_Tile;

   function Read_Pixel_Pattern
     (S : in out Sessions.Session;
      Item : out Pattern;
      Allowance : Pixel_Count;
      Work : out Pixel_Count) return Results.Result
   is
      Pattern_Type : Interfaces.Unsigned_16 := 0;
      Outcome : Results.Result := Sessions.Read_Word (S, Pattern_Type);
   begin
      Work := 0;
      Item := (others => <>);
      if Results.Succeeded (Outcome) then
         --  pat1Data, the 1-bit fallback for black-and-white ports.
         Outcome := Read_Bit_Pattern (S, Item);
      end if;
      if not Results.Succeeded (Outcome) then
         return Outcome;
      end if;
      case Pattern_Type is
         when 1 =>
            return Read_Color_Tile (S, Item, Allowance, Work);
         when 2 =>
            --  A dither pattern: in true color, its RGB color.
            declare
               Color : Streams.Byte_Array (1 .. 6);
            begin
               Outcome := Sessions.Read_Into (S, Color);
               Item.Kind := Solid_Color;
               Item.Color := (Color (1), Color (3), Color (5));
               return Outcome;
            end;
         when others =>
            return Sessions.Fail (S, Errors.Pattern_Invalid, 2, Byte_Count (Pattern_Type));
      end case;
   end Read_Pixel_Pattern;
end Pictlib.Internal.Patterns;
