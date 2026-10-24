with Pictlib.Errors;
with Pictlib.Fonts;
with Pictlib.Geometry;
with Pictlib.Images;
with Pictlib.Internal.Text;
with Pictlib.Internal.Transfer_Modes;
with Textrender;

package body Pictlib.Internal.Typesetting is
   use type Textrender.Status_Code;
   use type Textrender.Alpha;

   Default_Size : constant := 12;
   Largest_Size : constant := 512;
   --  Coverage at or above this is ink; QuickDraw text has no antialiasing.
   Ink_Threshold : constant := 128;
   Space : constant := 16#20#;


   function Has (Face : Byte; Bit : Byte) return Boolean is ((Face and Bit) /= 0);

   function Unavailable (S : in out Sessions.Session; Event : Pictures.Opcode_Event) return Results.Result is
     (Sessions.Reject_Or_Warn
        (S, Errors.Font_Unavailable, Errors.Approximated_Rendering, Errors.Data_Loss, Sessions.Context_Of (Event)));

   --  The characters, with the font in Slot loaded; called under the textrender lock.
   function Draw_Characters
     (P : in out Rendering.Painter;
      S : in out Sessions.Session;
      Event : Pictures.Opcode_Event;
      Characters : Streams.Byte_Array;
      Slot : Positive;
      Kind : Transfer_Modes.Mode_Kind;
      Size : Positive) return Results.Result;

   function Draw
     (P : in out Rendering.Painter;
      S : in out Sessions.Session;
      Event : Pictures.Opcode_Event;
      Characters : Streams.Byte_Array) return Results.Result
   is
      State : Text.Text_State renames P.Text_State;
      Family : constant String :=
        (if State.Names.Contains (State.Font) then State.Names.Element (State.Font) else "");
      Path : constant String := Fonts.Resolve (P.Fonts, State.Font, Family);
      Size : constant Natural := (if State.Size = 0 then Default_Size else State.Size);
      Outcome : Results.Result := Results.Success;
      Kind : Transfer_Modes.Mode_Kind;
      Slot : Positive;
   begin
      if Characters'Length = 0 then
         return Results.Success;
      elsif Path'Length = 0 then
         return Unavailable (S, Event);
      elsif Size > Largest_Size then
         return Rendering.Unsupported (S, Event);
      elsif Has (State.Face, Text.Outline) or else Has (State.Face, Text.Shadow) or else not State.Unit_Ratio then
         --  Leniently drawn plain, at the stated size.
         Outcome := Rendering.Unsupported (S, Event);
         if not Results.Succeeded (Outcome) then
            return Outcome;
         end if;
      end if;
      --  Loading a font is drawing work, charged before it is done, so a picture that keeps evicting fonts
      --  from the cache runs out of budget.
      if not Text.Cached (P.Font_Cache, Path, Size) then
         declare
            --  textrender keeps a copy of the whole file beside the atlas: both are this load's allocation.
            File : constant Byte_Count := Text.File_Bytes (Path);
         begin
            Outcome := Sessions.Admit_Allocation (S, Text.Atlas_Bytes (Size) + File);
            if Results.Succeeded (Outcome) then
               Outcome := Sessions.Charge_Work (S, Text.Load_Work (Size, File));
            end if;
         end;
         if not Results.Succeeded (Outcome) then
            return Outcome;
         end if;
      end if;
      Outcome := Rendering.Mode (S, Event, State.Mode, Kind);
      if not Results.Succeeded (Outcome) then
         return Outcome;
      end if;

      declare
         --  Every textrender call below is made under the process-wide textrender lock.
         Guard : Text.Textrender_Guard;
         pragma Unreferenced (Guard);
      begin
         if Text.Acquire (P.Font_Cache, Path, Size, Slot) /= Textrender.Success then
            return Unavailable (S, Event);
         end if;
         Outcome := Draw_Characters (P, S, Event, Characters, Slot, Kind, Size);
      end;
      return Outcome;
   end Draw;

   function Draw_Characters
     (P : in out Rendering.Painter;
      S : in out Sessions.Session;
      Event : Pictures.Opcode_Event;
      Characters : Streams.Byte_Array;
      Slot : Positive;
      Kind : Transfer_Modes.Mode_Kind;
      Size : Positive) return Results.Result
   is
      State : Text.Text_State renames P.Text_State;
      Font : constant not null access Textrender.Renderer := Text.Renderer (P.Font_Cache, Slot);
      Style : constant Textrender.Font_Style :=
        (if Has (State.Face, Text.Italic) then Textrender.Italic else Textrender.Regular);
      Bold : constant Natural := (if Has (State.Face, Text.Bold) then 1 else 0);
      Width_Change : constant Integer :=
        Bold + (if Has (State.Face, Text.Extend) then 1 else 0) - (if Has (State.Face, Text.Condense) then 1 else 0);
      Baseline : constant Integer := State.Origin_V;
      Ascent : constant Integer := Integer (Float'Ceiling (Font.Ascent));
      Descent : constant Integer := Integer (Float'Ceiling (abs Font.Descent));
      Start_X : constant Integer := State.Origin_H;
      Pen : Float := Float (State.Origin_H);
      Missing_Reported : Boolean := False;
      Outcome : Results.Result := Results.Success;

      --  Text is a bit source: ink black, the rest white, through the text mode.
      function Through_Mode (Ink : Boolean; Under : Images.RGB_Color) return Images.RGB_Color is
        (Transfer_Modes.Compose
           (Kind, (if Ink then Images.Black else Images.White), Under, P.Colors, Bit_Source => True));

      --  Paint the cell of a glyph drawn from the pen: the larger of its advance box and its ink.
      function Paint_Cell (Metric : Textrender.Glyph_Metric; Drawable : Boolean; Advance : Float)
        return Results.Result
      is
         Cell_Left : constant Integer := Integer (Float'Rounding (Pen));
         Cell_Right : constant Integer := Integer (Float'Rounding (Pen + Advance));
         Glyph_Left : constant Integer := Integer (Float'Rounding (Pen + Metric.Bearing_X));
         Glyph_Top : constant Integer := Baseline - Integer (Metric.Bearing_Y);
         Atlas_Width : constant Natural := Font.Atlas_Width;
         Atlas : constant access constant Textrender.Alpha_Buffer := Font.Atlas_Pixels;
         Left : constant Integer := (if Drawable then Integer'Min (Cell_Left, Glyph_Left) else Cell_Left);
         Right : constant Integer :=
           (if Drawable then Integer'Max (Cell_Right, Glyph_Left + Metric.W + Bold) else Cell_Right);
         Top : constant Integer :=
           (if Drawable then Integer'Min (Baseline - Ascent, Glyph_Top) else Baseline - Ascent);
         Bottom : constant Integer :=
           (if Drawable then Integer'Max (Baseline + Descent, Glyph_Top + Metric.H) else Baseline + Descent);
         Result : Results.Result := Results.Success;

         function Covered (X, Y : Integer) return Boolean is
           (Drawable
            and then X - Glyph_Left in 0 .. Metric.W - 1 and then Y - Glyph_Top in 0 .. Metric.H - 1
            and then Atlas ((Metric.Y + Y - Glyph_Top) * Atlas_Width + Metric.X + X - Glyph_Left) >= Ink_Threshold);

         --  Bold smears ink one pixel right.
         function Color_At (X, Y : Integer; Under : Images.RGB_Color) return Images.RGB_Color is
           (Through_Mode (Covered (X, Y) or else (Bold = 1 and then Covered (X - 1, Y)), Under));
         function Paint is new Rendering.Paint_Row (Color_At);
      begin
         for Y in Integer'Max (Top, P.Window.Top) .. Integer'Min (Bottom, P.Window.Bottom) - 1 loop
            Result := Rendering.Begin_Row (P, S, Y, Left, Right);
            if Results.Succeeded (Result) then
               Result := Paint (P, S, Y);
            end if;
            exit when not Results.Succeeded (Result);
         end loop;
         return Result;
      end Paint_Cell;

      --  The row below the baseline, under the whole string.
      function Paint_Underline return Results.Result is
         function Color_At (X, Y : Integer; Under : Images.RGB_Color) return Images.RGB_Color is
            pragma Unreferenced (X, Y);
         begin
            return Through_Mode (True, Under);
         end Color_At;
         function Paint is new Rendering.Paint_Row (Color_At);
         Result : constant Results.Result :=
           Rendering.Begin_Row (P, S, Baseline + 1, Start_X, Integer (Float'Rounding (Pen)));
      begin
         return (if Results.Succeeded (Result) then Paint (P, S, Baseline + 1) else Result);
      end Paint_Underline;
   begin
      for Item of Characters loop
         exit when not Results.Succeeded (Outcome);
         --  Every glyph request is drawing work, wherever the character lands; control characters draw nothing.
         if Item >= Space then
            Outcome := Sessions.Charge_Work (S, Text.Glyph_Work (Size));
            exit when not Results.Succeeded (Outcome);
            declare
               --  Defined even when the font lacks the glyph and leaves it alone.
               Metric : Textrender.Glyph_Metric :=
                 (X | Y | W | H => 0, U0 | V0 | U1 | V1 | Advance_X | Bearing_X | Bearing_Y => 0.0);
               Status : constant Textrender.Status_Code := Font.Get_Glyph (Text.To_Unicode (Item), Metric, Style);
               Advance : Float :=
                 (if Status = Textrender.Success then Metric.Advance_X else Float (Size) / 2.0)
                 + Float (State.Char_Extra + Width_Change);
            begin
               if Status /= Textrender.Success and then not Missing_Reported then
                  Sessions.Warn (S, Errors.Data_Loss, Errors.Data_Loss,
                                 (Sessions.Context_Of (Event) with delta Actual => Byte_Count (Item)));
                  Missing_Reported := True;
               end if;
               if Item = Space then
                  Advance := Advance + Float (State.Space_Extra) / Float (Geometry.Fixed_One);
               end if;
               Outcome :=
                 Paint_Cell (Metric, Status = Textrender.Success and then Metric.W > 0 and then Metric.H > 0, Advance);
               Pen := Pen + Advance;
            end;
         end if;
      end loop;
      if Results.Succeeded (Outcome) and then Has (State.Face, Text.Underline) then
         Outcome := Paint_Underline;
      end if;
      return Outcome;
   end Draw_Characters;
end Pictlib.Internal.Typesetting;
