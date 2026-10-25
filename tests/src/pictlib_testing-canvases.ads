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

   --  Frame bytes.
   --  @return The bytes a tightly packed view of Decoder's frame holds in Format; Decoder has read its header.
   function Frame_Bytes
     (Decoder : Pictlib.Decoding.Decoder;
      Format : Pictlib.Pixel_Format := Pictlib.RGB_24) return Natural;
   --  Frame view.
   --  @return A tightly packed view of Storage the size of Decoder's frame, which Render requires.
   function Frame_View
     (Decoder : Pictlib.Decoding.Decoder;
      Storage : not null Pictlib.Streams.Byte_Array_Access;
      Format : Pictlib.Pixel_Format := Pictlib.RGB_24) return Pictlib.Images.Mutable_Image_View
     with Pre => Storage'Length >= Frame_Bytes (Decoder, Format);

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
      Options : Pictlib.Decoding.Options := (others => <>);
      Max_Transfer : Pictlib.Byte_Count := Pictlib.Byte_Count'Last);

   --  A pixel an Expect_Pixels call checks.
   type Probe is record
      X, Y : Natural;
      Color : Pictlib.Images.RGB_Color;
   end record;
   type Probe_Array is array (Positive range <>) of Probe;

   --  Expect pixels: Input renders successfully in a Width x Height RGB_24 view, with each probe's pixel its color.
   procedure Expect_Pixels
     (Input : aliased Pictlib.Streams.Byte_Array;
      Width, Height : Positive;
      Probes : Probe_Array;
      Label : String);

   --  Expect failure: rendering Input fails with Code, naming Op unless it is Any_Opcode, and Limit when it is
   --  given, and leaves the decoder in State, with Code as its last error when that is Failed and none otherwise.
   procedure Expect_Failure
     (Input : aliased Pictlib.Streams.Byte_Array;
      Width, Height : Positive;
      Code : Pictlib.Errors.Error_Code;
      Label : String;
      Op : Expected_Opcode := Any_Opcode;
      Options : Pictlib.Decoding.Options := (others => <>);
      Budget : Pictlib.Limits.Limit_Set := Pictlib.Limits.Default_Limits;
      Limit : Pictlib.Limit_Kind := Pictlib.No_Limit;
      State : Pictlib.Decoding.Decoder_State := Pictlib.Decoding.Failed);

   --  Render leniently: success, Expected, and a warning with Code.
   procedure Expect_Lenient
     (Input : aliased Pictlib.Streams.Byte_Array;
      Width, Height : Positive;
      Expected : String;
      Code : Pictlib.Errors.Warning_Code;
      Label : String;
      Strictness : Pictlib.Strictness_Mode := Pictlib.Compatible);

   --  The least drawing budget Input renders under, found by bisection up to High; every budget below it must
   --  fail on the drawing limit, so the search never stops on another error.
   function Least_Drawing_Work
     (Input : aliased Pictlib.Streams.Byte_Array;
      Width, Height : Positive;
      Label : String;
      Options : Pictlib.Decoding.Options := (others => <>);
      Budget : Pictlib.Limits.Limit_Set := Pictlib.Limits.Default_Limits;
      High : Pictlib.Pixel_Count := 1_073_741_824) return Pictlib.Pixel_Count;

   --  How far two conforming JPEG decoders, libjpeg and jpeglib, may differ in a component of the same pixel,
   --  after the inverse DCT and color conversion.
   JPEG_Decoder_Tolerance : constant := 2;
   --  Difference.
   --  @return The largest difference of a component of Left from the same component of Right.
   function Difference (Left, Right : Pictlib.Images.RGB_Color) return Natural is
     (Natural'Max (abs (Integer (Left.Red) - Integer (Right.Red)),
                   Natural'Max (abs (Integer (Left.Green) - Integer (Right.Green)),
                                abs (Integer (Left.Blue) - Integer (Right.Blue)))));
   --  Pixel.
   --  @return The color at X, Y of an RGB_24 view.
   function Pixel (Output : Pictlib.Images.Mutable_Image_View; X, Y : Natural) return Pictlib.Images.RGB_Color;
   --  Picture of.
   --  @return The letters of an RGB_24 view, for comparison with an expected raster.
   function Picture_Of (Output : Pictlib.Images.Mutable_Image_View) return String;
end Pictlib_Testing.Canvases;
