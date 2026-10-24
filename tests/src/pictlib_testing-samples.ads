with Pictlib.Images;
with Pictlib.Streams;

--  Deterministic source images for the encoder, shared by the unit tests and the conformance tool.
package Pictlib_Testing.Samples is
   type Kind is (Gradient, Three_Colors, Black_And_White, Gray_Ramp, Translucent);

   type Bytes_Access is access Pictlib.Streams.Byte_Array;

   --  Make: a tightly packed image of Width x Height pixels in Format.
   function Make
     (Item : Kind;
      Width, Height : Positive;
      Format : Pictlib.Pixel_Format := Pictlib.RGB_24) return Bytes_Access;
   --  Color of the sample at X, Y.
   function Color (Item : Kind; X, Y : Natural) return Pictlib.Images.RGB_Color;
   --  View of storage Make returned.
   function View
     (Storage : not null Bytes_Access;
      Width, Height : Positive;
      Format : Pictlib.Pixel_Format := Pictlib.RGB_24) return Pictlib.Images.Image_View;
end Pictlib_Testing.Samples;
