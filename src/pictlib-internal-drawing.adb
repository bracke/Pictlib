with Interfaces;
with Pictlib.Errors;
with Pictlib.Geometry;
with Pictlib.Images;
with Pictlib.Internal.Bytes;
with Pictlib.Internal.Coverage;
with Pictlib.Internal.Failures;
with Pictlib.Internal.Text;
with Pictlib.Internal.Typesetting;
with Pictlib.Internal.Patterns;
with Pictlib.Opcodes;
with Pictlib.Internal.QuickTime;
with Pictlib.Internal.Pixmaps;
with Pictlib.Fonts;
with Pictlib.Internal.Region_Reader;
with Pictlib.Internal.Regions;
with Pictlib.Internal.Transfer_Modes;
with Pictlib.Streams;

package body Pictlib.Internal.Drawing is
   use type Opcodes.Data_Rule;

   subtype Area is Regions.Area;
   subtype Point is Coverage.Point;

   function Signed (Value : Interfaces.Unsigned_16) return Integer is (Integer (Bytes.To_Coordinate (Value)));

   function Signed (Value : Byte) return Integer is
     (if Value >= 16#80# then Integer (Value) - 16#100# else Integer (Value));

   --  A (v, h) pair as read, without the origin: pen and oval sizes, angles, polygon points.
   function Read_Pair (S : in out Sessions.Session; V, H : out Integer) return Results.Result is
      Raw_V, Raw_H : Interfaces.Unsigned_16 := 0;
      Outcome : Results.Result := Sessions.Read_Word (S, Raw_V);
   begin
      if Results.Succeeded (Outcome) then
         Outcome := Sessions.Read_Word (S, Raw_H);
      end if;
      V := Signed (Raw_V);
      H := Signed (Raw_H);
      return Outcome;
   end Read_Pair;

   --  A local point (v, h) as a picture point.
   function Read_Point (P : Rendering.Painter; S : in out Sessions.Session; Item : out Point) return Results.Result is
      V, H : Integer;
      Outcome : constant Results.Result := Read_Pair (S, V, H);
   begin
      Item := (H => H - P.Origin_H, V => V - P.Origin_V);
      return Outcome;
   end Read_Point;

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

   function Read_Polygon (S : in out Sessions.Session; Points : out Coverage.Point_Vectors.Vector)
     return Results.Result
   is
      Count : Natural;
      Box : Geometry.Rect;
      Outcome : Results.Result := Sessions.Read_Polygon_Size (S, Count);
   begin
      Points.Clear;
      --  The points are kept, counted against the session's allocation total.
      if Results.Succeeded (Outcome) then
         Outcome := Sessions.Admit_Aggregate (S, Sessions.Point_Cost_Bytes * Byte_Count (Count));
      end if;
      if Results.Succeeded (Outcome) then
         Outcome := Sessions.Read_Bounds (S, Box);
      end if;
      for Index in 1 .. Count loop
         exit when not Results.Succeeded (Outcome);
         declare
            V, H : Integer;
         begin
            Outcome := Read_Pair (S, V, H);
            --  Kept local; the origin applies when the polygon is drawn.
            Points.Append (Point'(H => H, V => V));
         end;
      end loop;
      return Outcome;
   end Read_Polygon;

   --  A coordinate the picture moved beyond Rendering.Reach.
   function Out_Of_Reach (Event : Pictures.Opcode_Event; Value : Integer) return Results.Result is
     (Failures.In_Opcode
        (Event, Errors.Opcode_Invalid, Rendering.Reach, Byte_Count (abs Long_Long_Integer (Value))));

   function Inset (Item : Area; Width, Height : Integer) return Area is
     ((Item.Top + Height, Item.Left + Width, Item.Bottom - Height, Item.Right - Width));

   --  A shape opcode is 16 times its kind (from 3), plus 8 for its "same" form, plus its verb. Verbs 5 .. 7 are
   --  reserved and never drawn.
   type Shape_Kind is (Rect_Shape, Round_Rect_Shape, Oval_Shape, Arc_Shape, Polygon_Shape, Region_Shape);
   subtype Rect_Like_Kind is Shape_Kind range Rect_Shape .. Arc_Shape;
   type Shape_Verb is (Framed, Painted, Erased, Inverted, Filled);

   function Kind_Of (Op : Opcode) return Shape_Kind is (Shape_Kind'Val (Natural (Op / 16) - 3))
     with Pre => Op in Opcodes.First_Shape .. Opcodes.Last_Shape;
   function Verb_Of (Op : Opcode) return Shape_Verb is (Shape_Verb'Val (Natural (Op mod 8)))
     with Pre => Op mod 8 <= 4;
   function Is_Same (Op : Opcode) return Boolean is (Op mod 16 >= 8);

   --  How frame and paint (pen), erase (background pattern), invert and fill (fill pattern) change pixels.
   function Paint_For (P : Rendering.Painter; Verb : Shape_Verb) return Rendering.Paint is
     (case Verb is
         when Framed | Painted => (Rendering.Pattern_Paint, Rendering.Pen_Slot, P.Pen_Mode),
         when Erased => (Rendering.Pattern_Paint, Rendering.Back_Slot, Transfer_Modes.Copy),
         when Inverted => (Rendering.Invert_Paint, Rendering.Pen_Slot, Transfer_Modes.Copy),
         when Filled => (Rendering.Pattern_Paint, Rendering.Fill_Slot, Transfer_Modes.Copy));

   --  The port pattern a pattern opcode sets: BkPat and BkPixPat, PnPat and PnPixPat, FillPat and FillPixPat.
   function Slot_Of (Op : Opcode) return Rendering.Pattern_Slot is
     (case Op is
         when Opcodes.Background_Pattern | Opcodes.Background_Pixel_Pattern => Rendering.Back_Slot,
         when Opcodes.Pen_Pattern | Opcodes.Pen_Pixel_Pattern => Rendering.Pen_Slot,
         when others => Rendering.Fill_Slot);

   --  The pixels a shape verb changes, for the rect, round rect, oval and arc kinds.
   procedure Rect_Like
     (P : Rendering.Painter;
      Kind : Rect_Like_Kind;
      Verb : Shape_Verb;
      Bounds : Area;
      Start_Angle, Arc_Angle : Integer;
      Shape : in out Coverage.Shape)
   is
      Frame : constant Boolean := Verb = Framed;
      Inner : Coverage.Shape;

      procedure Interior (Item : in out Coverage.Shape; Box : Area; Oval_Width, Oval_Height : Integer) is
      begin
         case Kind is
            when Rect_Shape => Coverage.Rectangle (Item, Box);
            when Round_Rect_Shape => Coverage.Round_Rect (Item, Box, Oval_Width, Oval_Height);
            when Oval_Shape | Arc_Shape => Coverage.Oval (Item, Box);
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
      if Kind = Arc_Shape then
         Coverage.Wedge (Shape, Bounds, Start_Angle, Arc_Angle);
      end if;
   end Rect_Like;

   function Draw_Shape
     (P : in out Rendering.Painter;
      S : in out Sessions.Session;
      Event : Pictures.Opcode_Event) return Results.Result
   is
      Kind : constant Shape_Kind := Kind_Of (Event.Op);
      Verb : constant Shape_Verb := Verb_Of (Event.Op);
      Same : constant Boolean := Is_Same (Event.Op);
      Shape : Coverage.Shape;
      Outcome : Results.Result := Results.Success;
   begin
      --  Each shape starts once its data is read and charged, so its allowance is what the budget has left.
      case Kind is
         when Rect_Like_Kind =>
            declare
               Start_Angle, Arc_Angle : Integer := 0;
            begin
               if not Same then
                  Outcome := Sessions.Read_Bounds (S, P.Last_Rect);
               end if;
               if Results.Succeeded (Outcome) and then Kind = Arc_Shape then
                  Outcome := Read_Pair (S, Start_Angle, Arc_Angle);
               end if;
               if not Results.Succeeded (Outcome) then
                  return Outcome;
               end if;
               Coverage.Start (Shape, P.Window, Sessions.Shape_Work_Left (S));
               Rect_Like (P, Kind, Verb, Rendering.To_Picture (P, P.Last_Rect), Start_Angle, Arc_Angle, Shape);
            end;
         when Polygon_Shape =>
            if not Same then
               Outcome := Read_Polygon (S, P.Last_Polygon);
               if not Results.Succeeded (Outcome) then
                  return Outcome;
               end if;
            end if;
            --  The polygon is copied for drawing; the copy counts against the aggregate allocation quota.
            Outcome := Sessions.Admit_Aggregate (S, Sessions.Point_Cost_Bytes * Byte_Count (P.Last_Polygon.Length));
            if not Results.Succeeded (Outcome) then
               return Outcome;
            end if;
            declare
               Points : Coverage.Point_Vectors.Vector;
            begin
               Coverage.Start (Shape, P.Window, Sessions.Shape_Work_Left (S));
               for Item of P.Last_Polygon loop
                  Points.Append (Point'(H => Item.H - P.Origin_H, V => Item.V - P.Origin_V));
               end loop;
               if Verb /= Framed then
                  Coverage.Polygon (Shape, Points);
               elsif Natural (Points.Length) >= 2 then
                  --  FramePoly draws the polygon's lines; it does not close the polygon.
                  for Index in 1 .. Natural (Points.Length) - 1 loop
                     Coverage.Line (Shape, Points (Index), Points (Index + 1), P.Pen_Width, P.Pen_Height);
                  end loop;
               end if;
            end;
         when Region_Shape =>
            if not Same then
               Outcome := Region_Reader.Read (S, P.Last_Region);
               if not Results.Succeeded (Outcome) then
                  return Outcome;
               end if;
            end if;
            --  Copying and moving the region is work like drawing it.
            Outcome := Sessions.Charge_Work (S, Regions.Size (P.Last_Region));
            if not Results.Succeeded (Outcome) then
               return Outcome;
            end if;
            --  So is the region: its scanlines and inversion points, by its size.
            Outcome :=
              Sessions.Admit_Aggregate (S, Sessions.Region_Unit_Bytes * Byte_Count (Regions.Size (P.Last_Region)));
            if not Results.Succeeded (Outcome) then
               return Outcome;
            end if;
            declare
               Region : Regions.Region := P.Last_Region;
            begin
               Coverage.Start (Shape, P.Window, Sessions.Shape_Work_Left (S));
               Regions.Translate (Region, -P.Origin_H, -P.Origin_V);
               if Verb = Framed then
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
      Coverage.Start (Shape, P.Window, Sessions.Shape_Work_Left (S));
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
      if Event.Op in Opcodes.Line | Opcodes.Short_Line then
         Outcome := Read_Point (P, S, From);
      end if;
      if not Results.Succeeded (Outcome) then
         return Outcome;
      end if;
      if Event.Op in Opcodes.Line | Opcodes.Line_From then
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
      if Event.Op = Opcodes.Long_Text then
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
            if Event.Op in Opcodes.DH_Text | Opcodes.DHDV_Text then
               Outcome := Sessions.Read_Count_Byte (S, Offset);
               P.Text_State.Origin_H := P.Text_State.Origin_H + Natural (Offset);
            end if;
            if Results.Succeeded (Outcome) and then Event.Op in Opcodes.DV_Text | Opcodes.DHDV_Text then
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

   --  Every pattern opcode is read, then charged (at least a unit of drawing work), like every other opcode;
   --  whatever fails leaves the slot its default pattern.
   function Consume_Pattern
     (P : in out Rendering.Painter;
      S : in out Sessions.Session;
      Event : Pictures.Opcode_Event) return Results.Result
   is
      Slot : constant Rendering.Pattern_Slot := Slot_Of (Event.Op);
      Work : Pixel_Count := 1;
      Outcome : Results.Result;
   begin
      if Event.Op in Opcodes.Background_Pixel_Pattern .. Opcodes.Fill_Pixel_Pattern then
         --  Decoded straight into the port's pattern, whose old tile goes first: a tile is held once.
         Outcome := Patterns.Read_Pixel_Pattern (S, Event, P.Pattern_Set (Slot), Sessions.Work_Left (S), Work);
      else
         Outcome := Patterns.Read_Bit_Pattern (S, P.Pattern_Set (Slot));
      end if;
      if Results.Succeeded (Outcome) then
         Outcome := Sessions.Charge_Work (S, Work);
      end if;
      if not Results.Succeeded (Outcome) then
         P.Pattern_Set (Slot) := Rendering.Default_Pattern (Slot);
      end if;
      return Outcome;
   end Consume_Pattern;

   --  The pen, the oval size and the origin.
   function Consume_Port
     (P : in out Rendering.Painter;
      S : in out Sessions.Session;
      Event : Pictures.Opcode_Event) return Results.Result
   is
      Outcome : Results.Result := Results.Success;
   begin
      case Event.Op is
         when Opcodes.Pen_Size =>
            Outcome := Read_Pair (S, P.Pen_Height, P.Pen_Width);
         when Opcodes.Pen_Mode =>
            declare
               Value : Interfaces.Unsigned_16;
            begin
               Outcome := Sessions.Read_Word (S, Value);
               if Results.Succeeded (Outcome) then
                  Outcome := Rendering.Mode (S, Event, Value, P.Pen_Mode);
               end if;
            end;
         when Opcodes.Oval_Size =>
            Outcome := Read_Pair (S, P.Oval_Height, P.Oval_Width);
         when others =>  --  Origin: the clip region keeps its local coordinates
            declare
               Dh, Dv : Integer;
            begin
               --  Origin's data is dh, then dv.
               Outcome := Read_Pair (S, Dh, Dv);
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
      end case;
      return Outcome;
   end Consume_Port;

   --  The port's colors and highlighting.
   function Consume_Color
     (P : in out Rendering.Painter;
      S : in out Sessions.Session;
      Event : Pictures.Opcode_Event) return Results.Result
   is
      Outcome : Results.Result := Results.Success;
   begin
      case Event.Op is
         when Opcodes.Foreground_Color | Opcodes.Background_Color =>
            declare
               Value : Interfaces.Unsigned_32;
               Color : Images.RGB_Color;
            begin
               Outcome := Sessions.Read_Long (S, Value);
               if Results.Succeeded (Outcome) then
                  if not Planar_Color (Value, Color) then
                     Outcome := Rendering.Unsupported (S, Event);
                  elsif Event.Op = Opcodes.Foreground_Color then
                     P.Colors.Foreground := Color;
                  else
                     P.Colors.Background := Color;
                  end if;
               end if;
            end;
         when Opcodes.RGB_Foreground_Color =>
            Outcome := Sessions.Read_RGB (S, P.Colors.Foreground);
         when Opcodes.RGB_Background_Color =>
            Outcome := Sessions.Read_RGB (S, P.Colors.Background);
         when Opcodes.Hilite_Color =>
            Outcome := Sessions.Read_RGB (S, P.Colors.Highlight);
         when Opcodes.Op_Color =>
            Outcome := Sessions.Read_RGB (S, P.Colors.Operation);
         when Opcodes.Hilite_Mode =>
            P.Hilite_Next := True;
         when others =>  --  DefHilite: black, so highlighting inverts black and white
            P.Colors.Highlight := Images.Black;
      end case;
      return Outcome;
   end Consume_Color;

   --  The text state the text opcodes draw with.
   function Consume_Text_State
     (P : in out Rendering.Painter;
      S : in out Sessions.Session;
      Event : Pictures.Opcode_Event) return Results.Result
   is
      State : Text.Text_State renames P.Text_State;
      Outcome : Results.Result := Results.Success;
      Value : Interfaces.Unsigned_16 := 0;
   begin
      case Event.Op is
         when Opcodes.Text_Font =>
            Outcome := Sessions.Read_Word (S, Value);
            State.Font := Fonts.Font_ID (Value);
         when Opcodes.Text_Face =>
            Outcome := Sessions.Read_Count_Byte (S, State.Face);
         when Opcodes.Text_Mode =>
            Outcome := Sessions.Read_Word (S, State.Mode);
         when Opcodes.Space_Extra =>
            declare
               Long : Interfaces.Unsigned_32;
            begin
               Outcome := Sessions.Read_Long (S, Long);
               State.Space_Extra := Geometry.Fixed (Bytes.To_Signed_32 (Long));
            end;
         when Opcodes.Text_Size =>
            Outcome := Sessions.Read_Word (S, Value);
            State.Size := Natural (Value);
         when Opcodes.Text_Ratio =>  --  numerator and denominator points
            declare
               Numerator_V, Numerator_H, Denominator_V, Denominator_H : Integer;
            begin
               Outcome := Read_Pair (S, Numerator_V, Numerator_H);
               if Results.Succeeded (Outcome) then
                  Outcome := Read_Pair (S, Denominator_V, Denominator_H);
               end if;
               State.Unit_Ratio := Numerator_V = Denominator_V and then Numerator_H = Denominator_H;
            end;
         when others =>  --  ChExtra
            Outcome := Sessions.Read_Word (S, Value);
            State.Char_Extra := Signed (Value);
      end case;
      return Outcome;
   end Consume_Text_State;

   --  A bits opcode copied, or a QuickTime image drawn.
   function Consume_Image
     (P : in out Rendering.Painter;
      S : in out Sessions.Session;
      Event : Pictures.Opcode_Event) return Results.Result
   is
      Outcome : Results.Result;
   begin
      if Event.Op = Opcodes.Compressed_QuickTime then
         --  Its data is a long length, then the image; rendering reads the image instead of retaining it.
         declare
            Length : Interfaces.Unsigned_32;
         begin
            Outcome := Sessions.Read_Long (S, Length);
            if Results.Succeeded (Outcome) then
               Outcome := Sessions.Admit_Data (S, Byte_Count (Length));
            end if;
            if Results.Succeeded (Outcome) then
               Outcome := QuickTime.Draw (P, S, Event, Byte_Count (Length));
            end if;
         end;
         return Outcome;
      end if;
      declare
         Header : Pixmaps.Bits_Header;
         Mask : Regions.Region;
      begin
         Outcome := Pixmaps.Read_Bits_Header (S, Event.Op, Header, Mask, Read_Mask => True, For_Decoding => True);
         if Results.Succeeded (Outcome) then
            Outcome := Rendering.Copy_Bits (P, S, Header, Mask, Event);
         end if;
      end;
      return Outcome;
   end Consume_Image;

   function Consume
     (P : in out Rendering.Painter;
      S : in out Sessions.Session;
      Event : Pictures.Opcode_Event;
      Handled : out Boolean) return Results.Result
   is
      Outcome : Results.Result := Results.Success;
   begin
      Handled := True;
      --  Only the opcode right after a QuickTime image is its placeholder.
      if Opcodes.Rule_For (Event.Op).Rule /= Opcodes.Bits_Data and then Event.Op /= Opcodes.Compressed_QuickTime then
         P.Skip_Next_Bits := False;
      end if;
      case Event.Op is
         when Opcodes.Clip =>  --  kept in local coordinates
            Outcome := Region_Reader.Read (S, P.Clip);
            P.Has_Clip := Results.Succeeded (Outcome);
         when Opcodes.Background_Pattern | Opcodes.Pen_Pattern | Opcodes.Fill_Pattern
            | Opcodes.Background_Pixel_Pattern .. Opcodes.Fill_Pixel_Pattern
         =>
            Outcome := Consume_Pattern (P, S, Event);
         when Opcodes.Pen_Size | Opcodes.Pen_Mode | Opcodes.Oval_Size | Opcodes.Origin =>
            Outcome := Consume_Port (P, S, Event);
         when Opcodes.Foreground_Color | Opcodes.Background_Color
            | Opcodes.RGB_Foreground_Color .. Opcodes.Op_Color
         =>
            Outcome := Consume_Color (P, S, Event);
         when Opcodes.Text_Font .. Opcodes.Space_Extra | Opcodes.Text_Size | Opcodes.Text_Ratio | Opcodes.Char_Extra =>
            Outcome := Consume_Text_State (P, S, Event);
         when Opcodes.Line .. Opcodes.Short_Line_From =>
            Outcome := Consume_Line (P, S, Event);
         when Opcodes.Long_Text .. Opcodes.DHDV_Text =>
            Outcome := Consume_Text (P, S, Event);
         when Opcodes.First_Shape .. Opcodes.Last_Shape =>
            if Event.Reserved then
               Handled := False;
            else
               Outcome := Draw_Shape (P, S, Event);
            end if;
         when Opcodes.Bits_Rect | Opcodes.Bits_Region | Opcodes.Pack_Bits_Rect | Opcodes.Pack_Bits_Region
            | Opcodes.Direct_Bits_Rect | Opcodes.Direct_Bits_Region | Opcodes.Compressed_QuickTime
         =>
            Outcome := Consume_Image (P, S, Event);
         when others =>
            Handled := False;
      end case;
      return Outcome;
   end Consume;

   procedure Register_Font_Name (P : in out Rendering.Painter; Font : Natural; Name : String) is
   begin
      P.Text_State.Names.Include (Fonts.Font_ID (Font), Name);
   end Register_Font_Name;
end Pictlib.Internal.Drawing;
