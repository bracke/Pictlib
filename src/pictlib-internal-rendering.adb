with Pictlib.Errors;

package body Pictlib.Internal.Rendering is
   use type Geometry.Rect;
   use type Patterns.Pattern_Kind;
   use type Transfer_Modes.Effect_Kind;

   procedure Start
     (P : in out Painter;
      View : Images.Mutable_Image_View;
      Frame : Geometry.Rect;
      Background : Images.RGB_Color;
      Font_Files : Pictlib.Fonts.Font_Table) is
   begin
      Canvas.Bind (P.Target, View);
      Canvas.Fill (P.Target, Background);
      P.Window := Regions.To_Area (Frame);
      P.Origin_H := 0;
      P.Origin_V := 0;
      P.Has_Clip := False;
      P.Clip := Regions.Rectangle (P.Window);
      P.Colors := (others => <>);
      P.Pen_Width := 1;
      P.Pen_Height := 1;
      P.Pen_Mode := Transfer_Modes.Copy;
      P.Pattern_Set := [for Slot in Pattern_Slot => Default_Pattern (Slot)];
      P.Pen_H := 0;
      P.Pen_V := 0;
      P.Oval_Width := 0;
      P.Oval_Height := 0;
      P.Hilite_Next := False;
      P.Skip_Next_Bits := False;
      P.Last_Rect := (others => 0);
      P.Last_Polygon.Clear;
      P.Last_Region := Regions.Rectangle ((others => 0));
      P.Text_State := (others => <>);
      P.Fonts := Font_Files;
      Text.Clear (P.Font_Cache);
      P.Work := 0;
   end Start;

   function Charge (P : in out Painter; S : Sessions.Session; Units : Natural) return Results.Result is
     (Charge (P, S, Pixel_Count (Units)));

   function Over_Budget (P : Painter; S : Sessions.Session; Units : Pixel_Count) return Results.Result is
     (Sessions.Over_Work (S, P.Work, Units));

   function Charge (P : in out Painter; S : Sessions.Session; Units : Pixel_Count) return Results.Result is
   begin
      if Units > Allowance (P, S) then
         return Over_Budget (P, S, Units);
      end if;
      P.Work := P.Work + Units;
      return Results.Success;
   end Charge;

   function Context_Of (Event : Pictures.Opcode_Event) return Errors.Diagnostic_Context is
     ((Source => Event.Offset, Op => Event.Op, Has_Opcode => True, Ordinal => Event.Ordinal, others => <>));

   function Unsupported
     (S : in out Sessions.Session;
      Event : Pictures.Opcode_Event;
      Expected, Actual : Byte_Count := 0) return Results.Result
   is
      Context : constant Errors.Diagnostic_Context :=
        (Context_Of (Event) with delta Expected => Expected, Actual => Actual);
   begin
      if not Sessions.Is_Lenient (S) then
         return Results.Failure (Errors.Make (Errors.Unsupported_Feature, Context));
      end if;
      Sessions.Warn (S, Errors.Approximated_Rendering, Errors.Data_Loss, Context);
      return Results.Success;
   end Unsupported;

   function Mode
     (S : in out Sessions.Session;
      Event : Pictures.Opcode_Event;
      Value : Interfaces.Unsigned_16;
      Kind : out Transfer_Modes.Mode_Kind) return Results.Result is
   begin
      if Transfer_Modes.Classify (Value, Kind) then
         return Results.Success;
      elsif not Sessions.Is_Lenient (S) then
         return Results.Failure
           (Errors.Make (Errors.Transfer_Mode_Invalid, (Context_Of (Event) with delta Actual => Byte_Count (Value))));
      end if;
      Sessions.Warn (S, Errors.Recovery_Applied, Errors.Recovery,
                     (Context_Of (Event) with delta Actual => Byte_Count (Value)));
      Kind := Transfer_Modes.Copy;
      return Results.Success;
   end Mode;

   function Clip_Row (P : in out Painter; S : Sessions.Session; Y : Integer) return Results.Result is
      Work : Natural;
   begin
      if not P.Has_Clip then
         return Results.Success;
      end if;
      --  The clip is local: picture row Y is its row Y + origin, and its columns lie origin to the right.
      Regions.Row_Spans (P.Clip, Y + P.Origin_V, P.Clip_Spans, Work, Walk_Allowance (P, S));
      for Item of P.Clip_Spans loop
         Item := (Item.Left - P.Origin_H, Item.Right - P.Origin_H);
      end loop;
      Regions.Intersect (P.Row_Spans, P.Clip_Spans, P.Scratch);
      P.Row_Spans.Move (P.Scratch);
      return Charge (P, S, Work);
   end Clip_Row;

   procedure Put (P : in out Painter; X, Y : Integer; Color : Images.RGB_Color) is
   begin
      Canvas.Put (P.Target, X - P.Window.Left, Y - P.Window.Top, Color);
   end Put;

   function Get (P : Painter; X, Y : Integer) return Images.RGB_Color is
     (Canvas.Get (P.Target, X - P.Window.Left, Y - P.Window.Top));

   function Fill
     (P : in out Painter;
      S : Sessions.Session;
      Shape : Coverage.Shape;
      How : Paint) return Results.Result
   is
      --  Building the shape, a unit for the opcode and one for every row painting walks. A shape that spent its
      --  allowance is over the limit, whatever allowance it was built with.
      Walked : constant Pixel_Count :=
        1 + Pixel_Count (Integer'Max (0, Coverage.Last_Row (Shape) - Coverage.First_Row (Shape) + 1));
      Outcome : Results.Result :=
        (if Coverage.Exhausted (Shape) then Over_Budget (P, S, Coverage.Work (Shape))
         elsif Coverage.Work (Shape) > Pixel_Count'Last - Walked then Over_Budget (P, S, Pixel_Count'Last)
         else Charge (P, S, Coverage.Work (Shape) + Walked));
      Source : Patterns.Pattern renames P.Pattern_Set (How.Source);
      Colorize : constant Boolean := Patterns.Kind (Source) = Patterns.Bit_Pattern;
      Kind : constant Transfer_Modes.Mode_Kind :=
        (if P.Hilite_Next then Transfer_Modes.Hilite else How.Mode);
   begin
      P.Hilite_Next := False;
      --  A uniform pattern whose result does not depend on the pixels under it paints one color, or nothing.
      if How.Kind = Pattern_Paint then
         declare
            Sample : Images.RGB_Color;
            Color : Images.RGB_Color;
            Effect : Transfer_Modes.Effect_Kind := Transfer_Modes.Depends_On_Destination;
         begin
            if Patterns.Uniform (Source, Sample) then
               Effect := Transfer_Modes.Effect (Kind, Sample, P.Colors, Colorize, Color);
            end if;
            if Effect = Transfer_Modes.Unchanged then
               return Outcome;
            elsif Effect = Transfer_Modes.Constant_Color then
               for Y in Coverage.First_Row (Shape) .. Coverage.Last_Row (Shape) loop
                  exit when not Results.Succeeded (Outcome);
                  P.Row_Spans := Coverage.Row (Shape, Y);
                  if not P.Row_Spans.Is_Empty then
                     Outcome := Clip_Row (P, S, Y);
                     for Span of P.Row_Spans loop
                        exit when not Results.Succeeded (Outcome);
                        Outcome := Charge (P, S, Span.Right - Span.Left);
                        if Results.Succeeded (Outcome) and then Span.Left < Span.Right then
                           Canvas.Put_Span
                             (P.Target, Span.Left - P.Window.Left, Span.Right - P.Window.Left,
                              Y - P.Window.Top, Color);
                        end if;
                     end loop;
                  end if;
               end loop;
               return Outcome;
            end if;
         end;
      end if;
      --  Only the rows the shape holds.
      for Y in Coverage.First_Row (Shape) .. Coverage.Last_Row (Shape) loop
         exit when not Results.Succeeded (Outcome);
         P.Row_Spans := Coverage.Row (Shape, Y);
         if not P.Row_Spans.Is_Empty then
            Outcome := Clip_Row (P, S, Y);
            for Span of P.Row_Spans loop
               exit when not Results.Succeeded (Outcome);
               Outcome := Charge (P, S, Span.Right - Span.Left);
               if Results.Succeeded (Outcome) then
                  for X in Span.Left .. Span.Right - 1 loop
                     if How.Kind = Invert_Paint then
                        Put (P, X, Y, Transfer_Modes.Invert (Get (P, X, Y)));
                     else
                        Put (P, X, Y,
                             Transfer_Modes.Compose
                               (Kind, Patterns.Sample (Source, X, Y), Get (P, X, Y), P.Colors, Colorize));
                     end if;
                  end loop;
               end if;
            end loop;
         end if;
      end loop;
      return Outcome;
   end Fill;

   function Ceiling_Divide (Left, Right : Long_Long_Integer) return Long_Long_Integer is ((Left + Right - 1) / Right);

   --  Paint the destination rows that sample source row Source_Y of Decoder.
   function Put_Row
     (P : in out Painter;
      S : Sessions.Session;
      Header : Pixmaps.Bits_Header;
      Source : Geometry.Rect;
      Destination : Area;
      Kind : Transfer_Modes.Mode_Kind;
      Mask : in out Regions.Region;
      Decoder : Pixmaps.Row_Decoder;
      Source_Y : Integer) return Results.Result
   is
      Source_Width : constant Long_Long_Integer := Long_Long_Integer (Geometry.Width (Source));
      Source_Height : constant Long_Long_Integer := Long_Long_Integer (Geometry.Height (Source));
      Destination_Width : constant Long_Long_Integer := Long_Long_Integer (Destination.Right - Destination.Left);
      Destination_Height : constant Long_Long_Integer := Long_Long_Integer (Destination.Bottom - Destination.Top);
      Relative : constant Long_Long_Integer := Long_Long_Integer (Source_Y) - Long_Long_Integer (Source.Top);
      --  Destination rows k sample source row floor (k * Source_Height / Destination_Height).
      First_Row : constant Long_Long_Integer := Ceiling_Divide (Relative * Destination_Height, Source_Height);
      Last_Row : constant Long_Long_Integer := Ceiling_Divide ((Relative + 1) * Destination_Height, Source_Height) - 1;
      Outcome : Results.Result;
      Work : Natural;
   begin
      if Relative < 0 or else Relative >= Source_Height then
         return Results.Success;
      end if;
      for K in First_Row .. Last_Row loop
         declare
            Y : constant Integer := Destination.Top + Integer (K);
         begin
            if Y in P.Window.Top .. P.Window.Bottom - 1 then
               P.Row_Spans.Clear;
               P.Row_Spans.Append
                 (Regions.Span'(Integer'Max (Destination.Left, P.Window.Left),
                                Integer'Min (Destination.Right, P.Window.Right)));
               Outcome := Clip_Row (P, S, Y);
               if not Results.Succeeded (Outcome) then
                  return Outcome;
               end if;
               if Header.Masked then
                  Regions.Row_Spans (Mask, Y, P.Mask_Spans, Work, Walk_Allowance (P, S));
                  Outcome := Charge (P, S, Work);
                  if not Results.Succeeded (Outcome) then
                     return Outcome;
                  end if;
                  Regions.Intersect (P.Row_Spans, P.Mask_Spans, P.Scratch);
                  P.Row_Spans.Move (P.Scratch);
               end if;

               for Item of P.Row_Spans loop
                  if Item.Left < Item.Right then
                     Outcome := Charge (P, S, Item.Right - Item.Left);
                     if not Results.Succeeded (Outcome) then
                        return Outcome;
                     end if;
                     for X in Item.Left .. Item.Right - 1 loop
                        declare
                           Column : constant Long_Long_Integer :=
                             (Long_Long_Integer (X) - Long_Long_Integer (Destination.Left)) * Source_Width
                             / Destination_Width;
                           Source_X : constant Integer := Integer (Source.Left) + Integer (Column);
                           Pixel : constant Images.RGB_Color :=
                             Pixmaps.Pixel (Decoder, Source_X - Integer (Header.Bounds.Left));
                        begin
                           Put (P, X, Y, Transfer_Modes.Compose (Kind, Pixel, Get (P, X, Y), P.Colors));
                        end;
                     end loop;
                  end if;
               end loop;
            end if;
         end;
      end loop;
      return Results.Success;
   end Put_Row;

   --  The part of srcRect inside the bounds; a strict decoder rejects a srcRect reaching outside them.
   function Source_Rect (S : in out Sessions.Session; Header : Pixmaps.Bits_Header; Event : Pictures.Opcode_Event;
                         Source : out Geometry.Rect) return Results.Result
   is
      Bounds : constant Geometry.Rect := Header.Bounds;
      Wanted : constant Geometry.Rect := Header.Source;
   begin
      Source :=
        (Top => Coordinate'Max (Wanted.Top, Bounds.Top), Left => Coordinate'Max (Wanted.Left, Bounds.Left),
         Bottom => Coordinate'Min (Wanted.Bottom, Bounds.Bottom), Right => Coordinate'Min (Wanted.Right, Bounds.Right));
      if Source /= Wanted and then not Geometry.Is_Empty (Wanted) then
         if not Sessions.Is_Lenient (S) then
            return Results.Failure (Errors.Make (Errors.Pixmap_Invalid, Context_Of (Event)));
         end if;
         Sessions.Warn (S, Errors.Recovery_Applied, Errors.Recovery, Context_Of (Event));
      end if;
      return Results.Success;
   end Source_Rect;

   --  Rows a copy skips undrawn cost a unit each, as their framing is still read.
   function Skip_Rows (P : in out Painter; S : in out Sessions.Session; Header : Pixmaps.Bits_Header)
     return Results.Result
   is
      Outcome : constant Results.Result := Charge (P, S, Header.Height);
   begin
      if not Results.Succeeded (Outcome) then
         return Outcome;
      end if;
      return Pixmaps.Skip_Pixels (S, Header);
   end Skip_Rows;

   function Copy_Bits
     (P : in out Painter;
      S : in out Sessions.Session;
      Header : Pixmaps.Bits_Header;
      Mask : in out Regions.Region;
      Event : Pictures.Opcode_Event) return Results.Result
   is
      Decoder : Pixmaps.Row_Decoder;
      Source : Geometry.Rect;
      Destination : constant Area := To_Picture (P, Header.Destination);
      Kind : Transfer_Modes.Mode_Kind;
      Outcome : Results.Result;
   begin
      --  A QuickTime image's placeholder is skipped like any undrawn copy: its rows are read whatever the image
      --  cost.
      if P.Skip_Next_Bits then
         P.Skip_Next_Bits := False;
         return Skip_Rows (P, S, Header);
      end if;
      Outcome := Mode (S, Event, Header.Mode, Kind);
      if P.Hilite_Next then
         Kind := Transfer_Modes.Hilite;
         P.Hilite_Next := False;
      end if;
      if Results.Succeeded (Outcome) then
         Outcome := Source_Rect (S, Header, Event, Source);
      end if;
      if not Results.Succeeded (Outcome) then
         return Outcome;
      end if;
      if Geometry.Is_Empty (Source) or else Regions.Is_Empty (Destination) then
         return Skip_Rows (P, S, Header);
      end if;
      if Header.Masked then
         Regions.Translate (Mask, -P.Origin_H, -P.Origin_V);
      end if;

      Outcome := Pixmaps.Start (S, Decoder, Header);
      for Row in 0 .. Header.Height - 1 loop
         exit when not Results.Succeeded (Outcome);
         --  Each row is converted whether or not any of it is drawn.
         Outcome := Charge (P, S, Header.Width + 1);
         if Results.Succeeded (Outcome) then
            Outcome := Pixmaps.Read_Row (S, Decoder, Row);
         end if;
         if Results.Succeeded (Outcome) then
            Outcome := Put_Row (P, S, Header, Source, Destination, Kind, Mask, Decoder,
                                Integer (Header.Bounds.Top) + Row);
         end if;
      end loop;
      Pixmaps.Finish (Decoder);
      return Outcome;
   end Copy_Bits;
end Pictlib.Internal.Rendering;
