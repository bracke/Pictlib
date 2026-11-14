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
   use type Transfer_Modes.Mode_Kind;
   use type Pixmaps.Pixel_Encoding;
   use type Images.RGB_Color;

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

   --  Item, a local region, moved to picture coordinates: uncharged, so only Region_To_Picture calls it.
   procedure To_Picture (P : Painter; Item : in out Regions.Region) is
   begin
      Regions.Translate (Item, -P.Port.Origin_H, -P.Port.Origin_V);
   end To_Picture;

   function Region_To_Picture (P : Painter; S : in out Sessions.Session; Item : in out Regions.Region)
     return Results.Result
   is
      Outcome : constant Results.Result := Accounting.Charge_Work (S, Regions.Size (Item));
   begin
      if Results.Succeeded (Outcome) then
         To_Picture (P, Item);
      end if;
      return Outcome;
   end Region_To_Picture;

   function Region_To_Picture
     (P : Painter;
      S : in out Sessions.Session;
      Source : Regions.Region;
      Moved : out Regions.Region) return Results.Result
   is
      Outcome : constant Results.Result := Accounting.Charge_Work (S, Regions.Size (Source));
      Empty : Regions.Region;
   begin
      if Results.Succeeded (Outcome) then
         Moved := Source;
         To_Picture (P, Moved);
      else
         Moved := Empty;
      end if;
      return Outcome;
   end Region_To_Picture;

   function Unsupported
     (S : in out Sessions.Session;
      Event : Pictures.Opcode_Event;
      Expected, Actual : Byte_Count := 0) return Results.Result is
   begin
      return Sessions.Reject_Or_Warn
        (S, Errors.Unsupported_Feature, Errors.Approximated_Rendering,
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
        (S, Errors.Transfer_Mode_Invalid, Errors.Recovery_Applied,
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

   --  The row primitives below leave Outcome, a success when they are called, as it is when they succeed and
   --  make it the failure otherwise: a result is built only for a failure, as one is made for every row.

   --  Cut Row_Spans to Item's row Row, its columns Shift to the left of the row's: the region walk is charged
   --  first, and the row is cut only once it is paid for.
   procedure Cut_Row
     (S : in out Sessions.Session;
      Item : in out Regions.Region;
      Row, Shift : Integer;
      Cut, Row_Spans, Scratch : in out Regions.Span_Vectors.Vector;
      Outcome : in out Results.Result)
   is
      Work : Pixel_Count;
   begin
      Regions.Row_Spans (Item, Row, Cut, Work, Accounting.Work_Left (S));
      if not Accounting.Charged (S, Work) then
         Outcome := Accounting.Charge_Work (S, Work);
         return;
      end if;
      if Shift /= 0 then
         for Span of Cut loop
            Span := (Span.Left - Shift, Span.Right - Shift);
         end loop;
      end if;
      Regions.Intersect (Row_Spans, Cut, Scratch);
      Row_Spans.Move (Scratch);
   end Cut_Row;

   --  The clip is local: picture row Y is its row Y + origin, and its columns lie origin to the right.
   procedure Clip_Row (P : in out Painter; S : in out Sessions.Session; Y : Integer; Outcome : in out Results.Result) is
   begin
      if P.Port.Has_Clip then
         Cut_Row (S, P.Port.Clip, Y + P.Port.Origin_V, P.Port.Origin_H, P.Machine.Clip_Spans, P.Machine.Row_Spans,
                  P.Machine.Scratch, Outcome);
      end if;
   end Clip_Row;

   procedure Begin_Row
     (P : in out Painter;
      S : in out Sessions.Session;
      Y, Left, Right : Integer;
      Outcome : in out Results.Result)
   is
      First : constant Integer := Integer'Max (Left, P.Window.Left);
      Last : constant Integer := Integer'Min (Right, P.Window.Right);
   begin
      P.Machine.Row_Spans.Clear;
      if Y not in P.Window.Top .. P.Window.Bottom - 1 or else First >= Last then
         return;
      end if;
      P.Machine.Row_Spans.Append (Regions.Span'(First, Last));
      Clip_Row (P, S, Y, Outcome);
   end Begin_Row;

   function Row_Is_Empty (P : Painter) return Boolean is (P.Machine.Row_Spans.Is_Empty);

   procedure Begin_Masked_Row
     (P : in out Painter;
      S : in out Sessions.Session;
      Y, Left, Right : Integer;
      Mask : in out Regions.Region;
      Masked : Boolean;
      Outcome : in out Results.Result) is
   begin
      Begin_Row (P, S, Y, Left, Right, Outcome);
      if Results.Succeeded (Outcome) and then Masked and then not Row_Is_Empty (P) then
         Cut_Row (S, Mask, Y, 0, P.Machine.Mask_Spans, P.Machine.Row_Spans, P.Machine.Scratch, Outcome);
      end if;
   end Begin_Masked_Row;

   function Never (X, Y : Integer) return Boolean is
      pragma Unreferenced (X, Y);
   begin
      return False;
   end Never;

   --  Each span of the begun row charged, then painted by Paint_Span, in order; none past the budget.
   generic
      with procedure Paint_Span (P : in out Painter; Left, Right : Integer);
   procedure Charged_Spans (P : in out Painter; S : in out Sessions.Session; Outcome : in out Results.Result);

   procedure Charged_Spans (P : in out Painter; S : in out Sessions.Session; Outcome : in out Results.Result) is
   begin
      for Index in P.Machine.Row_Spans.First_Index .. P.Machine.Row_Spans.Last_Index loop
         declare
            --  A copy: Paint_Span may not change the spans, and a read by index would hold a lock on them.
            Span : constant Regions.Span := P.Machine.Row_Spans.Element (Index);
         begin
            if not Accounting.Charged (S, Span.Right - Span.Left) then
               Outcome := Accounting.Charge_Work (S, Span.Right - Span.Left);
               exit;
            end if;
            Paint_Span (P, Span.Left, Span.Right);
         end;
      end loop;
   end Charged_Spans;

   procedure Paint_Row
     (P : in out Painter;
      S : in out Sessions.Session;
      Y : Integer;
      Outcome : in out Results.Result)
   is
      --  The view is stepped through a pixel at a time, its index worked out once a span.
      procedure Paint_Span (P : in out Painter; Left, Right : Integer) is
         At_Pixel : Positive;
      begin
         if Left >= Right then
            return;
         end if;
         At_Pixel := Canvas.Index (P.Machine.Target, Left - P.Window.Left, Y - P.Window.Top);
         for X in Left .. Right - 1 loop
            if not Keeps (X, Y) then
               Canvas.Put_At
                 (P.Machine.Target, At_Pixel,
                  Color_At (X, Y, (if Reads_Under then Canvas.Get_At (P.Machine.Target, At_Pixel) else Images.Black)));
            end if;
            At_Pixel := At_Pixel + P.Machine.Target.Step;
         end loop;
      end Paint_Span;
      procedure Paint is new Charged_Spans (Paint_Span);
   begin
      Paint (P, S, Outcome);
   end Paint_Row;

   procedure Paint_Row_Color
     (P : in out Painter;
      S : in out Sessions.Session;
      Y : Integer;
      Color : Images.RGB_Color;
      Outcome : in out Results.Result)
   is
      procedure Paint_Span (P : in out Painter; Left, Right : Integer) is
      begin
         Canvas.Put_Span (P.Machine.Target, Left - P.Window.Left, Right - P.Window.Left, Y - P.Window.Top, Color);
      end Paint_Span;
      procedure Paint is new Charged_Spans (Paint_Span);
   begin
      Paint (P, S, Outcome);
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
      --  The row being painted, for a span painter, which is given only its columns.
      Current_Row : Integer := 0;
      Source : Patterns.Pattern renames P.Port.Pattern_Set (How.Source);
      Colorize : constant Boolean := Patterns.Kind (Source) = Patterns.Bit_Pattern;
      Hilited : constant Boolean := Take_Hilite (P);
      Kind : constant Transfer_Modes.Mode_Kind := (if Hilited then Transfer_Modes.Hilite else How.Mode);
      --  The spans building made, which count against the session's allocation total.
      Span_Bytes : constant Byte_Count :=
        Checked_Arithmetic.Saturating_Multiply
          (Byte_Count (Coverage.Work (Shape)), Accounting.Shape_Bytes_Per_Work_Unit);
   begin
      --  A shape's allowance is the lesser of the drawing work and the spans the allocation total admits, so a
      --  spent shape names whichever of the two it crossed: the allocation total only when the work is within
      --  what is left.
      if Coverage.Exhausted (Shape) then
         if Coverage.Work (Shape) <= Accounting.Work_Left (S) then
            Outcome := Accounting.Admit_Aggregate (S, Span_Bytes);
            if not Results.Succeeded (Outcome) then
               return Outcome;
            end if;
         end if;
         return Accounting.Over_Work (S, Coverage.Work (Shape));
      end if;
      Outcome := Accounting.Charge_Work (S, Checked_Arithmetic.Saturating_Add (Coverage.Work (Shape), Walked));
      if Results.Succeeded (Outcome) then
         Outcome := Accounting.Admit_Aggregate (S, Span_Bytes);
      end if;
      declare
         Sample, Color : Images.RGB_Color := Images.Black;
         Effect : Transfer_Modes.Effect_Kind := Transfer_Modes.Depends_On_Destination;
         Patterned : constant Boolean := How.Kind = Pattern_Paint;

         --  An invert after HiliteMode highlights: every pixel is dark, so the background and highlight swap.
         function Color_At (X, Y : Integer; Under : Images.RGB_Color) return Images.RGB_Color is
           (if How.Kind = Invert_Paint and then not Hilited then Transfer_Modes.Invert (Under)
            elsif How.Kind = Invert_Paint
            then Transfer_Modes.Compose (Kind, Images.Black, Under, P.Port.Colors, Colorize => False,
                                         Bit_Source => True)
            else Transfer_Modes.Compose
                   (Kind, Patterns.Sample (Source, X, Y), Under, P.Port.Colors, Colorize, Bit_Source => Colorize));
         procedure Paint is new Paint_Row
           (Color_At, Reads_Under => not Patterned or else Transfer_Modes.Reads_Destination (Kind));

         --  A copied pattern does not depend on what is under it: one period of a row is composed, and copied
         --  over the rest of the span.
         procedure Repeat_Span (P : in out Painter; Left, Right : Integer) is
            Head : constant Integer := Integer'Min (Right, Left + Patterns.Period (Source));
            At_Pixel : Positive;
         begin
            if Left >= Right then
               return;
            end if;
            At_Pixel := Canvas.Index (P.Machine.Target, Left - P.Window.Left, Current_Row - P.Window.Top);
            for X in Left .. Head - 1 loop
               Canvas.Put_At (P.Machine.Target, At_Pixel, Color_At (X, Current_Row, Images.Black));
               At_Pixel := At_Pixel + P.Machine.Target.Step;
            end loop;
            if Head < Right then
               Canvas.Repeat
                 (P.Machine.Target, Left - P.Window.Left, Right - P.Window.Left, Current_Row - P.Window.Top,
                  Patterns.Period (Source));
            end if;
         end Repeat_Span;
         procedure Repeated is new Charged_Spans (Repeat_Span);

         --  A bit pattern under a mode where each of its two colors either paints one color or changes nothing,
         --  as or and bic do: a pixel is the dark bit's outcome or the light bit's, never read.
         Dark_Effect, Light_Effect : Transfer_Modes.Effect_Kind := Transfer_Modes.Depends_On_Destination;
         Dark_Color, Light_Color : Images.RGB_Color := Images.Black;
         Dark : Boolean := False;
         function Two_Tone_Keeps (X, Y : Integer) return Boolean is
         begin
            Dark := Patterns.Sample (Source, X, Y) = Images.Black;
            return (if Dark then Dark_Effect else Light_Effect) = Transfer_Modes.Unchanged;
         end Two_Tone_Keeps;
         function Two_Tone_Color (X, Y : Integer; Under : Images.RGB_Color) return Images.RGB_Color is
            pragma Unreferenced (X, Y, Under);
         begin
            return (if Dark then Dark_Color else Light_Color);
         end Two_Tone_Color;
         procedure Two_Tone is new Paint_Row (Two_Tone_Color, Reads_Under => False, Keeps => Two_Tone_Keeps);
         Two_Toned : Boolean := False;
      begin
         --  A uniform pattern whose result does not depend on the pixels under it paints one color, or nothing.
         if Patterned and then Patterns.Uniform (Source, Sample) then
            Effect := Transfer_Modes.Effect (Kind, Sample, P.Port.Colors, Colorize, Color);
         elsif Patterned and then Colorize then
            Dark_Effect := Transfer_Modes.Effect (Kind, Images.Black, P.Port.Colors, Colorize, Dark_Color);
            Light_Effect := Transfer_Modes.Effect (Kind, Images.White, P.Port.Colors, Colorize, Light_Color);
            Two_Toned := Dark_Effect /= Transfer_Modes.Depends_On_Destination
              and then Light_Effect /= Transfer_Modes.Depends_On_Destination;
         end if;
         if Effect = Transfer_Modes.Unchanged then
            return Outcome;
         end if;
         --  Only the rows the shape holds.
         for Y in Coverage.First_Row (Shape) .. Coverage.Last_Row (Shape) loop
            exit when not Results.Succeeded (Outcome);
            Coverage.Copy_Row (Shape, Y, P.Machine.Row_Spans);
            if not P.Machine.Row_Spans.Is_Empty then
               Clip_Row (P, S, Y, Outcome);
               if Results.Succeeded (Outcome) then
                  Current_Row := Y;
                  if Effect = Transfer_Modes.Constant_Color then
                     Paint_Row_Color (P, S, Y, Color, Outcome);
                  elsif Patterned and then not Transfer_Modes.Reads_Destination (Kind) then
                     Repeated (P, S, Outcome);
                  elsif Two_Toned then
                     Two_Tone (P, S, Y, Outcome);
                  else
                     Paint (P, S, Y, Outcome);
                  end if;
               end if;
            end if;
         end loop;
      end;
      return Outcome;
   end Fill;

   --  Paint the destination rows that sample source row Source_Y of Decoder, srcRect mapped onto Destination;
   --  only columns Painted.Left .. Painted.Right - 1, those sampling the bounds, are painted. Rows need no such
   --  bound: Copy_Bits reads only the bounds' rows, so Painted's top and bottom only tell it whether anything is
   --  painted at all.
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
      --  A copy in black on white is the source itself.
      Identity : constant Boolean := Transfer_Modes.Is_Identity (Kind, P.Port.Colors);
      --  The source column Sampled gives for column Next_X, as Column + Left_Over / Destination_Width: column X + 1
      --  follows from column X by adding Source_Width / Destination_Width with carry, so a row needs no division
      --  but at the start of each span.
      Next_X : Integer := Integer'First;
      Column, Left_Over : Long_Long_Integer := 0;
      Whole : constant Long_Long_Integer := Source_Width / Destination_Width;
      Part : constant Long_Long_Integer := Source_Width mod Destination_Width;

      --  The source pixel destination column X samples.
      function Source_At (X : Integer) return Images.RGB_Color is
      begin
         if X /= Next_X then
            declare
               Scaled : constant Long_Long_Integer := Long_Long_Integer (X - Destination.Left) * Source_Width;
            begin
               Column := Scaled / Destination_Width;
               Left_Over := Scaled mod Destination_Width;
            end;
         end if;
         return Pixel : constant Images.RGB_Color :=
           Pixmaps.Pixel (Decoder, Natural (Long_Long_Integer (Source.Left - Header.Bounds.Left) + Column))
         do
            Column := Column + Whole;
            Left_Over := Left_Over + Part;
            if Left_Over >= Destination_Width then
               Column := Column + 1;
               Left_Over := Left_Over - Destination_Width;
            end if;
            Next_X := X + 1;
         end return;
      end Source_At;

      function Color_At (X, Y : Integer; Under : Images.RGB_Color) return Images.RGB_Color is
         pragma Unreferenced (Y);
         Pixel : constant Images.RGB_Color := Source_At (X);
      begin
         return (if Identity then Pixel else Transfer_Modes.Compose (Kind, Pixel, Under, P.Port.Colors));
      end Color_At;
      procedure Paint is new Paint_Row (Color_At, Reads_Under => Transfer_Modes.Reads_Destination (Kind));

      --  An unscaled copy in black on white is the converted row itself: each span is written as one run.
      Run_Copy : constant Boolean := Identity and then Source_Width = Destination_Width;
      Current_Y : Integer := 0;
      procedure Copy_Span (P : in out Painter; Left, Right : Integer) is
         First : constant Natural :=
           Natural (Long_Long_Integer (Source.Left - Header.Bounds.Left) + Long_Long_Integer (Left - Destination.Left));
      begin
         if Left < Right then
            Canvas.Put_Run
              (P.Machine.Target, Canvas.Index (P.Machine.Target, Left - P.Window.Left, Current_Y - P.Window.Top),
               Pixmaps.Colors (Decoder) (First .. First + (Right - Left) - 1));
         end if;
      end Copy_Span;
      procedure Copied is new Charged_Spans (Copy_Span);

      --  A BitMap's pixels are black or white. Under the boolean modes but copy each of the two either paints one
      --  color, changes nothing, or, for xor, inverts what is under it: decided once for both, not composed a
      --  pixel at a time.
      Two_Toned : constant Boolean :=
        Header.Encoding = Pixmaps.Bitmap_Bits
        and then Kind in Transfer_Modes.Or_Mode | Transfer_Modes.Xor_Mode | Transfer_Modes.Bic
                       | Transfer_Modes.Not_Or | Transfer_Modes.Not_Xor | Transfer_Modes.Not_Bic;
      Xored : constant Boolean := Kind in Transfer_Modes.Xor_Mode | Transfer_Modes.Not_Xor;
      Dark_Color, Light_Color : Images.RGB_Color := Images.Black;
      Dark_Effect : constant Transfer_Modes.Effect_Kind :=
        (if Two_Toned and then not Xored
         then Transfer_Modes.Effect (Kind, Images.Black, P.Port.Colors, True, Dark_Color)
         else Transfer_Modes.Depends_On_Destination);
      Light_Effect : constant Transfer_Modes.Effect_Kind :=
        (if Two_Toned and then not Xored
         then Transfer_Modes.Effect (Kind, Images.White, P.Port.Colors, True, Light_Color)
         else Transfer_Modes.Depends_On_Destination);
      --  Whether the pixel Bit_Keeps last looked at is black, for Bit_Color, asked next of the same pixel.
      Dark : Boolean := False;
      --  Xor inverts under black and keeps under white; notXor the other way round.
      function Bit_Keeps (X, Y : Integer) return Boolean is
         pragma Unreferenced (Y);
      begin
         Dark := Source_At (X) = Images.Black;
         return
           (if Xored then Dark = (Kind = Transfer_Modes.Not_Xor)
            else (if Dark then Dark_Effect else Light_Effect) = Transfer_Modes.Unchanged);
      end Bit_Keeps;
      function Bit_Color (X, Y : Integer; Under : Images.RGB_Color) return Images.RGB_Color is
         pragma Unreferenced (X, Y);
      begin
         return (if Xored then Transfer_Modes.Invert (Under) elsif Dark then Dark_Color else Light_Color);
      end Bit_Color;
      procedure Bits is new Paint_Row (Bit_Color, Reads_Under => Xored, Keeps => Bit_Keeps);
      Bit_Painted : constant Boolean :=
        Two_Toned
        and then (Xored
                  or else (Dark_Effect /= Transfer_Modes.Depends_On_Destination
                           and then Light_Effect /= Transfer_Modes.Depends_On_Destination));
   begin
      if Relative < 0 or else Relative >= Source_Height then
         return Results.Success;
      end if;
      for K in First_Row .. Last_Row loop
         declare
            Y : constant Integer := Destination.Top + Integer (K);
         begin
            --  Every destination row a copy walks costs a unit, in the frame or not.
            if not Accounting.Charged (S, Natural'(1)) then
               return Accounting.Charge_Work (S, Natural'(1));
            end if;
            Begin_Masked_Row (P, S, Y, Painted.Left, Painted.Right, Mask, Header.Masked, Outcome);
            if Results.Succeeded (Outcome) then
               Current_Y := Y;
               if Run_Copy then
                  Copied (P, S, Outcome);
               elsif Bit_Painted then
                  Bits (P, S, Y, Outcome);
               else
                  Paint (P, S, Y, Outcome);
               end if;
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
           (S, Errors.Pixmap_Invalid, Errors.Recovery_Applied, Failures.Context_Of (Event));
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
         Outcome := Region_To_Picture (P, S, Mask);
         if not Results.Succeeded (Outcome) then
            return Outcome;
         end if;
      end if;

      Outcome := Pixmaps.Start (S, Decoder, Header);
      for Row in 0 .. Header.Height - 1 loop
         exit when not Results.Succeeded (Outcome);
         --  Each row is unpacked and converted whether or not any of it is drawn: a unit per pixel or per byte
         --  unpacked, whichever is more, as rowBytes may be far wider than the pixels.
         Outcome := Accounting.Charge_Work (S, Natural'Max (Header.Width, Header.Unpacked_Length) + 1);
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
