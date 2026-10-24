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
   use type Interfaces.Unsigned_32;
   use type Jpeglib.Source_Offset;

   --  version, matrix, matteSize, matteRect, mode, srcRect, accuracy, maskSize.
   Header_Bytes : constant := 2 + 36 + 4 + 8 + 2 + 8 + 4 + 4;
   --  The ImageDescription fields through clutID.
   Description_Bytes : constant := 86;
   --  Offsets into the description after its size and codec words: width, height and dataSize, which lie 32, 34
   --  and 44 bytes from the description's start.
   Width_Field : constant := 32 - 8 + 1;
   Height_Field : constant := 34 - 8 + 1;
   Data_Size_Field : constant := 44 - 8 + 1;
   JPEG_Codec : constant := 16#6A70_6567#;  --  'jpeg'
   Fixed_One : constant := 16#1_0000#;
   Fract_One : constant := 16#4000_0000#;
   --  Decoded pixels are RGB.
   Bytes_Per_Pixel : constant := 3;
   --  jpeglib's own buffers may take at most this many times the pixels, plus Jpeglib_Fixed_Bytes: what a
   --  progressive decode of that size needs, so one image does not take a session's whole allocation quota.
   Jpeglib_Pixel_Factor : constant := 8;
   Jpeglib_Fixed_Bytes : constant := 1_048_576;
   --  The most jpeglib is handed at once.
   Read_Chunk : constant := 4096;

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

   --  The fields before the matte.
   type Image_Header is record
      Transform : Matrix := [others => 0];
      Matte_Size, Mask_Size : Interfaces.Unsigned_32 := 0;
      Mode_Word : Interfaces.Unsigned_16 := 0;
      Source : Geometry.Rect;
   end record;

   --  The ImageDescription fields this renderer uses.
   type Description is record
      Size, Codec, Data_Size : Interfaces.Unsigned_32 := 0;
      Width, Height : Natural := 0;
   end record;

   function Read_Image_Header (S : in out Sessions.Session; Header : out Image_Header) return Results.Result is
      Version : Interfaces.Unsigned_16;
      Matte_Rect : Geometry.Rect;
      Accuracy : Interfaces.Unsigned_32;
      Outcome : Results.Result := Sessions.Read_Word (S, Version);
   begin
      Header := (others => <>);
      for Index in Header.Transform'Range loop
         exit when not Results.Succeeded (Outcome);
         declare
            Value : Interfaces.Unsigned_32;
         begin
            Outcome := Sessions.Read_Long (S, Value);
            Header.Transform (Index) := Signed (Value);
         end;
      end loop;
      if Results.Succeeded (Outcome) then
         Outcome := Sessions.Read_Long (S, Header.Matte_Size);
      end if;
      if Results.Succeeded (Outcome) then
         Outcome := Sessions.Read_Bounds (S, Matte_Rect);
      end if;
      if Results.Succeeded (Outcome) then
         Outcome := Sessions.Read_Word (S, Header.Mode_Word);
      end if;
      if Results.Succeeded (Outcome) then
         Outcome := Sessions.Read_Bounds (S, Header.Source);
      end if;
      if Results.Succeeded (Outcome) then
         Outcome := Sessions.Read_Long (S, Accuracy);
      end if;
      if Results.Succeeded (Outcome) then
         Outcome := Sessions.Read_Long (S, Header.Mask_Size);
      end if;
      return Outcome;
   end Read_Image_Header;

   --  The description's fixed fields; the caller skips what follows them.
   function Read_Description (S : in out Sessions.Session; Item : out Description) return Results.Result is
      Fields : Streams.Byte_Array (1 .. Description_Bytes - 8);
      Outcome : Results.Result := Sessions.Read_Long (S, Item.Size);

      function Word_At (Index : Positive) return Natural is
        (Natural (Fields (Index)) * 256 + Natural (Fields (Index + 1)));
   begin
      Item := (Size => Item.Size, others => <>);
      if Results.Succeeded (Outcome) then
         Outcome := Sessions.Read_Long (S, Item.Codec);
      end if;
      if Results.Succeeded (Outcome) then
         Outcome := Sessions.Read_Into (S, Fields);
      end if;
      if Results.Succeeded (Outcome) then
         Item.Width := Word_At (Width_Field);
         Item.Height := Word_At (Height_Field);
         for Index in Data_Size_Field .. Data_Size_Field + 3 loop
            Item.Data_Size := Interfaces.Shift_Left (Item.Data_Size, 8) or Interfaces.Unsigned_32 (Fields (Index));
         end loop;
      end if;
      return Outcome;
   end Read_Description;

   --  Only JPEG, and only matrices that translate and scale.
   function Is_Supported (Header : Image_Header; Item : Description) return Boolean is
     (Item.Codec = JPEG_Codec
      and then Header.Transform (2) = 0 and then Header.Transform (4) = 0 and then Header.Transform (3) = 0
      and then Header.Transform (6) = 0 and then Header.Transform (9) = Fract_One
      and then Header.Transform (1) > 0 and then Header.Transform (5) > 0);

   --  The embedded limits, and the one buffer of pixels, indexed by Natural, whatever the budget allows.
   function Check_Image (S : Sessions.Session; Event : Pictures.Opcode_Event; Item : Description)
     return Results.Result
   is
      Pixels : constant Byte_Count := Byte_Count (Item.Width) * Byte_Count (Item.Height);
      Largest : constant Byte_Count := Byte_Count'Min (S.Budget.Max_Allocation_Bytes, Byte_Count (Natural'Last));
   begin
      if Byte_Count (Item.Data_Size) > S.Budget.Max_Embedded_Image_Bytes then
         return Sessions.Over_Limit
           (S, Embedded_Image_Byte_Limit, S.Budget.Max_Embedded_Image_Bytes, Byte_Count (Item.Data_Size));
      elsif Pixels = 0 then
         return Results.Failure (Errors.Make (Errors.Embedded_Image_Failed, Context_Of (Event)));
      elsif Pixel_Count (Pixels) > S.Budget.Max_Embedded_Image_Pixels then
         return Sessions.Over_Limit
           (S, Embedded_Image_Pixel_Limit, Byte_Count (S.Budget.Max_Embedded_Image_Pixels), Pixels);
      elsif Bytes_Per_Pixel * Pixels > Largest then
         return Sessions.Over_Limit (S, Allocation_Byte_Limit, Largest, Bytes_Per_Pixel * Pixels);
      end if;
      return Results.Success;
   end Check_Image;

   --  Decode the JPEG, read straight from the picture, at most Item.Data_Size bytes, into Pixels, which is set
   --  aside only once the JPEG's header agrees with the description; jpeglib is given Share for its buffers.
   function Decode_JPEG
     (S : in out Sessions.Session;
      Event : Pictures.Opcode_Event;
      Item : Description;
      Share : Byte_Count;
      Pixels : out Pixel_Buffer_Access) return Results.Result
   is
      type Embedded_Source is limited new Jpeglib.Streams.Source with record
         Remaining : Byte_Count := Byte_Count (Item.Data_Size);
         Taken : Jpeglib.Source_Offset := 0;
         Failure : Results.Result := Results.Success;
      end record;

      overriding function Read
        (Object : in out Embedded_Source; Buffer : out Jpeglib.Streams.Byte_Array)
         return Jpeglib.Streams.Source_Result;
      overriding function Offset (Object : Embedded_Source) return Jpeglib.Source_Offset is (Object.Taken);
      overriding function Skip (Object : in out Embedded_Source; Count : Jpeglib.Byte_Count)
        return Jpeglib.Streams.Source_Result;

      function Failed (Object : in out Embedded_Source; Step : Results.Result)
        return Jpeglib.Streams.Source_Result is
      begin
         Object.Failure := Step;
         return (Result => Jpeglib.Errors.Make (Jpeglib.Errors.Source_Read_Failed), Count => 0,
                 End_Of_Input => False);
      end Failed;

      overriding function Read
        (Object : in out Embedded_Source; Buffer : out Jpeglib.Streams.Byte_Array)
         return Jpeglib.Streams.Source_Result
      is
         Count : constant Natural :=
           Natural (Byte_Count'Min (Byte_Count (Natural'Min (Buffer'Length, Read_Chunk)), Object.Remaining));
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
      Decoded : Jpeglib.Results.Result;
      Bytes : constant Natural := Bytes_Per_Pixel * Item.Width * Item.Height;

      function Rejected return Results.Result is
        (if not Results.Succeeded (Input.Failure) then Input.Failure
         else Results.Failure
           (Errors.Make
              (Errors.Embedded_Image_Failed,
               (Context_Of (Event) with delta
                  Underlying_Code => Long_Long_Integer (Jpeglib.Errors.Error_Code'Pos (Decoded.First_Error.Code)),
                  Has_Underlying_Code => True))));
   begin
      Pixels := null;
      Jpeglib.Decoding.Initialize
        (Decoder, Input'Access,
         (Output_Format => Jpeglib.Images.RGB_24, others => <>),
         (Jpeglib.Limits.Default_Limits with delta
            Max_Pixels => Jpeglib.Pixel_Count (S.Budget.Max_Embedded_Image_Pixels),
            Max_Allocation_Bytes => Jpeglib.Byte_Count (Share)));
      Decoded := Jpeglib.Decoding.Read_Header (Decoder);
      if Jpeglib.Results.Succeeded (Decoded)
        and then (Natural (Jpeglib.Decoding.Header (Decoder).Width) /= Item.Width
                  or else Natural (Jpeglib.Decoding.Header (Decoder).Height) /= Item.Height)
      then
         --  The JPEG must be the image the description states.
         Jpeglib.Decoding.Finalize (Decoder);
         return Results.Failure (Errors.Make (Errors.Embedded_Image_Failed, Context_Of (Event)));
      end if;
      if Jpeglib.Results.Succeeded (Decoded) then
         Pixels := new Jpeglib.Streams.Byte_Array (1 .. Bytes);
         declare
            View : Jpeglib.Images.Mutable_Image_View :=
              (Descriptor =>
                 (Width => Jpeglib.Image_Width (Item.Width), Height => Jpeglib.Image_Height (Item.Height),
                  Format => Jpeglib.Images.RGB_24, Stride => Jpeglib.Row_Stride (Bytes_Per_Pixel * Item.Width),
                  Accessible_Bytes => Jpeglib.Byte_Count (Bytes)),
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
      --  What jpeglib left of the image data.
      if Input.Remaining > 0 then
         return Sessions.Skip_Data (S, Input.Remaining);
      end if;
      return Results.Success;
   end Decode_JPEG;

   --  Draw srcRect, in image coordinates, through the matrix onto the picture, a row at a time.
   function Paint_Image
     (P : in out Rendering.Painter;
      S : in out Sessions.Session;
      Event : Pictures.Opcode_Event;
      Header : Image_Header;
      Item : Description;
      Mask : in out Regions.Region;
      Has_Mask : Boolean;
      Pixels : not null Pixel_Buffer_Access) return Results.Result
   is
      Transform : Matrix renames Header.Transform;
      Largest : constant Natural := Natural (Coordinate'Last);
      Clamped : constant Geometry.Rect :=
        (Top => Coordinate'Max (Header.Source.Top, 0), Left => Coordinate'Max (Header.Source.Left, 0),
         Bottom => Coordinate'Min (Header.Source.Bottom, Coordinate (Natural'Min (Item.Height, Largest))),
         Right => Coordinate'Min (Header.Source.Right, Coordinate (Natural'Min (Item.Width, Largest))));
      Destination : constant Regions.Area :=
        (Top => Round_Fixed (Long_Long_Integer (Clamped.Top) * Transform (5) + Transform (8)) - P.Origin_V,
         Left => Round_Fixed (Long_Long_Integer (Clamped.Left) * Transform (1) + Transform (7)) - P.Origin_H,
         Bottom => Round_Fixed (Long_Long_Integer (Clamped.Bottom) * Transform (5) + Transform (8)) - P.Origin_V,
         Right => Round_Fixed (Long_Long_Integer (Clamped.Right) * Transform (1) + Transform (7)) - P.Origin_H);
      Source_Width : constant Long_Long_Integer := Long_Long_Integer (Geometry.Width (Clamped));
      Source_Height : constant Long_Long_Integer := Long_Long_Integer (Geometry.Height (Clamped));
      Destination_Width : constant Long_Long_Integer := Long_Long_Integer (Destination.Right - Destination.Left);
      Destination_Height : constant Long_Long_Integer := Long_Long_Integer (Destination.Bottom - Destination.Top);
      Kind : Transfer_Modes.Mode_Kind;
      Outcome : Results.Result := Rendering.Mode (S, Event, Header.Mode_Word, Kind);

      --  The image pixel destination pixel X, Y samples; a decompressed image is not colorized.
      function Color_At (X, Y : Integer; Under : Images.RGB_Color) return Images.RGB_Color is
         Row : constant Natural :=
           Natural (Clamped.Top) + Natural ((Long_Long_Integer (Y - Destination.Top) * Source_Height)
                                            / Destination_Height);
         Column : constant Natural :=
           Natural (Clamped.Left) + Natural ((Long_Long_Integer (X - Destination.Left) * Source_Width)
                                             / Destination_Width);
         At_Pixel : constant Positive := Bytes_Per_Pixel * (Row * Item.Width + Column) + 1;
      begin
         return Transfer_Modes.Compose
           (Kind, (Byte (Pixels (At_Pixel)), Byte (Pixels (At_Pixel + 1)), Byte (Pixels (At_Pixel + 2))), Under,
            P.Colors, Colorize => False);
      end Color_At;
      function Paint is new Rendering.Paint_Row (Color_At);
   begin
      --  The drawing after HiliteMode, as for any copy.
      if P.Hilite_Next then
         Kind := Transfer_Modes.Hilite;
         P.Hilite_Next := False;
      end if;
      if not Results.Succeeded (Outcome) or else Geometry.Is_Empty (Clamped) or else Regions.Is_Empty (Destination)
      then
         return Outcome;
      end if;
      for Y in Integer'Max (Destination.Top, P.Window.Top) .. Integer'Min (Destination.Bottom, P.Window.Bottom) - 1
      loop
         exit when not Results.Succeeded (Outcome);
         Outcome := Rendering.Begin_Row (P, S, Y, Destination.Left, Destination.Right);
         if Results.Succeeded (Outcome) and then Has_Mask and then not P.Row_Spans.Is_Empty then
            Outcome := Rendering.Mask_Row (P, S, Mask, Y);
         end if;
         if Results.Succeeded (Outcome) then
            Outcome := Paint (P, S, Y);
         end if;
      end loop;
      return Outcome;
   end Paint_Image;

   function Draw
     (P : in out Rendering.Painter;
      S : in out Sessions.Session;
      Event : Pictures.Opcode_Event;
      Length : Byte_Count) return Results.Result
   is
      Start : constant Byte_Count := Picture_Stream.Picture_Offset (S.Stream);
      Header : Image_Header;
      Item : Description;
      Mask : Regions.Region;
      Has_Mask : Boolean := False;
      Pixels : Pixel_Buffer_Access;
      Outcome : Results.Result;

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
   begin
      --  Only an image drawn by this opcode hides the bits opcode after it.
      P.Skip_Next_Bits := False;
      if Length < Header_Bytes + Description_Bytes then
         return Too_Long (Header_Bytes + Description_Bytes);
      end if;
      Outcome := Read_Image_Header (S, Header);
      if not Results.Succeeded (Outcome) then
         return Outcome;
      end if;

      --  The matte: an alpha image of its own, which this renderer does not composite.
      if Header.Matte_Size > 0 then
         if Byte_Count (Header.Matte_Size) > Length - Used then
            return Too_Long (Byte_Count (Header.Matte_Size));
         end if;
         Outcome := Rendering.Unsupported (S, Event);
         if Results.Succeeded (Outcome) then
            Outcome := Sessions.Skip_Data (S, Byte_Count (Header.Matte_Size));
         end if;
         if not Results.Succeeded (Outcome) then
            return Outcome;
         end if;
      end if;
      if Header.Mask_Size > 0 then
         declare
            Before : constant Byte_Count := Used;
         begin
            if Byte_Count (Header.Mask_Size) > Length - Used then
               return Too_Long (Byte_Count (Header.Mask_Size));
            end if;
            Outcome := Regions.Read (S, Mask);
            if not Results.Succeeded (Outcome) then
               return Outcome;
            elsif Used - Before /= Byte_Count (Header.Mask_Size) then
               return Sessions.Fail (S, Errors.Region_Invalid, Byte_Count (Header.Mask_Size), Used - Before);
            end if;
            Has_Mask := True;
            Regions.Translate (Mask, -P.Origin_H, -P.Origin_V);
         end;
      end if;

      Outcome := Read_Description (S, Item);
      if not Results.Succeeded (Outcome) then
         return Outcome;
      elsif Item.Size < Description_Bytes then
         return Results.Failure
           (Errors.Make
              (Errors.Opcode_Length_Invalid,
               (Context_Of (Event) with delta Expected => Description_Bytes, Actual => Byte_Count (Item.Size))));
      elsif Byte_Count (Item.Size) - Description_Bytes > Length - Used then
         return Too_Long (Byte_Count (Item.Size) - Description_Bytes);
      end if;
      Outcome := Sessions.Skip_Data (S, Byte_Count (Item.Size) - Description_Bytes);
      if not Results.Succeeded (Outcome) then
         return Outcome;
      elsif Byte_Count (Item.Data_Size) > Length - Used then
         return Too_Long (Byte_Count (Item.Data_Size));
      elsif not Is_Supported (Header, Item) then
         return Finish (Rendering.Unsupported (S, Event));
      end if;
      Outcome := Check_Image (S, Event, Item);
      if not Results.Succeeded (Outcome) then
         return Outcome;
      end if;

      declare
         Pixel_Bytes : constant Byte_Count := Bytes_Per_Pixel * Byte_Count (Item.Width) * Byte_Count (Item.Height);
         --  What is left of the per-allocation budget, but no more than a decode of this size needs.
         Share : constant Byte_Count :=
           Byte_Count'Min (S.Budget.Max_Allocation_Bytes - Pixel_Bytes,
                           Jpeglib_Pixel_Factor * Pixel_Bytes + Jpeglib_Fixed_Bytes);
      begin
         --  Decoding is drawing work, a unit per pixel and per row, drawn or not, as for a copied pixmap; the
         --  pixels and jpeglib's share count against the aggregate allocation quota.
         Outcome :=
           Rendering.Charge (P, S, Pixel_Count (Item.Width) * Pixel_Count (Item.Height) + Pixel_Count (Item.Height));
         if Results.Succeeded (Outcome) then
            Outcome := Sessions.Admit_Aggregate (S, Pixel_Bytes + Share);
         end if;
         if Results.Succeeded (Outcome) then
            Outcome := Decode_JPEG (S, Event, Item, Share, Pixels);
         end if;
      end;
      if Results.Succeeded (Outcome) then
         Outcome := Finish (Results.Success);
      end if;
      if Results.Succeeded (Outcome) then
         Outcome := Paint_Image (P, S, Event, Header, Item, Mask, Has_Mask, Pixels);
      end if;
      Free (Pixels);
      P.Skip_Next_Bits := Results.Succeeded (Outcome);
      return Outcome;
   end Draw;
end Pictlib.Internal.QuickTime;
