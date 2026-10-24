with AUnit.Assertions;

with Pictlib;
with Pictlib.Decoding;
with Pictlib.Errors;
with Pictlib.Images;
with Pictlib.Limits;
with Pictlib.Results;
with Pictlib.Streams;
with Pictlib_Testing.Builders;
with Pictlib_Testing.Canvases;
with Pictlib_Testing.Recorders;

package body Pictlib_Testing.Test_Rendering is
   use AUnit.Assertions;
   use Pictlib_Testing.Builders;
   use type Pictlib.Byte_Count;
   use type Pictlib.Decoding.Decoder_State;
   use type Pictlib.Errors.Error_Code;
   use type Pictlib.Images.RGB_Color;
   use type Pictlib.Limit_Kind;
   use type Pictlib.Opcode;
   use type Pictlib.Row_Index;
   use type Pictlib.Streams.Byte_Array;

   package Decoding renames Pictlib.Decoding;

   --  Every fixture below is assembled from Inside Macintosh: Imaging With QuickDraw, Appendix A, and every
   --  expected raster is worked out by hand from the bits written into it.

   function Copy (Op : Natural; Row_Bytes : Natural; Bounds, Source, Destination : Bytes; Mode : Natural := 0)
     return Bytes is (W (Op) & W (Row_Bytes) & Bounds & Source & Destination & W (Mode));

   --  A 1-bit BitMap, rowBytes 2 < 8 so unpacked: 10100101 and 00001111.
   function Bitmap_2x8 (Mode : Natural := 0; Source : Bytes := Rect (0, 0, 2, 8)) return Bytes is
     (Copy (16#98#, 2, Rect (0, 0, 2, 8), Source, Rect (0, 0, 2, 8), Mode)
      & B (16#A5#) & B (0) & B (16#0F#) & B (0));
   Bitmap_2x8_Raster : constant String := "BWBWWBWB/WWWWBBBB";

   Unpacked_Bitmap : aliased constant Bytes := V2_Picture (0, 0, 2, 8, Bitmap_2x8);
   --  rowBytes 8: one packed row, 32 white then 32 black.
   Packed_Bitmap : aliased constant Bytes :=
     V2_Picture (0, 0, 1, 64, Copy (16#98#, 8, Rect (0, 0, 1, 64), Rect (0, 0, 1, 64), Rect (0, 0, 1, 64))
                 & B (4) & B (16#FD#) & B (0) & B (16#FD#) & B (16#FF#) & B (0));

   --  An 8-bit PixMap with a sparse table: values 0 red, 5 green, 200 blue.
   function Indexed_8 (Flags : Natural; Values : Bytes; Pixels : Bytes) return Bytes is
     (W (16#98#) & W (16#8000# + 4) & Rect (0, 0, 2, 4) & Pixmap_Tail (0, 8, 1, 8)
      & Table_Header (Flags, 3) & W (Natural (Values (1))) & W (16#FFFF#) & W (0) & W (0)
      & W (Natural (Values (2))) & W (0) & W (16#FFFF#) & W (0)
      & W (Natural (Values (3))) & W (0) & W (0) & W (16#FFFF#)
      & Rect (0, 0, 2, 4) & Rect (0, 0, 2, 4) & W (0) & Pixels);
   Sparse_Table : aliased constant Bytes :=
     V2_Picture (0, 0, 2, 4, Indexed_8 (0, [0, 5, 200], [0, 5, 200, 0, 200, 200, 5, 0]));
   Device_Table : aliased constant Bytes :=
     V2_Picture (0, 0, 2, 4, Indexed_8 (16#8000#, [99, 99, 99], [0, 1, 2, 0, 2, 2, 1, 0]));
   Undefined_Index : aliased constant Bytes :=
     V2_Picture (0, 0, 2, 4, Indexed_8 (0, [0, 5, 200], [0, 5, 7, 0, 200, 200, 5, 0]));
   Indexed_Raster : constant String := "RGUR/UUGR";

   --  A device table: 0 white, 1 red, 2 green, 3 blue.
   function Four_Colors return Bytes is
     (Table_Header (16#8000#, 4) & Table_Entry (0, 16#FFFF#, 16#FFFF#, 16#FFFF#)
      & Table_Entry (1, 16#FFFF#, 0, 0) & Table_Entry (2, 0, 16#FFFF#, 0) & Table_Entry (3, 0, 0, 16#FFFF#));
   Four_Bit : aliased constant Bytes :=
     V2_Picture (0, 0, 1, 4, W (16#98#) & W (16#8000# + 2) & Rect (0, 0, 1, 4) & Pixmap_Tail (0, 4, 1, 4)
                 & Four_Colors & Rect (0, 0, 1, 4) & Rect (0, 0, 1, 4) & W (0) & B (16#12#) & B (16#30#));
   Two_Bit : aliased constant Bytes :=
     V2_Picture (0, 0, 1, 8, W (16#98#) & W (16#8000# + 2) & Rect (0, 0, 1, 8) & Pixmap_Tail (0, 2, 1, 2)
                 & Four_Colors & Rect (0, 0, 1, 8) & Rect (0, 0, 1, 8) & W (0) & B (16#1B#) & B (16#E4#));
   --  rowBytes 8: a packed 8-bit row, eight pixels of index 1.
   Packed_Indexed : aliased constant Bytes :=
     V2_Picture (0, 0, 1, 8, W (16#98#) & W (16#8000# + 8) & Rect (0, 0, 1, 8) & Pixmap_Tail (0, 8, 1, 8)
                 & Four_Colors & Rect (0, 0, 1, 8) & Rect (0, 0, 1, 8) & W (0) & B (2) & B (16#F9#) & B (1)
                 & B (0));

   function Direct (Width, Row_Bytes, Pack, Depth, Components, Component_Size : Natural; Pixels : Bytes)
     return Bytes is
     (W (16#9A#) & L (16#FF#) & W (16#8000# + Row_Bytes) & Rect (0, 0, 1, Width)
      & Pixmap_Tail (Pack, Depth, Components, Component_Size)
      & Rect (0, 0, 1, Width) & Rect (0, 0, 1, Width) & W (0) & Pixels);
   --  16 bits, pack type 3: a literal of four words, red, green, blue, white.
   Sixteen_Literal : aliased constant Bytes :=
     V2_Picture (0, 0, 1, 4, Direct (4, 8, 3, 16, 3, 5,
                 B (9) & B (3) & W (16#7C00#) & W (16#03E0#) & W (16#001F#) & W (16#7FFF#)));
   Sixteen_Run : aliased constant Bytes :=
     V2_Picture (0, 0, 1, 4, Direct (4, 8, 3, 16, 3, 5, B (3) & B (16#FD#) & W (16#7C00#)));
   --  32 bits, planes R, G, B packed as one literal.
   Planar_3 : aliased constant Bytes :=
     V2_Picture (0, 0, 1, 2,
                 Direct (2, 8, 4, 32, 3, 8, B (7) & B (5) & [16#10#, 16#20#, 16#30#, 16#40#, 16#50#, 16#60#]));
   Planar_Default : aliased constant Bytes :=
     V2_Picture (0, 0, 1, 2,
                 Direct (2, 8, 0, 32, 3, 8, B (7) & B (5) & [16#10#, 16#20#, 16#30#, 16#40#, 16#50#, 16#60#]));
   --  Four components: the alpha plane comes first and is ignored.
   Planar_4 : aliased constant Bytes :=
     V2_Picture (0, 0, 1, 2, Direct (2, 8, 4, 32, 4, 8,
                 B (9) & B (7) & [16#00#, 16#FF#, 16#10#, 16#20#, 16#30#, 16#40#, 16#50#, 16#60#]));
   Chunky : aliased constant Bytes :=
     V2_Picture (0, 0, 1, 2, Direct (2, 8, 1, 32, 3, 8, [16#00#, 16#FF#, 0, 0, 16#00#, 0, 0, 16#FF#]));
   Triplets : aliased constant Bytes :=
     V2_Picture (0, 0, 1, 2, Direct (2, 8, 2, 32, 3, 8, [16#FF#, 0, 0, 0, 16#FF#, 0]));

   --  2x2 BitMap (01 / 10) stretched to 4x4.
   Upscaled : aliased constant Bytes :=
     V2_Picture (0, 0, 4, 4, Copy (16#98#, 2, Rect (0, 0, 2, 2), Rect (0, 0, 2, 2), Rect (0, 0, 4, 4))
                 & B (16#40#) & B (0) & B (16#80#) & B (0));
   --  1x4 BitMap 1010 squeezed to 1x2: columns 0 and 2.
   Downscaled : aliased constant Bytes :=
     V2_Picture (0, 0, 1, 2, Copy (16#98#, 2, Rect (0, 0, 1, 4), Rect (0, 0, 1, 4), Rect (0, 0, 1, 2))
                 & B (16#A0#) & B (0));
   --  4x1 BitMap black, white, white, black squeezed to 2x1: rows 0 and 2.
   Squeezed_Rows : aliased constant Bytes :=
     V2_Picture (0, 0, 2, 1, Copy (16#98#, 2, Rect (0, 0, 4, 1), Rect (0, 0, 4, 1), Rect (0, 0, 2, 1))
                 & B (16#80#) & B (0) & B (0) & B (0) & B (0) & B (0) & B (16#80#) & B (0));
   --  The frame starts at (20, 10); srcRect takes columns 2 .. 5 of 11110000 / 00001111.
   function Offset_Copy (Destination : Bytes) return Bytes is
     (Copy (16#98#, 2, Rect (0, 0, 2, 8), Rect (0, 2, 2, 6), Destination) & B (16#F0#) & B (0) & B (16#0F#) & B (0));
   Offset_Frame : aliased constant Bytes := V2_Picture (10, 20, 12, 24, Offset_Copy (Rect (10, 20, 12, 24)));
   Partly_Outside : aliased constant Bytes := V2_Picture (10, 20, 12, 24, Offset_Copy (Rect (11, 22, 13, 26)));

   Clipped : aliased constant Bytes := V2_Picture (0, 0, 2, 8, W (1) & Region (0, 0, 1, 8) & Bitmap_2x8);
   --  An L: rows 0 and 1 columns 0 .. 1, rows 2 and 3 columns 0 .. 3.
   L_Region : constant Bytes :=
     W (36) & Rect (0, 0, 4, 4) & W (0) & W (0) & W (2) & W (16#7FFF#) & W (2) & W (2) & W (4) & W (16#7FFF#)
     & W (4) & W (0) & W (4) & W (16#7FFF#) & W (16#7FFF#);
   Black_4x4 : constant Bytes := [16#F0#, 0, 16#F0#, 0, 16#F0#, 0, 16#F0#, 0];
   L_Raster : constant String := "BBWW/BBWW/BBBB/BBBB";
   Masked : aliased constant Bytes :=
     V2_Picture (0, 0, 4, 4, Copy (16#91#, 2, Rect (0, 0, 4, 4), Rect (0, 0, 4, 4), Rect (0, 0, 4, 4))
                 & L_Region & Black_4x4);
   Clipped_By_L : aliased constant Bytes :=
     V2_Picture (0, 0, 4, 4, W (1) & L_Region
                 & Copy (16#98#, 2, Rect (0, 0, 4, 4), Rect (0, 0, 4, 4), Rect (0, 0, 4, 4)) & Black_4x4);
   function Bad_Mask (Region_Bytes : Bytes) return Bytes is
     (V2_Picture (0, 0, 4, 4, Copy (16#91#, 2, Rect (0, 0, 4, 4), Rect (0, 0, 4, 4), Rect (0, 0, 4, 4))
                  & Region_Bytes & Black_4x4));
   Unsorted_Mask : aliased constant Bytes :=
     Bad_Mask (W (20) & Rect (0, 0, 4, 4) & W (0) & W (2) & W (0) & W (16#7FFF#) & W (16#7FFF#));
   Odd_Mask : aliased constant Bytes :=
     Bad_Mask (W (18) & Rect (0, 0, 4, 4) & W (0) & W (2) & W (16#7FFF#) & W (16#7FFF#));
   Unterminated_Mask : aliased constant Bytes :=
     Bad_Mask (W (20) & Rect (0, 0, 4, 4) & W (0) & W (0) & W (2) & W (16#7FFF#) & W (0));

   Short_Packed_Row : aliased constant Bytes :=
     V2_Picture (0, 0, 1, 64, Copy (16#98#, 8, Rect (0, 0, 1, 64), Rect (0, 0, 1, 64), Rect (0, 0, 1, 64))
                 & B (2) & B (16#FD#) & B (16#FF#) & B (0));
   Truncated_Pixels : aliased constant Bytes :=
     V2_Prefix (0, 0, 2, 8) & Copy (16#98#, 2, Rect (0, 0, 2, 8), Rect (0, 0, 2, 8), Rect (0, 0, 2, 8))
     & B (16#A5#) & B (0) & B (16#0F#);
   --  A QuickTime image in a codec other than JPEG.
   With_QuickTime : aliased constant Bytes :=
     V2_Picture (0, 0, 2, 8, QuickTime ("rle ", 2, 2, [1, 2, 3]) & Bitmap_2x8);
   Dither_Copy : aliased constant Bytes := V2_Picture (0, 0, 2, 8, Bitmap_2x8 (Mode => 16#40#));
   Default_Colors : aliased constant Bytes :=
     V2_Picture (0, 0, 2, 8, W (16#1A#) & W (0) & W (0) & W (0) & W (16#1B#) & W (16#FFFF#) & W (16#FFFF#)
                 & W (16#FFFF#) & W (16#0E#) & L (33) & W (16#0F#) & L (30) & W (16#0C#) & W (0) & W (0)
                 & Bitmap_2x8);
   Unknown_Planar : aliased constant Bytes := V2_Picture (0, 0, 2, 8, W (16#0E#) & L (1234) & Bitmap_2x8);
   Unknown_Mode : aliased constant Bytes := V2_Picture (0, 0, 2, 8, Bitmap_2x8 (Mode => 20));
   Wide_Source : aliased constant Bytes := V2_Picture (0, 0, 2, 8, Bitmap_2x8 (Source => Rect (0, 0, 2, 9)));
   Empty_Destination : aliased constant Bytes :=
     V2_Picture (0, 0, 2, 8, Copy (16#98#, 2, Rect (0, 0, 2, 8), Rect (0, 0, 2, 8), Rect (0, 0, 0, 8))
                 & B (16#A5#) & B (0) & B (16#0F#) & B (0));

   procedure Expect_Raster
     (Input : aliased Bytes;
      Width, Height : Positive;
      Expected : String;
      Label : String;
      Options : Decoding.Options := (others => <>);
      Max_Transfer : Pictlib.Byte_Count := Pictlib.Byte_Count'Last)
   is
      Storage : aliased Bytes := [1 .. 3 * Width * Height => 16#EE#];
      Output : constant Pictlib.Images.Mutable_Image_View := Canvases.View (Storage'Access, Width, Height);
      Decoder : Decoding.Decoder;
      Outcome : Pictlib.Results.Result;
   begin
      Canvases.Render (Input, Decoder, Output, Outcome, Options, Max_Transfer => Max_Transfer);
      Assert (Pictlib.Results.Succeeded (Outcome),
              Label & ": render failed with " & Outcome.First_Error.Code'Image & " at opcode"
              & Outcome.First_Error.Context.Op'Image);
      Assert (Decoding.State (Decoder) = Decoding.Finished, Label & ": the decoder did not finish");
      Assert (Canvases.Picture_Of (Output) = Expected,
              Label & ": rendered " & Canvases.Picture_Of (Output) & ", expected " & Expected);
   end Expect_Raster;

   procedure Expect_Render_Failure
     (Input : aliased Bytes;
      Width, Height : Positive;
      Code : Pictlib.Errors.Error_Code;
      Label : String;
      Op : Pictlib.Opcode := 0;
      Options : Decoding.Options := (others => <>);
      Budget : Pictlib.Limits.Limit_Set := Pictlib.Limits.Default_Limits;
      Limit : Pictlib.Limit_Kind := Pictlib.No_Limit)
   is
      Storage : aliased Bytes := [1 .. 3 * Width * Height => 0];
      Decoder : Decoding.Decoder;
      Outcome : Pictlib.Results.Result;
   begin
      Canvases.Render (Input, Decoder, Canvases.View (Storage'Access, Width, Height), Outcome, Options, Budget);
      Assert (Outcome.First_Error.Code = Code,
              Label & ": expected " & Code'Image & ", got " & Outcome.First_Error.Code'Image);
      if Op /= 0 then
         Assert (Outcome.First_Error.Context.Has_Opcode and then Outcome.First_Error.Context.Op = Op,
                 Label & ": the failing opcode was not recorded");
      end if;
      if Limit /= Pictlib.No_Limit then
         Assert (Outcome.First_Error.Context.Limit = Limit, Label & ": wrong limit");
      end if;
   end Expect_Render_Failure;

   --  Render leniently: success, Expected, and a warning with Code.
   procedure Expect_Lenient
     (Input : aliased Bytes;
      Width, Height : Positive;
      Expected : String;
      Code : Pictlib.Errors.Warning_Code;
      Label : String;
      Strictness : Pictlib.Strictness_Mode := Pictlib.Compatible)
   is
      Storage : aliased Bytes := [1 .. 3 * Width * Height => 0];
      Output : constant Pictlib.Images.Mutable_Image_View := Canvases.View (Storage'Access, Width, Height);
      Decoder : Decoding.Decoder;
      Outcome : Pictlib.Results.Result;
   begin
      Canvases.Render (Input, Decoder, Output, Outcome, (Strictness => Strictness, others => <>));
      Assert (Pictlib.Results.Succeeded (Outcome), Label & ": lenient render failed with "
              & Outcome.First_Error.Code'Image);
      Assert (Recorders.Has_Warning (Decoder, Code), Label & ": no " & Code'Image & " warning");
      Assert (Canvases.Picture_Of (Output) = Expected,
              Label & ": rendered " & Canvases.Picture_Of (Output) & ", expected " & Expected);
   end Expect_Lenient;

   procedure Bitmaps (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Indexed_Pixmaps (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Direct_Pixmaps (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Scaling_And_Placement (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Clip_And_Mask (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Output_Formats (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Malformed_Pixels (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Unsupported_Drawing (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Views_And_Limits (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Render_States (T : in out AUnit.Test_Cases.Test_Case'Class);

   overriding function Name (T : Test) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("rendering");
   end Name;

   overriding procedure Register_Tests (T : in out Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Bitmaps'Access, "rendering.bitmaps");
      Register_Routine (T, Indexed_Pixmaps'Access, "rendering.indexed_pixmaps");
      Register_Routine (T, Direct_Pixmaps'Access, "rendering.direct_pixmaps");
      Register_Routine (T, Scaling_And_Placement'Access, "rendering.scaling_and_placement");
      Register_Routine (T, Clip_And_Mask'Access, "rendering.clip_and_mask");
      Register_Routine (T, Output_Formats'Access, "rendering.output_formats");
      Register_Routine (T, Malformed_Pixels'Access, "rendering.malformed_pixels");
      Register_Routine (T, Unsupported_Drawing'Access, "rendering.unsupported_drawing");
      Register_Routine (T, Views_And_Limits'Access, "rendering.views_and_limits");
      Register_Routine (T, Render_States'Access, "rendering.states");
   end Register_Tests;

   procedure Bitmaps (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Expect_Raster (Unpacked_Bitmap, 8, 2, Bitmap_2x8_Raster, "unpacked BitMap");
      Expect_Raster (Packed_Bitmap, 64, 1, [1 .. 32 => 'W'] & [1 .. 32 => 'B'], "packed BitMap");
      Expect_Raster (Dither_Copy, 8, 2, Bitmap_2x8_Raster, "ditherCopy is srcCopy");
      Expect_Raster (Unpacked_Bitmap, 8, 2, Bitmap_2x8_Raster, "one-byte reads", Max_Transfer => 1);
   end Bitmaps;

   procedure Indexed_Pixmaps (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Expect_Raster (Sparse_Table, 4, 2, Indexed_Raster, "sparse color table");
      Expect_Raster (Device_Table, 4, 2, Indexed_Raster, "device color table");
      Expect_Raster (Four_Bit, 4, 1, "RGUW", "4-bit pixels");
      Expect_Raster (Two_Bit, 8, 1, "WRGUUGRW", "2-bit pixels");
      Expect_Raster (Packed_Indexed, 8, 1, "RRRRRRRR", "packed 8-bit row");
   end Indexed_Pixmaps;

   procedure Expect_Colors (Input : aliased Bytes; First, Second : Pictlib.Images.RGB_Color; Label : String) is
      Storage : aliased Bytes := [1 .. 6 => 16#EE#];
      Output : constant Pictlib.Images.Mutable_Image_View := Canvases.View (Storage'Access, 2, 1);
      Decoder : Decoding.Decoder;
      Outcome : Pictlib.Results.Result;
   begin
      Canvases.Render (Input, Decoder, Output, Outcome);
      Assert (Pictlib.Results.Succeeded (Outcome), Label & ": render failed with " & Outcome.First_Error.Code'Image);
      Assert (Canvases.Pixel (Output, 0, 0) = First and then Canvases.Pixel (Output, 1, 0) = Second,
              Label & ": wrong colors");
   end Expect_Colors;

   procedure Direct_Pixmaps (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Expect_Raster (Sixteen_Literal, 4, 1, "RGUW", "16-bit literal words");
      Expect_Raster (Sixteen_Run, 4, 1, "RRRR", "16-bit word run");
      Expect_Colors (Planar_3, (16#10#, 16#30#, 16#50#), (16#20#, 16#40#, 16#60#), "32-bit planar");
      Expect_Colors (Planar_Default, (16#10#, 16#30#, 16#50#), (16#20#, 16#40#, 16#60#), "32-bit default pack");
      Expect_Colors (Planar_4, (16#10#, 16#30#, 16#50#), (16#20#, 16#40#, 16#60#), "32-bit planar with alpha");
      Expect_Raster (Chunky, 2, 1, "RU", "32-bit unpacked");
      Expect_Raster (Triplets, 2, 1, "RG", "32-bit pad dropped");
   end Direct_Pixmaps;

   procedure Scaling_And_Placement (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Expect_Raster (Upscaled, 4, 4, "WWBB/WWBB/BBWW/BBWW", "2x upscale");
      Expect_Raster (Downscaled, 2, 1, "BB", "column downscale");
      Expect_Raster (Squeezed_Rows, 1, 2, "B/W", "row downscale");
      Expect_Raster (Offset_Frame, 4, 2, "BBWW/WWBB", "frame offset and srcRect");
      Expect_Raster (Partly_Outside, 4, 2, "WWWW/WWBB", "destination partly outside the frame");
      Expect_Raster (Empty_Destination, 8, 2, "WWWWWWWW/WWWWWWWW", "empty destination");
      Expect_Raster (Partly_Outside, 4, 2, "RRRR/RRBB", "background",
                     (Background => (16#FF#, 0, 0), others => <>));
   end Scaling_And_Placement;

   procedure Clip_And_Mask (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Expect_Raster (Clipped, 8, 2, "BWBWWBWB/WWWWWWWW", "rectangular clip");
      Expect_Raster (Masked, 4, 4, L_Raster, "BitsRgn mask");
      Expect_Raster (Clipped_By_L, 4, 4, L_Raster, "region clip");
      Expect_Raster (Masked, 4, 4, L_Raster, "BitsRgn mask, one-byte reads", Max_Transfer => 1);
      Expect_Render_Failure (Unsorted_Mask, 4, 4, Pictlib.Errors.Region_Invalid, "unsorted inversion points", 16#91#);
      Expect_Render_Failure (Odd_Mask, 4, 4, Pictlib.Errors.Region_Invalid, "odd inversion points", 16#91#);
      Expect_Render_Failure (Unterminated_Mask, 4, 4, Pictlib.Errors.Region_Invalid, "unterminated region", 16#91#);
   end Clip_And_Mask;

   procedure Output_Formats (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);

      --  The first pixel of Sparse_Table is red, the second green.
      procedure Check (Format : Pictlib.Pixel_Format; First_Two : Bytes) is
         Size : constant Natural := Natural (Pictlib.Images.Bytes_Per_Pixel (Format));
         Stride : constant Natural := 4 * Size + 3;
         Storage : aliased Bytes := [1 .. Stride + 4 * Size => 16#EE#];
         Decoder : Decoding.Decoder;
         Outcome : Pictlib.Results.Result;
      begin
         Canvases.Render (Sparse_Table, Decoder, Canvases.View (Storage'Access, 4, 2, Format, Stride), Outcome);
         Assert (Pictlib.Results.Succeeded (Outcome), Format'Image & ": render failed");
         Assert (Storage (1 .. 2 * Size) = First_Two, Format'Image & ": wrong bytes");
         Assert (Storage (4 * Size + 1 .. Stride) = [16#EE#, 16#EE#, 16#EE#], Format'Image & ": row padding written");
      end Check;
   begin
      Check (Pictlib.RGB_24, [16#FF#, 0, 0, 0, 16#FF#, 0]);
      Check (Pictlib.BGR_24, [0, 0, 16#FF#, 0, 16#FF#, 0]);
      Check (Pictlib.RGBA_32, [16#FF#, 0, 0, 16#FF#, 0, 16#FF#, 0, 16#FF#]);
      Check (Pictlib.BGRA_32, [0, 0, 16#FF#, 16#FF#, 0, 16#FF#, 0, 16#FF#]);
      Check (Pictlib.ARGB_32, [16#FF#, 16#FF#, 0, 0, 16#FF#, 0, 16#FF#, 0]);
   end Output_Formats;

   procedure Malformed_Pixels (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Storage : aliased Bytes := [1 .. 3 * 64 => 0];
      Decoder : Decoding.Decoder;
      Outcome : Pictlib.Results.Result;
   begin
      Canvases.Render (Short_Packed_Row, Decoder, Canvases.View (Storage'Access, 64, 1), Outcome);
      Assert (Outcome.First_Error.Code = Pictlib.Errors.PackBits_Invalid
              and then Outcome.First_Error.Context.Op = 16#98# and then Outcome.First_Error.Context.Row = 0
              and then Outcome.First_Error.Context.Expected = 8 and then Outcome.First_Error.Context.Actual = 4,
              "a short packed row was accepted");
      Expect_Lenient (Short_Packed_Row, 64, 1, [1 .. 32 => 'B'] & [1 .. 32 => 'W'], Pictlib.Errors.Recovery_Applied,
                      "short packed row");

      Expect_Render_Failure (Undefined_Index, 4, 2, Pictlib.Errors.Color_Table_Invalid, "undefined index", 16#98#);
      Expect_Lenient (Undefined_Index, 4, 2, "RGBR/UUGR", Pictlib.Errors.Recovery_Applied, "undefined index");

      Expect_Render_Failure (Wide_Source, 8, 2, Pictlib.Errors.Pixmap_Invalid, "srcRect outside bounds", 16#98#);
      Expect_Lenient (Wide_Source, 8, 2, Bitmap_2x8_Raster, Pictlib.Errors.Recovery_Applied, "srcRect clamped");

      Expect_Render_Failure (Truncated_Pixels, 8, 2, Pictlib.Errors.Source_Unexpected_End, "truncated pixels", 16#98#);
      Expect_Render_Failure (Truncated_Pixels, 8, 2, Pictlib.Errors.Source_Unexpected_End, "truncated pixels",
                             Options => (Strictness => Pictlib.Compatible, others => <>));
      Expect_Lenient (Truncated_Pixels, 8, 2, "BWBWWBWB/WWWWWWWW", Pictlib.Errors.Partial_Picture,
                      "truncated pixels", Pictlib.Recover_When_Safe);
   end Malformed_Pixels;

   procedure Unsupported_Drawing (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Expect_Render_Failure (With_QuickTime, 8, 2, Pictlib.Errors.Unsupported_Feature, "CompressedQuickTime", 16#8200#);
      Expect_Lenient (With_QuickTime, 8, 2, Bitmap_2x8_Raster, Pictlib.Errors.Approximated_Rendering,
                      "CompressedQuickTime");
      Expect_Render_Failure (Unknown_Planar, 8, 2, Pictlib.Errors.Unsupported_Feature, "unknown planar color", 16#0E#);
      Expect_Render_Failure (Unknown_Mode, 8, 2, Pictlib.Errors.Transfer_Mode_Invalid, "transfer mode 20", 16#98#);
      Expect_Lenient (Unknown_Mode, 8, 2, Bitmap_2x8_Raster, Pictlib.Errors.Recovery_Applied, "transfer mode 20");
      Expect_Raster (Default_Colors, 8, 2, Bitmap_2x8_Raster, "default colors and origin");
   end Unsupported_Drawing;

   procedure Views_And_Limits (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Defaults : constant Pictlib.Limits.Limit_Set := Pictlib.Limits.Default_Limits;
      Storage : aliased Bytes := [1 .. 48 => 0];
      Decoder : Decoding.Decoder;
      Outcome : Pictlib.Results.Result;
   begin
      Canvases.Render (Unpacked_Bitmap, Decoder, Canvases.View (Storage'Access, 8, 1), Outcome);
      Assert (Outcome.First_Error.Code = Pictlib.Errors.Invalid_Argument, "a view of the wrong size was accepted");
      Assert (Decoding.State (Decoder) = Decoding.Header_Read, "a rejected view changed the decoder state");
      Outcome := Decoding.Render (Decoder, Canvases.View (Storage'Access, 8, 2));
      Assert (Pictlib.Results.Succeeded (Outcome)
              and then Canvases.Picture_Of (Canvases.View (Storage'Access, 8, 2)) = Bitmap_2x8_Raster,
              "a good view after a rejected one did not render");

      Canvases.Render (Unpacked_Bitmap, Decoder, (Canvases.View (Storage'Access, 8, 2) with delta Storage => null),
                       Outcome);
      Assert (Outcome.First_Error.Code = Pictlib.Errors.Invalid_Argument, "a view without storage was accepted");

      Expect_Render_Failure (Unpacked_Bitmap, 8, 2, Pictlib.Errors.Limit_Exceeded, "canvas pixels",
                             Budget => (Defaults with delta Max_Canvas_Pixels => 15),
                             Limit => Pictlib.Canvas_Pixel_Limit);
      Expect_Render_Failure (Unpacked_Bitmap, 8, 2, Pictlib.Errors.Limit_Exceeded, "output bytes",
                             Budget => (Defaults with delta Max_Output_Bytes => 47),
                             Limit => Pictlib.Output_Byte_Limit);
      Expect_Render_Failure (Unpacked_Bitmap, 8, 2, Pictlib.Errors.Limit_Exceeded, "drawing work", 16#98#,
                             Budget => (Defaults with delta Max_Drawing_Work => 15),
                             Limit => Pictlib.Drawing_Work_Limit);
      Expect_Render_Failure (Packed_Bitmap, 64, 1, Pictlib.Errors.Limit_Exceeded, "row buffers", 16#98#,
                             Budget => (Defaults with delta Max_Allocation_Bytes => 100),
                             Limit => Pictlib.Allocation_Byte_Limit);
   end Views_And_Limits;

   procedure Render_States (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Storage : aliased Bytes := [1 .. 48 => 0];
      Output : constant Pictlib.Images.Mutable_Image_View := Canvases.View (Storage'Access, 8, 2);
      Decoder : Decoding.Decoder;
      Events : Recorders.Recorder;
      Outcome : Pictlib.Results.Result;
   begin
      Outcome := Decoding.Render (Decoder, Output);
      Assert (Outcome.First_Error.Code = Pictlib.Errors.Invalid_State, "an uninitialized decoder rendered");

      Recorders.Start (Unpacked_Bitmap, Decoder);
      Outcome := Decoding.Render (Decoder, Output);
      Assert (Outcome.First_Error.Code = Pictlib.Errors.Invalid_State
              and then Decoding.State (Decoder) = Decoding.Ready,
              "a decoder rendered before reading the header");

      Recorders.Decode (Unpacked_Bitmap, Decoder, Events, Outcome);
      Outcome := Decoding.Render (Decoder, Output);
      Assert (Outcome.First_Error.Code = Pictlib.Errors.Invalid_State, "an enumerated picture was rendered");

      Canvases.Render (Unpacked_Bitmap, Decoder, Output, Outcome);
      Assert (Pictlib.Results.Succeeded (Outcome), "the picture did not render");
      Outcome := Decoding.Render (Decoder, Output);
      Assert (Outcome.First_Error.Code = Pictlib.Errors.Invalid_State, "a picture was rendered twice");

      Recorders.Start (Unpacked_Bitmap, Decoder);
      Outcome := Decoding.Read_Header (Decoder);
      Assert (Pictlib.Results.Succeeded (Outcome), "the header was not read");
      Decoding.Cancel (Decoder);
      Outcome := Decoding.Render (Decoder, Output);
      Assert (Outcome.First_Error.Code = Pictlib.Errors.Operation_Cancelled, "a cancelled decoder rendered");

      Canvases.Render (With_QuickTime, Decoder, Output, Outcome);
      Assert (Decoding.State (Decoder) = Decoding.Failed
              and then Decoding.Last_Error (Decoder).Code = Pictlib.Errors.Unsupported_Feature,
              "an unsupported opcode did not fail the decoder");
   end Render_States;
end Pictlib_Testing.Test_Rendering;
