with Pictlib.Decoding;
with Pictlib.Errors;
with Pictlib.Images;
with Pictlib.Limits;
with Pictlib.Results;
with Pictlib.Streams;

--  Rendering helpers: caller-owned views, and expected rasters written as letters, one per pixel, rows
--  separated by '/': W white, B black, R red, G green, U blue, Y yellow, '?' anything else.
package Pictlib_Testing.Canvases is
   --  View.
   --  @return A view of Storage with the given extent, tightly packed unless Stride is given.
   function View
     (Storage : not null access Pictlib.Streams.Byte_Array;
      Width, Height : Positive;
      Format : Pictlib.Pixel_Format := Pictlib.RGB_24;
      Stride : Natural := 0) return Pictlib.Images.Mutable_Image_View;

   --  Render Input into Output with a fresh decoder.
   procedure Render
     (Input : aliased Pictlib.Streams.Byte_Array;
      Decoder : in out Pictlib.Decoding.Decoder;
      Output : Pictlib.Images.Mutable_Image_View;
      Outcome : out Pictlib.Results.Result;
      Options : Pictlib.Decoding.Options := (others => <>);
      Budget : Pictlib.Limits.Limit_Set := Pictlib.Limits.Default_Limits;
      Max_Transfer : Pictlib.Byte_Count := Pictlib.Byte_Count'Last);

   --  Expect raster: Input renders successfully to Expected in a Width x Height RGB_24 view.
   procedure Expect_Raster
     (Input : aliased Pictlib.Streams.Byte_Array;
      Width, Height : Positive;
      Expected : String;
      Label : String;
      Options : Pictlib.Decoding.Options := (others => <>));

   --  Expect failure: rendering Input fails with Code, naming Op when Op is not 0.
   procedure Expect_Failure
     (Input : aliased Pictlib.Streams.Byte_Array;
      Width, Height : Positive;
      Code : Pictlib.Errors.Error_Code;
      Label : String;
      Op : Pictlib.Opcode := 0;
      Options : Pictlib.Decoding.Options := (others => <>);
      Budget : Pictlib.Limits.Limit_Set := Pictlib.Limits.Default_Limits);

   --  Pixel.
   --  @return The color at X, Y of an RGB_24 view.
   function Pixel (Output : Pictlib.Images.Mutable_Image_View; X, Y : Natural) return Pictlib.Images.RGB_Color;
   --  Picture of.
   --  @return The letters of an RGB_24 view, for comparison with an expected raster.
   function Picture_Of (Output : Pictlib.Images.Mutable_Image_View) return String;
end Pictlib_Testing.Canvases;
