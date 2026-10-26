with Interfaces;
with Pictlib.Errors;
with Pictlib.Geometry;
with Pictlib.Images;
with Pictlib.Internal.Bytes;
with Pictlib.Internal.Failures;
with Pictlib.Internal.JPEG_Bridge;
with Pictlib.Internal.Region_Reader;
with Pictlib.Internal.Regions;
with Pictlib.Internal.Transfer_Modes;
with Pictlib.Streams;

package body Pictlib.Internal.QuickTime is
   use type Interfaces.Unsigned_32;

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
   Fixed_One : constant Long_Long_Integer := Long_Long_Integer (Geometry.Fixed_One);
   Fract_One : constant := 16#4000_0000#;


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
            Header.Transform (Index) := Bytes.To_Signed_32 (Value);
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

   begin
      Item := (Size => Item.Size, others => <>);
      if Results.Succeeded (Outcome) then
         Outcome := Sessions.Read_Long (S, Item.Codec);
      end if;
      if Results.Succeeded (Outcome) then
         Outcome := Sessions.Read_Into (S, Fields);
      end if;
      if Results.Succeeded (Outcome) then
         Item.Width := Natural (Bytes.Word_At (Fields, Width_Field));
         Item.Height := Natural (Bytes.Word_At (Fields, Height_Field));
         Item.Data_Size := Bytes.Long_At (Fields, Data_Size_Field);
      end if;
      return Outcome;
   end Read_Description;

   --  Only JPEG, and only matrices that translate and scale.
   function Is_Supported (Header : Image_Header; Item : Description) return Boolean is
     (Item.Codec = JPEG_Codec
      and then Header.Transform (2) = 0 and then Header.Transform (4) = 0 and then Header.Transform (3) = 0
      and then Header.Transform (6) = 0 and then Header.Transform (9) = Fract_One
      and then Header.Transform (1) > 0 and then Header.Transform (5) > 0);

   --  The embedded limits, and the one buffer of pixels, indexed by Natural, whatever the budget allows; the
   --  allocation budget is the session's to check, as for any allocation.
   function Check_Image (S : Sessions.Session; Event : Pictures.Opcode_Event; Item : Description)
     return Results.Result
   is
      Pixels : constant Byte_Count := Byte_Count (Item.Width) * Byte_Count (Item.Height);
      Largest : constant Byte_Count := Byte_Count (Natural'Last);
   begin
      if Byte_Count (Item.Data_Size) > S.Budget.Max_Embedded_Image_Bytes then
         return Sessions.Over_Limit
           (S, Embedded_Image_Byte_Limit, S.Budget.Max_Embedded_Image_Bytes, Byte_Count (Item.Data_Size));
      elsif Pixels = 0 then
         return Failures.In_Opcode (Event, Errors.Embedded_Image_Failed);
      elsif Pixel_Count (Pixels) > S.Budget.Max_Embedded_Image_Pixels then
         return Sessions.Over_Limit
           (S, Embedded_Image_Pixel_Limit, Byte_Count (S.Budget.Max_Embedded_Image_Pixels), Pixels);
      elsif JPEG_Bridge.Pixel_Bytes ((Item.Width, Item.Height, Item.Data_Size)) > Largest then
         --  The budget as set when it is the smaller bound.
         return Sessions.Over_Limit
           (S, Allocation_Byte_Limit, Byte_Count'Min (Largest, S.Budget.Max_Allocation_Bytes),
            JPEG_Bridge.Pixel_Bytes ((Item.Width, Item.Height, Item.Data_Size)));
      end if;
      return Results.Success;
   end Check_Image;

   --  Draw srcRect, in image coordinates, through the matrix onto the picture, a row at a time.
   function Paint_Image
     (P : in out Rendering.Painter;
      S : in out Sessions.Session;
      Event : Pictures.Opcode_Event;
      Header : Image_Header;
      Item : Description;
      Mask : in out Regions.Region;
      Has_Mask : Boolean;
      Pixels : not null JPEG_Bridge.Pixel_Buffer_Access) return Results.Result
   is
      Transform : Matrix renames Header.Transform;
      Largest : constant Natural := Natural (Coordinate'Last);
      Clamped : constant Geometry.Rect :=
        (Top => Coordinate'Max (Header.Source.Top, 0), Left => Coordinate'Max (Header.Source.Left, 0),
         Bottom => Coordinate'Min (Header.Source.Bottom, Coordinate (Natural'Min (Item.Height, Largest))),
         Right => Coordinate'Min (Header.Source.Right, Coordinate (Natural'Min (Item.Width, Largest))));
      Destination : constant Regions.Area :=
        (Top => Round_Fixed (Long_Long_Integer (Clamped.Top) * Transform (5) + Transform (8)) - P.Port.Origin_V,
         Left => Round_Fixed (Long_Long_Integer (Clamped.Left) * Transform (1) + Transform (7)) - P.Port.Origin_H,
         Bottom => Round_Fixed (Long_Long_Integer (Clamped.Bottom) * Transform (5) + Transform (8)) - P.Port.Origin_V,
         Right => Round_Fixed (Long_Long_Integer (Clamped.Right) * Transform (1) + Transform (7)) - P.Port.Origin_H);
      Source_Width : constant Long_Long_Integer := Long_Long_Integer (Geometry.Width (Clamped));
      Source_Height : constant Long_Long_Integer := Long_Long_Integer (Geometry.Height (Clamped));
      Destination_Width : constant Long_Long_Integer := Long_Long_Integer (Destination.Right - Destination.Left);
      Destination_Height : constant Long_Long_Integer := Long_Long_Integer (Destination.Bottom - Destination.Top);
      Kind : Transfer_Modes.Mode_Kind;
      --  The drawing after HiliteMode, as for any copy.
      Outcome : Results.Result :=
        Rendering.Drawing_Mode (S, Event, Header.Mode_Word, Rendering.Take_Hilite (P), Kind);

      --  The image pixel destination pixel X, Y samples; a decompressed image is not colorized.
      function Color_At (X, Y : Integer; Under : Images.RGB_Color) return Images.RGB_Color is
         Row : constant Natural :=
           Natural (Clamped.Top) + Rendering.Sampled (Y - Destination.Top, Source_Height, Destination_Height);
         Column : constant Natural :=
           Natural (Clamped.Left) + Rendering.Sampled (X - Destination.Left, Source_Width, Destination_Width);
         At_Pixel : constant Positive := JPEG_Bridge.Bytes_Per_Pixel * (Row * Item.Width + Column) + 1;
      begin
         return Transfer_Modes.Compose
           (Kind, (Byte (Pixels (At_Pixel)), Byte (Pixels (At_Pixel + 1)), Byte (Pixels (At_Pixel + 2))), Under,
            P.Port.Colors, Colorize => False);
      end Color_At;
      function Paint is new Rendering.Paint_Row (Color_At);
   begin
      if not Results.Succeeded (Outcome) or else Geometry.Is_Empty (Clamped) or else Regions.Is_Empty (Destination)
      then
         return Outcome;
      end if;
      for Y in Integer'Max (Destination.Top, P.Window.Top) .. Integer'Min (Destination.Bottom, P.Window.Bottom) - 1
      loop
         exit when not Results.Succeeded (Outcome);
         Outcome := Rendering.Begin_Masked_Row (P, S, Y, Destination.Left, Destination.Right, Mask, Has_Mask);
         if Results.Succeeded (Outcome) then
            Outcome := Paint (P, S, Y);
         end if;
      end loop;
      return Outcome;
   end Paint_Image;

   --  Where an opcode's data began and how long it is, so its parts can be checked against what is left.
   type Extent is record
      Start, Length : Byte_Count := 0;
   end record;

   function Used (S : Sessions.Session; Within : Extent) return Byte_Count is (S.Picture_Offset - Within.Start);

   function Left (S : Sessions.Session; Within : Extent) return Byte_Count is (Within.Length - Used (S, Within));

   --  A part wanting more bytes than are left of the opcode.
   function Part_Too_Long
     (S : Sessions.Session; Event : Pictures.Opcode_Event; Within : Extent; Wanted : Byte_Count)
      return Results.Result
   is (Failures.In_Opcode (Event, Errors.Opcode_Length_Invalid, Within.Length, Used (S, Within) + Wanted));

   --  The matte: an alpha image of its own, which this renderer does not composite.
   function Skip_Matte
     (S : in out Sessions.Session; Event : Pictures.Opcode_Event; Within : Extent; Header : Image_Header)
      return Results.Result
   is
      Outcome : Results.Result;
   begin
      if Header.Matte_Size = 0 then
         return Results.Success;
      elsif Byte_Count (Header.Matte_Size) > Left (S, Within) then
         return Part_Too_Long (S, Event, Within, Byte_Count (Header.Matte_Size));
      end if;
      Outcome := Rendering.Unsupported (S, Event, 0, Byte_Count (Header.Matte_Size));
      if Results.Succeeded (Outcome) then
         Outcome := Sessions.Skip_Data (S, Byte_Count (Header.Matte_Size));
      end if;
      return Outcome;
   end Skip_Matte;

   --  The mask region, in the port's local coordinates, which must take exactly the bytes the header gives it.
   function Read_Mask
     (P : Rendering.Painter;
      S : in out Sessions.Session;
      Event : Pictures.Opcode_Event;
      Within : Extent;
      Header : Image_Header;
      Mask : in out Regions.Region;
      Has_Mask : out Boolean) return Results.Result
   is
      Before : constant Byte_Count := Used (S, Within);
      Outcome : Results.Result;
   begin
      Has_Mask := False;
      if Header.Mask_Size = 0 then
         return Results.Success;
      elsif Byte_Count (Header.Mask_Size) > Left (S, Within) then
         return Part_Too_Long (S, Event, Within, Byte_Count (Header.Mask_Size));
      end if;
      Outcome := Region_Reader.Read (S, Mask);
      if not Results.Succeeded (Outcome) then
         return Outcome;
      elsif Used (S, Within) - Before /= Byte_Count (Header.Mask_Size) then
         return Sessions.Fail (S, Errors.Region_Invalid, Byte_Count (Header.Mask_Size), Used (S, Within) - Before);
      end if;
      Has_Mask := True;
      Regions.Translate (Mask, -P.Port.Origin_H, -P.Port.Origin_V);
      return Results.Success;
   end Read_Mask;

   --  The image description, its bytes past the fields read skipped, and room for the data it announces.
   function Read_Image_Description
     (S : in out Sessions.Session; Event : Pictures.Opcode_Event; Within : Extent; Item : out Description)
      return Results.Result
   is
      Outcome : Results.Result;
   begin
      Item := (others => <>);
      --  The matte and mask may leave no room for the description.
      if Description_Bytes > Left (S, Within) then
         return Part_Too_Long (S, Event, Within, Description_Bytes);
      end if;
      Outcome := Read_Description (S, Item);
      if not Results.Succeeded (Outcome) then
         return Outcome;
      elsif Item.Size < Description_Bytes then
         return Failures.In_Opcode (Event, Errors.Opcode_Length_Invalid, Description_Bytes, Byte_Count (Item.Size));
      elsif Byte_Count (Item.Size) - Description_Bytes > Left (S, Within) then
         return Part_Too_Long (S, Event, Within, Byte_Count (Item.Size) - Description_Bytes);
      end if;
      Outcome := Sessions.Skip_Data (S, Byte_Count (Item.Size) - Description_Bytes);
      if not Results.Succeeded (Outcome) then
         return Outcome;
      elsif Byte_Count (Item.Data_Size) > Left (S, Within) then
         return Part_Too_Long (S, Event, Within, Byte_Count (Item.Data_Size));
      end if;
      return Results.Success;
   end Read_Image_Description;

   function Draw
     (P : in out Rendering.Painter;
      S : in out Sessions.Session;
      Event : Pictures.Opcode_Event;
      Length : Byte_Count) return Results.Result
   is
      Within : constant Extent := (Start => S.Picture_Offset, Length => Length);
      Header : Image_Header;
      Item : Description;
      Mask : Regions.Region;
      Has_Mask : Boolean := False;
      Pixels : JPEG_Bridge.Pixel_Buffer_Access;
      Outcome : Results.Result;

      --  Skip whatever of the opcode is left.
      function Finish (Result : Results.Result) return Results.Result is
      begin
         if Results.Succeeded (Result) and then Left (S, Within) > 0 then
            return Sessions.Skip_Data (S, Left (S, Within));
         end if;
         return Result;
      end Finish;
   begin
      --  Only an image drawn by this opcode hides the bits opcode after it.
      P.Port.Skip_Next_Bits := False;
      if Length < Header_Bytes + Description_Bytes then
         return Part_Too_Long (S, Event, Within, Header_Bytes + Description_Bytes);
      end if;
      Outcome := Read_Image_Header (S, Header);
      if Results.Succeeded (Outcome) then
         Outcome := Skip_Matte (S, Event, Within, Header);
      end if;
      if Results.Succeeded (Outcome) then
         Outcome := Read_Mask (P, S, Event, Within, Header, Mask, Has_Mask);
      end if;
      if Results.Succeeded (Outcome) then
         Outcome := Read_Image_Description (S, Event, Within, Item);
      end if;
      if not Results.Succeeded (Outcome) then
         return Outcome;
      elsif not Is_Supported (Header, Item) then
         --  The codec named, when it is not JPEG's.
         return Finish
           (Rendering.Unsupported
              (S, Event, (if Item.Codec = JPEG_Codec then 0 else JPEG_Codec),
               (if Item.Codec = JPEG_Codec then 0 else Byte_Count (Item.Codec))));
      end if;
      Outcome := Check_Image (S, Event, Item);
      if not Results.Succeeded (Outcome) then
         return Outcome;
      end if;

      Outcome := JPEG_Bridge.Admit_And_Decode (S, Event, (Item.Width, Item.Height, Item.Data_Size), Pixels);
      --  A JPEG jpeglib cannot decode is an image this renderer cannot draw, as another codec is: strictly
      --  unsupported, otherwise skipped with a warning, the rest of the opcode with it.
      if not Results.Succeeded (Outcome)
        and then Errors."=" (Outcome.First_Error.Code, Errors.Unsupported_Feature)
        and then Sessions.Is_Lenient (S)
      then
         JPEG_Bridge.Free (Pixels);
         return Finish
           (Rendering.Unsupported (S, Event, Outcome.First_Error.Context.Expected, Outcome.First_Error.Context.Actual));
      end if;
      if Results.Succeeded (Outcome) then
         Outcome := Finish (Results.Success);
      end if;
      if Results.Succeeded (Outcome) then
         Outcome := Paint_Image (P, S, Event, Header, Item, Mask, Has_Mask, Pixels);
      end if;
      JPEG_Bridge.Free (Pixels);
      P.Port.Skip_Next_Bits := Results.Succeeded (Outcome);
      return Outcome;
   exception
      --  The source's exception, met skipping the rest of the opcode, passes through, the pixels released.
      when others =>
         JPEG_Bridge.Free (Pixels);
         raise;
   end Draw;
end Pictlib.Internal.QuickTime;
