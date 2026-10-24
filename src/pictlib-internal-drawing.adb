with Interfaces;
with Pictlib.Errors;
with Pictlib.Geometry;
with Pictlib.Images;
with Pictlib.Internal.Coverage;
with Pictlib.Internal.Typesetting;
with Pictlib.Internal.Patterns;
with Pictlib.Fonts;
with Pictlib.Internal.Regions;
with Pictlib.Internal.Transfer_Modes;
with Pictlib.Streams;

package body Pictlib.Internal.Drawing is
   use type Interfaces.Unsigned_16;
   use type Interfaces.Unsigned_32;

   subtype Area is Regions.Area;
   subtype Point is Coverage.Point;

   Smallest_Polygon : constant := 10;

   function Signed (Value : Interfaces.Unsigned_16) return Integer is
     (if Value >= 16#8000# then Integer (Value) - 16#1_0000# else Integer (Value));

   function Signed (Value : Byte) return Integer is
     (if Value >= 16#80# then Integer (Value) - 16#100# else Integer (Value));

   --  A local point (v, h) as a picture point.
   function Read_Point (P : Rendering.Painter; S : in out Sessions.Session; Item : out Point) return Results.Result is
      V, H : Interfaces.Unsigned_16 := 0;
      Outcome : Results.Result := Sessions.Read_Word (S, V);
   begin
      if Results.Succeeded (Outcome) then
         Outcome := Sessions.Read_Word (S, H);
      end if;
      Item := (H => Signed (H) - P.Origin_H, V => Signed (V) - P.Origin_V);
      return Outcome;
   end Read_Point;

   --  A (v, h) pair as read, without the origin: pen and oval sizes.
   function Read_Size (S : in out Sessions.Session; Height, Width : out Integer) return Results.Result is
      V, H : Interfaces.Unsigned_16 := 0;
      Outcome : Results.Result := Sessions.Read_Word (S, V);
   begin
      if Results.Succeeded (Outcome) then
         Outcome := Sessions.Read_Word (S, H);
      end if;
      Height := Signed (V);
      Width := Signed (H);
      return Outcome;
   end Read_Size;

   function Read_Color (S : in out Sessions.Session; Color : out Images.RGB_Color) return Results.Result is
      Data : Streams.Byte_Array (1 .. 6);
      Outcome : constant Results.Result := Sessions.Read_Into (S, Data);
   begin
      --  The high byte of each 16-bit component.
      Color := (Data (1), Data (3), Data (5));
      return Outcome;
   end Read_Color;

   --  Classic QuickDraw's eight planar colors, as Color QuickDraw shows them.
   function Planar_Color (Value : Interfaces.Unsigned_32; Color : out Images.RGB_Color) return Boolean is
   begin
      case Value is
         when 30 => Color := Images.White;
         when 33 => Color := Images.Black;
         when 69 => Color := (16#FC#, 16#F3#, 16#05#);
         when 137 => Color := (16#F2#, 16#08#, 16#84#);
         when 205 => Color := (16#DD#, 16#08#, 16#06#);
         when 273 => Color := (16#02#, 16#AB#, 16#EA#);
         when 341 => Color := (16#00#, 16#80#, 16#11#);
         when 409 => Color := (16#00#, 16#00#, 16#D4#);
         when others =>
            Color := Images.Black;
            return False;
      end case;
      return True;
   end Planar_Color;

   function Read_Polygon
     (P : Rendering.Painter;
      S : in out Sessions.Session;
      Points : out Coverage.Point_Vectors.Vector) return Results.Result
   is
      pragma Unreferenced (P);
      Size : Interfaces.Unsigned_16 := 0;
      Box : Geometry.Rect;
      Outcome : Results.Result := Sessions.Read_Word (S, Size);
   begin
      Points.Clear;
      if not Results.Succeeded (Outcome) then
         return Outcome;
      elsif Size < Smallest_Polygon or else (Size - Smallest_Polygon) mod 4 /= 0 then
         return Sessions.Fail (S, Errors.Polygon_Invalid, Smallest_Polygon, Byte_Count (Size));
      elsif Natural (Size - Smallest_Polygon) / 4 > S.Budget.Max_Polygon_Points then
         return Sessions.Over_Limit
           (S, Polygon_Point_Limit, Byte_Count (S.Budget.Max_Polygon_Points),
            Byte_Count (Size - Smallest_Polygon) / 4);
      end if;
      Outcome :=
        Sessions.Admit_Aggregate
          (S, Byte_Count (Size - Smallest_Polygon) * 8);
      if not Results.Succeeded (Outcome) then
         return Outcome;
      end if;
      Outcome := Sessions.Read_Bounds (S, Box);
      for Index in 1 .. Natural (Size - Smallest_Polygon) / 4 loop
         exit when not Results.Succeeded (Outcome);
         declare
            V, H : Interfaces.Unsigned_16 := 0;
         begin
            Outcome := Sessions.Read_Word (S, V);
            if Results.Succeeded (Outcome) then
               Outcome := Sessions.Read_Word (S, H);
            end if;
            --  Kept local; the origin applies when the polygon is drawn.
            Points.Append (Point'(H => Signed (H), V => Signed (V)));
         end;
      end loop;
      return Outcome;
   end Read_Polygon;

   --  A coordinate the picture moved beyond Rendering.Reach.
   function Out_Of_Reach (Event : Pictures.Opcode_Event; Value : Integer)
     return Results.Result is
     (Results.Failure
        (Errors.Make
           (Errors.Opcode_Invalid,
            (Source => Event.Offset, Op => Event.Op, Has_Opcode => True, Ordinal => Event.Ordinal,
             Expected => Rendering.Reach, Actual => Byte_Count (abs Long_Long_Integer (Value)), others => <>))));

   function Inset (Item : Area; Width, Height : Integer) return Area is
     ((Item.Top + Height, Item.Left + Width, Item.Bottom - Height, Item.Right - Width));

   --  How frame and paint (pen), erase (background pattern), invert and fill (fill pattern) change pixels.
   function Paint_For (P : Rendering.Painter; Verb : Natural) return Rendering.Paint is
     (case Verb is
         when 0 | 1 => (Rendering.Pattern_Paint, Rendering.Pen_Slot, P.Pen_Mode),
         when 2 => (Rendering.Pattern_Paint, Rendering.Back_Slot, Transfer_Modes.Copy),
         when 3 => (Rendering.Invert_Paint, Rendering.Pen_Slot, Transfer_Modes.Copy),
         when others => (Rendering.Pattern_Paint, Rendering.Fill_Slot, Transfer_Modes.Copy));

   --  The port pattern a pattern opcode sets: BkPat and BkPixPat, PnPat and PnPixPat, FillPat and FillPixPat.
   function Slot_Of (Op : Opcode) return Rendering.Pattern_Slot is
     (case Op is
         when 16#0002# | 16#0012# => Rendering.Back_Slot,
         when 16#0009# | 16#0013# => Rendering.Pen_Slot,
         when others => Rendering.Fill_Slot);

   --  The pixels a shape verb changes, for the rect, round rect, oval and arc groups.
   procedure Rect_Like
     (P : Rendering.Painter;
      Group : Natural;
      Verb : Natural;
      Bounds : Area;
      Start_Angle, Arc_Angle : Integer;
      Shape : in out Coverage.Shape)
   is
      Frame : constant Boolean := Verb = 0;
      Inner : Coverage.Shape;

      procedure Interior (Item : in out Coverage.Shape; Box : Area; Oval_Width, Oval_Height : Integer) is
      begin
         case Group is
            when 3 => Coverage.Rectangle (Item, Box);
            when 4 => Coverage.Round_Rect (Item, Box, Oval_Width, Oval_Height);
            when others => Coverage.Oval (Item, Box);
         end case;
      end Interior;
   begin
      if Frame and then (P.Pen_Width <= 0 or else P.Pen_Height <= 0) then
         return;
      end if;
      Interior (Shape, Bounds, P.Oval_Width, P.Oval_Height);
      if Frame then
         Coverage.Start (Inner, Coverage.Window_Of (Shape), Coverage.Remaining (Shape));
         Interior (Inner, Inset (Bounds, P.Pen_Width, P.Pen_Height),
                   P.Oval_Width - 2 * P.Pen_Width, P.Oval_Height - 2 * P.Pen_Height);
         Coverage.Subtract (Shape, Inner);
      end if;
      if Group = 6 then
         Coverage.Wedge (Shape, Bounds, Start_Angle, Arc_Angle);
      end if;
   end Rect_Like;

   function Draw_Shape
     (P : in out Rendering.Painter;
      S : in out Sessions.Session;
      Event : Pictures.Opcode_Event) return Results.Result
   is
      Group : constant Natural := Natural (Event.Op / 16);
      Verb : constant Natural := Natural (Event.Op mod 8);
      Same : constant Boolean := Event.Op mod 16 >= 8;
      Shape : Coverage.Shape;
      Outcome : Results.Result := Results.Success;
   begin
      --  Each shape starts once its data is read and charged, so its allowance is what the budget has left.
      case Group is
         when 3 .. 6 =>
            declare
               Start_Angle, Arc_Angle : Integer := 0;
            begin
               if not Same then
                  Outcome := Sessions.Read_Bounds (S, P.Last_Rect);
               end if;
               if Results.Succeeded (Outcome) and then Group = 6 then
                  Outcome := Read_Size (S, Start_Angle, Arc_Angle);
               end if;
               if not Results.Succeeded (Outcome) then
                  return Outcome;
               end if;
               Coverage.Start (Shape, P.Window, Rendering.Shape_Allowance (P, S));
               Rect_Like (P, Group, Verb, Rendering.To_Picture (P, P.Last_Rect), Start_Angle, Arc_Angle, Shape);
            end;
         when 7 =>
            if not Same then
               Outcome := Read_Polygon (P, S, P.Last_Polygon);
               if not Results.Succeeded (Outcome) then
                  return Outcome;
               end if;
            end if;
            declare
               Points : Coverage.Point_Vectors.Vector;
            begin
               Coverage.Start (Shape, P.Window, Rendering.Shape_Allowance (P, S));
               for Item of P.Last_Polygon loop
                  Points.Append (Point'(H => Item.H - P.Origin_H, V => Item.V - P.Origin_V));
               end loop;
               if Verb /= 0 then
                  Coverage.Polygon (Shape, Points);
               elsif Natural (Points.Length) >= 2 then
                  --  FramePoly draws the polygon's lines; it does not close the polygon.
                  for Index in 1 .. Natural (Points.Length) - 1 loop
                     Coverage.Line (Shape, Points (Index), Points (Index + 1), P.Pen_Width, P.Pen_Height);
                  end loop;
               end if;
            end;
         when others =>
            if not Same then
               Outcome := Regions.Read (S, P.Last_Region);
               if not Results.Succeeded (Outcome) then
                  return Outcome;
               end if;
            end if;
            --  Copying and moving the region is work like drawing it.
            Outcome := Rendering.Charge (P, S, Regions.Size (P.Last_Region));
            if not Results.Succeeded (Outcome) then
               return Outcome;
            end if;
            declare
               Region : Regions.Region := P.Last_Region;
            begin
               Coverage.Start (Shape, P.Window, Rendering.Shape_Allowance (P, S));
               Regions.Translate (Region, -P.Origin_H, -P.Origin_V);
               if Verb = 0 then
                  Coverage.Region_Frame (Shape, Region, P.Pen_Width, P.Pen_Height);
               else
                  Coverage.From_Region (Shape, Region);
               end if;
            end;
      end case;
      return Rendering.Fill (P, S, Shape, Paint_For (P, Verb));
   end Draw_Shape;

   function Draw_Line
     (P : in out Rendering.Painter;
      S : in out Sessions.Session;
      Event : Pictures.Opcode_Event;
      From, To : Point) return Results.Result
   is
      Shape : Coverage.Shape;
   begin
      if not Rendering.Within_Reach (To.H) then
         return Out_Of_Reach (Event, To.H);
      elsif not Rendering.Within_Reach (To.V) then
         return Out_Of_Reach (Event, To.V);
      end if;
      Coverage.Start (Shape, P.Window, Rendering.Shape_Allowance (P, S));
      Coverage.Line (Shape, From, To, P.Pen_Width, P.Pen_Height);
      P.Pen_H := To.H;
      P.Pen_V := To.V;
      return Rendering.Fill (P, S, Shape, (Rendering.Pattern_Paint, Rendering.Pen_Slot, P.Pen_Mode));
   end Draw_Line;

   function Consume_Line
     (P : in out Rendering.Painter;
      S : in out Sessions.Session;
      Event : Pictures.Opcode_Event) return Results.Result
   is
      From : Point := (H => P.Pen_H, V => P.Pen_V);
      To : Point;
      Outcome : Results.Result := Results.Success;
   begin
      if Event.Op in 16#0020# | 16#0022# then
         Outcome := Read_Point (P, S, From);
      end if;
      if not Results.Succeeded (Outcome) then
         return Outcome;
      end if;
      if Event.Op in 16#0020# | 16#0021# then
         Outcome := Read_Point (P, S, To);
      else
         --  ShortLine and ShortLineFrom: a signed byte dh, then dv.
         declare
            Dh, Dv : Byte := 0;
         begin
            Outcome := Sessions.Read_Count_Byte (S, Dh);
            if Results.Succeeded (Outcome) then
               Outcome := Sessions.Read_Count_Byte (S, Dv);
            end if;
            To := (H => From.H + Signed (Dh), V => From.V + Signed (Dv));
         end;
      end if;
      if not Results.Succeeded (Outcome) then
         return Outcome;
      end if;
      return Draw_Line (P, S, Event, From, To);
   end Consume_Line;

   --  LongText, DHText, DVText, DHDVText: move the text origin, then draw the characters from it.
   function Consume_Text
     (P : in out Rendering.Painter;
      S : in out Sessions.Session;
      Event : Pictures.Opcode_Event) return Results.Result
   is
      Outcome : Results.Result := Results.Success;
      Count : Byte := 0;
   begin
      if Event.Op = 16#0028# then
         declare
            Origin : Point;
         begin
            Outcome := Read_Point (P, S, Origin);
            P.Text_State.Origin_H := Origin.H;
            P.Text_State.Origin_V := Origin.V;
         end;
      else
         --  Unsigned offsets from the previous text origin.
         declare
            Offset : Byte := 0;
         begin
            if Event.Op in 16#0029# | 16#002B# then
               Outcome := Sessions.Read_Count_Byte (S, Offset);
               P.Text_State.Origin_H := P.Text_State.Origin_H + Natural (Offset);
            end if;
            if Results.Succeeded (Outcome) and then Event.Op in 16#002A# | 16#002B# then
               Outcome := Sessions.Read_Count_Byte (S, Offset);
               P.Text_State.Origin_V := P.Text_State.Origin_V + Natural (Offset);
            end if;
            if Results.Succeeded (Outcome) and then not Rendering.Within_Reach (P.Text_State.Origin_H) then
               return Out_Of_Reach (Event, P.Text_State.Origin_H);
            elsif Results.Succeeded (Outcome) and then not Rendering.Within_Reach (P.Text_State.Origin_V) then
               return Out_Of_Reach (Event, P.Text_State.Origin_V);
            end if;
         end;
      end if;
      if Results.Succeeded (Outcome) then
         Outcome := Sessions.Read_Count_Byte (S, Count);
      end if;
      if not Results.Succeeded (Outcome) then
         return Outcome;
      end if;
      declare
         Characters : Streams.Byte_Array (1 .. Natural (Count));
      begin
         Outcome := Sessions.Read_Into (S, Characters);
         if Results.Succeeded (Outcome) then
            Outcome := Typesetting.Draw (P, S, Event, Characters);
         end if;
      end;
      return Outcome;
   end Consume_Text;

   function Consume
     (P : in out Rendering.Painter;
      S : in out Sessions.Session;
      Event : Pictures.Opcode_Event;
      Handled : out Boolean) return Results.Result
   is
      Outcome : Results.Result := Results.Success;
   begin
      Handled := True;
      case Event.Op is
         when 16#0001# =>  --  Clip, kept in local coordinates
            Outcome := Regions.Read (S, P.Clip);
            P.Has_Clip := Results.Succeeded (Outcome);
         --  Every pattern opcode is read, then charged (at least a unit of drawing work), like every other
         --  opcode; whatever fails leaves the slot its default pattern.
         when 16#0002# | 16#0009# | 16#000A# | 16#0012# .. 16#0014# =>
            declare
               Slot : constant Rendering.Pattern_Slot := Slot_Of (Event.Op);
               Work : Pixel_Count := 1;
               Too_Large : Boolean := False;
               Tile_Pixels : Byte_Count := 0;

               --  A tile too large to index is unsupported, its 1-bit pattern standing in when lenient.
               function Unsupported_Tile return Results.Result is
                 (Rendering.Unsupported (S, Event, Expected => Patterns.Max_Tile_Pixels, Actual => Tile_Pixels));
            begin
               if Event.Op in 16#0012# .. 16#0014# then
                  --  Decoded straight into the port's pattern, whose old tile goes first: a tile is held once.
                  Outcome :=
                    Patterns.Read_Pixel_Pattern
                      (S, P.Pattern_Set (Slot), Rendering.Allowance (P, S), Work, Too_Large, Tile_Pixels);
               else
                  Outcome := Patterns.Read_Bit_Pattern (S, P.Pattern_Set (Slot));
               end if;
               if Results.Succeeded (Outcome) then
                  Outcome := Rendering.Charge (P, S, Work);
               end if;
               --  A tile too large to index read leniently: its 1-bit pattern stands in, reported once the
               --  charge has succeeded. Strictly the read itself failed.
               if Results.Succeeded (Outcome) and then Too_Large then
                  Outcome := Unsupported_Tile;
               end if;
               if not Results.Succeeded (Outcome) then
                  P.Pattern_Set (Slot) := Rendering.Default_Pattern (Slot);
               end if;
            end;
         when 16#0007# =>
            Outcome := Read_Size (S, P.Pen_Height, P.Pen_Width);
         when 16#0008# =>
            declare
               Value : Interfaces.Unsigned_16;
            begin
               Outcome := Sessions.Read_Word (S, Value);
               if Results.Succeeded (Outcome) then
                  Outcome := Rendering.Mode (S, Event, Value, P.Pen_Mode);
               end if;
            end;
         when 16#000B# =>
            Outcome := Read_Size (S, P.Oval_Height, P.Oval_Width);
         when 16#000C# =>  --  Origin: the clip region keeps its local coordinates
            declare
               Dh, Dv : Integer;
            begin
               Outcome := Read_Size (S, Dh, Dv);
               --  Origin's data is dh, then dv.
               if Results.Succeeded (Outcome) then
                  if not Rendering.Origin_Within_Reach (P.Origin_H + Dh) then
                     return Out_Of_Reach (Event, P.Origin_H + Dh);
                  elsif not Rendering.Origin_Within_Reach (P.Origin_V + Dv) then
                     return Out_Of_Reach (Event, P.Origin_V + Dv);
                  end if;
                  P.Origin_H := P.Origin_H + Dh;
                  P.Origin_V := P.Origin_V + Dv;
               end if;
            end;
         when 16#000E# | 16#000F# =>
            declare
               Value : Interfaces.Unsigned_32;
               Color : Images.RGB_Color;
            begin
               Outcome := Sessions.Read_Long (S, Value);
               if Results.Succeeded (Outcome) then
                  if not Planar_Color (Value, Color) then
                     Outcome := Rendering.Unsupported (S, Event);
                  elsif Event.Op = 16#000E# then
                     P.Colors.Foreground := Color;
                  else
                     P.Colors.Background := Color;
                  end if;
               end if;
            end;
         when 16#001A# =>
            Outcome := Read_Color (S, P.Colors.Foreground);
         when 16#001B# =>
            Outcome := Read_Color (S, P.Colors.Background);
         when 16#001D# =>
            Outcome := Read_Color (S, P.Colors.Highlight);
         when 16#001F# =>
            Outcome := Read_Color (S, P.Colors.Operation);
         when 16#001C# =>
            P.Hilite_Next := True;
         when 16#001E# =>
            --  The default highlight: black, so highlighting inverts black and white.
            P.Colors.Highlight := Images.Black;
         when 16#0020# .. 16#0023# =>
            Outcome := Consume_Line (P, S, Event);
         when 16#0003# =>
            declare
               Value : Interfaces.Unsigned_16;
            begin
               Outcome := Sessions.Read_Word (S, Value);
               P.Text_State.Font := Fonts.Font_ID (Value);
            end;
         when 16#0004# =>
            Outcome := Sessions.Read_Count_Byte (S, P.Text_State.Face);
         when 16#0005# =>
            Outcome := Sessions.Read_Word (S, P.Text_State.Mode);
         when 16#0006# =>
            declare
               Value : Interfaces.Unsigned_32;
            begin
               Outcome := Sessions.Read_Long (S, Value);
               P.Text_State.Space_Extra :=
                 Geometry.Fixed (if Value >= 16#8000_0000# then Long_Long_Integer (Value) - 16#1_0000_0000#
                                 else Long_Long_Integer (Value));
            end;
         when 16#000D# =>
            declare
               Value : Interfaces.Unsigned_16;
            begin
               Outcome := Sessions.Read_Word (S, Value);
               P.Text_State.Size := Natural (Value);
            end;
         when 16#0010# =>  --  TxRatio: numerator and denominator points
            declare
               Numerator_V, Numerator_H, Denominator_V, Denominator_H : Integer;
            begin
               Outcome := Read_Size (S, Numerator_V, Numerator_H);
               if Results.Succeeded (Outcome) then
                  Outcome := Read_Size (S, Denominator_V, Denominator_H);
               end if;
               P.Text_State.Unit_Ratio := Numerator_V = Denominator_V and then Numerator_H = Denominator_H;
            end;
         when 16#0016# =>
            declare
               Value : Interfaces.Unsigned_16;
            begin
               Outcome := Sessions.Read_Word (S, Value);
               P.Text_State.Char_Extra := Signed (Value);
            end;
         when 16#0028# .. 16#002B# =>
            Outcome := Consume_Text (P, S, Event);
         when 16#0030# .. 16#008F# =>
            if Event.Reserved then
               Handled := False;
            else
               Outcome := Draw_Shape (P, S, Event);
            end if;
         when others =>
            Handled := False;
      end case;
      return Outcome;
   end Consume;
end Pictlib.Internal.Drawing;
