with Ada.Strings.Unbounded;
with Pictlib_Testing.Recorders;

package body Pictlib_Testing.Canvases is
   use type Pictlib.Images.RGB_Color;

   function View
     (Storage : not null access Pictlib.Streams.Byte_Array;
      Width, Height : Positive;
      Format : Pictlib.Pixel_Format := Pictlib.RGB_24;
      Stride : Natural := 0) return Pictlib.Images.Mutable_Image_View
   is
      Row : constant Natural := Width * Natural (Pictlib.Images.Bytes_Per_Pixel (Format));
      Step : constant Natural := (if Stride = 0 then Row else Stride);
   begin
      return
        (Descriptor =>
           (Width => Pictlib.Image_Width (Width),
            Height => Pictlib.Image_Height (Height),
            Format => Format,
            Stride => Pictlib.Row_Stride (Step),
            Accessible_Bytes => Pictlib.Byte_Count (Step * (Height - 1) + Row)),
         Storage => Storage);
   end View;

   procedure Render
     (Input : aliased Pictlib.Streams.Byte_Array;
      Decoder : in out Pictlib.Decoding.Decoder;
      Output : Pictlib.Images.Mutable_Image_View;
      Outcome : out Pictlib.Results.Result;
      Options : Pictlib.Decoding.Options := (others => <>);
      Budget : Pictlib.Limits.Limit_Set := Pictlib.Limits.Default_Limits;
      Max_Transfer : Pictlib.Byte_Count := Pictlib.Byte_Count'Last)
   is
   begin
      Recorders.Start (Input, Decoder, Options, Budget, Max_Transfer);
      Outcome := Pictlib.Decoding.Read_Header (Decoder);
      if Pictlib.Results.Succeeded (Outcome) then
         Outcome := Pictlib.Decoding.Render (Decoder, Output);
      end if;
   end Render;

   function Pixel (Output : Pictlib.Images.Mutable_Image_View; X, Y : Natural) return Pictlib.Images.RGB_Color is
      At_Pixel : constant Positive :=
        Output.Storage'First + Y * Natural (Output.Descriptor.Stride) + 3 * X;
   begin
      return (Output.Storage (At_Pixel), Output.Storage (At_Pixel + 1), Output.Storage (At_Pixel + 2));
   end Pixel;

   function Letter (Color : Pictlib.Images.RGB_Color) return Character is
     (if Color = (16#FF#, 16#FF#, 16#FF#) then 'W'
      elsif Color = (0, 0, 0) then 'B'
      elsif Color = (16#FF#, 0, 0) then 'R'
      elsif Color = (0, 16#FF#, 0) then 'G'
      elsif Color = (0, 0, 16#FF#) then 'U'
      elsif Color = (16#FF#, 16#FF#, 0) then 'Y'
      else '?');

   function Picture_Of (Output : Pictlib.Images.Mutable_Image_View) return String is
      Result : Ada.Strings.Unbounded.Unbounded_String;
   begin
      for Y in 0 .. Natural (Output.Descriptor.Height) - 1 loop
         if Y > 0 then
            Ada.Strings.Unbounded.Append (Result, '/');
         end if;
         for X in 0 .. Natural (Output.Descriptor.Width) - 1 loop
            Ada.Strings.Unbounded.Append (Result, Letter (Pixel (Output, X, Y)));
         end loop;
      end loop;
      return Ada.Strings.Unbounded.To_String (Result);
   end Picture_Of;
end Pictlib_Testing.Canvases;
