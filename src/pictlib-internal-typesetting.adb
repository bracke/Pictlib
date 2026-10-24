with Pictlib.Errors;
with Pictlib.Fonts;
with Pictlib.Geometry;
with Pictlib.Images;
with Pictlib.Internal.Regions;
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

   function Context_Of (Event : Pictures.Opcode_Event) return Errors.Diagnostic_Context is
     ((Source => Event.Offset, Op => Event.Op, Has_Opcode => True, Ordinal => Event.Ordinal, others => <>));

   function Has (Face : Byte; Bit : Byte) return Boolean is ((Face and Bit) /= 0);

   function Unavailable (S : in out Sessions.Session; Event : Pictures.Opcode_Event) return Results.Result is
   begin
      if not Sessions.Is_Lenient (S) then
         return Results.Failure (Errors.Make (Errors.Font_Unavailable, Context_Of (Event)));
      end if;
      Sessions.Warn (S, Errors.Approximated_Rendering, Errors.Data_Loss, Context_Of (Event));
      return Results.Success;
   end Unavailable;

   --  The characters, with the font in Slot loaded; called under the textrender lock.
   function Draw_Characters
     (P : in out Rendering.Painter;
      S : in out Sessions.Session;
      Event : Pictures.Opcode_Event;
      Characters : Streams.Byte_Array;
      Slot : Positive;
      Kind : Transfer_Modes.Mode_Kind) return Results.Result;

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
      if Text.Atlas_Bytes (Size) > S.Budget.Max_Allocation_Bytes then
         return Sessions.Over_Limit (S, Allocation_Byte_Limit, S.Budget.Max_Allocation_Bytes, Text.Atlas_Bytes (Size));
      end if;
      --  Loading a font is drawing work, charged before it is done, so a picture that keeps evicting fonts
      --  from the cache runs out of budget.
      if not Text.Cached (P.Font_Cache, Path, Size) then
         Outcome := Rendering.Charge (P, S, Text.Load_Work (Size));
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
         Outcome := Draw_Characters (P, S, Event, Characters, Slot, Kind);
      end;
      return Outcome;
   end Draw;

   function Draw_Characters
     (P : in out Rendering.Painter;
      S : in out Sessions.Session;
      Event : Pictures.Opcode_Event;
      Characters : Streams.Byte_Array;
      Slot : Positive;
      Kind : Transfer_Modes.Mode_Kind) return Results.Result
   is
      State : Text.Text_State renames P.Text_State;
      Size : constant Natural := (if State.Size = 0 then Default_Size else State.Size);
      Outcome : Results.Result := Results.Success;
   begin
      declare
         Font : constant not null access Textrender.Renderer := Text.Renderer (P.Font_Cache, Slot);
         Style : constant Textrender.Font_Style :=
           (if Has (State.Face, Text.Italic) then Textrender.Italic else Textrender.Regular);
         Bold : constant Natural := (if Has (State.Face, Text.Bold) then 1 else 0);
         Width_Change : constant Integer :=
           Bold + (if Has (State.Face, Text.Extend) then 1 else 0) - (if Has (State.Face, Text.Condense) then 1 else 0);
         Baseline : constant Integer := State.Origin_V;
         Ascent : constant Integer := Integer (Float'Ceiling (Font.Ascent));
         Descent : constant Integer := Integer (Float'Ceiling (abs Font.Descent));
         Pen : Float := Float (State.Origin_H);
         Start_X : constant Integer := State.Origin_H;
         Missing_Reported : Boolean := False;
      begin
         for Item of Characters loop
            exit when not Results.Succeeded (Outcome);
            --  Every glyph request is drawing work, wherever the character lands.
            if Item >= Space then
               Outcome := Rendering.Charge (P, S, Text.Glyph_Work (Size));
            end if;
            exit when not Results.Succeeded (Outcome);
            if Item >= Space then
               declare
                  --  Defined even when the font lacks the glyph and leaves it alone.
                  Metric : Textrender.Glyph_Metric :=
                    (X | Y | W | H => 0, U0 | V0 | U1 | V1 | Advance_X | Bearing_X | Bearing_Y => 0.0);
                  Status : constant Textrender.Status_Code :=
                    Font.Get_Glyph (Text.To_Unicode (Item), Metric, Style);
                  Drawable : constant Boolean :=
                    Status = Textrender.Success and then Metric.W > 0 and then Metric.H > 0;
                  Advance : Float :=
                    (if Status = Textrender.Success then Metric.Advance_X else Float (Size) / 2.0)
                    + Float (State.Char_Extra + Width_Change);
               begin
                  if Status /= Textrender.Success and then not Missing_Reported then
                     Sessions.Warn (S, Errors.Data_Loss, Errors.Data_Loss,
                                    (Context_Of (Event) with delta Actual => Byte_Count (Item)));
                     Missing_Reported := True;
                  end if;
                  if Item = Space then
                     Advance := Advance + Float (State.Space_Extra) / Float (Geometry.Fixed_One);
                  end if;
                  declare
                     Cell_Left : constant Integer := Integer (Float'Rounding (Pen));
                     Cell_Right : constant Integer := Integer (Float'Rounding (Pen + Advance));
                     Glyph_Left : constant Integer := Integer (Float'Rounding (Pen + Metric.Bearing_X));
                     Glyph_Top : constant Integer := Baseline - Integer (Metric.Bearing_Y);
                     Atlas_Width : constant Natural := Font.Atlas_Width;
                     Atlas : constant access constant Textrender.Alpha_Buffer := Font.Atlas_Pixels;
                     Left : constant Integer :=
                       (if Drawable then Integer'Min (Cell_Left, Glyph_Left) else Cell_Left);
                     Right : constant Integer :=
                       (if Drawable then Integer'Max (Cell_Right, Glyph_Left + Metric.W + Bold) else Cell_Right);
                     Top : constant Integer :=
                       (if Drawable then Integer'Min (Baseline - Ascent, Glyph_Top) else Baseline - Ascent);
                     Bottom : constant Integer :=
                       (if Drawable then Integer'Max (Baseline + Descent, Glyph_Top + Metric.H)
                        else Baseline + Descent);

                     function Covered (X, Y : Integer) return Boolean is
                       (Drawable
                        and then X - Glyph_Left in 0 .. Metric.W - 1 and then Y - Glyph_Top in 0 .. Metric.H - 1
                        and then Atlas ((Metric.Y + Y - Glyph_Top) * Atlas_Width + Metric.X + X - Glyph_Left)
                                 >= Ink_Threshold);
                  begin
                     --  The character's cell: ink is a black source, the rest a white one, through the text mode.
                     for Y in Integer'Max (Top, P.Window.Top) .. Integer'Min (Bottom, P.Window.Bottom) - 1 loop
                        exit when not Results.Succeeded (Outcome);
                        P.Row_Spans.Clear;
                        P.Row_Spans.Append
                          (Regions.Span'(Integer'Max (Left, P.Window.Left), Integer'Min (Right, P.Window.Right)));
                        Outcome := Rendering.Clip_Row (P, S, Y);
                        for Span of P.Row_Spans loop
                           exit when not Results.Succeeded (Outcome);
                           Outcome := Rendering.Charge (P, S, Natural'Max (0, Span.Right - Span.Left));
                           for X in Span.Left .. Span.Right - 1 loop
                              declare
                                 Ink : constant Boolean :=
                                   Covered (X, Y) or else (Bold = 1 and then Covered (X - 1, Y));
                              begin
                                 Rendering.Put
                                   (P, X, Y,
                                    Transfer_Modes.Compose
                                      (Kind, (if Ink then Images.Black else Images.White), Rendering.Get (P, X, Y),
                                       P.Colors));
                              end;
                           end loop;
                        end loop;
                     end loop;
                  end;
                  Pen := Pen + Advance;
               end;
            end if;
         end loop;

         --  Underline: the row below the baseline, under the whole string.
         if Results.Succeeded (Outcome) and then Has (State.Face, Text.Underline)
           and then Baseline + 1 in P.Window.Top .. P.Window.Bottom - 1
         then
            P.Row_Spans.Clear;
            P.Row_Spans.Append
              (Regions.Span'(Integer'Max (Start_X, P.Window.Left),
                Integer'Min (Integer (Float'Rounding (Pen)), P.Window.Right)));
            Outcome := Rendering.Clip_Row (P, S, Baseline + 1);
            for Span of P.Row_Spans loop
               for X in Span.Left .. Span.Right - 1 loop
                  Rendering.Put
                    (P, X, Baseline + 1,
                     Transfer_Modes.Compose (Kind, Images.Black, Rendering.Get (P, X, Baseline + 1), P.Colors));
               end loop;
            end loop;
         end if;
      end;
      return Outcome;
   end Draw_Characters;
end Pictlib.Internal.Typesetting;
