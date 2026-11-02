with Pictlib.Internal.Sessions.Accounting;
with Ada.Unchecked_Deallocation;
with Pictlib.Internal.Failures;
with Pictlib.Errors;
with Pictlib.Fonts;
with Pictlib.Geometry;
with Pictlib.Images;
with Pictlib.Internal.Text;
with Pictlib.Internal.Transfer_Modes;
with Textrender;

package body Pictlib.Internal.Typesetting is
   package Accounting renames Pictlib.Internal.Sessions.Accounting;
   use type Textrender.Status_Code;
   use type Textrender.Alpha;

   Default_Size : constant := 12;
   Largest_Size : constant := 512;
   --  Coverage at or above this is ink; QuickDraw text has no antialiasing.
   Ink_Threshold : constant := 128;
   Space : constant := 16#20#;
   --  ChExtra is 4.12 fixed point.
   Char_Extra_Unit : constant := 4096.0;
   --  The metric of a glyph the font lacks: textrender leaves its out parameter unset then, so it is never read.
   No_Glyph : constant Textrender.Glyph_Metric :=
     (X | Y | W | H => 0, U0 | V0 | U1 | V1 | Advance_X | Bearing_X | Bearing_Y => 0.0);

   function Has (Face : Byte; Bit : Byte) return Boolean is ((Face and Bit) /= 0);

   function Unavailable (S : in out Sessions.Session; Event : Pictures.Opcode_Event) return Results.Result is
     (Sessions.Reject_Or_Warn
        (S, Errors.Font_Unavailable, Errors.Approximated_Rendering, Failures.Context_Of (Event)));

   --  The characters, with the font in Slot loaded; called under the textrender lock, which Held is.
   function Draw_Characters
     (P : in out Rendering.Painter;
      S : in out Sessions.Session;
      Event : Pictures.Opcode_Event;
      Characters : Streams.Byte_Array;
      Slot : Positive;
      Kind : Transfer_Modes.Mode_Kind;
      Size : Positive;
      Held : Text.Textrender_Guard) return Results.Result;

   function Draw
     (P : in out Rendering.Painter;
      S : in out Sessions.Session;
      Event : Pictures.Opcode_Event;
      Characters : Streams.Byte_Array) return Results.Result
   is
      State : Text.Text_State renames P.Port.Text_State;
      Family : constant String :=
        (if State.Names.Contains (State.Font) then State.Names.Element (State.Font) else "");
      Path : constant String := Fonts.Resolve (P.Fonts, State.Font, Family);
      Size : constant Natural := (if State.Size = 0 then Default_Size else State.Size);
      --  Taken whether or not the text is drawn, as by any drawing.
      Hilited : constant Boolean := Rendering.Take_Hilite (P);
      Outcome : Results.Result := Results.Success;
      Kind : Transfer_Modes.Mode_Kind;
      Slot : Positive;
   begin
      if Characters'Length = 0 then
         return Results.Success;
      elsif Path'Length = 0 then
         return Unavailable (S, Event);
      elsif Size > Largest_Size then
         return Rendering.Unsupported (S, Event, Largest_Size, Byte_Count (Size));
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
            Outcome := Accounting.Admit_Allocation (S, Text.Atlas_Bytes (Size) + File);
            if Results.Succeeded (Outcome) then
               Outcome := Accounting.Charge_Work (S, Text.Load_Work (Size, File));
            end if;
         end;
         if not Results.Succeeded (Outcome) then
            return Outcome;
         end if;
      end if;
      Kind := (if Hilited then Transfer_Modes.Hilite else State.Mode);

      declare
         --  Every textrender call below is made under the process-wide textrender lock, which the calls that
         --  reach textrender require.
         Guard : Text.Textrender_Guard;
      begin
         if Text.Acquire (P.Font_Cache, Path, Size, Slot, Guard) /= Textrender.Success then
            return Unavailable (S, Event);
         end if;
         Outcome := Draw_Characters (P, S, Event, Characters, Slot, Kind, Size, Guard);
      end;
      return Outcome;
   end Draw;

   --  A glyph drawn from the pen paints its cell: the larger of its advance box and its ink.
   type Cell is record
      --  The character, in Mac Roman.
      Item : Byte := 0;
      Metric : Textrender.Glyph_Metric;
      Drawable : Boolean := False;
      Glyph_Left, Glyph_Top : Integer := 0;
      Left, Right, Top, Bottom : Integer := 0;
   end record;
   type Cell_Array is array (Positive range <>) of Cell;
   type Cell_Array_Access is access Cell_Array;
   procedure Free is new Ada.Unchecked_Deallocation (Cell_Array, Cell_Array_Access);

   --  The cell of a glyph drawn at Pen, Advance wide, on Baseline, emboldened by Bold columns. The pen is a
   --  Long_Float: text may start millions of pixels off the frame, where a Float could not hold a fraction.
   function Cell_At
     (Item : Byte;
      Metric : Textrender.Glyph_Metric;
      Drawable : Boolean;
      Pen, Advance : Long_Float;
      Baseline, Ascent, Descent : Integer;
      Bold : Natural) return Cell
   is
      Cell_Left : constant Integer := Integer (Long_Float'Rounding (Pen));
      Cell_Right : constant Integer := Integer (Long_Float'Rounding (Pen + Advance));
      Glyph_Left : constant Integer := Integer (Long_Float'Rounding (Pen + Long_Float (Metric.Bearing_X)));
      Glyph_Top : constant Integer := Baseline - Integer (Metric.Bearing_Y);
   begin
      return
        (Item => Item,
         Metric => Metric,
         Drawable => Drawable,
         Glyph_Left => Glyph_Left,
         Glyph_Top => Glyph_Top,
         Left => (if Drawable then Integer'Min (Cell_Left, Glyph_Left) else Cell_Left),
         Right => (if Drawable then Integer'Max (Cell_Right, Glyph_Left + Metric.W + Bold) else Cell_Right),
         Top => (if Drawable then Integer'Min (Baseline - Ascent, Glyph_Top) else Baseline - Ascent),
         Bottom => (if Drawable then Integer'Max (Baseline + Descent, Glyph_Top + Metric.H) else Baseline + Descent));
   end Cell_At;

   --  How far the pen moves past Item, whose glyph advances Glyph_Advance: the face's width change, and ChExtra
   --  for every character but the space, which SpExtra widens instead.
   function Advance_Of
     (Item : Byte;
      Glyph_Advance : Float;
      Width_Change : Integer;
      State : Text.Text_State) return Long_Float
   is
     (Long_Float (Glyph_Advance) + Long_Float (Width_Change)
      + (if Item = Space then Long_Float (State.Space_Extra) / Long_Float (Geometry.Fixed_One)
         else Long_Float (State.Char_Extra) / Char_Extra_Unit));

   function Draw_Characters
     (P : in out Rendering.Painter;
      S : in out Sessions.Session;
      Event : Pictures.Opcode_Event;
      Characters : Streams.Byte_Array;
      Slot : Positive;
      Kind : Transfer_Modes.Mode_Kind;
      Size : Positive;
      Held : Text.Textrender_Guard) return Results.Result
   is
      State : Text.Text_State renames P.Port.Text_State;
      Font : constant not null access Textrender.Renderer := Text.Renderer (P.Font_Cache, Slot, Held);
      Style : constant Textrender.Font_Style :=
        (if Has (State.Face, Text.Italic) then Textrender.Italic else Textrender.Regular);
      Bold : constant Natural := (if Has (State.Face, Text.Bold) then 1 else 0);
      Width_Change : constant Integer :=
        Bold + (if Has (State.Face, Text.Extend) then 1 else 0) - (if Has (State.Face, Text.Condense) then 1 else 0);
      Baseline : constant Integer := State.Origin_V;
      Ascent : constant Integer := Integer (Float'Ceiling (Font.Ascent));
      Descent : constant Integer := Integer (Float'Ceiling (abs Font.Descent));
      Start_X : constant Integer := State.Origin_H;
      Pen : Long_Float := Long_Float (State.Origin_H);
      Missing_Reported : Boolean := False;
      Outcome : Results.Result := Results.Success;

      --  A character the font cannot draw loses data: said once an opcode, naming the first such character.
      procedure Report_Missing (Item : Byte) is
      begin
         if not Missing_Reported then
            Sessions.Warn (S, Errors.Data_Loss, (Failures.Context_Of (Event) with delta Actual => Byte_Count (Item)));
            Missing_Reported := True;
         end if;
      end Report_Missing;

      --  Text is a bit source: ink black, the rest white, through the text mode.
      function Through_Mode (Ink : Boolean; Under : Images.RGB_Color) return Images.RGB_Color is
        (Transfer_Modes.Compose
           (Kind, (if Ink then Images.Black else Images.White), Under, P.Port.Colors, Bit_Source => True));

      Atlas_Width : constant Natural := Font.Atlas_Width;
      Atlas : access constant Textrender.Alpha_Buffer := Font.Atlas_Pixels;
      --  A metric points into the atlas only until a glyph request empties it, which textrender counts as a new
      --  generation: Cells (Run_First .. Cell_Count) were all taken in the generation Run_Generation.
      Run_First : Positive := 1;
      Run_Generation : Natural := Font.Atlas_Generation;
      --  A text opcode holds at most 255 characters; their cells, some 20 KB, are on the heap all the same, as
      --  a decoder may run in a task with a small stack. Allocated last, after every call that could raise
      --  before the handler below covers it.
      Cells : Cell_Array_Access := new Cell_Array (1 .. Characters'Length);
      Cell_Count : Natural := 0;
      --  The cell Color_At paints.
      Current : Positive := 1;

      function Covered (X, Y : Integer) return Boolean is
        (Cells (Current).Drawable
         and then X - Cells (Current).Glyph_Left in 0 .. Cells (Current).Metric.W - 1
         and then Y - Cells (Current).Glyph_Top in 0 .. Cells (Current).Metric.H - 1
         and then Atlas
           ((Cells (Current).Metric.Y + Y - Cells (Current).Glyph_Top) * Atlas_Width
            + Cells (Current).Metric.X + X - Cells (Current).Glyph_Left) >= Ink_Threshold);

      --  Bold smears ink one pixel right.
      function Glyph_Color (X, Y : Integer; Under : Images.RGB_Color) return Images.RGB_Color is
        (Through_Mode (Covered (X, Y) or else (Bold = 1 and then Covered (X - 1, Y)), Under));
      function Paint_Glyph is new Rendering.Paint_Row (Glyph_Color);

      function Ink_Color (X, Y : Integer; Under : Images.RGB_Color) return Images.RGB_Color is
         pragma Unreferenced (X, Y);
      begin
         return Through_Mode (True, Under);
      end Ink_Color;
      function Paint_Ink is new Rendering.Paint_Row (Ink_Color);

      --  Paint Cells (First .. Last) row by row, top to bottom, so the clip region is walked once for them all;
      --  within a row the cells go in string order. Their metrics must all be of the atlas's current generation.
      function Paint_Run (First, Last : Positive) return Results.Result is
         Top : Integer := Integer'Last;
         Bottom : Integer := Integer'First;
         Result : Results.Result := Results.Success;
      begin
         Atlas := Font.Atlas_Pixels;
         for Index in First .. Last loop
            Top := Integer'Min (Top, Cells (Index).Top);
            Bottom := Integer'Max (Bottom, Cells (Index).Bottom - 1);
         end loop;
         for Y in Integer'Max (Top, P.Window.Top) .. Integer'Min (Bottom, P.Window.Bottom - 1) loop
            for Index in First .. Last loop
               if Y in Cells (Index).Top .. Cells (Index).Bottom - 1 then
                  Current := Index;
                  Result := Rendering.Begin_Row (P, S, Y, Cells (Index).Left, Cells (Index).Right);
                  if Results.Succeeded (Result) then
                     Result := Paint_Glyph (P, S, Y);
                  end if;
                  exit when not Results.Succeeded (Result);
               end if;
            end loop;
            exit when not Results.Succeeded (Result);
         end loop;
         return Result;
      end Paint_Run;

      --  Take cell Index's glyph again, into the atlas as it is now: drawing work like the first request.
      function Retake (Index : Positive) return Results.Result is
         Result : constant Results.Result :=
           (if Cells (Index).Drawable then Accounting.Charge_Work (S, Text.Glyph_Work (Size)) else Results.Success);
         Taken : Textrender.Glyph_Metric;
      begin
         if Results.Succeeded (Result) and then Cells (Index).Drawable then
            if Font.Get_Glyph (Text.To_Unicode (Cells (Index).Item), Taken, Style) = Textrender.Success then
               Cells (Index).Metric := Taken;
            else
               Cells (Index).Metric := No_Glyph;
               Cells (Index).Drawable := False;
               Report_Missing (Cells (Index).Item);
            end if;
         end if;
         return Result;
      end Retake;

      --  The request for cell Last emptied the atlas, so the run's earlier cells point at pixels no longer
      --  theirs. Each is taken again and painted at once, alone, since they may not fit the atlas together;
      --  then cell Last, which those requests may have displaced, starts the next run.
      function Restart_Run (Last : Positive) return Results.Result is
         Taken_In : constant Natural := Font.Atlas_Generation;
         Result : Results.Result := Results.Success;
      begin
         for Index in Run_First .. Last - 1 loop
            Result := Retake (Index);
            if Results.Succeeded (Result) then
               Result := Paint_Run (Index, Index);
            end if;
            exit when not Results.Succeeded (Result);
         end loop;
         if Results.Succeeded (Result) and then Font.Atlas_Generation /= Taken_In then
            Result := Retake (Last);
         end if;
         Run_First := Last;
         Run_Generation := Font.Atlas_Generation;
         return Result;
      end Restart_Run;

      --  The row below the baseline, under the whole string, after every glyph.
      function Paint_Underline return Results.Result is
         Result : constant Results.Result :=
           Rendering.Begin_Row (P, S, Baseline + 1, Start_X, Integer (Long_Float'Rounding (Pen)));
      begin
         return (if Results.Succeeded (Result) then Paint_Ink (P, S, Baseline + 1) else Result);
      end Paint_Underline;

      --  Take Item's glyph as the next cell, its request charged, and restart the run when the request emptied
      --  the atlas. Control characters draw nothing and cost nothing.
      function Take_Glyph (Item : Byte) return Results.Result is
         Result : Results.Result;
      begin
         if Item < Space then
            return Results.Success;
         end if;
         --  Every glyph request is drawing work, wherever the character lands.
         Result := Accounting.Charge_Work (S, Text.Glyph_Work (Size));
         if not Results.Succeeded (Result) then
            return Result;
         end if;
         declare
            Taken : Textrender.Glyph_Metric;
            Status : constant Textrender.Status_Code := Font.Get_Glyph (Text.To_Unicode (Item), Taken, Style);
            Metric : constant Textrender.Glyph_Metric := (if Status = Textrender.Success then Taken else No_Glyph);
            Advance : constant Long_Float :=
              Advance_Of (Item, (if Status = Textrender.Success then Metric.Advance_X else Float (Size) / 2.0),
                          Width_Change, State);
         begin
            if Status /= Textrender.Success then
               Report_Missing (Item);
            end if;
            Cell_Count := Cell_Count + 1;
            Cells (Cell_Count) :=
              Cell_At (Item, Metric,
                       Status = Textrender.Success and then Metric.W > 0 and then Metric.H > 0,
                       Pen, Advance, Baseline, Ascent, Descent, Bold);
            Pen := Pen + Advance;
            if Font.Atlas_Generation /= Run_Generation then
               Result := Restart_Run (Cell_Count);
            end if;
         end;
         return Result;
      end Take_Glyph;
   begin
      for Item of Characters loop
         Outcome := Take_Glyph (Item);
         --  A failed charge or restart ends the text: a later, smaller charge must not paper over it.
         exit when not Results.Succeeded (Outcome);
      end loop;
      if Results.Succeeded (Outcome) and then Cell_Count >= Run_First then
         Outcome := Paint_Run (Run_First, Cell_Count);
      end if;
      if Results.Succeeded (Outcome) and then Has (State.Face, Text.Underline) then
         Outcome := Paint_Underline;
      end if;
      Free (Cells);
      return Outcome;
   exception
      when others =>
         Free (Cells);
         raise;
   end Draw_Characters;
end Pictlib.Internal.Typesetting;
