with Interfaces;
with Pictlib.Errors;
with Pictlib.Internal.Pixmaps;
with Pictlib.Streams;

package body Pictlib.Internal.Patterns is

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
      Event : Pictures.Opcode_Event;
      Item : in out Pattern;
      Allowance : Pixel_Count;
      Work : in out Pixel_Count) return Results.Result
   is
      Header : Pixmaps.Bits_Header;
      Decoder : Pixmaps.Row_Decoder;
      Outcome : Results.Result := Pixmaps.Read_Pattern_Header (S, Header, For_Decoding => True);
      Needed : Pixel_Count := 0;

      --  The tile's pixels, once its extent is read.
      function Pixels return Byte_Count is (Byte_Count (Header.Width) * Byte_Count (Header.Height));
   begin
      if not Results.Succeeded (Outcome) then
         return Outcome;
      end if;
      --  A tile of more than Max_Tile_Pixels is not malformed, and no budget raises the bound, so it is never
      --  decoded and its budgets do not apply. Strictly that ends the picture at once, before any row is read,
      --  so no limit on reading them hides it; leniently its rows are skipped and Item keeps pat1Data.
      if Pixels > Max_Tile_Pixels then
         Outcome := Sessions.Reject_Or_Warn
           (S, Errors.Unsupported_Feature, Errors.Approximated_Rendering, Errors.Data_Loss,
            (Sessions.Context_Of (Event) with delta Expected => Max_Tile_Pixels, Actual => Pixels));
         return (if Results.Succeeded (Outcome) then Pixmaps.Skip_Pixels (S, Header) else Outcome);
      end if;
      --  Decoding is drawing work, a unit per pixel and per row, like converting a copied row: checked before
      --  anything is set aside, so a picture without the budget for its tile never allocates it.
      Needed := Pixel_Count (Header.Width + 1) * Pixel_Count (Header.Height);
      if Needed > Allowance - Pixel_Count'Min (Work, Allowance) then
         return Sessions.Over_Work (S, Work + Needed);
      end if;
      --  The tile and the row buffers are one opcode's allocation; the tile is set aside whole, once.
      Outcome := Pixmaps.Start (S, Decoder, Header, Extra => 3 * Pixels);
      if not Results.Succeeded (Outcome) then
         return Outcome;
      end if;
      Work := Work + Needed;
      Item.Kind := Color_Pattern;
      Item.Width := Header.Width;
      Item.Height := Header.Height;
      Item.Tile.Clear;
      Item.Tile.Reserve_Capacity (Ada.Containers.Count_Type (Pixels));
      for Row in 0 .. Header.Height - 1 loop
         Outcome := Pixmaps.Read_Row (S, Decoder, Row);
         exit when not Results.Succeeded (Outcome);
         for Column in 0 .. Header.Width - 1 loop
            Item.Tile.Append (Pixmaps.Pixel (Decoder, Column));
         end loop;
      end loop;
      Pixmaps.Finish (Decoder);
      return Outcome;
   end Read_Color_Tile;

   function Read_Pixel_Pattern
     (S : in out Sessions.Session;
      Event : Pictures.Opcode_Event;
      Item : out Pattern;
      Allowance : Pixel_Count;
      Work : out Pixel_Count) return Results.Result
   is
      Pattern_Type : Interfaces.Unsigned_16 := 0;
      Outcome : Results.Result := Sessions.Read_Word (S, Pattern_Type);
   begin
      --  Every PixPat costs a unit, whatever its type.
      Work := 1;
      Item := (others => <>);
      if Results.Succeeded (Outcome) then
         --  pat1Data, the 1-bit fallback for black-and-white ports.
         Outcome := Read_Bit_Pattern (S, Item);
      end if;
      if Results.Succeeded (Outcome) then
         case Pattern_Type is
            when 1 =>
               Outcome := Read_Color_Tile (S, Event, Item, Allowance, Work);
            when 2 =>
               --  A dither pattern: in true color, its RGB color.
               declare
                  Color : Streams.Byte_Array (1 .. 6);
               begin
                  Outcome := Sessions.Read_Into (S, Color);
                  if Results.Succeeded (Outcome) then
                     Item.Kind := Solid_Color;
                     Item.Color := (Color (1), Color (3), Color (5));
                  end if;
               end;
            when others =>
               Outcome := Sessions.Fail (S, Errors.Pattern_Invalid, 2, Byte_Count (Pattern_Type));
         end case;
      end if;
      --  Never a part-read tile, whoever calls; the caller puts the pattern's own default in its place.
      if not Results.Succeeded (Outcome) then
         Item := (others => <>);
      end if;
      return Outcome;
   end Read_Pixel_Pattern;
end Pictlib.Internal.Patterns;
