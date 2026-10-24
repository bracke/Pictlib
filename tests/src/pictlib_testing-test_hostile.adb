with Ada.Real_Time;
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

--  Pictures built to make the renderer overflow, allocate or work without bound; each must end quickly with a
--  result, never an exception.
package body Pictlib_Testing.Test_Hostile is
   use AUnit.Assertions;
   use Pictlib_Testing.Builders;
   use type Ada.Real_Time.Time;
   use type Ada.Real_Time.Time_Span;
   use type Pictlib.Streams.Byte_Array;
   use type Pictlib.Errors.Error_Code;
   use type Pictlib.Images.RGB_Color;
   use type Pictlib.Limit_Kind;
   use type Pictlib.Opcode;

   package Errors renames Pictlib.Errors;

   --  Every case here finishes in a fraction of this on any machine the suite runs on.
   Slow : constant Ada.Real_Time.Time_Span := Ada.Real_Time.Seconds (2);

   function Pic (Width, Height : Natural; Body_Bytes : Bytes) return Bytes is
     (V2_Picture (0, 0, Height, Width, Body_Bytes));
   function Op_Rect (Op, Top, Left, Bottom, Right : Integer) return Bytes is (W (Op) & Rect (Top, Left, Bottom, Right));
   function Origin (Dh, Dv : Integer) return Bytes is (W (16#0C#) & W (Dh) & W (Dv));

   function Repeat (Item : Bytes; Count : Natural) return Bytes is
      Result : Bytes (1 .. Item'Length * Count);
   begin
      for Index in 0 .. Count - 1 loop
         Result (Result'First + Index * Item'Length .. Result'First + (Index + 1) * Item'Length - 1) := Item;
      end loop;
      return Result;
   end Repeat;

   Compatible : constant Pictlib.Decoding.Options := (Strictness => Pictlib.Compatible, others => <>);

   procedure Check_Time (Started : Ada.Real_Time.Time; Label : String) is
   begin
      Assert (Ada.Real_Time.Clock - Started < Slow, Label & ": took too long");
   end Check_Time;

   procedure Coordinates (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Pen_Steps (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Pixel_Layouts (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Shape_Work (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Pixel_Work (T : in out AUnit.Test_Cases.Test_Case'Class);

   overriding function Name (T : Test) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("hostile");
   end Name;

   overriding procedure Register_Tests (T : in out Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Coordinates'Access, "hostile.coordinates");
      Register_Routine (T, Pen_Steps'Access, "hostile.pen_steps");
      Register_Routine (T, Pixel_Layouts'Access, "hostile.pixel_layouts");
      Register_Routine (T, Shape_Work'Access, "hostile.shape_work");
      Register_Routine (T, Pixel_Work'Access, "hostile.pixel_work");
   end Register_Tests;

   --  Extreme and accumulated coordinates.
   procedure Coordinates (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  The longest line a picture can hold, corner to corner, through the frame's diagonal.
      Extreme_Line : aliased constant Bytes := Pic (4, 4, W (16#20#) & W (-32_768) & W (-32_768) & W (32_767)
                                                    & W (32_767));
      Runaway_Origin : aliased constant Bytes := Pic (4, 4, Repeat (Origin (32_767, 32_767), 600));
      --  70,000 DHText steps of 255 move the text origin past any picture.
      Runaway_Text : aliased constant Bytes := Pic (4, 4, Repeat (W (16#29#) & B (255) & B (0), 70_000));
      Started : constant Ada.Real_Time.Time := Ada.Real_Time.Clock;
   begin
      Canvases.Expect_Raster (Extreme_Line, 4, 4, "BWWW/WBWW/WWBW/WWWB", "line from -32768 to 32767");
      Canvases.Expect_Failure (Runaway_Origin, 4, 4, Errors.Opcode_Invalid, "origin moved 600 times", 16#0C#);
      Canvases.Expect_Failure (Runaway_Text, 4, 4, Errors.Opcode_Invalid, "text origin moved 70,000 times", 16#29#,
                               Compatible);
      Check_Time (Started, "coordinates");
   end Coordinates;

   procedure Pen_Steps (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  140,000 short lines of 127 move the pen beyond the frame; each line costs its opcode, nothing more.
      Runaway_Pen : aliased constant Bytes := Pic (4, 4, Repeat (W (16#23#) & B (127) & B (0), 140_000));
      Started : constant Ada.Real_Time.Time := Ada.Real_Time.Clock;
   begin
      Canvases.Expect_Failure (Runaway_Pen, 4, 4, Errors.Opcode_Invalid, "pen moved 140,000 times", 16#23#);
      Assert (Ada.Real_Time.Clock - Started < 3 * Slow, "pen steps: took too long");
   end Pen_Steps;

   --  Pixel layouts that enumeration and rendering must read alike.
   procedure Pixel_Layouts (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  A planar 32-bit row whose cmpCount 16#FFFF# would make the planes wider than any buffer.
      Planar_Count : aliased constant Bytes :=
        Pic (4, 1, W (16#9A#) & L (16#FF#) & W (16#8000# + 16) & Rect (0, 0, 1, 4)
                   & Pixmap_Tail (4, 32, 16#FFFF#, 8) & Rect (0, 0, 1, 4) & Rect (0, 0, 1, 4) & W (0));
      --  A PixPat with packType 1: rowBytes 8, yet unpacked, red and blue in columns.
      Unpacked_Tile : aliased constant Bytes :=
        Pic (8, 2, W (16#14#) & W (1) & Zeros (8) & W (16#8000# + 8) & Rect (0, 0, 2, 8)
                   & Pixmap_Tail (1, 8, 1, 8) & Table_Header (16#8000#, 2) & Table_Entry (0, 16#FFFF#, 0, 0)
                   & Table_Entry (1, 0, 0, 16#FFFF#) & Repeat (B (0) & B (1), 8) & Op_Rect (16#34#, 0, 0, 2, 8));
      Decoder : Pictlib.Decoding.Decoder;
      Events : Recorders.Recorder;
      Outcome : Pictlib.Results.Result;
   begin
      Recorders.Decode (Planar_Count, Decoder, Events, Outcome);
      Assert (Outcome.First_Error.Code = Errors.Pixmap_Invalid,
              "cmpCount 16#FFFF# enumerated with " & Outcome.First_Error.Code'Image);
      Canvases.Expect_Failure (Planar_Count, 4, 1, Errors.Pixmap_Invalid, "cmpCount 16#FFFF#", 16#9A#);

      Recorders.Decode (Unpacked_Tile, Decoder, Events, Outcome);
      Assert (Pictlib.Results.Succeeded (Outcome), "packType 1 PixPat enumerated with "
              & Outcome.First_Error.Code'Image);
      Assert (Events.Count > 0 and then Events.Events (Events.Count).Op = 16#FF#,
              "packType 1 PixPat: enumeration lost the opcode stream");
      Canvases.Expect_Raster (Unpacked_Tile, 8, 2, "RURURURU/RURURURU", "packType 1 PixPat");
   end Pixel_Layouts;

   --  Shapes whose coverage costs more than they draw.
   procedure Shape_Work (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Points : constant := 8_000;

      function Zig_Zag return Bytes is
         Result : Bytes (1 .. 4 * Points);
      begin
         for K in 0 .. Points - 1 loop
            Result (Result'First + 4 * K .. Result'First + 4 * K + 3) :=
              W (if K mod 2 = 0 then 0 else 199) & W (K mod 200);
         end loop;
         return Result;
      end Zig_Zag;

      --  4,000 region lines, every other row inside.
      function Striped_Region return Bytes is
         Result : Bytes (1 .. 8 * 4_000);
      begin
         for K in 0 .. 3_999 loop
            Result (Result'First + 8 * K .. Result'First + 8 * K + 7) := W (K) & W (0) & W (4) & W (16#7FFF#);
         end loop;
         return W (10 + Result'Length + 2) & Rect (0, 0, 4_000, 4) & Result & W (16#7FFF#);
      end Striped_Region;

      Polygon : aliased constant Bytes :=
        Pic (200, 200, W (16#71#) & W (10 + 4 * Points) & Rect (0, 0, 200, 200) & Zig_Zag);
      Moving_Clip : aliased constant Bytes :=
        Pic (4, 4, W (16#01#) & Striped_Region & Repeat (Origin (1, 1) & Origin (-1, -1), 20_000)
                   & Op_Rect (16#31#, 0, 0, 4, 4));
      Small : Pictlib.Limits.Limit_Set := Pictlib.Limits.Default_Limits;
      Storage : aliased Bytes := [1 .. 3 * 200 * 200 => 0];
      Decoder : Pictlib.Decoding.Decoder;
      Outcome : Pictlib.Results.Result;
      Started : constant Ada.Real_Time.Time := Ada.Real_Time.Clock;
   begin
      Canvases.Render (Polygon, Decoder, Canvases.View (Storage'Access, 200, 200), Outcome);
      Assert (Pictlib.Results.Succeeded (Outcome), "zig-zag polygon failed with " & Outcome.First_Error.Code'Image);
      Small.Max_Drawing_Work := 50_000;
      Canvases.Expect_Failure (Polygon, 200, 200, Errors.Limit_Exceeded, "zig-zag polygon over budget", 16#71#,
                               Budget => Small);
      Canvases.Render (Polygon, Decoder, Canvases.View (Storage'Access, 200, 200), Outcome, Budget => Small);
      Assert (Outcome.First_Error.Context.Limit = Pictlib.Drawing_Work_Limit, "zig-zag polygon: wrong limit");
      Canvases.Expect_Raster (Moving_Clip, 4, 4, "BBBB/WWWW/BBBB/WWWW", "clip kept while the origin moves");
      Check_Time (Started, "shape work");
   end Shape_Work;

   --  Pixel data that costs work without drawing anything.
   procedure Pixel_Work (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  1,000 BitMap rows that each claim zero packed bytes.
      Empty_Rows : aliased constant Bytes :=
        Pic (64, 1_000, W (16#98#) & W (8) & Rect (0, 0, 1_000, 64) & Rect (0, 0, 1_000, 64)
                        & Rect (0, 0, 1_000, 64) & W (0) & Zeros (1_000));
      Storage : aliased Bytes := [1 .. 3 * 64 * 1_000 => 0];
      Decoder : Pictlib.Decoding.Decoder;
      Outcome : Pictlib.Results.Result;
      Small : Pictlib.Limits.Limit_Set := Pictlib.Limits.Default_Limits;
      Wide : aliased constant Bytes :=
        Pic (16, 1, W (16#98#) & W (2) & Rect (0, 0, 1, 16) & Rect (0, 0, 1, 16) & Rect (0, 0, 1, 16) & W (0)
                    & Zeros (2));
      Started : constant Ada.Real_Time.Time := Ada.Real_Time.Clock;
   begin
      Canvases.Expect_Failure (Empty_Rows, 64, 1_000, Errors.PackBits_Invalid, "empty packed rows", 16#98#,
                               Compatible);
      Canvases.Render (Empty_Rows, Decoder, Canvases.View (Storage'Access, 64, 1_000), Outcome,
                       (Strictness => Pictlib.Recover_When_Safe, others => <>));
      Assert (Pictlib.Results.Succeeded (Outcome) and then Recorders.Has_Warning (Decoder, Errors.Partial_Picture),
              "empty packed rows did not end the picture early");
      Assert (Canvases.Pixel (Canvases.View (Storage'Access, 64, 1_000), 0, 999) = (16#FF#, 16#FF#, 16#FF#),
              "empty packed rows drew something");
      --  Rows are charged as they are converted, drawn or not.
      Small.Max_Drawing_Work := 10;
      Canvases.Expect_Failure (Wide, 16, 1, Errors.Limit_Exceeded, "row conversion over budget", 16#98#,
                               Budget => Small);
      Check_Time (Started, "pixel work");
   end Pixel_Work;
end Pictlib_Testing.Test_Hostile;
