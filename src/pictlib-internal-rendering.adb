with Pictlib.Internal.Checked_Arithmetic;
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
      Canvas.Bind (P.Machine.Target, View);
      Canvas.Fill (P.Machine.Target, Background);
      P.Window := Regions.To_Area (Frame);
      P.Port := (others => <>);
      P.Fonts := Font_Files;
      Text.Clear (P.Font_Cache);
   end Start;

   function Unsupported
     (S : in out Sessions.Session;
      Event : Pictures.Opcode_Event;
      Expected, Actual : Byte_Count := 0) return Results.Result is
   begin
      return Sessions.Reject_Or_Warn
        (S, Errors.Unsupported_Feature, Errors.Approximated_Rendering, Errors.Data_Loss,
         (Sessions.Context_Of (Event) with delta Expected => Expected, Actual => Actual));
   end Unsupported;

   function Mode
     (S : in out Sessions.Session;
      Event : Pictures.Opcode_Event;
      Value : Interfaces.Unsigned_16;
      Kind : out Transfer_Modes.Mode_Kind) return Results.Result is
   begin
      if Transfer_Modes.Classify (Value, Kind) then
         return Results.Success;
      end if;
      --  Leniently an unknown mode is copy.
      Kind := Transfer_Modes.Copy;
      return Sessions.Reject_Or_Warn
        (S, Errors.Transfer_Mode_Invalid, Errors.Recovery_Applied, Errors.Recovery,
         (Sessions.Context_Of (Event) with delta Actual => Byte_Count (Value)));
   end Mode;

   function Drawing_Mode
     (S : in out Sessions.Session;
      Event : Pictures.Opcode_Event;
      Value : Interfaces.Unsigned_16;
      Hilited : Boolean;
      Kind : out Transfer_Modes.Mode_Kind) return Results.Result
   is
      Outcome : constant Results.Result := Mode (S, Event, Value, Kind);
   begin
      if Hilited then
         Kind := Transfer_Modes.Hilite;
      end if;
      return Outcome;
   end Drawing_Mode;

   function Take_Hilite (P : in out Painter) return Boolean is
      Hilited : constant Boolean := P.Port.Hilite_Next;
   begin
      P.Port.Hilite_Next := False;
      return Hilited;
   end Take_Hilite;

   function Clip_Row (P : in out Painter; S : in out Sessions.Session; Y : Integer) return Results.Result is
      Work : Pixel_Count;
   begin
      if not P.Port.Has_Clip then
         return Results.Success;
      end if;
      --  The clip is local: picture row Y is its row Y + origin, and its columns lie origin to the right.
      Regions.Row_Spans (P.Port.Clip, Y + P.Port.Origin_V, P.Machine.Clip_Spans, Work, Sessions.Work_Left (S));
      for Item of P.Machine.Clip_Spans loop
         Item := (Item.Left - P.Port.Origin_H, Item.Right - P.Port.Origin_H);
      end loop;
      Regions.Intersect (P.Machine.Row_Spans, P.Machine.Clip_Spans, P.Machine.Scratch);
      P.Machine.Row_Spans.Move (P.Machine.Scratch);
      return Sessions.Charge_Work (S, Work);
   end Clip_Row;

   procedure Put (P : in out Painter; X, Y : Integer; Color : Images.RGB_Color) is
   begin
      Canvas.Put (P.Machine.Target, X - P.Window.Left, Y - P.Window.Top, Color);
   end Put;

   function Get (P : Painter; X, Y : Integer) return Images.RGB_Color is
     (Canvas.Get (P.Machine.Target, X - P.Window.Left, Y - P.Window.Top));

   function Begin_Row (P : in out Painter; S : in out Sessions.Session; Y, Left, Right : Integer)
     return Results.Result
   is
      First : constant Integer := Integer'Max (Left, P.Window.Left);
      Last : constant Integer := Integer'Min (Right, P.Window.Right);
   begin
      P.Machine.Row_Spans.Clear;
      if Y not in P.Window.Top .. P.Window.Bottom - 1 or else First >= Last then
         return Results.Success;
      end if;
      P.Machine.Row_Spans.Append (Regions.Span'(First, Last));
      return Clip_Row (P, S, Y);
   end Begin_Row;

   function Row_Is_Empty (P : Painter) return Boolean is (P.Machine.Row_Spans.Is_Empty);

   function Mask_Row (P : in out Painter; S : in out Sessions.Session; Mask : in out Regions.Region; Y : Integer)
     return Results.Result
   is
      Work : Pixel_Count;
      Outcome : Results.Result;
   begin
      Regions.Row_Spans (Mask, Y, P.Machine.Mask_Spans, Work, Sessions.Work_Left (S));
      Outcome := Sessions.Charge_Work (S, Work);
      if Results.Succeeded (Outcome) then
         Regions.Intersect (P.Machine.Row_Spans, P.Machine.Mask_Spans, P.Machine.Scratch);
         P.Machine.Row_Spans.Move (P.Machine.Scratch);
      end if;
      return Outcome;
   end Mask_Row;

   function Begin_Masked_Row
     (P : in out Painter;
      S : in out Sessions.Session;
      Y, Left, Right : Integer;
      Mask : in out Regions.Region;
      Masked : Boolean) return Results.Result
   is
      Outcome : constant Results.Result := Begin_Row (P, S, Y, Left, Right);
   begin
      if Results.Succeeded (Outcome) and then Masked and then not Row_Is_Empty (P) then
         return Mask_Row (P, S, Mask, Y);
      end if;
      return Outcome;
   end Begin_Masked_Row;

   function Paint_Row (P : in out Painter; S : in out Sessions.Session; Y : Integer) return Results.Result is
      Outcome : Results.Result := Results.Success;
   begin
      for Span of P.Machine.Row_Spans loop
         Outcome := Sessions.Charge_Work (S, Span.Right - Span.Left);
         exit when not Results.Succeeded (Outcome);
         for X in Span.Left .. Span.Right - 1 loop
            Put (P, X, Y, Color_At (X, Y, Get (P, X, Y)));
         end loop;
      end loop;
      return Outcome;
   end Paint_Row;

   function Paint_Row_Color (P : in out Painter; S : in out Sessions.Session; Y : Integer; Color : Images.RGB_Color)
     return Results.Result
   is
      Outcome : Results.Result := Results.Success;
   begin
      for Span of P.Machine.Row_Spans loop
         Outcome := Sessions.Charge_Work (S, Span.Right - Span.Left);
         exit when not Results.Succeeded (Outcome);
         Canvas.Put_Span
           (P.Machine.Target, Span.Left - P.Window.Left, Span.Right - P.Window.Left, Y - P.Window.Top, Color);
      end loop;
      return Outcome;
   end Paint_Row_Color;

   function Fill
     (P : in out Painter;
      S : in out Sessions.Session;
      Shape : Coverage.Shape;
      How : Paint) return Results.Result
   is
      --  Building the shape, a unit for the opcode and one for every row painting walks. A shape that spent its
      --  allowance is over the limit, whatever allowance it was built with.
      Walked : constant Pixel_Count :=
        1 + Pixel_Count (Integer'Max (0, Coverage.Last_Row (Shape) - Coverage.First_Row (Shape) + 1));
      Outcome : Results.Result :=
        (if Coverage.Exhausted (Shape) then Sessions.Over_Work (S, Coverage.Work (Shape))
         else Sessions.Charge_Work (S, Checked_Arithmetic.Saturating_Add (Coverage.Work (Shape), Walked)));
      Source : Patterns.Pattern renames P.Port.Pattern_Set (How.Source);
      Colorize : constant Boolean := Patterns.Kind (Source) = Patterns.Bit_Pattern;
      Kind : constant Transfer_Modes.Mode_Kind := (if Take_Hilite (P) then Transfer_Modes.Hilite else How.Mode);
   begin
      --  The spans building made count against the session's allocation total.
      if Results.Succeeded (Outcome) then
         Outcome := Sessions.Admit_Aggregate
           (S, Checked_Arithmetic.Saturating_Multiply
                 (Byte_Count (Coverage.Work (Shape)), Sessions.Shape_Bytes_Per_Work_Unit));
      end if;
      declare
         Sample, Color : Images.RGB_Color := Images.Black;
         Effect : Transfer_Modes.Effect_Kind := Transfer_Modes.Depends_On_Destination;

         function Color_At (X, Y : Integer; Under : Images.RGB_Color) return Images.RGB_Color is
           (if How.Kind = Invert_Paint then Transfer_Modes.Invert (Under)
            else Transfer_Modes.Compose
                   (Kind, Patterns.Sample (Source, X, Y), Under, P.Port.Colors, Colorize, Bit_Source => Colorize));
         function Paint is new Paint_Row (Color_At);
      begin
         --  A uniform pattern whose result does not depend on the pixels under it paints one color, or nothing.
         if How.Kind = Pattern_Paint and then Patterns.Uniform (Source, Sample) then
            Effect := Transfer_Modes.Effect (Kind, Sample, P.Port.Colors, Colorize, Color);
         end if;
         if Effect = Transfer_Modes.Unchanged then
            return Outcome;
         end if;
         --  Only the rows the shape holds.
         for Y in Coverage.First_Row (Shape) .. Coverage.Last_Row (Shape) loop
            exit when not Results.Succeeded (Outcome);
            P.Machine.Row_Spans := Coverage.Row (Shape, Y);
            if not P.Machine.Row_Spans.Is_Empty then
               Outcome := Clip_Row (P, S, Y);
               if Results.Succeeded (Outcome) then
                  Outcome :=
                    (if Effect = Transfer_Modes.Constant_Color then Paint_Row_Color (P, S, Y, Color)
                     else Paint (P, S, Y));
               end if;
            end if;
         end loop;
      end;
      return Outcome;
   end Fill;

   --  Paint the destination rows that sample source row Source_Y of Decoder.
   function Put_Row
     (P : in out Painter;
      S : in out Sessions.Session;
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
      --  Destination rows k sample source row Sampled (k, Source_Height, Destination_Height): these.
      First_Row : constant Long_Long_Integer :=
        Coverage.Ceiling_Divide (Relative * Destination_Height, Source_Height);
      Last_Row : constant Long_Long_Integer :=
        Coverage.Ceiling_Divide ((Relative + 1) * Destination_Height, Source_Height) - 1;
      Outcome : Results.Result;

      function Color_At (X, Y : Integer; Under : Images.RGB_Color) return Images.RGB_Color is
         pragma Unreferenced (Y);
         Source_X : constant Integer :=
           Integer (Source.Left) + Sampled (X - Destination.Left, Source_Width, Destination_Width);
      begin
         return Transfer_Modes.Compose
           (Kind, Pixmaps.Pixel (Decoder, Source_X - Integer (Header.Bounds.Left)), Under, P.Port.Colors);
      end Color_At;
      function Paint is new Paint_Row (Color_At);
   begin
      if Relative < 0 or else Relative >= Source_Height then
         return Results.Success;
      end if;
      for K in First_Row .. Last_Row loop
         declare
            Y : constant Integer := Destination.Top + Integer (K);
         begin
            --  Every destination row a copy walks costs a unit, in the frame or not.
            Outcome := Sessions.Charge_Work (S, Natural'(1));
            if not Results.Succeeded (Outcome) then
               return Outcome;
            end if;
            Outcome := Begin_Masked_Row (P, S, Y, Destination.Left, Destination.Right, Mask, Header.Masked);
            if Results.Succeeded (Outcome) then
               Outcome := Paint (P, S, Y);
            end if;
            if not Results.Succeeded (Outcome) then
               return Outcome;
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
         return Sessions.Reject_Or_Warn
           (S, Errors.Pixmap_Invalid, Errors.Recovery_Applied, Errors.Recovery, Sessions.Context_Of (Event));
      end if;
      return Results.Success;
   end Source_Rect;

   --  Rows a copy skips undrawn cost a unit each, as their framing is still read.
   function Skip_Copy (S : in out Sessions.Session; Header : Pixmaps.Bits_Header)
     return Results.Result
   is
      Outcome : constant Results.Result := Sessions.Charge_Work (S, Header.Height);
   begin
      if not Results.Succeeded (Outcome) then
         return Outcome;
      end if;
      return Pixmaps.Skip_Pixels (S, Header);
   end Skip_Copy;

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
      if P.Port.Skip_Next_Bits then
         P.Port.Skip_Next_Bits := False;
         return Skip_Copy (S, Header);
      end if;
      Outcome := Drawing_Mode (S, Event, Header.Mode, Take_Hilite (P), Kind);
      if Results.Succeeded (Outcome) then
         Outcome := Source_Rect (S, Header, Event, Source);
      end if;
      if not Results.Succeeded (Outcome) then
         return Outcome;
      end if;
      if Geometry.Is_Empty (Source) or else Regions.Is_Empty (Destination) then
         return Skip_Copy (S, Header);
      end if;
      if Header.Masked then
         Regions.Translate (Mask, -P.Port.Origin_H, -P.Port.Origin_V);
      end if;

      Outcome := Pixmaps.Start (S, Decoder, Header);
      for Row in 0 .. Header.Height - 1 loop
         exit when not Results.Succeeded (Outcome);
         --  Each row is converted whether or not any of it is drawn.
         Outcome := Sessions.Charge_Work (S, Header.Width + 1);
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
