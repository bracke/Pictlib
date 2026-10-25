with Pictlib.Encoding;
with Pictlib.Images;
with Pictlib.Limits;
with Pictlib.Results;
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
   --  Alpha of the sample at X, Y in the formats that have it: opaque but for Translucent.
   function Alpha (Item : Kind; X, Y : Natural) return Pictlib.Byte;
   --  Row bytes: rowBytes the encoder writes for Layout (not Auto) at Width; below 8 rows are stored unpacked.
   --  The test-side mirror of the encoder's rule, as Expected_Color mirrors its pixels.
   function Row_Bytes (Layout : Pictlib.Encoding.Layout_Kind; Width : Positive) return Natural
     with Pre => Pictlib.Encoding."/=" (Layout, Pictlib.Encoding.Auto);
   --  Expected color: what a reader of the sample encoded in Layout must see at X, Y -- the sample's color, or
   --  for Mono_1 black below Threshold luminance and white otherwise. The independent oracle of the round trip
   --  tests and the conformance tool.
   function Expected_Color
     (Item : Kind;
      X, Y : Natural;
      Layout : Pictlib.Encoding.Layout_Kind;
      Threshold : Pictlib.Byte := Pictlib.Encoding.Default_Mono_Threshold) return Pictlib.Images.RGB_Color;
   --  View of storage Make returned.
   function View
     (Storage : not null Bytes_Access;
      Width, Height : Positive;
      Format : Pictlib.Pixel_Format := Pictlib.RGB_24) return Pictlib.Images.Image_View;

   --  An encoded picture: what the encoder wrote, also when it failed.
   type Encoded is record
      Data : Bytes_Access;
      Outcome : Pictlib.Results.Result;
      Layout : Pictlib.Encoding.Layout_Kind := Pictlib.Encoding.Auto;
      Bytes_Written : Pictlib.Byte_Count := 0;
   end record;

   --  Encode Image with a fresh encoder into a buffer of Room bytes, finishing it when encoding succeeds.
   function Encode
     (Image : Pictlib.Images.Image_View;
      Settings : Pictlib.Encoding.Options := (others => <>);
      Budget : Pictlib.Limits.Limit_Set := Pictlib.Limits.Default_Limits;
      Max_Transfer : Pictlib.Byte_Count := Pictlib.Byte_Count'Last;
      Room : Positive := 4_000_000) return Encoded;
   --  Encode the sample Item, Width x Height in Format.
   function Encode
     (Item : Kind;
      Width, Height : Positive;
      Settings : Pictlib.Encoding.Options := (others => <>);
      Format : Pictlib.Pixel_Format := Pictlib.RGB_24;
      Budget : Pictlib.Limits.Limit_Set := Pictlib.Limits.Default_Limits;
      Max_Transfer : Pictlib.Byte_Count := Pictlib.Byte_Count'Last;
      Room : Positive := 4_000_000) return Encoded;
end Pictlib_Testing.Samples;
