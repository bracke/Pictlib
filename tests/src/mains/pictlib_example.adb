--  The README's example: encode a small RGB image as a PICT in memory, then decode the picture and render it
--  back into a view of its frame's size. It is built with the tests crate so it stays true to the API.
with Ada.Command_Line;
with Ada.Text_IO;
with Pictlib;
with Pictlib.Decoding;
with Pictlib.Encoding;
with Pictlib.Images;
with Pictlib.Results;
with Pictlib.Streams;

procedure Pictlib_Example is
   use type Pictlib.Streams.Byte_Array;

   Width : constant := 4;
   Height : constant := 2;
   Row_Bytes : constant := 3 * Width;
   Image_Bytes : constant := Row_Bytes * Height;
   --  Tightly packed RGB, the layout of both the image encoded and the view rendered into.
   Layout : constant Pictlib.Images.Image_Descriptor :=
     (Width => Width, Height => Height, Format => Pictlib.RGB_24, Stride => Row_Bytes,
      Accessible_Bytes => Image_Bytes);

   --  A 4 x 2 RGB image to encode, and room for the picture.
   Pixels : constant Pictlib.Streams.Byte_Array_Access := new Pictlib.Streams.Byte_Array (1 .. Image_Bytes);
   Picture : constant Pictlib.Streams.Byte_Array_Access := new Pictlib.Streams.Byte_Array (1 .. 4_096);
   Output : aliased Pictlib.Streams.Fixed_Buffer_Destination;
   Encoder : Pictlib.Encoding.Encoder;
   Outcome : Pictlib.Results.Result;
begin
   for Index in Pixels'Range loop
      Pixels (Index) := Pictlib.Byte ((Index * 40) mod 256);
   end loop;

   --  Encode: one image becomes one picture.
   Pictlib.Streams.Open (Output, Picture);
   Pictlib.Encoding.Initialize (Encoder, Output'Access);
   Outcome := Pictlib.Encoding.Encode (Encoder, (Descriptor => Layout, Storage => Pixels));
   if Pictlib.Results.Succeeded (Outcome) then
      Outcome := Pictlib.Encoding.Finish (Encoder);
   end if;
   if not Pictlib.Results.Succeeded (Outcome) then
      Ada.Text_IO.Put_Line ("encode failed: " & Outcome.First_Error.Code'Image);
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      return;
   end if;

   --  Decode: read the header for the frame, then render into a view of the frame's size.
   declare
      Length : constant Natural := Natural (Pictlib.Encoding.Bytes_Written (Encoder));
      Input : aliased Pictlib.Streams.Memory_Source;
      Decoder : Pictlib.Decoding.Decoder;
      Canvas : constant Pictlib.Streams.Byte_Array_Access := new Pictlib.Streams.Byte_Array (1 .. Image_Bytes);
   begin
      Pictlib.Streams.Open (Input, new Pictlib.Streams.Byte_Array'(Picture (1 .. Length)));
      Pictlib.Decoding.Initialize (Decoder, Input'Access);
      Outcome := Pictlib.Decoding.Read_Header (Decoder);
      if Pictlib.Results.Succeeded (Outcome) then
         Outcome := Pictlib.Decoding.Render (Decoder, (Descriptor => Layout, Storage => Canvas));
      end if;
      if Pictlib.Results.Succeeded (Outcome) and then Canvas.all = Pixels.all then
         Ada.Text_IO.Put_Line ("a" & Length'Image & "-byte picture decoded back to its pixels");
      else
         Ada.Text_IO.Put_Line ("decode failed: " & Outcome.First_Error.Code'Image);
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      end if;
   end;
end Pictlib_Example;
