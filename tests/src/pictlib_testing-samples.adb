package body Pictlib_Testing.Samples is
   function Color (Item : Kind; X, Y : Natural) return Pictlib.Images.RGB_Color is
   begin
      case Item is
         when Gradient | Translucent =>
            return (Pictlib.Byte ((X * 7) mod 256), Pictlib.Byte ((Y * 11) mod 256), Pictlib.Byte ((X * Y) mod 256));
         when Three_Colors =>
            return (case (X / 3 + Y / 2) mod 3 is
                       when 0 => (16#FF#, 0, 0),
                       when 1 => (16#12#, 16#34#, 16#56#),
                       when others => (16#FF#, 16#FF#, 16#FF#));
         when Black_And_White =>
            return (if (X + Y) mod 3 = 0 or else X mod 7 = 1 then Pictlib.Images.Black else Pictlib.Images.White);
         when Gray_Ramp =>
            return (Pictlib.Byte ((X * 37) mod 256), Pictlib.Byte ((X * 37) mod 256), Pictlib.Byte ((X * 37) mod 256));
      end case;
   end Color;

   function Alpha (Item : Kind; X, Y : Natural) return Pictlib.Byte is
     (if Item = Translucent then Pictlib.Byte ((X * 13 + Y) mod 256) else 16#FF#);

   function Make
     (Item : Kind;
      Width, Height : Positive;
      Format : Pictlib.Pixel_Format := Pictlib.RGB_24) return Bytes_Access
   is
      Size : constant Natural := Natural (Pictlib.Images.Bytes_Per_Pixel (Format));
      Result : constant Bytes_Access := new Pictlib.Streams.Byte_Array (1 .. Size * Width * Height);
   begin
      for Y in 0 .. Height - 1 loop
         for X in 0 .. Width - 1 loop
            declare
               C : constant Pictlib.Images.RGB_Color := Color (Item, X, Y);
               A : constant Pictlib.Byte := Alpha (Item, X, Y);
               At_Pixel : constant Positive := Size * (Y * Width + X) + 1;
            begin
               case Format is
                  when Pictlib.RGB_24 => Result (At_Pixel .. At_Pixel + 2) := [C.Red, C.Green, C.Blue];
                  when Pictlib.BGR_24 => Result (At_Pixel .. At_Pixel + 2) := [C.Blue, C.Green, C.Red];
                  when Pictlib.RGBA_32 => Result (At_Pixel .. At_Pixel + 3) := [C.Red, C.Green, C.Blue, A];
                  when Pictlib.BGRA_32 => Result (At_Pixel .. At_Pixel + 3) := [C.Blue, C.Green, C.Red, A];
                  when Pictlib.ARGB_32 => Result (At_Pixel .. At_Pixel + 3) := [A, C.Red, C.Green, C.Blue];
               end case;
            end;
         end loop;
      end loop;
      return Result;
   end Make;

   function View
     (Storage : not null Bytes_Access;
      Width, Height : Positive;
      Format : Pictlib.Pixel_Format := Pictlib.RGB_24) return Pictlib.Images.Image_View
   is
      Size : constant Natural := Natural (Pictlib.Images.Bytes_Per_Pixel (Format));
   begin
      return
        (Descriptor =>
           (Width => Pictlib.Image_Width (Width), Height => Pictlib.Image_Height (Height), Format => Format,
            Stride => Pictlib.Row_Stride (Size * Width),
            Accessible_Bytes => Pictlib.Byte_Count (Size * Width * Height)),
         Storage => Storage);
   end View;

   function Expected_Color
     (Item : Kind;
      X, Y : Natural;
      Layout : Pictlib.Encoding.Layout_Kind;
      Threshold : Pictlib.Byte := Pictlib.Encoding.Default_Mono_Threshold) return Pictlib.Images.RGB_Color
   is
      use type Pictlib.Encoding.Layout_Kind;
      Sample : constant Pictlib.Images.RGB_Color := Color (Item, X, Y);
   begin
      if Layout /= Pictlib.Encoding.Mono_1 then
         return Sample;
      end if;
      --  Rec. 601 luma, in integers.
      return
        (if (299 * Natural (Sample.Red) + 587 * Natural (Sample.Green) + 114 * Natural (Sample.Blue)) / 1000
              < Natural (Threshold)
         then Pictlib.Images.Black else Pictlib.Images.White);
   end Expected_Color;

   function Encode
     (Image : Pictlib.Images.Image_View;
      Settings : Pictlib.Encoding.Options := (others => <>);
      Budget : Pictlib.Limits.Limit_Set := Pictlib.Limits.Default_Limits;
      Max_Transfer : Pictlib.Byte_Count := Pictlib.Byte_Count'Last;
      Room : Positive := 4_000_000) return Encoded
   is
      Storage : constant Pictlib.Streams.Byte_Array_Access := new Pictlib.Streams.Byte_Array (1 .. Room);
      Output : aliased Pictlib.Streams.Fixed_Buffer_Destination;
      Encoder : Pictlib.Encoding.Encoder;
      Result : Encoded;
   begin
      Pictlib.Streams.Open (Output, Storage, Max_Transfer);
      Pictlib.Encoding.Initialize (Encoder, Output'Access, Settings, Budget);
      Result.Outcome := Pictlib.Encoding.Encode (Encoder, Image);
      if Pictlib.Results.Succeeded (Result.Outcome) then
         Result.Outcome := Pictlib.Encoding.Finish (Encoder);
      end if;
      Result.Data := new Pictlib.Streams.Byte_Array'(Storage (1 .. Natural (Output.Offset)));
      Result.Layout := Pictlib.Encoding.Layout_Used (Encoder);
      Result.Bytes_Written := Pictlib.Encoding.Bytes_Written (Encoder);
      return Result;
   end Encode;

   function Encode
     (Item : Kind;
      Width, Height : Positive;
      Settings : Pictlib.Encoding.Options := (others => <>);
      Format : Pictlib.Pixel_Format := Pictlib.RGB_24;
      Budget : Pictlib.Limits.Limit_Set := Pictlib.Limits.Default_Limits;
      Max_Transfer : Pictlib.Byte_Count := Pictlib.Byte_Count'Last;
      Room : Positive := 4_000_000) return Encoded is
     (Encode (View (Make (Item, Width, Height, Format), Width, Height, Format), Settings, Budget, Max_Transfer, Room));
end Pictlib_Testing.Samples;
