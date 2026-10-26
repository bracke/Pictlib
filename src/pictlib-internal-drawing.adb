with Pictlib.Internal.Sessions.Accounting;
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
with Pictlib.Internal.Shapes;
with Pictlib.Streams;

package body Pictlib.Internal.Drawing is
   package Accounting renames Pictlib.Internal.Sessions.Accounting;
   use type Opcodes.Data_Rule;

   subtype Point is Coverage.Point;

   function Signed (Value : Interfaces.Unsigned_16) return Integer is (Integer (Bytes.To_Coordinate (Value)));

   function Signed (Value : Byte) return Integer is
     (if Value >= 16#80# then Integer (Value) - 16#100# else Integer (Value));

   --  A local point (v, h) as a picture point.
   function Read_Point (P : Rendering.Painter; S : in out Sessions.Session; Item : out Point) return Results.Result is
      V, H : Integer;
      Outcome : constant Results.Result := Sessions.Read_Pair (S, V, H);
   begin
      Item := (H => H - P.Port.Origin_H, V => V - P.Port.Origin_V);
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

   --  A coordinate the picture moved beyond Reach: Rendering.Reach for points, Rendering.Origin_Reach for the
   --  origin.
   function Out_Of_Reach (Event : Pictures.Opcode_Event; Value : Integer; Reach : Byte_Count := Rendering.Reach)
     return Results.Result is
     (Failures.In_Opcode (Event, Errors.Opcode_Invalid, Reach, Byte_Count (abs Long_Long_Integer (Value))));

   --  The port pattern a pattern opcode sets: BkPat and BkPixPat, PnPat and PnPixPat, FillPat and FillPixPat.
   function Slot_Of (Op : Opcode) return Rendering.Pattern_Slot is
     (case Op is
         when Opcodes.Background_Pattern | Opcodes.Background_Pixel_Pattern => Rendering.Back_Slot,
         when Opcodes.Pen_Pattern | Opcodes.Pen_Pixel_Pattern => Rendering.Pen_Slot,
         when others => Rendering.Fill_Slot);

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
      Coverage.Start (Shape, P.Window, Accounting.Shape_Work_Left (S));
      Coverage.Line (Shape, From, To, P.Port.Pen_Width, P.Port.Pen_Height);
      P.Port.Pen_H := To.H;
      P.Port.Pen_V := To.V;
      return Rendering.Fill (P, S, Shape, (Rendering.Pattern_Paint, Rendering.Pen_Slot, P.Port.Pen_Mode));
   end Draw_Line;

   function Consume_Line
     (P : in out Rendering.Painter;
      S : in out Sessions.Session;
      Event : Pictures.Opcode_Event) return Results.Result
   is
      From : Point := (H => P.Port.Pen_H, V => P.Port.Pen_V);
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
            P.Port.Text_State.Origin_H := Origin.H;
            P.Port.Text_State.Origin_V := Origin.V;
         end;
      else
         --  Unsigned offsets from the previous text origin, which moves only once both are read and in reach.
         declare
            Offset : Byte := 0;
            H : Integer := P.Port.Text_State.Origin_H;
            V : Integer := P.Port.Text_State.Origin_V;
         begin
            if Event.Op in Opcodes.DH_Text | Opcodes.DHDV_Text then
               Outcome := Sessions.Read_Count_Byte (S, Offset);
               H := H + Natural (Offset);
            end if;
            if Results.Succeeded (Outcome) and then Event.Op in Opcodes.DV_Text | Opcodes.DHDV_Text then
               Outcome := Sessions.Read_Count_Byte (S, Offset);
               V := V + Natural (Offset);
            end if;
            if Results.Succeeded (Outcome) and then not Rendering.Within_Reach (H) then
               return Out_Of_Reach (Event, H);
            elsif Results.Succeeded (Outcome) and then not Rendering.Within_Reach (V) then
               return Out_Of_Reach (Event, V);
            elsif Results.Succeeded (Outcome) then
               P.Port.Text_State.Origin_H := H;
               P.Port.Text_State.Origin_V := V;
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
         Outcome := Patterns.Read_Pixel_Pattern (S, Event, P.Port.Pattern_Set (Slot), Accounting.Work_Left (S), Work);
      else
         Outcome := Patterns.Read_Bit_Pattern (S, P.Port.Pattern_Set (Slot));
      end if;
      if Results.Succeeded (Outcome) then
         Outcome := Accounting.Charge_Work (S, Work);
      end if;
      if not Results.Succeeded (Outcome) then
         P.Port.Pattern_Set (Slot) := Rendering.Default_Pattern (Slot);
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
            Outcome := Sessions.Read_Pair (S, P.Port.Pen_Height, P.Port.Pen_Width);
         when Opcodes.Pen_Mode =>
            declare
               Value : Interfaces.Unsigned_16;
            begin
               Outcome := Sessions.Read_Word (S, Value);
               if Results.Succeeded (Outcome) then
                  Outcome := Rendering.Mode (S, Event, Value, P.Port.Pen_Mode);
               end if;
            end;
         when Opcodes.Oval_Size =>
            Outcome := Sessions.Read_Pair (S, P.Port.Oval_Height, P.Port.Oval_Width);
         when others =>  --  Origin: the clip region keeps its local coordinates
            declare
               Dh, Dv : Integer;
            begin
               --  Origin's data is dh, then dv.
               Outcome := Sessions.Read_Pair (S, Dh, Dv);
               if Results.Succeeded (Outcome) then
                  if not Rendering.Origin_Within_Reach (P.Port.Origin_H + Dh) then
                     return Out_Of_Reach (Event, P.Port.Origin_H + Dh, Rendering.Origin_Reach);
                  elsif not Rendering.Origin_Within_Reach (P.Port.Origin_V + Dv) then
                     return Out_Of_Reach (Event, P.Port.Origin_V + Dv, Rendering.Origin_Reach);
                  end if;
                  P.Port.Origin_H := P.Port.Origin_H + Dh;
                  P.Port.Origin_V := P.Port.Origin_V + Dv;
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
                     --  The planar color value, which names no color this release knows.
                     Outcome := Rendering.Unsupported (S, Event, Actual => Byte_Count (Value));
                  elsif Event.Op = Opcodes.Foreground_Color then
                     P.Port.Colors.Foreground := Color;
                  else
                     P.Port.Colors.Background := Color;
                  end if;
               end if;
            end;
         when Opcodes.RGB_Foreground_Color =>
            Outcome := Sessions.Read_RGB (S, P.Port.Colors.Foreground);
         when Opcodes.RGB_Background_Color =>
            Outcome := Sessions.Read_RGB (S, P.Port.Colors.Background);
         when Opcodes.Hilite_Color =>
            Outcome := Sessions.Read_RGB (S, P.Port.Colors.Highlight);
         when Opcodes.Op_Color =>
            Outcome := Sessions.Read_RGB (S, P.Port.Colors.Operation);
         when Opcodes.Hilite_Mode =>
            P.Port.Hilite_Next := True;
         when others =>  --  DefHilite: black, so highlighting inverts black and white
            P.Port.Colors.Highlight := Images.Black;
      end case;
      return Outcome;
   end Consume_Color;

   --  lineJustify: a length word, the extra space between characters and the extra space of the line, both
   --  Fixed, and any further bytes of the length. Zero extra space changes nothing; any other is unsupported.
   function Consume_Line_Justify
     (S : in out Sessions.Session;
      Event : Pictures.Opcode_Event) return Results.Result
   is
      Length : Interfaces.Unsigned_16 := 0;
      Between, Line : Interfaces.Unsigned_32 := 0;
      Outcome : Results.Result := Sessions.Read_Word (S, Length);
      Fields : constant := 8;
      use type Interfaces.Unsigned_32;
   begin
      if Results.Succeeded (Outcome) and then Natural (Length) >= Fields then
         Outcome := Sessions.Read_Long (S, Between);
         if Results.Succeeded (Outcome) then
            Outcome := Sessions.Read_Long (S, Line);
         end if;
         if Results.Succeeded (Outcome) then
            Outcome := Sessions.Skip_Data (S, Byte_Count (Length) - Fields);
         end if;
      elsif Results.Succeeded (Outcome) then
         Outcome := Sessions.Skip_Data (S, Byte_Count (Length));
      end if;
      if Results.Succeeded (Outcome) and then (Between /= 0 or else Line /= 0) then
         return Rendering.Unsupported (S, Event);
      end if;
      return Outcome;
   end Consume_Line_Justify;

   --  The text state the text opcodes draw with.
   function Consume_Text_State
     (P : in out Rendering.Painter;
      S : in out Sessions.Session;
      Event : Pictures.Opcode_Event) return Results.Result
   is
      State : Text.Text_State renames P.Port.Text_State;
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
               Outcome := Sessions.Read_Pair (S, Numerator_V, Numerator_H);
               if Results.Succeeded (Outcome) then
                  Outcome := Sessions.Read_Pair (S, Denominator_V, Denominator_H);
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
         P.Port.Skip_Next_Bits := False;
      end if;
      case Event.Op is
         when Opcodes.Clip =>  --  kept in local coordinates
            Outcome := Region_Reader.Read (S, P.Port.Clip);
            P.Port.Has_Clip := Results.Succeeded (Outcome);
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
         when Opcodes.Line_Justify =>
            Outcome := Consume_Line_Justify (S, Event);
         when Opcodes.First_Shape .. Opcodes.Last_Shape =>
            --  A reserved verb is never drawn, whatever the opcode table says of it.
            if Event.Reserved or else not Shapes.Has_Verb (Event.Op) then
               Handled := False;
            else
               Outcome := Shapes.Draw (P, S, Event);
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
      P.Port.Text_State.Names.Include (Fonts.Font_ID (Font), Name);
   end Register_Font_Name;
end Pictlib.Internal.Drawing;
