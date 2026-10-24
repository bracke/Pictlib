with AUnit.Assertions;

with Pictlib;
with Pictlib.Decoding;
with Pictlib.Errors;
with Pictlib.Images;
with Pictlib.Internal.Coverage;
with Pictlib.Limits;
with Pictlib.Results;
with Pictlib.Streams;
with Pictlib_Testing.Builders;
with Pictlib_Testing.Canvases;
with Pictlib_Testing.Recorders;

--  Pictures built to make the renderer overflow, allocate or work without bound; each must end with a result
--  within its budgets, never an exception. What they cost is asserted through the budgets, not the clock.
package body Pictlib_Testing.Test_Hostile is
   use AUnit.Assertions;
   use Pictlib_Testing.Builders;
   use type Pictlib.Streams.Byte_Array;
   use type Pictlib.Byte_Count;
   use type Pictlib.Errors.Error_Code;
   use type Pictlib.Errors.Warning_Code;
   use type Pictlib.Images.RGB_Color;
   use type Pictlib.Limit_Kind;
   use type Pictlib.Opcode;

   package Errors renames Pictlib.Errors;

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
      --  511 steps of -32768 put the origin at its bound; any 16-bit point is still within reach after it.
      Origin_At_Bound : aliased constant Bytes :=
        Pic (4, 4, Repeat (Origin (-32_768, 0), 511) & W (16#20#) & W (0) & W (-32_768) & W (0) & W (32_767));
      Origin_Past_Bound : aliased constant Bytes := Pic (4, 4, Repeat (Origin (-32_768, 0), 512));
   begin
      Canvases.Expect_Raster (Origin_At_Bound, 4, 4, "WWWW/WWWW/WWWW/WWWW", "a line after the origin at its bound");
      Canvases.Expect_Failure (Origin_Past_Bound, 4, 4, Errors.Opcode_Invalid, "origin past its bound", 16#0C#);
      Canvases.Expect_Raster (Extreme_Line, 4, 4, "BWWW/WBWW/WWBW/WWWB", "line from -32768 to 32767");
      Canvases.Expect_Failure (Runaway_Origin, 4, 4, Errors.Opcode_Invalid, "origin moved 600 times", 16#0C#);
      Canvases.Expect_Failure (Runaway_Text, 4, 4, Errors.Opcode_Invalid, "text origin moved 70,000 times", 16#29#,
                               Compatible);
   end Coordinates;

   procedure Pen_Steps (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  140,000 short lines of 127 move the pen beyond the frame; each line costs its opcode, nothing more.
      Runaway_Pen : aliased constant Bytes := Pic (4, 4, Repeat (W (16#23#) & B (127) & B (0), 140_000));
   begin
      Canvases.Expect_Failure (Runaway_Pen, 4, 4, Errors.Opcode_Invalid, "pen moved 140,000 times", 16#23#);
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
      --  A PixPat deeper than 8 bits, and one with empty bounds: rendering rejects both, so enumeration does.
      Deep_Tile : aliased constant Bytes :=
        Pic (8, 2, W (16#14#) & W (1) & Zeros (8) & W (16#8000# + 32) & Rect (0, 0, 2, 8)
                   & Pixmap_Tail (4, 32, 3, 8) & Table_Header (16#8000#, 1) & Table_Entry (0, 0, 0, 0)
                   & B (0) & B (0) & Op_Rect (16#34#, 0, 0, 2, 8));
      Empty_Tile : aliased constant Bytes :=
        Pic (8, 2, W (16#14#) & W (1) & Zeros (8) & W (16#8000# + 8) & Rect (0, 0, 0, 8)
                   & Pixmap_Tail (0, 8, 1, 8) & Table_Header (16#8000#, 1) & Table_Entry (0, 0, 0, 0)
                   & Op_Rect (16#34#, 0, 0, 2, 8));
      --  A PixPat cut off right after its type.
      Cut_Tile : aliased constant Bytes := V2_Prefix (0, 0, 2, 8) & W (16#14#) & W (1) & Zeros (8);
      --  A 20000 x 20000 PixPat, its tile over the allocation budget: rejected before any row is read.
      Huge_Tile : aliased constant Bytes :=
        V2_Prefix (0, 0, 2, 8) & W (16#14#) & W (1) & Zeros (8) & W (16#8000# + 2_500) & Rect (0, 0, 20_000, 20_000)
        & Pixmap_Tail (0, 1, 1, 1) & Table_Header (16#8000#, 2) & Table_Entry (0, 0, 0, 0)
        & Table_Entry (1, 0, 0, 0) & B (0);
      --  A 200 x 200 tile: 120,000 bytes, and 881 for its row buffers (255 stored, 26 unpacked, 600 colors), all
      --  one opcode's allocation.
      --  Every row is one run of 26 zero bytes.
      Grown_Tile : aliased constant Bytes :=
        Pic (8, 2, W (16#14#) & W (1) & Zeros (8) & W (16#8000# + 26) & Rect (0, 0, 200, 200)
                   & Pixmap_Tail (0, 1, 1, 1) & Table_Header (16#8000#, 2) & Table_Entry (0, 0, 0, 0)
                   & Table_Entry (1, 0, 0, 0) & Repeat (B (2) & B (16#E7#) & B (0), 200));
      --  An 18000 x 18000 PixPat that ends at once. Under budgets too small both to allocate and to decode it,
      --  the drawing limit is reported: decoding is checked first, before anything is set aside.
      Unaffordable_Tile : aliased constant Bytes :=
        V2_Prefix (0, 0, 2, 8) & W (16#14#) & W (1) & Zeros (8) & W (16#8000# + 2_250) & Rect (0, 0, 18_000, 18_000)
        & Pixmap_Tail (0, 1, 1, 1) & Table_Header (16#8000#, 2) & Table_Entry (0, 0, 0, 0)
        & Table_Entry (1, 0, 0, 0) & B (0);
      --  A 65535 x 65535 PixPat has more pixels than a tile can index.
      Unindexable_Tile : aliased constant Bytes :=
        V2_Prefix (0, 0, 2, 8) & W (16#14#) & W (1) & Zeros (8) & W (16#8000# + 8_192)
        & Rect (-32_768, -32_768, 32_767, 32_767) & Pixmap_Tail (0, 1, 1, 1) & Table_Header (16#8000#, 2)
        & Table_Entry (0, 0, 0, 0) & Table_Entry (1, 0, 0, 0) & B (0);
      --  An 8 x 20 tile, 9 units of decoding per row, under 100 units of drawing work.
      Costly_Tile : aliased constant Bytes :=
        Pic (8, 2, W (16#14#) & W (1) & Zeros (8) & W (16#8000# + 2) & Rect (0, 0, 20, 8)
                   & Pixmap_Tail (0, 1, 1, 1) & Table_Header (16#8000#, 2) & Table_Entry (0, 0, 0, 0)
                   & Table_Entry (1, 0, 0, 0) & Zeros (40) & Op_Rect (16#34#, 0, 0, 2, 8));
      Tight : Pictlib.Limits.Limit_Set := Pictlib.Limits.Default_Limits;
      Decoder : Pictlib.Decoding.Decoder;
      Events : Recorders.Recorder;
      Outcome : Pictlib.Results.Result;
      Storage : aliased Bytes := [1 .. 3 * 16 => 0];

      procedure Over (Input : aliased Bytes; Budget : Pictlib.Limits.Limit_Set; Limit : Pictlib.Limit_Kind;
                      Label : String) is
      begin
         Canvases.Render (Input, Decoder, Canvases.View (Storage'Access, 8, 2), Outcome, Budget => Budget);
         Assert (Outcome.First_Error.Code = Errors.Limit_Exceeded
                 and then Outcome.First_Error.Context.Limit = Limit
                 and then Outcome.First_Error.Context.Op = 16#14#,
                 Label & ": rendered with " & Outcome.First_Error.Code'Image & " "
                 & Outcome.First_Error.Context.Limit'Image);
      end Over;

      procedure Both (Input : aliased Bytes; Code : Errors.Error_Code; Label : String) is
      begin
         Recorders.Decode (Input, Decoder, Events, Outcome);
         Assert (Outcome.First_Error.Code = Code, Label & ": enumerated with " & Outcome.First_Error.Code'Image);
         Canvases.Expect_Failure (Input, 8, 2, Code, Label, 16#14#);
      end Both;
   begin
      Both (Deep_Tile, Errors.Pattern_Invalid, "32-bit PixPat");
      Both (Empty_Tile, Errors.Pattern_Invalid, "empty PixPat");
      Both (Cut_Tile, Errors.Source_Unexpected_End, "PixPat cut after its type");
      Over (Huge_Tile, Pictlib.Limits.Default_Limits, Pictlib.Allocation_Byte_Limit, "20000 x 20000 PixPat");
      Tight.Max_Drawing_Work := 100;
      Tight.Max_Allocation_Bytes := 1_000;
      Over (Unaffordable_Tile, Tight, Pictlib.Drawing_Work_Limit, "18000 x 18000 PixPat on small budgets");
      Tight := Pictlib.Limits.Default_Limits;
      --  A tile of more than the 2^31 - 1 pixels a tile can index is never decoded, so no budget applies:
      --  strictly it is unsupported before its rows are read, so this one, which has none, says so; leniently its
      --  rows are skipped, so it is cut short.
      Canvases.Expect_Failure (Unindexable_Tile, 8, 2, Errors.Unsupported_Feature, "65535 x 65535 PixPat", 16#14#);
      Canvases.Expect_Failure (Unindexable_Tile, 8, 2, Errors.Source_Unexpected_End, "65535 x 65535 PixPat",
                               16#14#, Options => Compatible);
      --  The same skip with every row present: drawing goes on, with the black pat1Data in the tile's place.
      declare
         Rows : constant := 32_769;
         --  A row of 8192 zero bytes: its word count, then 64 runs of 128.
         Row : constant Bytes := W (128) & Repeat (B (16#81#) & B (0), 64);
         Head : constant Bytes :=
           V2_Prefix (0, 0, 2, 8) & W (16#14#) & W (1) & [1 .. 8 => 16#FF#] & W (16#8000# + 8_192)
           & Rect (-32_768, -32_768, Rows - 32_768, 32_767) & Pixmap_Tail (0, 1, 1, 1)
           & Table_Header (16#8000#, 2) & Table_Entry (0, 0, 0, 0) & Table_Entry (1, 0, 0, 0);
         Tail : constant Bytes := Op_Rect (16#34#, 0, 0, 2, 8) & W (16#FF#);
         Whole : constant Pictlib.Streams.Byte_Array_Access :=
           new Bytes (1 .. Head'Length + Rows * Row'Length + Tail'Length);
      begin
         Whole (1 .. Head'Length) := Head;
         for Index in 0 .. Rows - 1 loop
            Whole (Head'Length + 1 + Index * Row'Length .. Head'Length + (Index + 1) * Row'Length) := Row;
         end loop;
         Whole (Whole'Last - Tail'Length + 1 .. Whole'Last) := Tail;
         Canvases.Render (Whole.all, Decoder, Canvases.View (Storage'Access, 8, 2), Outcome, Compatible,
                          Budget => Tight);
         Assert (Pictlib.Results.Succeeded (Outcome) and then Recorders.Has_Warning
                   (Decoder, Errors.Approximated_Rendering),
                 "65535 x 32769 PixPat with its rows: " & Outcome.First_Error.Code'Image);
         --  The warning says why: the bound and the tile's pixels, at the opcode.
         for Index in 1 .. Pictlib.Decoding.Warning_Count (Decoder) loop
            declare
               Item : constant Errors.Warning := Pictlib.Decoding.Warning_At (Decoder, Index);
            begin
               if Item.Code = Errors.Approximated_Rendering then
                  Assert (Item.Context.Op = 16#14# and then Item.Context.Expected = 2 ** 31 - 1
                          and then Item.Context.Actual = 65_535 * Rows,
                          "65535 x 32769 PixPat: the warning does not say why");
               end if;
            end;
         end loop;
         Assert (Canvases.Picture_Of (Canvases.View (Storage'Access, 8, 2)) = "BBBBBBBB/BBBBBBBB",
                 "65535 x 32769 PixPat: pat1Data did not stand in, drew "
                 & Canvases.Picture_Of (Canvases.View (Storage'Access, 8, 2)));
         --  The skip costs only the pattern's unit, under any budget: 100 units draw the whole picture.
         Tight.Max_Drawing_Work := 100;
         Canvases.Render (Whole.all, Decoder, Canvases.View (Storage'Access, 8, 2), Outcome, Compatible,
                          Budget => Tight);
         Assert (Pictlib.Results.Succeeded (Outcome),
                 "the skipped tile was charged more than its unit: " & Outcome.First_Error.Code'Image);
         Tight := Pictlib.Limits.Default_Limits;
         --  Strictly it is unsupported whatever the budgets: none left for the pattern's unit, and too few bytes
         --  per opcode for its rows.
         Tight.Max_Drawing_Work := 0;
         Tight.Max_Allocation_Bytes := 1_000;
         Tight.Max_Opcode_Bytes := 1_000;
         Canvases.Render (Whole.all, Decoder, Canvases.View (Storage'Access, 8, 2), Outcome,
                          (Strictness => Pictlib.Strict, others => <>), Budget => Tight);
         Assert (Outcome.First_Error.Code = Errors.Unsupported_Feature
                 and then Outcome.First_Error.Context.Op = 16#14#
                 and then Outcome.First_Error.Context.Expected = 2 ** 31 - 1
                 and then Outcome.First_Error.Context.Actual = 65_535 * Rows,
                 "65535 x 32769 PixPat, strictly on no budget: " & Outcome.First_Error.Code'Image);
      end;
      --  Limits apply only to rendering: enumeration reads on, to the rows this picture does not have.
      Recorders.Decode (Unindexable_Tile, Decoder, Events, Outcome);
      Assert (Outcome.First_Error.Code = Errors.Source_Unexpected_End,
              "65535 x 65535 PixPat enumerated with " & Outcome.First_Error.Code'Image);
      Tight := Pictlib.Limits.Default_Limits;
      Tight.Max_Allocation_Bytes := 120_880;
      Over (Grown_Tile, Tight, Pictlib.Allocation_Byte_Limit, "a tile and its row buffers over the budget");
      Tight.Max_Allocation_Bytes := 120_881;
      Canvases.Render (Grown_Tile, Decoder, Canvases.View (Storage'Access, 8, 2), Outcome, Budget => Tight);
      Assert (Pictlib.Results.Succeeded (Outcome), "a tile and its row buffers within the budget failed with "
              & Outcome.First_Error.Code'Image);
      Tight := Pictlib.Limits.Default_Limits;
      Tight.Max_Drawing_Work := 100;
      Over (Costly_Tile, Tight, Pictlib.Drawing_Work_Limit, "a tile that costs more than the budget");
      Tight.Max_Drawing_Work := 10_000;
      Canvases.Render (Costly_Tile, Decoder, Canvases.View (Storage'Access, 8, 2), Outcome, Budget => Tight);
      Assert (Pictlib.Results.Succeeded (Outcome), "a tile within the budget failed with "
              & Outcome.First_Error.Code'Image);
      --  Pack types and component counts are checked whether or not the rows are packed.
      declare
         function Direct (Row_Bytes, Pack, Size, Count : Natural; Data : Bytes) return Bytes is
           (Pic (1, 1, W (16#9A#) & L (16#FF#) & W (16#8000# + Row_Bytes) & Rect (0, 0, 1, 1)
                       & Pixmap_Tail (Pack, Size, Count, (if Size = 16 then 5 else 8)) & Rect (0, 0, 1, 1)
                       & Rect (0, 0, 1, 1) & W (0) & Data));
         Pack_4_At_16 : aliased constant Bytes := Direct (2, 4, 16, 3, Zeros (2));
         Pack_3_At_32 : aliased constant Bytes := Direct (4, 3, 32, 3, Zeros (4));
         Seven_Components : aliased constant Bytes := Direct (4, 1, 32, 7, Zeros (4));
      begin
         Canvases.Expect_Failure (Pack_4_At_16, 1, 1, Errors.Pixmap_Invalid, "pack type 4 at 16 bits", 16#9A#);
         Canvases.Expect_Failure (Pack_3_At_32, 1, 1, Errors.Pixmap_Invalid, "pack type 3 at 32 bits", 16#9A#);
         Canvases.Expect_Failure (Seven_Components, 1, 1, Errors.Pixmap_Invalid, "cmpCount 7, unpacked", 16#9A#);
      end;
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
   begin
      Canvases.Render (Polygon, Decoder, Canvases.View (Storage'Access, 200, 200), Outcome);
      Assert (Pictlib.Results.Succeeded (Outcome), "zig-zag polygon failed with " & Outcome.First_Error.Code'Image);
      Small.Max_Drawing_Work := 50_000;
      Canvases.Expect_Failure (Polygon, 200, 200, Errors.Limit_Exceeded, "zig-zag polygon over budget", 16#71#,
                               Budget => Small);
      Canvases.Render (Polygon, Decoder, Canvases.View (Storage'Access, 200, 200), Outcome, Budget => Small);
      Assert (Outcome.First_Error.Context.Limit = Pictlib.Drawing_Work_Limit, "zig-zag polygon: wrong limit");
      Canvases.Expect_Raster (Moving_Clip, 4, 4, "BBBB/WWWW/BBBB/WWWW", "clip kept while the origin moves");
      --  A shape that runs out of its allowance part-way covers nothing, whoever asks.
      declare
         package Coverage renames Pictlib.Internal.Coverage;
         Partial, Whole : Coverage.Shape;
         Window : constant Coverage.Area := (Top => 0, Left => 0, Bottom => 10, Right => 10);
      begin
         Coverage.Start (Partial, Window, Allowance => 3);
         Coverage.Rectangle (Partial, Window);
         Assert (Coverage.Exhausted (Partial), "a rectangle of 10 rows fit an allowance of 3");
         for Y in 0 .. 9 loop
            Assert (Coverage.Row (Partial, Y).Is_Empty, "an exhausted shape covers row" & Y'Image);
         end loop;
         --  Above Natural'Last: only the budget bounds a shape.
         Coverage.Start (Whole, Window, Allowance => Pictlib.Pixel_Count'Succ (Pictlib.Pixel_Count (Natural'Last)));
         Coverage.Rectangle (Whole, Window);
         Assert (not Coverage.Exhausted (Whole) and then not Coverage.Row (Whole, 9).Is_Empty,
                 "a wide allowance cut the rectangle short");
      end;
      --  A shape holds only the rows it reaches, so a small shape costs little in a tall window, and an empty
      --  one nothing but its opcode.
      declare
         package Coverage renames Pictlib.Internal.Coverage;
         use type Pictlib.Pixel_Count;
         Small : Coverage.Shape;
         Tall : constant Coverage.Area := (Top => 0, Left => 0, Bottom => 16_384, Right => 1);
         Same_Rects : aliased constant Bytes := Pic (1, 16_384, Repeat (W (16#39#), 10_000));
         Tall_Storage : aliased Bytes := [1 .. 3 * 16_384 => 0];
         Budget : Pictlib.Limits.Limit_Set := Pictlib.Limits.Default_Limits;
      begin
         Coverage.Start (Small, Tall);
         Coverage.Rectangle (Small, (Top => 100, Left => 0, Bottom => 101, Right => 1));
         Assert (Coverage.First_Row (Small) = 100 and then Coverage.Last_Row (Small) = 100
                 and then Coverage.Work (Small) < 10,
                 "a one-row shape holds rows" & Coverage.First_Row (Small)'Image & " .."
                 & Coverage.Last_Row (Small)'Image);
         --  Every row a shape walks is charged, whether or not any of it lands in the window: a tall oval whose
         --  edge just reaches the window's one column, and a tall pen far left of it.
         declare
            Edge, Pen, Away : Coverage.Shape;
         begin
            Coverage.Start (Edge, Tall);
            Coverage.Oval (Edge, (Top => 0, Left => -100, Bottom => 16_384, Right => 1));
            Assert (Coverage.Work (Edge) >= 16_384, "an oval's walked rows were not charged:"
                    & Coverage.Work (Edge)'Image);
            Coverage.Start (Pen, Tall);
            Coverage.Line (Pen, (H => -30_000, V => 0), (H => -30_000, V => 0), 1, 16_384);
            Assert (Coverage.Work (Pen) >= 16_384, "a tall pen's rows were not charged:" & Coverage.Work (Pen)'Image);
            --  Wholly left of the window: no rows are walked at all.
            Coverage.Start (Away, Tall);
            Coverage.Oval (Away, (Top => 0, Left => -30_000, Bottom => 16_384, Right => -29_000));
            Assert (Coverage.Work (Away) = 0, "an oval left of the window walked its rows");
         end;
         --  10,000 paintSameRect before any rect: a unit each.
         Budget.Max_Drawing_Work := 10_000;
         Canvases.Render (Same_Rects, Decoder, Canvases.View (Tall_Storage'Access, 1, 16_384), Outcome,
                          Budget => Budget);
         Assert (Pictlib.Results.Succeeded (Outcome), "10,000 empty shapes cost more than a unit each: "
                 & Outcome.First_Error.Code'Image);
         Budget.Max_Drawing_Work := 9_999;
         Canvases.Expect_Failure (Same_Rects, 1, 16_384, Errors.Limit_Exceeded, "10,000 empty shapes on 9,999",
                                  16#39#, Budget => Budget);
      end;
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
      --  A 1 x 1 BitMap stretched over 65,535 rows, all left of the frame: each destination row walked costs.
      Stretched : aliased constant Bytes :=
        Pic (16, 1, W (16#90#) & W (2) & Rect (0, 0, 1, 1) & Rect (0, 0, 1, 1)
                    & Rect (-32_768, -30_000, 32_767, -29_999) & W (0) & Zeros (2));
      Wide : aliased constant Bytes :=
        Pic (16, 1, W (16#98#) & W (2) & Rect (0, 0, 1, 16) & Rect (0, 0, 1, 16) & Rect (0, 0, 1, 16) & W (0)
                    & Zeros (2));
      --  20 one-row copies, all outside the frame: each row is still charged.
      Missing : aliased constant Bytes :=
        Pic (16, 1, Repeat (W (16#98#) & W (2) & Rect (0, 0, 1, 16) & Rect (0, 0, 1, 16) & Rect (100, 100, 101, 116)
                            & W (0) & Zeros (2), 20));
      Pen_Bits : aliased constant Bytes := Pic (4, 4, W (16#09#) & Zeros (8));
      Cut_Pen_Bits : aliased constant Bytes := V2_Prefix (0, 0, 4, 4) & W (16#09#) & Zeros (3);
      Cut_Pixel_Pattern : aliased constant Bytes := V2_Prefix (0, 0, 4, 4) & W (16#13#) & W (1);
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
      Canvases.Expect_Failure (Missing, 16, 1, Errors.Limit_Exceeded, "skipped rows over budget", 16#98#,
                               Budget => Small);
      Small.Max_Drawing_Work := 10_000;
      Canvases.Expect_Failure (Stretched, 16, 1, Errors.Limit_Exceeded, "a copy's off-frame rows over budget",
                               16#90#, Budget => Small);
      Small.Max_Drawing_Work := 10;
      --  Pattern opcodes are read, then charged, like every other opcode: a complete one past the budget reports
      --  the limit, one cut short the truncation, as a PixPat does.
      Small.Max_Drawing_Work := 0;
      Canvases.Expect_Failure (Pen_Bits, 4, 4, Errors.Limit_Exceeded, "PnPat past the budget", 16#09#,
                               Budget => Small);
      Canvases.Expect_Failure (Cut_Pen_Bits, 4, 4, Errors.Source_Unexpected_End, "cut PnPat past the budget",
                               16#09#, Budget => Small);
      Canvases.Expect_Failure (Cut_Pixel_Pattern, 4, 4, Errors.Source_Unexpected_End, "cut PnPixPat past the budget",
                               16#13#, Budget => Small);
   end Pixel_Work;
end Pictlib_Testing.Test_Hostile;
