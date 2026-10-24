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

package body Pictlib_Testing.Test_Shapes is
   use AUnit.Assertions;
   use Pictlib_Testing.Builders;
   use type Pictlib.Images.RGB_Color;
   use type Pictlib.Streams.Byte_Array;

   package Errors renames Pictlib.Errors;

   --  Expected rasters follow the rules of the specification, section 3.2, worked out by hand.

   Red_Foreground : constant Bytes := RGB (16#1A#, 16#FFFF#, 0, 0);
   Black_Foreground : constant Bytes := RGB (16#1A#, 0, 0, 0);
   function Bitmap (Mode : Natural; Destination : Bytes := Rect (0, 0, 2, 8)) return Bytes is
     (Bitmap_2x8 (Mode, Destination => Destination));
   Red_Under : constant Bytes := Red_Foreground & Op_Rect (16#31#, 0, 0, 2, 8) & Black_Foreground;
   Black_Under : constant Bytes := Op_Rect (16#31#, 0, 0, 2, 8);

   --  A rectangle encoded as scanlines, so that framing takes the general erosion path.
   Scanline_Square : constant Bytes :=
     W (28) & Rect (0, 0, 6, 6) & W (0) & W (0) & W (6) & W (16#7FFF#) & W (6) & W (0) & W (6) & W (16#7FFF#)
     & W (16#7FFF#);
   L_Region : constant Bytes :=
     W (36) & Rect (0, 0, 4, 4) & W (0) & W (0) & W (2) & W (16#7FFF#) & W (2) & W (2) & W (4) & W (16#7FFF#)
     & W (4) & W (0) & W (4) & W (16#7FFF#) & W (16#7FFF#);
   Triangle : constant Bytes :=
     W (26) & Rect (0, 0, 4, 4) & W (0) & W (0) & W (0) & W (4) & W (4) & W (0) & W (0) & W (0);

   --  2x2 tile of 8-bit pixels: 0 1 / 1 0, device table 0 red, 1 blue.
   Color_Tile : constant Bytes :=
     W (16#14#) & W (1) & Zeros (8) & W (16#8000# + 2) & Rect (0, 0, 2, 2) & Pixmap_Tail (0, 8, 1, 8)
     & Table_Header (16#8000#, 2) & Table_Entry (0, 16#FFFF#, 0, 0) & Table_Entry (1, 0, 0, 16#FFFF#)
     & B (0) & B (1) & B (1) & B (0);

   Rect_Paint : aliased constant Bytes := Pic (6, 4, Op_Rect (16#31#, 1, 2, 3, 5));
   Rect_Frame : aliased constant Bytes := Pic (6, 4, Op_Rect (16#30#, 0, 0, 4, 6));
   Wide_Pen_Frame : aliased constant Bytes := Pic (6, 6, Pen_Size (1, 2) & Op_Rect (16#30#, 0, 0, 6, 6));
   Erase : aliased constant Bytes := Pic (6, 4, Op_Rect (16#31#, 0, 0, 4, 6) & Op_Rect (16#32#, 1, 1, 3, 5));
   Invert : aliased constant Bytes := Pic (6, 4, Op_Rect (16#33#, 0, 0, 2, 6) & Op_Rect (16#33#, 1, 0, 3, 6));
   Fill_Checker : aliased constant Bytes := Pic (4, 2, W (16#0A#) & Checker & Op_Rect (16#34#, 0, 0, 2, 4));
   Pattern_Xor : aliased constant Bytes :=
     Pic (4, 2, Op_Rect (16#31#, 0, 0, 2, 4) & Pen_Mode (10) & Op_Rect (16#31#, 0, 0, 1, 4));
   Pattern_Bic : aliased constant Bytes :=
     Pic (4, 2,
          Op_Rect (16#31#, 0, 0, 2, 4) & Pen_Mode (11) & W (16#09#) & Checker & Op_Rect (16#31#, 0, 0, 1, 4));
   Pattern_Or : aliased constant Bytes :=
     Pic (4, 2, Pen_Mode (9) & W (16#09#) & Checker & Op_Rect (16#31#, 0, 0, 1, 4));
   Not_Pattern : aliased constant Bytes :=
     Pic (4, 2, Pen_Mode (12) & W (16#09#) & Checker & Op_Rect (16#31#, 0, 0, 1, 4));
   --  Uniform patterns: a constant result, or none.
   Red_Field : constant Bytes := Red_Foreground & Op_Rect (16#31#, 0, 0, 2, 4) & Black_Foreground;
   Solid_Or : aliased constant Bytes := Pic (4, 2, Red_Field & Pen_Mode (9) & Op_Rect (16#31#, 0, 0, 1, 4));
   White_Or : aliased constant Bytes :=
     Pic (4, 2, Red_Field & Pen_Mode (9) & W (16#09#) & Zeros (8) & Op_Rect (16#31#, 0, 0, 1, 4));
   Solid_Bic : aliased constant Bytes := Pic (4, 2, Red_Field & Pen_Mode (11) & Op_Rect (16#31#, 0, 0, 1, 4));
   --  Transparent, red background: a bit pattern's 0 bits are the background, so they leave the black below;
   --  its 1 bits are the foreground, blue here.
   Transparent_Bits : aliased constant Bytes :=
     Pic (4, 2, Op_Rect (16#31#, 0, 0, 2, 4) & RGB (16#1B#, 16#FFFF#, 0, 0) & RGB (16#1A#, 0, 0, 16#FFFF#)
                & Pen_Mode (36) & W (16#09#) & [16#FF#, 0, 16#FF#, 0, 16#FF#, 0, 16#FF#, 0]
                & Op_Rect (16#31#, 0, 0, 2, 4));
   --  Transparent, red background, copying white and green 32-bit pixels: a copied pixel is itself, so both
   --  are drawn; only a red one would be left out.
   Transparent_Copy : aliased constant Bytes :=
     Pic (2, 1, Op_Rect (16#31#, 0, 0, 1, 2) & RGB (16#1B#, 16#FFFF#, 0, 0)
                & W (16#9A#) & L (16#FF#) & W (16#8000# + 8) & Rect (0, 0, 1, 2) & Pixmap_Tail (1, 32, 3, 8)
                & Rect (0, 0, 1, 2) & Rect (0, 0, 1, 2) & W (36)
                & [0, 16#FF#, 16#FF#, 16#FF#, 0, 0, 16#FF#, 0]);
   Source_Mode_As_Pen : aliased constant Bytes :=
     Pic (4, 2, Op_Rect (16#31#, 0, 0, 2, 4) & Pen_Mode (2) & Op_Rect (16#31#, 0, 0, 1, 4));

   Red_Paint : aliased constant Bytes := Pic (2, 1, Red_Foreground & Op_Rect (16#31#, 0, 0, 1, 2));
   Blue_Erase : aliased constant Bytes := Pic (2, 1, RGB (16#1B#, 0, 0, 16#FFFF#) & Op_Rect (16#32#, 0, 0, 1, 2));
   Planar_Blue : aliased constant Bytes := Pic (1, 1, W (16#0E#) & L (409) & Op_Rect (16#31#, 0, 0, 1, 1));

   Small_Oval : aliased constant Bytes := Pic (4, 4, Op_Rect (16#51#, 0, 0, 4, 4));
   Wide_Oval : aliased constant Bytes := Pic (6, 4, Op_Rect (16#51#, 0, 0, 4, 6));
   Framed_Oval : aliased constant Bytes := Pic (4, 4, Op_Rect (16#50#, 0, 0, 4, 4));
   Dot_Oval : aliased constant Bytes := Pic (1, 1, Op_Rect (16#51#, 0, 0, 1, 1));
   Round : aliased constant Bytes := Pic (8, 6, W (16#0B#) & W (4) & W (4) & Op_Rect (16#41#, 0, 0, 6, 8));
   Square_Round : aliased constant Bytes := Pic (3, 2, Op_Rect (16#41#, 0, 0, 2, 3));
   Framed_Round : aliased constant Bytes := Pic (8, 6, W (16#0B#) & W (4) & W (4) & Op_Rect (16#40#, 0, 0, 6, 8));

   function Arc (Start_Angle, Arc_Angle : Integer) return Bytes is
     (Pic (4, 4, Op_Rect (16#61#, 0, 0, 4, 4) & W (Start_Angle) & W (Arc_Angle)));
   Quadrant : aliased constant Bytes := Arc (0, 90);
   Lower_Half : aliased constant Bytes := Arc (90, 180);
   Backward : aliased constant Bytes := Arc (0, -90);
   Three_Quarters : aliased constant Bytes := Arc (0, 270);
   Whole_Arc : aliased constant Bytes := Arc (0, 360);
   No_Arc : aliased constant Bytes := Arc (45, 0);
   Framed_Quadrant : aliased constant Bytes := Pic (4, 4, Op_Rect (16#60#, 0, 0, 4, 4) & W (0) & W (90));
   Same_Arc : aliased constant Bytes :=
     Pic (4, 4, Op_Rect (16#61#, 0, 0, 4, 4) & W (0) & W (90) & W (16#69#) & W (90) & W (180));

   Painted_Triangle : aliased constant Bytes := Pic (4, 4, W (16#71#) & Triangle);
   Framed_Triangle : aliased constant Bytes := Pic (4, 4, W (16#70#) & Triangle);
   Undone_Triangle : aliased constant Bytes := Pic (4, 4, W (16#71#) & Triangle & W (16#7B#));

   Thick_Line : aliased constant Bytes := Pic (4, 4, Pen_Size (2, 2) & W (16#20#) & W (0) & W (0) & W (2) & W (2));
   Line_Then_From : aliased constant Bytes :=
     Pic (4, 4, W (16#20#) & W (0) & W (0) & W (0) & W (3) & W (16#21#) & W (3) & W (3));
   Short_Lines : aliased constant Bytes :=
     Pic (4, 4, W (16#22#) & W (1) & W (0) & B (3) & B (0) & W (16#23#) & B (0) & B (2));
   No_Pen : aliased constant Bytes :=
     Pic (4, 1, Pen_Size (0, 0) & W (16#20#) & W (0) & W (0) & W (0) & W (3) & Op_Rect (16#30#, 0, 0, 1, 4));

   Painted_L : aliased constant Bytes := Pic (4, 4, W (16#81#) & L_Region);
   Framed_Rect_Region : aliased constant Bytes := Pic (4, 4, W (16#80#) & Region (0, 0, 4, 4));
   Framed_Scanlines : aliased constant Bytes := Pic (6, 6, W (16#80#) & Scanline_Square);
   Undone_L : aliased constant Bytes := Pic (4, 4, W (16#81#) & L_Region & W (16#8B#));

   Undone_Rect : aliased constant Bytes := Pic (4, 2, Op_Rect (16#31#, 0, 0, 2, 2) & W (16#3B#));

   Moved_Rect : aliased constant Bytes := Pic (4, 2, W (16#0C#) & W (2) & W (1) & Op_Rect (16#31#, 1, 2, 3, 4));
   Moved_Copy : aliased constant Bytes := Pic (8, 2, W (16#0C#) & W (2) & W (1) & Bitmap (0, Rect (1, 2, 3, 10)));
   Moved_Clip : aliased constant Bytes :=
     Pic (4, 2, W (16#01#) & Region (0, 0, 2, 2) & W (16#0C#) & W (1) & W (0) & Op_Rect (16#31#, 0, 1, 2, 5));

   Dither_Fill : aliased constant Bytes :=
     Pic (2, 1, W (16#14#) & W (2) & Zeros (8) & W (16#FFFF#) & W (0) & W (0) & Op_Rect (16#34#, 0, 0, 1, 2));
   Tile_Fill : aliased constant Bytes := Pic (4, 2, Color_Tile & Op_Rect (16#34#, 0, 0, 2, 4));

   Copy_Or : aliased constant Bytes := Pic (8, 2, Red_Under & Bitmap (1));
   Copy_Colorized : aliased constant Bytes :=
     Pic (8, 2, Red_Foreground & RGB (16#1B#, 0, 0, 16#FFFF#) & Bitmap (0));
   Copy_Xor : aliased constant Bytes := Pic (8, 2, Black_Under & Bitmap (2));
   Copy_Bic : aliased constant Bytes := Pic (8, 2, Black_Under & Bitmap (3));
   Copy_Not : aliased constant Bytes := Pic (8, 2, Bitmap (4));
   Copy_Max : aliased constant Bytes := Pic (8, 2, Red_Under & Bitmap (37));
   Copy_Min : aliased constant Bytes := Pic (8, 2, Red_Under & Bitmap (39));
   Copy_Transparent : aliased constant Bytes := Pic (8, 2, Red_Under & Bitmap (36));
   Copy_Hilite : aliased constant Bytes := Pic (8, 2, RGB (16#1D#, 16#FFFF#, 0, 0) & Bitmap (50));
   Hilite_Next : aliased constant Bytes := Pic (8, 2, RGB (16#1D#, 16#FFFF#, 0, 0) & W (16#1C#) & Bitmap (0));
   Copy_Blend : aliased constant Bytes := Pic (8, 2, RGB (16#1F#, 16#8000#, 16#8000#, 16#8000#) & Bitmap (32));

   Overhanging : aliased constant Bytes := Pic (4, 2, Op_Rect (16#31#, -5, -5, 100, 100));
   Clipped : aliased constant Bytes :=
     Pic (4, 2, W (16#01#) & Region (0, 1, 2, 3) & Op_Rect (16#31#, -5, -5, 100, 100));

   Odd_Polygon : aliased constant Bytes := Pic (4, 4, W (16#71#) & W (11) & Rect (0, 0, 4, 4) & B (0));
   Bad_Pen_Mode : aliased constant Bytes := Pic (4, 4, Pen_Mode (20) & Op_Rect (16#31#, 0, 0, 1, 1));
   Bad_Pattern : aliased constant Bytes := Pic (4, 4, W (16#14#) & W (3) & Zeros (8));
   Reserved_Shape : aliased constant Bytes := Pic (4, 1, Op_Rect (16#35#, 0, 0, 1, 4));

   procedure Rectangles (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Patterns_And_Modes (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Colors (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Ovals_And_Round_Rects (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Arcs (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Polygons (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Lines (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Region_Shapes (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Origin (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Pixel_Patterns (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Copy_Modes (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Clipping_And_Limits (T : in out AUnit.Test_Cases.Test_Case'Class);

   overriding function Name (T : Test) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("shapes");
   end Name;

   overriding procedure Register_Tests (T : in out Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Rectangles'Access, "shapes.rectangles");
      Register_Routine (T, Patterns_And_Modes'Access, "shapes.patterns_and_modes");
      Register_Routine (T, Colors'Access, "shapes.colors");
      Register_Routine (T, Ovals_And_Round_Rects'Access, "shapes.ovals_and_round_rects");
      Register_Routine (T, Arcs'Access, "shapes.arcs");
      Register_Routine (T, Polygons'Access, "shapes.polygons");
      Register_Routine (T, Lines'Access, "shapes.lines");
      Register_Routine (T, Region_Shapes'Access, "shapes.regions");
      Register_Routine (T, Origin'Access, "shapes.origin");
      Register_Routine (T, Pixel_Patterns'Access, "shapes.pixel_patterns");
      Register_Routine (T, Copy_Modes'Access, "shapes.copy_modes");
      Register_Routine (T, Clipping_And_Limits'Access, "shapes.clipping_and_limits");
   end Register_Tests;

   procedure Rectangles (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Canvases.Expect_Raster (Rect_Paint, 6, 4, "WWWWWW/WWBBBW/WWBBBW/WWWWWW", "paintRect");
      Canvases.Expect_Raster (Rect_Frame, 6, 4, "BBBBBB/BWWWWB/BWWWWB/BBBBBB", "frameRect");
      Canvases.Expect_Raster (Wide_Pen_Frame, 6, 6, "BBBBBB/BBWWBB/BBWWBB/BBWWBB/BBWWBB/BBBBBB", "frameRect, pen 2x1");
      Canvases.Expect_Raster (Erase, 6, 4, "BBBBBB/BWWWWB/BWWWWB/BBBBBB", "eraseRect");
      Canvases.Expect_Raster (Invert, 6, 4, "BBBBBB/WWWWWW/BBBBBB/WWWWWW", "invertRect");
      Canvases.Expect_Raster (Undone_Rect, 4, 2, "WWWW/WWWW", "invertSameRect");
   end Rectangles;

   procedure Patterns_And_Modes (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Canvases.Expect_Raster (Fill_Checker, 4, 2, "BWBW/WBWB", "fillRect with FillPat");
      Canvases.Expect_Raster (Pattern_Xor, 4, 2, "WWWW/BBBB", "patXor");
      Canvases.Expect_Raster (Pattern_Bic, 4, 2, "WBWB/BBBB", "patBic");
      Canvases.Expect_Raster (Pattern_Or, 4, 2, "BWBW/WWWW", "patOr");
      Canvases.Expect_Raster (Not_Pattern, 4, 2, "WBWB/WWWW", "notPatCopy");
      Canvases.Expect_Raster (Source_Mode_As_Pen, 4, 2, "WWWW/BBBB", "srcXor as a pen mode");
      Canvases.Expect_Raster (Solid_Or, 4, 2, "BBBB/RRRR", "patOr, solid black");
      Canvases.Expect_Raster (White_Or, 4, 2, "RRRR/RRRR", "patOr, white");
      Canvases.Expect_Raster (Solid_Bic, 4, 2, "WWWW/RRRR", "patBic, solid black");
      Canvases.Expect_Raster (Transparent_Bits, 4, 2, "UUUU/BBBB", "transparent with a colored background");
      Canvases.Expect_Raster (Transparent_Copy, 2, 1, "WG", "a transparent copy is not colorized");
   end Patterns_And_Modes;

   procedure Expect_Color (Input : aliased Bytes; Width, Height : Positive; Color : Pictlib.Images.RGB_Color;
                           Label : String) is
      Storage : aliased Bytes := [1 .. 3 * Width * Height => 16#EE#];
      Output : constant Pictlib.Images.Mutable_Image_View := Canvases.View (Storage'Access, Width, Height);
      Decoder : Pictlib.Decoding.Decoder;
      Outcome : Pictlib.Results.Result;
   begin
      Canvases.Render (Input, Decoder, Output, Outcome);
      Assert (Pictlib.Results.Succeeded (Outcome), Label & ": render failed with " & Outcome.First_Error.Code'Image);
      Assert (Canvases.Pixel (Output, 0, 0) = Color, Label & ": wrong color");
   end Expect_Color;

   procedure Colors (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Canvases.Expect_Raster (Red_Paint, 2, 1, "RR", "RGBFgCol");
      Canvases.Expect_Raster (Blue_Erase, 2, 1, "UU", "RGBBkCol");
      Expect_Color (Planar_Blue, 1, 1, (0, 0, 16#D4#), "FgColor blueColor");
   end Colors;

   procedure Ovals_And_Round_Rects (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Canvases.Expect_Raster (Small_Oval, 4, 4, "WBBW/BBBB/BBBB/WBBW", "paintOval 4x4");
      Canvases.Expect_Raster (Wide_Oval, 6, 4, "WBBBBW/BBBBBB/BBBBBB/WBBBBW", "paintOval 6x4");
      Canvases.Expect_Raster (Framed_Oval, 4, 4, "WBBW/BWWB/BWWB/WBBW", "frameOval");
      Canvases.Expect_Raster (Dot_Oval, 1, 1, "B", "1x1 oval");
      Canvases.Expect_Raster
        (Round, 8, 6, "WBBBBBBW/BBBBBBBB/BBBBBBBB/BBBBBBBB/BBBBBBBB/WBBBBBBW", "paintRoundRect");
      Canvases.Expect_Raster (Square_Round, 3, 2, "BBB/BBB", "round rect without oval size");
      Canvases.Expect_Raster
        (Framed_Round, 8, 6, "WBBBBBBW/BWWWWWWB/BWWWWWWB/BWWWWWWB/BWWWWWWB/WBBBBBBW", "frameRoundRect");
   end Ovals_And_Round_Rects;

   procedure Arcs (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Canvases.Expect_Raster (Quadrant, 4, 4, "WWBW/WWBB/WWWW/WWWW", "arc 0, 90");
      Canvases.Expect_Raster (Lower_Half, 4, 4, "WWWW/WWWW/BBBB/WBBW", "arc 90, 180");
      Canvases.Expect_Raster (Backward, 4, 4, "WBWW/BBWW/WWWW/WWWW", "arc 0, -90");
      Canvases.Expect_Raster (Three_Quarters, 4, 4, "WWBW/WWBB/BBBB/WBBW", "arc 0, 270");
      Canvases.Expect_Raster (Whole_Arc, 4, 4, "WBBW/BBBB/BBBB/WBBW", "arc 0, 360");
      Canvases.Expect_Raster (No_Arc, 4, 4, "WWWW/WWWW/WWWW/WWWW", "arc of 0 degrees");
      Canvases.Expect_Raster (Same_Arc, 4, 4, "WWBW/WWBB/BBBB/WBBW", "paintSameArc");
      Canvases.Expect_Raster (Framed_Quadrant, 4, 4, "WWBW/WWWB/WWWW/WWWW", "frameArc");
   end Arcs;

   procedure Polygons (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Canvases.Expect_Raster (Painted_Triangle, 4, 4, "BBBW/BBWW/BWWW/WWWW", "paintPoly");
      Canvases.Expect_Raster (Framed_Triangle, 4, 4, "BBBB/BWWB/BWBW/BBWW", "framePoly");
      Canvases.Expect_Raster (Undone_Triangle, 4, 4, "WWWW/WWWW/WWWW/WWWW", "invertSamePoly");
   end Polygons;

   procedure Lines (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Canvases.Expect_Raster (Thick_Line, 4, 4, "BBWW/BBBW/WBBB/WWBB", "line with a 2x2 pen");
      Canvases.Expect_Raster (Line_Then_From, 4, 4, "BBBB/WWWB/WWWB/WWWB", "Line then LineFrom");
      Canvases.Expect_Raster (Short_Lines, 4, 4, "WWWW/BBBB/WWWB/WWWB", "ShortLine then ShortLineFrom");
      Canvases.Expect_Raster (No_Pen, 4, 1, "WWWW", "a zero pen draws no lines or frames");
   end Lines;

   procedure Region_Shapes (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Canvases.Expect_Raster (Painted_L, 4, 4, "BBWW/BBWW/BBBB/BBBB", "paintRgn");
      Canvases.Expect_Raster (Framed_Rect_Region, 4, 4, "BBBB/BWWB/BWWB/BBBB", "frameRgn, rectangular");
      Canvases.Expect_Raster
        (Framed_Scanlines, 6, 6, "BBBBBB/BWWWWB/BWWWWB/BWWWWB/BWWWWB/BBBBBB", "frameRgn, scanlines");
      Canvases.Expect_Raster (Undone_L, 4, 4, "WWWW/WWWW/WWWW/WWWW", "invertSameRgn");
   end Region_Shapes;

   procedure Origin (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Canvases.Expect_Raster (Moved_Rect, 4, 2, "BBWW/BBWW", "Origin moves shapes");
      Canvases.Expect_Raster (Moved_Copy, 8, 2, "BWBWWBWB/WWWWBBBB", "Origin moves copies");
      Canvases.Expect_Raster (Moved_Clip, 4, 2, "BWWW/BWWW", "the clip keeps its local coordinates");
   end Origin;

   procedure Pixel_Patterns (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Canvases.Expect_Raster (Dither_Fill, 2, 1, "RR", "dither pattern");
      Canvases.Expect_Raster (Tile_Fill, 4, 2, "RURU/URUR", "color pattern");
   end Pixel_Patterns;

   procedure Copy_Modes (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Canvases.Expect_Raster (Copy_Or, 8, 2, "BRBRRBRB/RRRRBBBB", "srcOr");
      Canvases.Expect_Raster (Copy_Colorized, 8, 2, "RURUURUR/UUUURRRR", "colorized srcCopy");
      Canvases.Expect_Raster (Copy_Xor, 8, 2, "WBWBBWBW/BBBBWWWW", "srcXor");
      Canvases.Expect_Raster (Copy_Bic, 8, 2, "WBWBBWBW/BBBBWWWW", "srcBic");
      Canvases.Expect_Raster (Copy_Not, 8, 2, "WBWBBWBW/BBBBWWWW", "notSrcCopy");
      Canvases.Expect_Raster (Copy_Max, 8, 2, "RWRWWRWR/WWWWRRRR", "addMax");
      Canvases.Expect_Raster (Copy_Min, 8, 2, "BRBRRBRB/RRRRBBBB", "adMin");
      Canvases.Expect_Raster (Copy_Transparent, 8, 2, "BRBRRBRB/RRRRBBBB", "transparent");
      Canvases.Expect_Raster (Copy_Hilite, 8, 2, "RWRWWRWR/WWWWRRRR", "hilite");
      Canvases.Expect_Raster (Hilite_Next, 8, 2, "RWRWWRWR/WWWWRRRR", "HiliteMode");
      Expect_Color (Copy_Blend, 8, 2, (127, 127, 127), "blend at half weight");
   end Copy_Modes;

   procedure Clipping_And_Limits (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Canvases.Expect_Raster (Overhanging, 4, 2, "BBBB/BBBB", "a rect larger than the canvas");
      Canvases.Expect_Raster (Clipped, 4, 2, "WBBW/WBBW", "a clipped rect");
      Canvases.Expect_Raster (Reserved_Shape, 4, 1, "WWWW", "reserved shape opcodes draw nothing");
      Canvases.Expect_Failure (Rect_Paint, 6, 4, Errors.Limit_Exceeded, "drawing work", 16#31#,
                               Budget => (Pictlib.Limits.Default_Limits with delta Max_Drawing_Work => 5));
      Canvases.Expect_Failure (Odd_Polygon, 4, 4, Errors.Polygon_Invalid, "odd polygon", 16#71#);
      Canvases.Expect_Failure (Bad_Pen_Mode, 4, 4, Errors.Transfer_Mode_Invalid, "pen mode 20", 16#08#);
      Canvases.Expect_Raster (Bad_Pen_Mode, 4, 4, "BWWW/WWWW/WWWW/WWWW", "pen mode 20, lenient",
                              (Strictness => Pictlib.Compatible, others => <>));
      Canvases.Expect_Failure (Bad_Pattern, 4, 4, Errors.Pattern_Invalid, "pattern type 3", 16#14#);
   end Clipping_And_Limits;
end Pictlib_Testing.Test_Shapes;
