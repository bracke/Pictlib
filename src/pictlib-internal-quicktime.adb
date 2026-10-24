with Ada.Unchecked_Deallocation;
with Interfaces;
with Jpeglib;
with Jpeglib.Decoding;
with Jpeglib.Errors;
with Jpeglib.Images;
with Jpeglib.Limits;
with Jpeglib.Results;
with Jpeglib.Streams;
with Pictlib.Errors;
with Pictlib.Geometry;
with Pictlib.Images;
with Pictlib.Internal.Picture_Stream;
with Pictlib.Internal.Regions;
with Pictlib.Internal.Transfer_Modes;
with Pictlib.Streams;

package body Pictlib.Internal.QuickTime is
   use type Interfaces.Unsigned_16;
   use type Interfaces.Unsigned_32;
   use type Jpeglib.Source_Offset;

   --  version, matrix, matteSize, matteRect, mode, srcRect, accuracy, maskSize.
   Header_Bytes : constant := 2 + 36 + 4 + 8 + 2 + 8 + 4 + 4;
   --  The ImageDescription fields through clutID.
   Description_Bytes : constant := 86;
   JPEG_Codec : constant := 16#6A70_6567#;  --  'jpeg'
   Fixed_One : constant := 16#1_0000#;
   Fract_One : constant := 16#4000_0000#;

   type Pixel_Buffer_Access is access Jpeglib.Streams.Byte_Array;
   procedure Free is new Ada.Unchecked_Deallocation (Jpeglib.Streams.Byte_Array, Pixel_Buffer_Access);

   function Context_Of (Event : Pictures.Opcode_Event) return Errors.Diagnostic_Context is
     ((Source => Event.Offset, Op => Event.Op, Has_Opcode => True, Ordinal => Event.Ordinal, others => <>));

   function Signed (Value : Interfaces.Unsigned_32) return Long_Long_Integer is
     (if Value >= 16#8000_0000# then Long_Long_Integer (Value) - 16#1_0000_0000# else Long_Long_Integer (Value));

   --  A 16.16 coordinate, rounded to the nearest pixel.
   function Round_Fixed (Value : Long_Long_Integer) return Integer is
     (Integer ((if Value >= 0 then (Value + Fixed_One / 2) / Fixed_One
                else -((-Value + Fixed_One / 2) / Fixed_One))));

   type Matrix is array (1 .. 9) of Long_Long_Integer;

   function Draw
     (P : in out Rendering.Painter;
      S : in out Sessions.Session;
      Event : Pictures.Opcode_Event;
      Length : Byte_Count) return Results.Result
   is
      Start : constant Byte_Count := Picture_Stream.Picture_Offset (S.Stream);
      Transform : Matrix := [others => 0];
      Matte_Size, Accuracy, Mask_Size : Interfaces.Unsigned_32 := 0;
      Version, Mode_Word : Interfaces.Unsigned_16 := 0;
      Matte_Rect, Source : Geometry.Rect;
      Mask : Regions.Region;
      Has_Mask : Boolean := False;
      Outcome : Results.Result := Results.Success;
      Pixel_Bytes, Jpeglib_Share : Byte_Count := 0;

      function Used return Byte_Count is (Picture_Stream.Picture_Offset (S.Stream) - Start);

      --  Skip whatever of the opcode is left.
      function Finish (Result : Results.Result) return Results.Result is
      begin
         if Results.Succeeded (Result) and then Used < Length then
            return Sessions.Skip_Data (S, Length - Used);
         end if;
         return Result;
      end Finish;

      function Too_Long (Wanted : Byte_Count) return Results.Result is
        (Results.Failure
           (Errors.Make
              (Errors.Opcode_Length_Invalid,
               (Context_Of (Event) with delta Expected => Length, Actual => Used + Wanted))));

      function Read_Long (Value : out Interfaces.Unsigned_32) return Results.Result is
        (Sessions.Read_Long (S, Value));
   begin
      --  Only an image drawn by this opcode hides the bits opcode after it.
      P.Skip_Next_Bits := False;
      if Length < Header_Bytes + Description_Bytes then
         return Too_Long (Header_Bytes + Description_Bytes);
      end if;
      Outcome := Sessions.Read_Word (S, Version);
      for Index in Transform'Range loop
         exit when not Results.Succeeded (Outcome);
         declare
            Value : Interfaces.Unsigned_32;
         begin
            Outcome := Read_Long (Value);
            Transform (Index) := Signed (Value);
         end;
      end loop;
      if Results.Succeeded (Outcome) then
         Outcome := Read_Long (Matte_Size);
      end if;
      if Results.Succeeded (Outcome) then
         Outcome := Sessions.Read_Bounds (S, Matte_Rect);
      end if;
      if Results.Succeeded (Outcome) then
         Outcome := Sessions.Read_Word (S, Mode_Word);
      end if;
      if Results.Succeeded (Outcome) then
         Outcome := Sessions.Read_Bounds (S, Source);
      end if;
      if Results.Succeeded (Outcome) then
         Outcome := Read_Long (Accuracy);
      end if;
      if Results.Succeeded (Outcome) then
         Outcome := Read_Long (Mask_Size);
      end if;
      if not Results.Succeeded (Outcome) then
         return Outcome;
      end if;

      --  The matte: an alpha image of its own, which this renderer does not composite.
      if Matte_Size > 0 then
         if Byte_Count (Matte_Size) > Length - Used then
            return Too_Long (Byte_Count (Matte_Size));
         end if;
         Outcome := Rendering.Unsupported (S, Event);
         if Results.Succeeded (Outcome) then
            Outcome := Sessions.Skip_Data (S, Byte_Count (Matte_Size));
         end if;
         if not Results.Succeeded (Outcome) then
            return Outcome;
         end if;
      end if;
      if Mask_Size > 0 then
         declare
            Before : constant Byte_Count := Used;
         begin
            if Byte_Count (Mask_Size) > Length - Used then
               return Too_Long (Byte_Count (Mask_Size));
            end if;
            Outcome := Regions.Read (S, Mask);
            if not Results.Succeeded (Outcome) then
               return Outcome;
            elsif Used - Before /= Byte_Count (Mask_Size) then
               return Sessions.Fail (S, Errors.Region_Invalid, Byte_Count (Mask_Size), Used - Before);
            end if;
            Has_Mask := True;
            Regions.Translate (Mask, -P.Origin_H, -P.Origin_V);
         end;
      end if;

      declare
         Description_Size, Codec, Data_Size : Interfaces.Unsigned_32 := 0;
         Image_Width, Image_Height : Interfaces.Unsigned_16 := 0;
         Fields : Streams.Byte_Array (1 .. Description_Bytes - 8);
      begin
         Outcome := Read_Long (Description_Size);
         if Results.Succeeded (Outcome) then
            Outcome := Read_Long (Codec);
         end if;
         if Results.Succeeded (Outcome) then
            Outcome := Sessions.Read_Into (S, Fields);
         end if;
         if not Results.Succeeded (Outcome) then
            return Outcome;
         end if;
         --  Offsets from the description's start: width 32, height 34, dataSize 44.
         Image_Width := Interfaces.Shift_Left (Interfaces.Unsigned_16 (Fields (25)), 8)
           or Interfaces.Unsigned_16 (Fields (26));
         Image_Height := Interfaces.Shift_Left (Interfaces.Unsigned_16 (Fields (27)), 8)
           or Interfaces.Unsigned_16 (Fields (28));
         for Index in 37 .. 40 loop
            Data_Size := Interfaces.Shift_Left (Data_Size, 8) or Interfaces.Unsigned_32 (Fields (Index));
         end loop;
         if Description_Size < Description_Bytes then
            return Results.Failure
              (Errors.Make
                 (Errors.Opcode_Length_Invalid,
                  (Context_Of (Event) with delta Expected => Description_Bytes,
                                                 Actual => Byte_Count (Description_Size))));
         elsif Byte_Count (Description_Size) - Description_Bytes > Length - Used then
            return Too_Long (Byte_Count (Description_Size) - Description_Bytes);
         end if;
         Outcome := Sessions.Skip_Data (S, Byte_Count (Description_Size) - Description_Bytes);
         if not Results.Succeeded (Outcome) then
            return Outcome;
         elsif Byte_Count (Data_Size) > Length - Used then
            return Too_Long (Byte_Count (Data_Size));
         end if;

         --  Only JPEG, and only matrices that translate and scale.
         if Codec /= JPEG_Codec
           or else Transform (2) /= 0 or else Transform (4) /= 0 or else Transform (3) /= 0
           or else Transform (6) /= 0 or else Transform (9) /= Fract_One
           or else Transform (1) <= 0 or else Transform (5) <= 0
         then
            return Finish (Rendering.Unsupported (S, Event));
         elsif Byte_Count (Data_Size) > S.Budget.Max_Embedded_Image_Bytes then
            return Sessions.Over_Limit
              (S, Embedded_Image_Byte_Limit, S.Budget.Max_Embedded_Image_Bytes, Byte_Count (Data_Size));
         elsif Image_Width = 0 or else Image_Height = 0 then
            return Results.Failure (Errors.Make (Errors.Embedded_Image_Failed, Context_Of (Event)));
         elsif Pixel_Count (Image_Width) * Pixel_Count (Image_Height) > S.Budget.Max_Embedded_Image_Pixels then
            return Sessions.Over_Limit
              (S, Embedded_Image_Pixel_Limit, Byte_Count (S.Budget.Max_Embedded_Image_Pixels),
               Byte_Count (Image_Width) * Byte_Count (Image_Height));
         elsif 3 * Byte_Count (Image_Width) * Byte_Count (Image_Height)
           > Byte_Count'Min (S.Budget.Max_Allocation_Bytes, Byte_Count (Natural'Last))
         then
            --  The pixels are one buffer indexed by Natural, whatever the budget allows.
            return Sessions.Over_Limit
              (S, Allocation_Byte_Limit, Byte_Count'Min (S.Budget.Max_Allocation_Bytes, Byte_Count (Natural'Last)),
               3 * Byte_Count (Image_Width) * Byte_Count (Image_Height));
         end if;

         --  Decoding is drawing work, a unit per pixel and per row, drawn or not, as for a copied pixmap.
         Outcome :=
           Rendering.Charge
             (P, S, Pixel_Count (Image_Width) * Pixel_Count (Image_Height) + Pixel_Count (Image_Height));
         if not Results.Succeeded (Outcome) then
            return Outcome;
         end if;
         --  The pixels, plus what jpeglib is given for its own buffers: what is left of the per-allocation
         --  budget, but no more than a progressive decode of this size needs, so one image does not take a
         --  session's whole quota. Both count against the aggregate allocation quota.
         Pixel_Bytes := 3 * Byte_Count (Image_Width) * Byte_Count (Image_Height);
         Jpeglib_Share :=
           Byte_Count'Min (S.Budget.Max_Allocation_Bytes - Pixel_Bytes, 8 * Pixel_Bytes + 1_048_576);
         Outcome := Sessions.Admit_Aggregate (S, Pixel_Bytes + Jpeglib_Share);
         if not Results.Succeeded (Outcome) then
            return Outcome;
         end if;

         declare
            --  jpeglib reads the JPEG straight from the picture, at most Data_Size bytes.
            type Embedded_Source is limited new Jpeglib.Streams.Source with record
               Remaining : Byte_Count := Byte_Count (Data_Size);
               Taken : Jpeglib.Source_Offset := 0;
               Failure : Results.Result := Results.Success;
            end record;

            overriding function Read
              (Object : in out Embedded_Source; Buffer : out Jpeglib.Streams.Byte_Array)
               return Jpeglib.Streams.Source_Result;
            overriding function Offset (Object : Embedded_Source) return Jpeglib.Source_Offset is (Object.Taken);
            overriding function Skip (Object : in out Embedded_Source; Count : Jpeglib.Byte_Count)
              return Jpeglib.Streams.Source_Result;

            function Failed (Object : in out Embedded_Source; Item : Results.Result)
              return Jpeglib.Streams.Source_Result is
            begin
               Object.Failure := Item;
               return (Result => Jpeglib.Errors.Make (Jpeglib.Errors.Source_Read_Failed), Count => 0,
                       End_Of_Input => False);
            end Failed;

            overriding function Read
              (Object : in out Embedded_Source; Buffer : out Jpeglib.Streams.Byte_Array)
               return Jpeglib.Streams.Source_Result
            is
               Count : constant Natural :=
                 Natural (Byte_Count'Min (Byte_Count (Natural'Min (Buffer'Length, 4096)), Object.Remaining));
               Chunk : Streams.Byte_Array (1 .. Count);
               Step : Results.Result;
            begin
               Buffer := [others => 0];
               if Count = 0 then
                  return (Result => Jpeglib.Errors.Make (Jpeglib.Errors.No_Error), Count => 0, End_Of_Input => True);
               end if;
               Step := Sessions.Read_Into (S, Chunk);
               if not Results.Succeeded (Step) then
                  return Failed (Object, Step);
               end if;
               for Index in Chunk'Range loop
                  Buffer (Buffer'First + Index - 1) := Jpeglib.Byte (Chunk (Index));
               end loop;
               Object.Remaining := Object.Remaining - Byte_Count (Count);
               Object.Taken := Object.Taken + Jpeglib.Source_Offset (Count);
               return (Result => Jpeglib.Errors.Make (Jpeglib.Errors.No_Error), Count => Jpeglib.Byte_Count (Count),
                       End_Of_Input => Object.Remaining = 0);
            end Read;

            overriding function Skip (Object : in out Embedded_Source; Count : Jpeglib.Byte_Count)
              return Jpeglib.Streams.Source_Result
            is
               Wanted : constant Byte_Count := Byte_Count'Min (Byte_Count (Count), Object.Remaining);
               Step : constant Results.Result := Sessions.Skip_Data (S, Wanted);
            begin
               if not Results.Succeeded (Step) then
                  return Failed (Object, Step);
               end if;
               Object.Remaining := Object.Remaining - Wanted;
               Object.Taken := Object.Taken + Jpeglib.Source_Offset (Wanted);
               return (Result => Jpeglib.Errors.Make (Jpeglib.Errors.No_Error), Count => Jpeglib.Byte_Count (Wanted),
                       End_Of_Input => Object.Remaining = 0);
            end Skip;

            Input : aliased Embedded_Source;
            Decoder : Jpeglib.Decoding.Decoder;
            Width : constant Natural := Natural (Image_Width);
            Height : constant Natural := Natural (Image_Height);
            --  Set aside only once the JPEG's header agrees with the description, so a picture with a garbage
            --  JPEG allocates nothing for its claimed size.
            Pixels : Pixel_Buffer_Access := null;
            Decoded : Jpeglib.Results.Result;

            function Rejected return Results.Result is
              (if not Results.Succeeded (Input.Failure) then Input.Failure
               else Results.Failure
                 (Errors.Make
                    (Errors.Embedded_Image_Failed,
                     (Context_Of (Event) with delta
                        Underlying_Code => Long_Long_Integer (Jpeglib.Errors.Error_Code'Pos (Decoded.First_Error.Code)),
                        Has_Underlying_Code => True))));
         begin
            Jpeglib.Decoding.Initialize
              (Decoder, Input'Access,
               (Output_Format => Jpeglib.Images.RGB_24, others => <>),
               (Jpeglib.Limits.Default_Limits with delta
                  Max_Pixels => Jpeglib.Pixel_Count (S.Budget.Max_Embedded_Image_Pixels),
                  --  The decoded pixels and jpeglib's own buffers share the one allocation budget.
                  Max_Allocation_Bytes => Jpeglib.Byte_Count (Jpeglib_Share)));
            Decoded := Jpeglib.Decoding.Read_Header (Decoder);
            if Jpeglib.Results.Succeeded (Decoded)
              and then (Natural (Jpeglib.Decoding.Header (Decoder).Width) /= Width
                        or else Natural (Jpeglib.Decoding.Header (Decoder).Height) /= Height)
            then
               --  The JPEG must be the image the description states.
               Jpeglib.Decoding.Finalize (Decoder);
               Free (Pixels);
               return Results.Failure (Errors.Make (Errors.Embedded_Image_Failed, Context_Of (Event)));
            end if;
            if Jpeglib.Results.Succeeded (Decoded) then
               Pixels := new Jpeglib.Streams.Byte_Array (1 .. 3 * Width * Height);
               declare
                  View : Jpeglib.Images.Mutable_Image_View :=
                    (Descriptor =>
                       (Width => Jpeglib.Image_Width (Width), Height => Jpeglib.Image_Height (Height),
                        Format => Jpeglib.Images.RGB_24, Stride => Jpeglib.Row_Stride (3 * Width),
                        Accessible_Bytes => Jpeglib.Byte_Count (3 * Width * Height)),
                     Storage => Pixels);
               begin
                  Decoded := Jpeglib.Decoding.Decode_Image (Decoder, View);
               end;
            end if;
            Jpeglib.Decoding.Finalize (Decoder);
            if not Jpeglib.Results.Succeeded (Decoded) then
               Free (Pixels);
               return Rejected;
            end if;
            --  What jpeglib left of the image data, then of the opcode.
            if Input.Remaining > 0 then
               Outcome := Sessions.Skip_Data (S, Input.Remaining);
            end if;
            if Results.Succeeded (Outcome) then
               Outcome := Finish (Results.Success);
            end if;

            --  Draw srcRect, in image coordinates, through the matrix onto the picture.
            declare
               Clamped : constant Geometry.Rect :=
                 (Top => Coordinate'Max (Source.Top, 0), Left => Coordinate'Max (Source.Left, 0),
                  Bottom => Coordinate'Min (Source.Bottom, Coordinate (Natural'Min (Height, 32_767))),
                  Right => Coordinate'Min (Source.Right, Coordinate (Natural'Min (Width, 32_767))));
               Destination : constant Regions.Area :=
                 (Top => Round_Fixed (Long_Long_Integer (Clamped.Top) * Transform (5) + Transform (8)) - P.Origin_V,
                  Left => Round_Fixed (Long_Long_Integer (Clamped.Left) * Transform (1) + Transform (7)) - P.Origin_H,
                  Bottom =>
                    Round_Fixed (Long_Long_Integer (Clamped.Bottom) * Transform (5) + Transform (8)) - P.Origin_V,
                  Right =>
                    Round_Fixed (Long_Long_Integer (Clamped.Right) * Transform (1) + Transform (7)) - P.Origin_H);
               Kind : Transfer_Modes.Mode_Kind;
               Source_Width : constant Long_Long_Integer := Long_Long_Integer (Geometry.Width (Clamped));
               Source_Height : constant Long_Long_Integer := Long_Long_Integer (Geometry.Height (Clamped));
               Destination_Width : constant Long_Long_Integer :=
                 Long_Long_Integer (Destination.Right - Destination.Left);
               Destination_Height : constant Long_Long_Integer :=
                 Long_Long_Integer (Destination.Bottom - Destination.Top);
               Work : Natural;
            begin
               if Results.Succeeded (Outcome) then
                  Outcome := Rendering.Mode (S, Event, Mode_Word, Kind);
               end if;
               if Results.Succeeded (Outcome) and then not Geometry.Is_Empty (Clamped)
                 and then not Regions.Is_Empty (Destination)
               then
                  for Y in Integer'Max (Destination.Top, P.Window.Top)
                    .. Integer'Min (Destination.Bottom, P.Window.Bottom) - 1
                  loop
                     exit when not Results.Succeeded (Outcome);
                     P.Row_Spans.Clear;
                     P.Row_Spans.Append
                       (Regions.Span'(Integer'Max (Destination.Left, P.Window.Left),
                                      Integer'Min (Destination.Right, P.Window.Right)));
                     Outcome := Rendering.Clip_Row (P, S, Y);
                     if Results.Succeeded (Outcome) and then Has_Mask then
                        Regions.Row_Spans (Mask, Y, P.Mask_Spans, Work, Rendering.Walk_Allowance (P, S));
                        Regions.Intersect (P.Row_Spans, P.Mask_Spans, P.Scratch);
                        P.Row_Spans.Move (P.Scratch);
                        Outcome := Rendering.Charge (P, S, Work);
                     end if;
                     declare
                        Row : constant Natural :=
                          Natural (Clamped.Top)
                          + Natural ((Long_Long_Integer (Y - Destination.Top) * Source_Height) / Destination_Height);
                     begin
                        for Span of P.Row_Spans loop
                           exit when not Results.Succeeded (Outcome);
                           Outcome := Rendering.Charge (P, S, Natural'Max (0, Span.Right - Span.Left));
                           --  Nothing is drawn past the budget.
                           exit when not Results.Succeeded (Outcome);
                           for X in Span.Left .. Span.Right - 1 loop
                              declare
                                 Column : constant Natural :=
                                   Natural (Clamped.Left)
                                   + Natural ((Long_Long_Integer (X - Destination.Left) * Source_Width)
                                              / Destination_Width);
                                 At_Pixel : constant Positive := 3 * (Row * Width + Column) + 1;
                                 Color : constant Images.RGB_Color :=
                                   (Byte (Pixels (At_Pixel)), Byte (Pixels (At_Pixel + 1)),
                                    Byte (Pixels (At_Pixel + 2)));
                              begin
                                 --  A decompressed image is not colorized by the port's colors.
                                 Rendering.Put
                                   (P, X, Y,
                                    Transfer_Modes.Compose (Kind, Color, Rendering.Get (P, X, Y), P.Colors,
                                                            Colorize => False));
                              end;
                           end loop;
                        end loop;
                     end;
                  end loop;
               end if;
            end;
            Free (Pixels);
            P.Skip_Next_Bits := Results.Succeeded (Outcome);
            return Outcome;
         end;
      end;
   end Draw;
end Pictlib.Internal.QuickTime;
