with Interfaces;
with Pictlib.Errors;

package body Pictlib.Internal.Rendering is
   use type Interfaces.Unsigned_16;
   use type Geometry.Rect;

   --  srcCopy; the ditherCopy flag (16#40#) makes no difference to true-color output.
   Source_Copy : constant := 0;
   Dither_Flag : constant := 16#40#;

   procedure Start
     (P : in out Painter;
      View : Images.Mutable_Image_View;
      Frame : Geometry.Rect;
      Background : Images.RGB_Color) is
   begin
      Canvas.Bind (P.Target, View);
      Canvas.Fill (P.Target, Background);
      P.Frame := Frame;
      P.Has_Clip := False;
      P.Clip := Regions.Rectangle (Frame);
      P.Work := 0;
      P.Default_Foreground := True;
      P.Default_Background := True;
   end Start;

   function Charge (P : in out Painter; S : Sessions.Session; Units : Natural) return Results.Result is
   begin
      if Pixel_Count (Units) > S.Budget.Max_Drawing_Work - Pixel_Count'Min (P.Work, S.Budget.Max_Drawing_Work) then
         return Sessions.Over_Limit
           (S, Drawing_Work_Limit, Byte_Count (S.Budget.Max_Drawing_Work), Byte_Count (P.Work) + Byte_Count (Units));
      end if;
      P.Work := P.Work + Pixel_Count (Units);
      return Results.Success;
   end Charge;

   function Unsupported (S : in out Sessions.Session; Event : Pictures.Opcode_Event) return Results.Result is
      Context : constant Errors.Diagnostic_Context :=
        (Source => Event.Offset, Op => Event.Op, Has_Opcode => True, Ordinal => Event.Ordinal, others => <>);
   begin
      if not Sessions.Is_Lenient (S) then
         return Results.Failure (Errors.Make (Errors.Unsupported_Feature, Context));
      end if;
      Sessions.Warn (S, Errors.Approximated_Rendering, Errors.Data_Loss, Context);
      return Results.Success;
   end Unsupported;

   function Ceiling_Divide (Left, Right : Long_Long_Integer) return Long_Long_Integer is ((Left + Right - 1) / Right);

   --  Paint the destination rows that sample source row Source_Y of Decoder.
   function Put_Row
     (P : in out Painter;
      S : Sessions.Session;
      Header : Pixmaps.Bits_Header;
      Source : Geometry.Rect;
      Mask : in out Regions.Region;
      Decoder : Pixmaps.Row_Decoder;
      Source_Y : Integer) return Results.Result
   is
      Destination : constant Geometry.Rect := Header.Destination;
      Source_Width : constant Long_Long_Integer := Long_Long_Integer (Geometry.Width (Source));
      Source_Height : constant Long_Long_Integer := Long_Long_Integer (Geometry.Height (Source));
      Destination_Width : constant Long_Long_Integer := Long_Long_Integer (Geometry.Width (Destination));
      Destination_Height : constant Long_Long_Integer := Long_Long_Integer (Geometry.Height (Destination));
      Relative : constant Long_Long_Integer := Long_Long_Integer (Source_Y) - Long_Long_Integer (Source.Top);
      --  Destination rows k sample source row floor (k * Source_Height / Destination_Height).
      First_Row : constant Long_Long_Integer := Ceiling_Divide (Relative * Destination_Height, Source_Height);
      Last_Row : constant Long_Long_Integer := Ceiling_Divide ((Relative + 1) * Destination_Height, Source_Height) - 1;
      Frame_Left : constant Integer := Integer (P.Frame.Left);
      Frame_Top : constant Integer := Integer (P.Frame.Top);
      Outcome : Results.Result;
      Work : Natural;
   begin
      if Relative < 0 or else Relative >= Source_Height then
         return Results.Success;
      end if;
      for K in First_Row .. Last_Row loop
         declare
            Y : constant Integer := Integer (Destination.Top) + Integer (K);
            Canvas_Y : constant Integer := Y - Frame_Top;
         begin
            if Canvas_Y in 0 .. P.Target.Height - 1 then
               --  The row's paintable spans: destination and canvas, then clip, then mask.
               P.Row_Spans.Clear;
               P.Row_Spans.Append
                 (Regions.Span'(Integer'Max (Integer (Destination.Left), Frame_Left),
                   Integer'Min (Integer (Destination.Right), Frame_Left + P.Target.Width)));
               if P.Has_Clip then
                  Regions.Row_Spans (P.Clip, Y, P.Clip_Spans, Work);
                  Outcome := Charge (P, S, Work);
                  if not Results.Succeeded (Outcome) then
                     return Outcome;
                  end if;
                  Regions.Intersect (P.Row_Spans, P.Clip_Spans, P.Scratch);
                  P.Row_Spans.Move (P.Scratch);
               end if;
               if Header.Masked then
                  Regions.Row_Spans (Mask, Y, P.Mask_Spans, Work);
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
                        begin
                           Canvas.Put (P.Target, X - Frame_Left, Canvas_Y,
                                       Pixmaps.Pixel (Decoder, Source_X - Integer (Header.Bounds.Left)));
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
            return Results.Failure
              (Errors.Make
                 (Errors.Pixmap_Invalid,
                  (Source => S.Stream.Offset, Op => Event.Op, Has_Opcode => True, Ordinal => Event.Ordinal,
                   others => <>)));
         end if;
         Sessions.Warn (S, Errors.Recovery_Applied, Errors.Recovery,
                        (Op => Event.Op, Has_Opcode => True, Ordinal => Event.Ordinal, others => <>));
      end if;
      return Results.Success;
   end Source_Rect;

   function Copy_Bits
     (P : in out Painter;
      S : in out Sessions.Session;
      Header : Pixmaps.Bits_Header;
      Mask : in out Regions.Region;
      Event : Pictures.Opcode_Event) return Results.Result
   is
      Decoder : Pixmaps.Row_Decoder;
      Source : Geometry.Rect;
      Outcome : Results.Result := Results.Success;
      Mode : constant Interfaces.Unsigned_16 := Header.Mode and not Dither_Flag;
   begin
      if Mode /= Source_Copy or else not (P.Default_Foreground and then P.Default_Background) then
         --  Other transfer modes and colorizing arrive with the rasterizer; lenient decoders copy instead.
         Outcome := Unsupported (S, Event);
      end if;
      if Results.Succeeded (Outcome) then
         Outcome := Source_Rect (S, Header, Event, Source);
      end if;
      if not Results.Succeeded (Outcome) then
         return Outcome;
      end if;
      if Geometry.Is_Empty (Source) or else Geometry.Is_Empty (Header.Destination) then
         return Pixmaps.Skip_Pixels (S, Header);
      end if;

      Outcome := Pixmaps.Start (S, Decoder, Header);
      for Row in 0 .. Header.Height - 1 loop
         exit when not Results.Succeeded (Outcome);
         Outcome := Pixmaps.Read_Row (S, Decoder, Row);
         if Results.Succeeded (Outcome) then
            Outcome := Put_Row (P, S, Header, Source, Mask, Decoder, Integer (Header.Bounds.Top) + Row);
         end if;
      end loop;
      Pixmaps.Finish (Decoder);
      return Outcome;
   end Copy_Bits;
end Pictlib.Internal.Rendering;
