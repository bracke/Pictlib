with AUnit.Assertions;
with Textrender;

with Pictlib;
with Pictlib.Decoding;
with Pictlib.Errors;
with Pictlib.Fonts;
with Pictlib.Images;
with Pictlib.Internal.Text;
with Pictlib.Limits;
with Pictlib.Results;
with Pictlib.Streams;
with Pictlib_Testing.Builders;
with Pictlib_Testing.Canvases;
with Pictlib_Testing.Recorders;

package body Pictlib_Testing.Test_Text is
   use AUnit.Assertions;
   use Pictlib_Testing.Builders;
   use type Pictlib.Byte;
   use type Pictlib.Errors.Error_Code;
   use type Pictlib.Errors.Warning_Code;
   use type Pictlib.Limit_Kind;
   use type Pictlib.Images.RGB_Color;
   use type Pictlib.Streams.Byte_Array;
   use type Textrender.Alpha;
   use type Textrender.Status_Code;

   Sans : constant String := "fixtures/fonts/DejaVuSans.ttf";
   Mono : constant String := "fixtures/fonts/DejaVuSansMono.ttf";
   Width : constant := 48;
   Height : constant := 24;

   type Codepoints is array (Positive range <>) of Textrender.Codepoint;

   function Points (Item : String) return Codepoints is
      Result : Codepoints (1 .. Item'Length);
   begin
      for Index in Item'Range loop
         Result (Index - Item'First + 1) := Character'Pos (Item (Index));
      end loop;
      return Result;
   end Points;

   type Grid is array (0 .. Height - 1, 0 .. Width - 1) of Character;

   function Blank (Fill : Character := 'W') return Grid is ([others => [others => Fill]]);

   function Image (Item : Grid) return String is
      Result : String (1 .. Height * (Width + 1) - 1) := [others => '/'];
   begin
      for Y in Grid'Range (1) loop
         for X in Grid'Range (2) loop
            Result (Y * (Width + 1) + X + 1) := Item (Y, X);
         end loop;
      end loop;
      return Result;
   end Image;

   --  The oracle: textrender's own glyphs placed by the rules of the specification, section 3.4 -- the pen
   --  starts at the text origin, each glyph's left edge is round (pen + bearing), its top is the baseline less
   --  its bearing, coverage of 128 or more is ink, bold smears ink one pixel right and widens the advance by one.
   procedure Ink
     (Target : in out Grid;
      Path : String;
      Size : Positive;
      Start_H : Float;
      Baseline : Integer;
      Text_Points : Codepoints;
      Pen_End : out Float;
      Bold : Boolean := False;
      Color : Character := 'B';
      Extra : Float := 0.0;
      Space_Extra : Float := 0.0;
      Char_Extra : Float := 0.0;
      Style : Textrender.Font_Style := Textrender.Regular)
   is
      Font : Textrender.Renderer;
      Cell : constant Positive := 2 * Size + 2;
      Side : constant Positive := Positive'Max (256, 4 * Cell);
      Pen : Float := Start_H;
   begin
      Assert (Font.Load_Font (Path, Size, Cell, Cell, Side, Side) = Textrender.Success, "oracle font did not load");
      --  Each glyph is drawn as soon as it is taken, so the oracle stays right when the atlas empties.
      Font.Set_Atlas_Eviction (True);
      for Code of Text_Points loop
         declare
            Metric : Textrender.Glyph_Metric;
         begin
            Assert (Font.Get_Glyph (Code, Metric, Style) = Textrender.Success, "oracle glyph missing");
            declare
               Left : constant Integer := Integer (Float'Rounding (Pen + Metric.Bearing_X));
               Top : constant Integer := Baseline - Integer (Metric.Bearing_Y);
               Atlas : constant access constant Textrender.Alpha_Buffer := Font.Atlas_Pixels;
            begin
               for GY in 0 .. Metric.H - 1 loop
                  for GX in 0 .. Metric.W - 1 loop
                     if Atlas ((Metric.Y + GY) * Font.Atlas_Width + Metric.X + GX) >= 128 then
                        for Smear in 0 .. (if Bold then 1 else 0) loop
                           if Top + GY in Grid'Range (1) and then Left + GX + Smear in Grid'Range (2) then
                              Target (Top + GY, Left + GX + Smear) := Color;
                           end if;
                        end loop;
                     end if;
                  end loop;
               end loop;
               --  The face's width change after every character; SpExtra after a space, ChExtra after any other.
               Pen := Pen + Metric.Advance_X + (if Bold then 1.0 else 0.0) + Extra
                 + (if Code = Character'Pos (' ') then Space_Extra else Char_Extra);
            end;
         end;
      end loop;
      Pen_End := Pen;
   end Ink;

   procedure Ink (Target : in out Grid; Path : String; Size : Positive; Start_H, Baseline : Integer; Text : String) is
      Ignored : Float;
   begin
      Ink (Target, Path, Size, Float (Start_H), Baseline, Points (Text), Ignored);
   end Ink;

   function Expected (Path : String; Size : Positive; Start_H, Baseline : Integer; Text : String) return String is
      Result : Grid := Blank;
   begin
      Ink (Result, Path, Size, Start_H, Baseline, Text);
      return Image (Result);
   end Expected;

   function Pad (Item : Bytes) return Bytes is (if Item'Length mod 2 = 0 then Item else Item & B (0));
   function Long_Text (V, H : Integer; Item : String) return Bytes is
     (Pad (W (16#28#) & W (V) & W (H) & B (Item'Length) & Text (Item)));
   function Long_Text_Bytes (V, H : Integer; Item : Bytes) return Bytes is
     (Pad (W (16#28#) & W (V) & W (H) & B (Item'Length) & Item));
   function DH_Text (Dh : Natural; Item : String) return Bytes is
     (Pad (W (16#29#) & B (Dh) & B (Item'Length) & Text (Item)));
   function DV_Text (Dv : Natural; Item : String) return Bytes is
     (Pad (W (16#2A#) & B (Dv) & B (Item'Length) & Text (Item)));
   function DHDV_Text (Dh, Dv : Natural; Item : String) return Bytes is
     (Pad (W (16#2B#) & B (Dh) & B (Dv) & B (Item'Length) & Text (Item)));
   function Size_Op (Size : Natural) return Bytes is (W (16#0D#) & W (Size));
   function Font_Op (ID : Natural) return Bytes is (W (16#03#) & W (ID));
   function Face_Op (Face : Natural) return Bytes is (W (16#04#) & B (Face) & B (0));
   function Mode_Op (Mode : Natural) return Bytes is (W (16#05#) & W (Mode));
   function Font_Name (ID : Natural; Name : String) return Bytes is
     (Pad (W (16#2C#) & W (3 + Name'Length) & W (ID) & B (Name'Length) & Text (Name)));
   function Pic (Body_Bytes : Bytes) return Bytes is (V2_Picture (0, 0, Height, Width, Body_Bytes));

   function With_Fonts (Default : String := Sans; Strictness : Pictlib.Strictness_Mode := Pictlib.Strict)
     return Pictlib.Decoding.Options
   is
      Table : Pictlib.Fonts.Font_Table := Pictlib.Fonts.Empty;
   begin
      Pictlib.Fonts.Set_Default (Table, Default);
      return (Fonts => Table, Strictness => Strictness, others => <>);
   end With_Fonts;

   Hi : aliased constant Bytes := Pic (Size_Op (12) & Long_Text (15, 2, "Hi"));
   Default_Size : aliased constant Bytes := Pic (Long_Text (15, 2, "Hi"));
   Large : aliased constant Bytes := Pic (Size_Op (20) & Long_Text (20, 1, "Ag"));
   Moved_H : aliased constant Bytes := Pic (Long_Text (15, 2, "a") & DH_Text (14, "b"));
   Moved_V : aliased constant Bytes := Pic (Long_Text (10, 2, "a") & DV_Text (12, "b"));
   Moved_Both : aliased constant Bytes := Pic (Long_Text (10, 2, "a") & DHDV_Text (20, 12, "b"));
   Named_Font : aliased constant Bytes := Pic (Font_Name (77, "Example Sans") & Font_Op (77) & Long_Text (15, 2, "Hi"));
   Classic_Font : aliased constant Bytes := Pic (Font_Op (21) & Long_Text (15, 2, "Hi"));
   Numbered_Font : aliased constant Bytes := Pic (Font_Op (300) & Long_Text (15, 2, "Hi"));
   Mac_Roman : aliased constant Bytes := Pic (Long_Text_Bytes (15, 2, [16#8A#, 16#A7#]));
   Bold_Text : aliased constant Bytes := Pic (Face_Op (1) & Long_Text (15, 2, "Hi"));
   Underlined : aliased constant Bytes := Pic (Face_Op (4) & Long_Text (15, 2, "Hi"));
   Outlined : aliased constant Bytes := Pic (Face_Op (8) & Long_Text (15, 2, "Hi"));
   Shadowed : aliased constant Bytes := Pic (Face_Op (16) & Long_Text (15, 2, "Hi"));
   Stretched : aliased constant Bytes :=
     Pic (W (16#10#) & W (2) & W (1) & W (1) & W (1) & Long_Text (15, 2, "Hi"));
   Too_Large : aliased constant Bytes := Pic (Size_Op (600) & Long_Text (15, 2, "Hi"));
   Italic_Text : aliased constant Bytes := Pic (Face_Op (2) & Long_Text (15, 2, "Hi"));
   Condensed : aliased constant Bytes := Pic (Face_Op (32) & Long_Text (15, 2, "Hi"));
   Extended : aliased constant Bytes := Pic (Face_Op (64) & Long_Text (15, 2, "Hi"));
   --  Mac Roman 16#F0# is the Apple logo, U+F8FF, which DejaVu Sans does not have.
   Missing_Glyph : aliased constant Bytes :=
     Pic (Long_Text_Bytes (15, 2, [Character'Pos ('a'), 16#F0#, Character'Pos ('b'), 16#F0#]));
   Big_Atlas : aliased constant Bytes := Pic (Size_Op (100) & Long_Text (15, 2, "H"));
   Red_Text : aliased constant Bytes := Pic (W (16#1A#) & W (16#FFFF#) & W (0) & W (0) & Long_Text (15, 2, "Hi"));
   --  HiliteColor red, then HiliteMode: the text after it draws its ink in the highlight color, the rectangle
   --  after the text in the pen's black again.
   Hilite_Text : aliased constant Bytes :=
     Pic (W (16#1D#) & W (16#FFFF#) & W (0) & W (0) & W (16#1C#) & Long_Text (15, 2, "Hi")
          & W (16#31#) & Rect (0, 40, 2, Width));
   Black_Under : constant Bytes := W (16#31#) & Rect (0, 0, Height, Width);
   Xor_Text : aliased constant Bytes := Pic (Black_Under & Mode_Op (2) & Long_Text (15, 2, "Hi"));
   Copy_Text : aliased constant Bytes := Pic (Black_Under & Mode_Op (0) & Long_Text (15, 2, "."));
   Clipped_Text : aliased constant Bytes := Pic (W (16#01#) & Region (0, 0, 10, Width) & Long_Text (15, 2, "Hi"));
   --  ChExtra 3 pixels, recorded as 4.12 fixed point, and SpExtra 4.
   Spaced : aliased constant Bytes :=
     Pic (W (16#16#) & W (3 * 4096) & W (16#06#) & L (4 * 16#1_0000#) & Long_Text (15, 2, "a b"));

   procedure Plain_Text (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Missing_Fonts (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Text_Origins (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Font_Resolution (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Characters (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Faces (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Modes_And_Colors (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Spacing_And_Clipping (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Text_Work (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Font_Cache (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Atlas_Eviction (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Eviction_Over_Budget (T : in out AUnit.Test_Cases.Test_Case'Class);

   overriding function Name (T : Test) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("text");
   end Name;

   overriding procedure Register_Tests (T : in out Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Plain_Text'Access, "text.plain");
      Register_Routine (T, Missing_Fonts'Access, "text.missing_fonts");
      Register_Routine (T, Text_Origins'Access, "text.origins");
      Register_Routine (T, Font_Resolution'Access, "text.font_resolution");
      Register_Routine (T, Characters'Access, "text.mac_roman");
      Register_Routine (T, Faces'Access, "text.faces");
      Register_Routine (T, Modes_And_Colors'Access, "text.modes_and_colors");
      Register_Routine (T, Spacing_And_Clipping'Access, "text.spacing_and_clipping");
      Register_Routine (T, Text_Work'Access, "text.work");
      Register_Routine (T, Font_Cache'Access, "text.font_cache");
      Register_Routine (T, Atlas_Eviction'Access, "text.atlas_eviction");
      Register_Routine (T, Eviction_Over_Budget'Access, "text.eviction_over_budget");
   end Register_Tests;

   procedure Plain_Text (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Hi_Raster : constant String := Expected (Sans, 12, 2, 15, "Hi");
   begin
      Assert ((for some C of Hi_Raster => C = 'B'), "the oracle drew no ink");
      Canvases.Expect_Raster (Hi, Width, Height, Hi_Raster, "LongText", With_Fonts);
      Canvases.Expect_Raster (Default_Size, Width, Height, Hi_Raster, "TxSize 0 is 12", With_Fonts);
      Canvases.Expect_Raster (Large, Width, Height, Expected (Sans, 20, 1, 20, "Ag"), "TxSize 20", With_Fonts);
   end Plain_Text;

   procedure Missing_Fonts (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Storage : aliased Bytes := [1 .. 3 * Width * Height => 0];
      Decoder : Pictlib.Decoding.Decoder;
      Outcome : Pictlib.Results.Result;
   begin
      Canvases.Expect_Failure (Hi, Width, Height, Pictlib.Errors.Font_Unavailable, "no font", 16#28#);
      Canvases.Expect_Failure (Hi, Width, Height, Pictlib.Errors.Font_Unavailable, "unloadable font", 16#28#,
                               With_Fonts ("fixtures/fonts/missing.ttf"));
      Canvases.Render (Hi, Decoder, Canvases.View (Storage'Access, Width, Height), Outcome,
                       (Strictness => Pictlib.Compatible, others => <>));
      Assert (Pictlib.Results.Succeeded (Outcome)
              and then Recorders.Has_Warning (Decoder, Pictlib.Errors.Approximated_Rendering),
              "a compatible decoder did not skip text without a font");
      Assert (Canvases.Picture_Of (Canvases.View (Storage'Access, Width, Height)) = Image (Blank),
              "text without a font drew something");
   end Missing_Fonts;

   procedure Text_Origins (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Horizontal, Vertical, Both : Grid := Blank;
   begin
      Ink (Horizontal, Sans, 12, 2, 15, "a");
      Ink (Horizontal, Sans, 12, 16, 15, "b");
      Canvases.Expect_Raster (Moved_H, Width, Height, Image (Horizontal), "DHText", With_Fonts);
      Ink (Vertical, Sans, 12, 2, 10, "a");
      Ink (Vertical, Sans, 12, 2, 22, "b");
      Canvases.Expect_Raster (Moved_V, Width, Height, Image (Vertical), "DVText", With_Fonts);
      Ink (Both, Sans, 12, 2, 10, "a");
      Ink (Both, Sans, 12, 22, 22, "b");
      Canvases.Expect_Raster (Moved_Both, Width, Height, Image (Both), "DHDVText", With_Fonts);
   end Text_Origins;

   procedure Font_Resolution (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Sans_Raster : constant String := Expected (Sans, 12, 2, 15, "Hi");
      Mono_Raster : constant String := Expected (Mono, 12, 2, 15, "Hi");
      By_Name, By_Classic, By_ID : Pictlib.Decoding.Options := With_Fonts (Mono);
   begin
      Assert (Sans_Raster /= Mono_Raster, "the two test fonts draw alike");
      Pictlib.Fonts.Add (By_Name.Fonts, "example sans", Sans);
      Pictlib.Fonts.Add (By_Classic.Fonts, "Helvetica", Sans);
      Pictlib.Fonts.Add (By_ID.Fonts, Pictlib.Fonts.Font_ID (300), Sans);
      Canvases.Expect_Raster (Named_Font, Width, Height, Sans_Raster, "fontName, any case", By_Name);
      Canvases.Expect_Raster (Named_Font, Width, Height, Mono_Raster, "the default", With_Fonts (Mono));
      Canvases.Expect_Raster (Classic_Font, Width, Height, Sans_Raster, "classic ID 21", By_Classic);
      Canvases.Expect_Raster (Numbered_Font, Width, Height, Sans_Raster, "font ID", By_ID);
      declare
         Storage : aliased Bytes := [1 .. 3 * Width * Height => 0];
         Decoder : Pictlib.Decoding.Decoder;
         Outcome : Pictlib.Results.Result;
      begin
         Canvases.Render (Named_Font, Decoder, Canvases.View (Storage'Access, Width, Height), Outcome, By_Name);
         Assert (Pictlib.Results.Succeeded (Outcome) and then Pictlib.Decoding.Metadata_Count (Decoder) = 1,
                 "rendering lost the retained font name");
      end;
      Assert (Pictlib.Fonts.Classic_Name (21) = "Helvetica" and then Pictlib.Fonts.Classic_Name (22) = "Courier"
              and then Pictlib.Fonts.Classic_Name (999) = "", "classic names");
   end Font_Resolution;

   procedure Characters (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Result : Grid := Blank;
      Ignored : Float;
   begin
      --  16#8A# is a-diaeresis and 16#A7# sharp s in Mac Roman.
      Ink (Result, Sans, 12, 2.0, 15, [16#00E4#, 16#00DF#], Ignored);
      Canvases.Expect_Raster (Mac_Roman, Width, Height, Image (Result), "Mac Roman", With_Fonts);
   end Characters;

   procedure Faces (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Bold, Underline : Grid := Blank;
      Pen_End : Float;
   begin
      Ink (Bold, Sans, 12, 2.0, 15, Points ("Hi"), Pen_End, Bold => True);
      Canvases.Expect_Raster (Bold_Text, Width, Height, Image (Bold), "bold", With_Fonts);
      Ink (Underline, Sans, 12, 2.0, 15, Points ("Hi"), Pen_End);
      for X in 2 .. Integer (Float'Rounding (Pen_End)) - 1 loop
         Underline (16, X) := 'B';
      end loop;
      Canvases.Expect_Raster (Underlined, Width, Height, Image (Underline), "underline", With_Fonts);
      Canvases.Expect_Failure (Outlined, Width, Height, Pictlib.Errors.Unsupported_Feature, "outline", 16#28#,
                               With_Fonts);
      Canvases.Expect_Raster (Outlined, Width, Height, Expected (Sans, 12, 2, 15, "Hi"), "outline drawn plain",
                              With_Fonts (Strictness => Pictlib.Compatible));
      Canvases.Expect_Failure (Shadowed, Width, Height, Pictlib.Errors.Unsupported_Feature, "shadow", 16#28#,
                               Options => With_Fonts);
      Canvases.Expect_Raster (Shadowed, Width, Height, Expected (Sans, 12, 2, 15, "Hi"), "shadow drawn plain",
                              With_Fonts (Strictness => Pictlib.Compatible));
      Canvases.Expect_Failure (Stretched, Width, Height, Pictlib.Errors.Unsupported_Feature, "TxRatio 2:1", 16#28#,
                               With_Fonts);
      Canvases.Expect_Failure (Too_Large, Width, Height, Pictlib.Errors.Unsupported_Feature, "TxSize 600", 16#28#,
                               With_Fonts);
      --  lineJustify without extra space changes nothing; with any it is unsupported.
      declare
         Plain : constant String := Expected (Sans, 12, 2, 15, "Hi");
         No_Extra : aliased constant Bytes :=
           Pic (W (16#2D#) & W (8) & L (0) & L (0) & Size_Op (12) & Long_Text (15, 2, "Hi"));
         Extra : aliased constant Bytes :=
           Pic (W (16#2D#) & W (8) & L (16#1_0000#) & L (0) & Size_Op (12) & Long_Text (15, 2, "Hi"));
      begin
         Canvases.Expect_Raster (No_Extra, Width, Height, Plain, "lineJustify without extra space", With_Fonts);
         Canvases.Expect_Failure (Extra, Width, Height, Pictlib.Errors.Unsupported_Feature, "lineJustify", 16#2D#,
                                  With_Fonts);
         declare
            Storage : aliased Bytes := [1 .. 3 * Width * Height => 0];
            Output : constant Pictlib.Images.Mutable_Image_View := Canvases.View (Storage'Access, Width, Height);
            Decoder : Pictlib.Decoding.Decoder;
            Outcome : Pictlib.Results.Result;
         begin
            Canvases.Render (Extra, Decoder, Output, Outcome, With_Fonts (Strictness => Pictlib.Compatible));
            Assert (Pictlib.Results.Succeeded (Outcome)
                    and then Recorders.Has_Warning (Decoder, Pictlib.Errors.Approximated_Rendering)
                    and then Canvases.Picture_Of (Output) = Plain,
                    "lineJustify was not drawn unjustified with a warning, leniently");
         end;
      end;
      --  The failure names the largest size against the one asked for.
      declare
         Storage : aliased Bytes := [1 .. 3 * Width * Height => 0];
         Decoder : Pictlib.Decoding.Decoder;
         Outcome : Pictlib.Results.Result;
         use type Pictlib.Byte_Count;
      begin
         Canvases.Render (Too_Large, Decoder, Canvases.View (Storage'Access, Width, Height), Outcome, With_Fonts);
         Assert (Outcome.First_Error.Context.Expected = 512 and then Outcome.First_Error.Context.Actual = 600,
                 "TxSize 600 reported" & Outcome.First_Error.Context.Expected'Image & " against"
                 & Outcome.First_Error.Context.Actual'Image);
      end;
      --  Italic is textrender's synthetic oblique; condense and extend take one pixel off or add one to every
      --  advance.
      declare
         Slanted, Narrow, Wide : Grid := Blank;
      begin
         Ink (Slanted, Sans, 12, 2.0, 15, Points ("Hi"), Pen_End, Style => Textrender.Italic);
         Canvases.Expect_Raster (Italic_Text, Width, Height, Image (Slanted), "italic", With_Fonts);
         Ink (Narrow, Sans, 12, 2.0, 15, Points ("Hi"), Pen_End, Extra => -1.0);
         Canvases.Expect_Raster (Condensed, Width, Height, Image (Narrow), "condense", With_Fonts);
         Ink (Wide, Sans, 12, 2.0, 15, Points ("Hi"), Pen_End, Extra => 1.0);
         Canvases.Expect_Raster (Extended, Width, Height, Image (Wide), "extend", With_Fonts);
         --  Each face changes something.
         Assert (Image (Slanted) /= Expected (Sans, 12, 2, 15, "Hi")
                 and then Image (Narrow) /= Expected (Sans, 12, 2, 15, "Hi")
                 and then Image (Wide) /= Expected (Sans, 12, 2, 15, "Hi"),
                 "a face's oracle is plain text");
      end;
      --  A character the font lacks advances half the size, and the opcode warns once, however many it has.
      declare
         Holes : Grid := Blank;
         Storage : aliased Bytes := [1 .. 3 * Width * Height => 0];
         Output : constant Pictlib.Images.Mutable_Image_View := Canvases.View (Storage'Access, Width, Height);
         Decoder : Pictlib.Decoding.Decoder;
         Outcome : Pictlib.Results.Result;
         Losses : Natural := 0;
      begin
         Ink (Holes, Sans, 12, 2.0, 15, Points ("a"), Pen_End);
         Ink (Holes, Sans, 12, Pen_End + 6.0, 15, Points ("b"), Pen_End);
         Canvases.Render (Missing_Glyph, Decoder, Output, Outcome, With_Fonts);
         Assert (Pictlib.Results.Succeeded (Outcome), "a missing glyph failed: " & Outcome.First_Error.Code'Image);
         Assert (Canvases.Picture_Of (Output) = Image (Holes), "a missing glyph: wrong advance");
         Losses := Recorders.Count_Warnings (Decoder, Pictlib.Errors.Data_Loss);
         Assert (Losses = 1, "two missing glyphs in one opcode warned" & Losses'Image & " times");
      end;
      --  A size 100 font's atlas is 808 x 808 bytes: over a smaller allocation budget, it is never loaded.
      declare
         Storage : aliased Bytes := [1 .. 3 * Width * Height => 0];
         Decoder : Pictlib.Decoding.Decoder;
         Outcome : Pictlib.Results.Result;
      begin
         Canvases.Render (Big_Atlas, Decoder, Canvases.View (Storage'Access, Width, Height), Outcome, With_Fonts,
                          (Pictlib.Limits.Default_Limits with delta Max_Allocation_Bytes => 600_000));
         Assert (Outcome.First_Error.Code = Pictlib.Errors.Limit_Exceeded
                 and then Outcome.First_Error.Context.Limit = Pictlib.Allocation_Byte_Limit,
                 "a size 100 atlas over the allocation budget: " & Outcome.First_Error.Code'Image);
      end;
   end Faces;

   procedure Modes_And_Colors (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Red, Inverted : Grid := Blank;
      Pen_End : Float;
      Storage : aliased Bytes := [1 .. 3 * Width * Height => 0];
      Output : constant Pictlib.Images.Mutable_Image_View := Canvases.View (Storage'Access, Width, Height);
      Decoder : Pictlib.Decoding.Decoder;
      Outcome : Pictlib.Results.Result;
   begin
      Ink (Red, Sans, 12, 2.0, 15, Points ("Hi"), Pen_End, Color => 'R');
      Canvases.Expect_Raster (Red_Text, Width, Height, Image (Red), "RGBFgCol", With_Fonts);
      for Y in 0 .. 1 loop
         for X in 40 .. Width - 1 loop
            Red (Y, X) := 'B';
         end loop;
      end loop;
      Canvases.Expect_Raster (Hilite_Text, Width, Height, Image (Red), "HiliteMode before text", With_Fonts);
      Inverted := Blank ('B');
      Ink (Inverted, Sans, 12, 2.0, 15, Points ("Hi"), Pen_End, Color => 'W');
      Canvases.Expect_Raster (Xor_Text, Width, Height, Image (Inverted), "srcXor", With_Fonts);

      --  srcCopy paints the character's cell in the background color.
      Canvases.Render (Copy_Text, Decoder, Output, Outcome, With_Fonts);
      Assert (Pictlib.Results.Succeeded (Outcome), "srcCopy text failed");
      Assert (Canvases.Pixel (Output, 2, 6) = Pictlib.Images.White, "srcCopy left the cell's background");
      Assert (Canvases.Pixel (Output, 40, 6) = Pictlib.Images.Black, "srcCopy painted beyond the cell");
   end Modes_And_Colors;

   procedure Spacing_And_Clipping (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Clipped, Spaced_Out : Grid := Blank;
      Pen_End : Float;
   begin
      Ink (Clipped, Sans, 12, 2, 15, "Hi");
      for Y in 10 .. Height - 1 loop
         for X in Grid'Range (2) loop
            Clipped (Y, X) := 'W';
         end loop;
      end loop;
      Canvases.Expect_Raster (Clipped_Text, Width, Height, Image (Clipped), "clipped text", With_Fonts);

      --  ChExtra 3 after every character but the space, SpExtra 4 after the space.
      Ink (Spaced_Out, Sans, 12, 2.0, 15, Points ("a b"), Pen_End, Space_Extra => 4.0, Char_Extra => 3.0);
      Canvases.Expect_Raster (Spaced, Width, Height, Image (Spaced_Out), "ChExtra and SpExtra", With_Fonts);
   end Spacing_And_Clipping;

   --  Text is drawing work wherever it lands: each font loaded, each glyph asked for. Everything here is drawn
   --  below the frame, so only the charges stop it.
   procedure Text_Work (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      use type Pictlib.Pixel_Count;
      Big_Font : aliased constant Bytes := Pic (Size_Op (500) & Long_Text (500, 2, "A"));
      Many_Glyphs : aliased constant Bytes := Pic (Size_Op (12) & Long_Text (500, 2, [1 .. 255 => 'A']));
      One_Glyph : aliased constant Bytes := Pic (Size_Op (12) & Long_Text (500, 2, "A"));

      --  Nine sizes in turn, Rounds times: more fonts than the cache holds, so every one is loaded again.
      function Sizes (Rounds : Positive) return Bytes is
         One : constant Bytes :=
           Size_Op (12) & Long_Text (500, 2, "A") & Size_Op (13) & Long_Text (500, 2, "A")
           & Size_Op (14) & Long_Text (500, 2, "A") & Size_Op (15) & Long_Text (500, 2, "A")
           & Size_Op (16) & Long_Text (500, 2, "A") & Size_Op (17) & Long_Text (500, 2, "A")
           & Size_Op (18) & Long_Text (500, 2, "A") & Size_Op (19) & Long_Text (500, 2, "A")
           & Size_Op (20) & Long_Text (500, 2, "A");
      begin
         return (if Rounds = 1 then One else One & Sizes (Rounds - 1));
      end Sizes;

      Once : aliased constant Bytes := Pic (Sizes (1));
      Twice : aliased constant Bytes := Pic (Sizes (2));
      Storage : aliased Bytes := [1 .. 3 * Width * Height => 0];
      Decoder : Pictlib.Decoding.Decoder;
      Outcome : Pictlib.Results.Result;
      Options : constant Pictlib.Decoding.Options := With_Fonts;
      Budget : Pictlib.Limits.Limit_Set := Pictlib.Limits.Default_Limits;

      function Renders (Input : aliased Bytes; Work : Pictlib.Pixel_Count) return Boolean is
      begin
         Budget.Max_Drawing_Work := Work;
         Canvases.Render (Input, Decoder, Canvases.View (Storage'Access, Width, Height), Outcome, Options, Budget);
         Assert (Pictlib.Results.Succeeded (Outcome)
                 or else (Outcome.First_Error.Code = Pictlib.Errors.Limit_Exceeded
                          and then Outcome.First_Error.Context.Limit = Pictlib.Drawing_Work_Limit),
                 "text work: failed with " & Outcome.First_Error.Code'Image & " on "
                 & Outcome.First_Error.Context.Limit'Image);
         return Pictlib.Results.Succeeded (Outcome);
      end Renders;

      function Load (Size : Positive) return Pictlib.Pixel_Count is
        (Pictlib.Internal.Text.Load_Work (Size, Pictlib.Internal.Text.File_Bytes (Sans)));
      function Glyphs (Size : Positive; Count : Natural) return Pictlib.Pixel_Count is
        (Pictlib.Pixel_Count (Count) * Pictlib.Internal.Text.Glyph_Work (Size));

      --  The least drawing budget Input renders under, searched below twice Estimate, what its fonts and glyphs
      --  cost, which it must render under: a search from 2^30 would load the fonts some thirty times.
      function Least (Input : aliased Bytes; Estimate : Pictlib.Pixel_Count) return Pictlib.Pixel_Count is
         High : constant Pictlib.Pixel_Count := 2 * Estimate + 1_000_000;
      begin
         Assert (Renders (Input, High), "text work: the estimate is below what the picture needs");
         return Canvases.Least_Drawing_Work (Input, Width, Height, "text work", Options, High => High);
      end Least;

      --  Nine fonts of sizes 12 .. 20, a glyph each.
      function Round_Estimate return Pictlib.Pixel_Count is
         Total : Pictlib.Pixel_Count := 0;
      begin
         for Size in 12 .. 20 loop
            Total := Total + Load (Size) + Glyphs (Size, 1);
         end loop;
         return Total;
      end Round_Estimate;

      One_Glyph_Least : Pictlib.Pixel_Count;
   begin
      --  A size 500 font costs its 16 MiB atlas before it is loaded, so a small budget never loads it.
      Assert (not Renders (Big_Font, 10_000_000), "a size 500 font was loaded on a budget below its atlas");
      --  255 glyphs cost more than one.
      --  Each glyph asked for costs its full charge, 16 units a cell pixel, drawn or not.
      One_Glyph_Least := Least (One_Glyph, Load (12) + Glyphs (12, 1));
      Assert (Least (Many_Glyphs, Load (12) + Glyphs (12, 255)) - One_Glyph_Least
              >= 254 * Pictlib.Internal.Text.Glyph_Work (12),
              "glyphs drawn below the frame cost less than their charge");
      --  Loading a font costs its atlas and its file, which textrender copies whole.
      Assert (One_Glyph_Least >= Load (12),
              "a font load cost less than its atlas and file");
      --  Text counts against an aggregate allocation quota only what it allocates, the font: a hundred full
      --  runs fit a quota a few times the font's size.
      declare
         function Runs (Count : Positive) return Bytes is
           (if Count = 1 then Long_Text (500, 2, [1 .. 255 => 'A'])
            else Long_Text (500, 2, [1 .. 255 => 'A']) & Runs (Count - 1));
         Many_Runs : aliased constant Bytes := Pic (Size_Op (12) & Runs (100));
      begin
         Canvases.Render (Many_Runs, Decoder, Canvases.View (Storage'Access, Width, Height), Outcome, Options,
                          (Pictlib.Limits.Default_Limits with delta Max_Total_Allocation_Bytes => 8_388_608));
         Assert (Pictlib.Results.Succeeded (Outcome), "a hundred text runs overran an 8 MiB allocation quota: "
                 & Outcome.First_Error.Code'Image);
      end;
      --  Nothing is painted past the budget: on black, copy-mode text whose budget ends right after its glyph is
      --  asked for paints no cell pixel, not even the first row's white.
      declare
         Base : aliased constant Bytes := Pic (Black_Under & Mode_Op (0) & Size_Op (12));
         Copy_H : aliased constant Bytes := Pic (Black_Under & Mode_Op (0) & Size_Op (12) & Long_Text (15, 2, "H"));
         Before_Cells : constant Pictlib.Pixel_Count :=
           Least (Base, 1_000) + Load (12)
           + Pictlib.Internal.Text.Glyph_Work (12);
      begin
         Assert (not Renders (Copy_H, Before_Cells), "copy-mode text fit a budget that ends before its cells");
         for Index in Storage'Range loop
            Assert (Storage (Index) = 0, "a glyph cell was painted past the budget");
         end loop;
      end;
      --  An underline is painted pixels too, even where the characters above it are outside the frame: at
      --  size 4 the baseline one row above the frame puts every cell row out and the underline row in.
      declare
         Plain : aliased constant Bytes := Pic (Size_Op (4) & Long_Text (-1, 0, [1 .. 255 => 'A']));
         Underlined : aliased constant Bytes :=
           Pic (Size_Op (4) & Face_Op (4) & Long_Text (-1, 0, [1 .. 255 => 'A']));
      begin
         Assert (Least (Underlined, Load (4) + Glyphs (4, 255)) >= Least (Plain, Load (4) + Glyphs (4, 255)) + Width,
                 "an underline below off-frame text cost nothing");
      end;
      --  Reloading an evicted font costs as much as loading it the first time.
      declare
         First_Round : constant Pictlib.Pixel_Count := Least (Once, Round_Estimate);
      begin
         Assert (First_Round > 0 and then Least (Twice, 2 * Round_Estimate) >= 2 * First_Round - First_Round / 10,
                 "fonts evicted and loaded again cost nothing");
      end;
   end Text_Work;

   --  Eight fonts stay loaded; a ninth that fails to load evicts none, and one that loads evicts the least
   --  recently used, which a font asked for again is not.
   procedure Font_Cache (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      package Text renames Pictlib.Internal.Text;
      Cache : Text.Font_Cache;
      Slot : Positive;
   begin
      declare
         Guard : Text.Textrender_Guard;

         function Loads (Path : String; Size : Positive) return Boolean is
           (Text.Acquire (Cache, Path, Size, Slot, Guard) = Textrender.Success);
      begin
         for Size in 10 .. 17 loop
            Assert (Loads (Sans, Size), "size" & Size'Image & " did not load");
         end loop;
         --  Size 10, the oldest, is used again: size 11 is now the least recently used.
         Assert (Loads (Sans, 10), "a loaded font was not found");
         --  A file that is there but is no font.
         Assert (not Loads ("fixtures/README.md", 12), "a text file loaded");
         Assert ((for all Size in 10 .. 17 => Text.Cached (Cache, Sans, Size)),
                 "a font that failed to load evicted a loaded one");
         Assert (Loads (Mono, 12), "a ninth font did not load");
         Assert (Text.Cached (Cache, Mono, 12) and then not Text.Cached (Cache, Sans, 11)
                 and then Text.Cached (Cache, Sans, 10)
                 and then (for all Size in 12 .. 17 => Text.Cached (Cache, Sans, Size)),
                 "a ninth font did not replace only the least recently used one");
      end;
      --  Clear takes the lock itself.
      Text.Clear (Cache);
   end Font_Cache;

   --  A string of more glyphs than the atlas holds empties it part-way: the glyphs taken before still draw.
   procedure Atlas_Eviction (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Size : constant := 30;
      Many : constant String := [for Index in 1 .. 94 => Character'Val (16#20# + Index)];
      Picture : aliased constant Bytes := Pic (Size_Op (Size) & Long_Text (22, 2, Many));
   begin
      --  The string does empty an atlas of the size pictlib gives this font.
      declare
         Font : Textrender.Renderer;
         Metric : Textrender.Glyph_Metric;
      begin
         --  As pictlib loads it, so the check is of pictlib's atlas.
         Assert (Font.Load_Font (Sans, Size, Pictlib.Internal.Text.Cell (Size), Pictlib.Internal.Text.Cell (Size),
                                 Pictlib.Internal.Text.Atlas_Side (Size), Pictlib.Internal.Text.Atlas_Side (Size))
                 = Textrender.Success, "the font did not load");
         Font.Set_Atlas_Eviction (True);
         for Code of Points (Many) loop
            Assert (Font.Get_Glyph (Code, Metric) = Textrender.Success, "a glyph is missing");
         end loop;
         Assert (Font.Atlas_Generation > 0, "the string fits the atlas, so it tests nothing");
      end;
      Canvases.Expect_Raster (Picture, Width, Height, Expected (Sans, Size, 2, 22, Many),
                              "a string that empties the atlas", With_Fonts);
   end Atlas_Eviction;

   --  The work limit crossed while the glyphs an eviction displaced are painted again ends the text, whatever
   --  is left: at every budget the picture fails over the limit or draws all of itself.
   procedure Eviction_Over_Budget (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      use type Pictlib.Pixel_Count;
      package Text renames Pictlib.Internal.Text;
      Size : constant := 30;
      Glyph : constant Pictlib.Pixel_Count := Text.Glyph_Work (Size);
      --  The clip's lines above the canvas, each adding Added points far to the right, and a last one taking them
      --  all away: the first row any paint walks passes all of them, at a cost of about Added * Lines ** 2 / 2,
      --  several glyphs' work, and stops part-way when the budget runs out.
      Lines : constant := 40;
      Added : constant := 400;
      Last : Natural := 0;

      function Clip return Bytes is
         function Points (First, Count : Natural) return Bytes is
            Result : Bytes (1 .. 2 * Count);
         begin
            for Index in 0 .. Count - 1 loop
               Result (Result'First + 2 * Index .. Result'First + 2 * Index + 1) := W (First + Index);
            end loop;
            return Result;
         end Points;
         function Adding (Line : Natural) return Bytes is
           (W (-Lines + Line) & (if Line = 0 then W (0) & W (Width) else [1 .. 0 => 0])
            & Points (1_000 + Line * Added, Added) & W (16#7FFF#));
         function All_Adding (From : Natural) return Bytes is
           (if From = Lines - 1 then Adding (From) else Adding (From) & All_Adding (From + 1));
         Body_Lines : constant Bytes :=
           All_Adding (0) & W (0) & Points (1_000, Lines * Added) & W (16#7FFF#)
           & W (Height) & W (0) & W (Width) & W (16#7FFF#) & W (16#7FFF#);
      begin
         return W (16#01#) & W (10 + Body_Lines'Length) & Rect (-Lines, 0, Height, 1_000 + Lines * Added)
           & Body_Lines;
      end Clip;
   begin
      declare
         Font : Textrender.Renderer;
         Metric : Textrender.Glyph_Metric;
      begin
         --  As pictlib loads it, so the check is of pictlib's atlas.
         Assert (Font.Load_Font (Sans, Size, Pictlib.Internal.Text.Cell (Size), Pictlib.Internal.Text.Cell (Size),
                                 Pictlib.Internal.Text.Atlas_Side (Size), Pictlib.Internal.Text.Atlas_Side (Size))
                 = Textrender.Success, "the font did not load");
         Font.Set_Atlas_Eviction (True);
         for Code in Pictlib.Byte range 16#21# .. 16#FE# loop
            if Font.Get_Glyph (Text.To_Unicode (Code), Metric) = Textrender.Success
              and then Font.Atlas_Generation > 0
            then
               Last := Natural (Code) + 1;
               exit;
            end if;
         end loop;
         Assert (Last > 0, "no string of these characters empties the atlas");
      end;
      declare
         --  The request that empties the atlas is the last but one.
         Characters : Bytes (1 .. Last - 16#21# + 1);
      begin
         for Index in Characters'Range loop
            Characters (Index) := Pictlib.Byte (16#20# + Index);
         end loop;
         declare
            Picture : aliased constant Bytes := Pic (Clip & Size_Op (Size) & Long_Text_Bytes (22, 2, Characters));
            Whole_Storage, Storage : aliased Bytes := [1 .. 3 * Width * Height => 0];
            Decoder : Pictlib.Decoding.Decoder;
            Outcome : Pictlib.Results.Result;
            --  The font's load and a request per character.
            Requests : constant Pictlib.Pixel_Count :=
              Pictlib.Pixel_Count (Characters'Length) * Glyph + Text.Load_Work (Size, Text.File_Bytes (Sans));
            --  Where the bug lived: past the requests, the clip's own cost and the glyph taken again, and short of
            --  the first repaint's clip walk, the cost of passing every line of the clip.
            Clip_Alone : aliased constant Bytes := Pic (Clip);
            Clip_Cost : constant Pictlib.Pixel_Count :=
              Canvases.Least_Drawing_Work (Clip_Alone, Width, Height, "the clip alone", With_Fonts);
            Walk : constant Pictlib.Pixel_Count := Added * Lines * (Lines + 1) / 2;
            Window_Low : constant Pictlib.Pixel_Count := Requests + Clip_Cost + Glyph;
            Window_High : constant Pictlib.Pixel_Count := Requests + Clip_Cost + Walk;
            In_Window : Boolean := False;
         begin
            Canvases.Render (Picture, Decoder, Canvases.View (Whole_Storage'Access, Width, Height), Outcome,
                             With_Fonts);
            Assert (Pictlib.Results.Succeeded (Outcome), "the whole picture failed: " & Outcome.First_Error.Code'Image);
            --  The font's load and a request per character come before the first repaint's clip walk; the
            --  budgets sweep that walk. Before the fix, budgets from step 4 on drew with glyphs missing.
            for Step in 2 .. 9 loop
               Canvases.Render
                 (Picture, Decoder, Canvases.View (Storage'Access, Width, Height), Outcome, With_Fonts,
                  (Pictlib.Limits.Default_Limits with delta
                     Max_Drawing_Work => Requests + Pictlib.Pixel_Count (Step) * 16_000));
               if Requests + Pictlib.Pixel_Count (Step) * 16_000 in Window_Low .. Window_High - 1 then
                  In_Window := True;
               end if;
               Assert ((Pictlib.Results.Succeeded (Outcome) and then Storage = Whole_Storage)
                       or else (Outcome.First_Error.Code = Pictlib.Errors.Limit_Exceeded
                                and then Outcome.First_Error.Context.Limit = Pictlib.Drawing_Work_Limit),
                       "at step" & Step'Image & " the text "
                       & (if Pictlib.Results.Succeeded (Outcome) then "succeeded with glyphs missing"
                          else "failed with " & Outcome.First_Error.Code'Image));
            end loop;
            --  The sweep reaches the window, or it tests nothing.
            Assert (In_Window, "no budget of the sweep lies between" & Window_Low'Image & " and" & Window_High'Image);
         end;
      end;
   end Eviction_Over_Budget;
end Pictlib_Testing.Test_Text;
