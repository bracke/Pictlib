with Pictlib.Internal.Sessions.Accounting;
with Pictlib.Internal.Failures;
with Pictlib.Internal.Divisions;
with Pictlib.Internal.Checked_Arithmetic;
with Pictlib.Errors;

package body Pictlib.Internal.Rendering is
   package Accounting renames Pictlib.Internal.Sessions.Accounting;
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
         (Failures.Context_Of (Event) with delta Expected => Expected, Actual => Actual));
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
         (Failures.Context_Of (Event) with delta Actual => Byte_Count (Value)));
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

   --  Cut Row_Spans to Item's row Row, its columns Shift to the left of the row's: the region walk is charged
   --  first, and the row is cut only once it is paid for.
   function Cut_Row
     (S : in out Sessions.Session;
      Item : in out Regions.Region;
      Row, Shift : Integer;
      Cut, Row_Spans, Scratch : in out Regions.Span_Vectors.Vector) return Results.Result
   is
      Work : Pixel_Count;
      Outcome : Results.Result;
   begin
      Regions.Row_Spans (Item, Row, Cut, Work, Accounting.Work_Left (S));
      Outcome := Accounting.Charge_Work (S, Work);
      if Results.Succeeded (Outcome) then
         if Shift /= 0 then
            for Span of Cut loop
               Span := (Span.Left - Shift, Span.Right - Shift);
            end loop;
         end if;
         Regions.Intersect (Row_Spans, Cut, Scratch);
         Row_Spans.Move (Scratch);
      end if;
      return Outcome;
   end Cut_Row;

   --  The clip is local: picture row Y is its row Y + origin, and its columns lie origin to the right.
   function Clip_Row (P : in out Painter; S : in out Sessions.Session; Y : Integer) return Results.Result is
     (if not P.Port.Has_Clip then Results.Success
      else Cut_Row (S, P.Port.Clip, Y + P.Port.Origin_V, P.Port.Origin_H, P.Machine.Clip_Spans, P.Machine.Row_Spans,
                    P.Machine.Scratch));

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
     return Results.Result is
     (Cut_Row (S, Mask, Y, 0, P.Machine.Mask_Spans, P.Machine.Row_Spans, P.Machine.Scratch));

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
         Outcome := Accounting.Charge_Work (S, Span.Right - Span.Left);
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
         Outcome := Accounting.Charge_Work (S, Span.Right - Span.Left);
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
      Outcome : Results.Result := Results.Success;
      Source : Patterns.Pattern renames P.Port.Pattern_Set (How.Source);
      Colorize : constant Boolean := Patterns.Kind (Source) = Patterns.Bit_Pattern;
      Hilited : constant Boolean := Take_Hilite (P);
      Kind : constant Transfer_Modes.Mode_Kind := (if Hilited then Transfer_Modes.Hilite else How.Mode);
   begin
      --  A shape's allowance is the lesser of the drawing work and the spans the allocation total admits, so a
      --  spent shape names whichever of the two it crossed.
      if not Coverage.Exhausted (Shape) then
         Outcome := Accounting.Charge_Work (S, Checked_Arithmetic.Saturating_Add (Coverage.Work (Shape), Walked));
      elsif Coverage.Work (Shape) > Accounting.Work_Left (S) then
         return Accounting.Over_Work (S, Coverage.Work (Shape));
      else
         Outcome := Accounting.Admit_Aggregate
           (S, Checked_Arithmetic.Saturating_Multiply
                 (Byte_Count (Coverage.Work (Shape)), Accounting.Shape_Bytes_Per_Work_Unit));
         return (if Results.Succeeded (Outcome) then Accounting.Over_Work (S, Coverage.Work (Shape)) else Outcome);
      end if;
      --  The spans building made count against the session's allocation total.
      if Results.Succeeded (Outcome) then
         Outcome := Accounting.Admit_Aggregate
           (S, Checked_Arithmetic.Saturating_Multiply
                 (Byte_Count (Coverage.Work (Shape)), Accounting.Shape_Bytes_Per_Work_Unit));
      end if;
      declare
         Sample, Color : Images.RGB_Color := Images.Black;
         Effect : Transfer_Modes.Effect_Kind := Transfer_Modes.Depends_On_Destination;

         --  An invert after HiliteMode highlights: every pixel is dark, so the background and highlight swap.
         function Color_At (X, Y : Integer; Under : Images.RGB_Color) return Images.RGB_Color is
           (if How.Kind = Invert_Paint and then not Hilited then Transfer_Modes.Invert (Under)
            elsif How.Kind = Invert_Paint
            then Transfer_Modes.Compose (Kind, Images.Black, Under, P.Port.Colors, Colorize => False,
                                         Bit_Source => True)
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
            Coverage.Copy_Row (Shape, Y, P.Machine.Row_Spans);
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

   --  Paint the destination rows that sample source row Source_Y of Decoder, srcRect mapped onto Destination;
   --  only columns Painted.Left .. Painted.Right - 1, those sampling the bounds, are painted.
   function Put_Row
     (P : in out Painter;
      S : in out Sessions.Session;
      Header : Pixmaps.Bits_Header;
      Destination : Area;
      Painted : Area;
      Kind : Transfer_Modes.Mode_Kind;
      Mask : in out Regions.Region;
      Decoder : Pixmaps.Row_Decoder;
      Source_Y : Integer) return Results.Result
   is
      Source : Geometry.Rect renames Header.Source;
      Source_Width : constant Long_Long_Integer := Long_Long_Integer (Geometry.Width (Source));
      Source_Height : constant Long_Long_Integer := Long_Long_Integer (Geometry.Height (Source));
      Destination_Width : constant Long_Long_Integer := Long_Long_Integer (Destination.Right - Destination.Left);
      Destination_Height : constant Long_Long_Integer := Long_Long_Integer (Destination.Bottom - Destination.Top);
      Relative : constant Long_Long_Integer := Long_Long_Integer (Source_Y) - Long_Long_Integer (Source.Top);
      --  Destination rows k sample source row Sampled (k, Source_Height, Destination_Height): these.
      First_Row : constant Long_Long_Integer :=
        Divisions.Ceiling_Divide (Relative * Destination_Height, Source_Height);
      Last_Row : constant Long_Long_Integer :=
        Divisions.Ceiling_Divide ((Relative + 1) * Destination_Height, Source_Height) - 1;
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
            Outcome := Accounting.Charge_Work (S, Natural'(1));
            if not Results.Succeeded (Outcome) then
               return Outcome;
            end if;
            Outcome := Begin_Masked_Row (P, S, Y, Painted.Left, Painted.Right, Mask, Header.Masked);
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
           (S, Errors.Pixmap_Invalid, Errors.Recovery_Applied, Errors.Recovery, Failures.Context_Of (Event));
      end if;
      return Results.Success;
   end Source_Rect;

   --  The part of Destination whose pixels sample Clamped, a part of Wanted, by the mapping of Wanted onto
   --  Destination: destination column k samples Wanted.Left + floor (k * Wanted's width / Destination's width),
   --  so the columns from ceil ((Clamped.Left - Wanted.Left) * width ratio) on, up to the one for Clamped.Right,
   --  sample Clamped, and rows likewise: the part of Destination a clamped srcRect paints.
   function Shrunk (Destination : Area; Wanted, Clamped : Geometry.Rect) return Area is
      function Edge (First, Extent, Wanted_First, Wanted_Extent, Clamped_Edge : Integer) return Integer is
        (First + Integer
           (Divisions.Ceiling_Divide
              (Long_Long_Integer (Clamped_Edge - Wanted_First) * Long_Long_Integer (Extent),
               Long_Long_Integer (Wanted_Extent))));
      Width : constant Integer := Destination.Right - Destination.Left;
      Height : constant Integer := Destination.Bottom - Destination.Top;
      Wanted_Width : constant Integer := Geometry.Width (Wanted);
      Wanted_Height : constant Integer := Geometry.Height (Wanted);
   begin
      return
        (Top => Edge (Destination.Top, Height, Integer (Wanted.Top), Wanted_Height, Integer (Clamped.Top)),
         Left => Edge (Destination.Left, Width, Integer (Wanted.Left), Wanted_Width, Integer (Clamped.Left)),
         Bottom => Edge (Destination.Top, Height, Integer (Wanted.Top), Wanted_Height, Integer (Clamped.Bottom)),
         Right => Edge (Destination.Left, Width, Integer (Wanted.Left), Wanted_Width, Integer (Clamped.Right)));
   end Shrunk;

   --  Rows a copy skips undrawn cost a unit each, as their framing is still read.
   function Skip_Copy (S : in out Sessions.Session; Header : Pixmaps.Bits_Header)
     return Results.Result
   is
      Outcome : constant Results.Result := Accounting.Charge_Work (S, Header.Height);
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
      --  The part of Destination painted: all of it, or what a clamped srcRect maps to.
      Painted : Area := Destination;
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
      --  A clamped srcRect keeps its mapping: the whole srcRect is sampled over the whole dstRect, and only the
      --  destination the clamped part maps to is painted.
      if Source /= Header.Source then
         Painted := Shrunk (Destination, Header.Source, Source);
         if Regions.Is_Empty (Painted) then
            return Skip_Copy (S, Header);
         end if;
      end if;
      if Header.Masked then
         Regions.Translate (Mask, -P.Port.Origin_H, -P.Port.Origin_V);
      end if;

      Outcome := Pixmaps.Start (S, Decoder, Header);
      for Row in 0 .. Header.Height - 1 loop
         exit when not Results.Succeeded (Outcome);
         --  Each row is converted whether or not any of it is drawn.
         Outcome := Accounting.Charge_Work (S, Header.Width + 1);
         if Results.Succeeded (Outcome) then
            Outcome := Pixmaps.Read_Row (S, Decoder, Row);
         end if;
         if Results.Succeeded (Outcome) then
            Outcome := Put_Row (P, S, Header, Destination, Painted, Kind, Mask, Decoder,
                                Integer (Header.Bounds.Top) + Row);
         end if;
      end loop;
      Pixmaps.Finish (Decoder);
      return Outcome;
   end Copy_Bits;
end Pictlib.Internal.Rendering;
