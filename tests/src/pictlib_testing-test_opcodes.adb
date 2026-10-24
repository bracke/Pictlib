with AUnit.Assertions;

with Pictlib;
with Pictlib.Geometry;
with Pictlib.Opcodes;

package body Pictlib_Testing.Test_Opcodes is
   use AUnit.Assertions;
   use type Pictlib.Coordinate;
   use type Pictlib.Opcodes.Data_Rule;
   use type Pictlib.Opcodes.Length_Rule;

   package Op renames Pictlib.Opcodes;

   procedure Fixed_Lengths (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Structured_Rules (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Reserved_Ranges (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Names (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Rect_Geometry (T : in out AUnit.Test_Cases.Test_Case'Class);

   overriding function Name (T : Test) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("opcodes");
   end Name;

   overriding procedure Register_Tests (T : in out Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Fixed_Lengths'Access, "opcodes.rules.fixed_lengths");
      Register_Routine (T, Structured_Rules'Access, "opcodes.rules.structured");
      Register_Routine (T, Reserved_Ranges'Access, "opcodes.reserved_ranges");
      Register_Routine (T, Names'Access, "opcodes.names");
      Register_Routine (T, Rect_Geometry'Access, "geometry.rect");
   end Register_Tests;

   procedure Expect_Fixed (Code : Pictlib.Opcode; Length : Natural) is
      Rule : constant Op.Length_Rule := Op.Rule_For (Code);
   begin
      Assert (Rule.Rule = Op.Fixed_Data and then Rule.Fixed_Length = Length,
              "opcode" & Code'Image & " should carry" & Length'Image & " bytes");
   end Expect_Fixed;

   procedure Expect_Rule (Code : Pictlib.Opcode; Rule : Op.Data_Rule) is
   begin
      Assert (Op.Rule_For (Code).Rule = Rule, "opcode" & Code'Image & " should use " & Rule'Image);
   end Expect_Rule;

   --  Lengths from Inside Macintosh: Imaging With QuickDraw, Table A-2.
   procedure Fixed_Lengths (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Expect_Fixed (16#0000#, 0);   --  NOP
      Expect_Fixed (16#0002#, 8);   --  BkPat
      Expect_Fixed (16#0003#, 2);   --  TxFont
      Expect_Fixed (16#0004#, 1);   --  TxFace
      Expect_Fixed (16#0006#, 4);   --  SpExtra
      Expect_Fixed (16#0007#, 4);   --  PnSize
      Expect_Fixed (16#000B#, 4);   --  OvSize
      Expect_Fixed (16#000C#, 4);   --  Origin
      Expect_Fixed (16#000D#, 2);   --  TxSize
      Expect_Fixed (16#000E#, 4);   --  FgColor
      Expect_Fixed (16#0010#, 8);   --  TxRatio
      Expect_Fixed (16#0015#, 2);   --  PnLocHFrac
      Expect_Fixed (16#0017#, 0);   --  reserved
      Expect_Fixed (16#001A#, 6);   --  RGBFgCol
      Expect_Fixed (16#001C#, 0);   --  HiliteMode
      Expect_Fixed (16#001D#, 6);   --  HiliteColor
      Expect_Fixed (16#001E#, 0);   --  DefHilite
      Expect_Fixed (16#001F#, 6);   --  OpColor
      Expect_Fixed (16#0020#, 8);   --  Line
      Expect_Fixed (16#0021#, 4);   --  LineFrom
      Expect_Fixed (16#0022#, 6);   --  ShortLine
      Expect_Fixed (16#0023#, 2);   --  ShortLineFrom
      Expect_Fixed (16#0030#, 8);   --  frameRect
      Expect_Fixed (16#0037#, 8);   --  reserved, a rect
      Expect_Fixed (16#0038#, 0);   --  frameSameRect
      Expect_Fixed (16#0044#, 8);   --  fillRRect
      Expect_Fixed (16#004C#, 0);   --  fillSameRRect
      Expect_Fixed (16#0050#, 8);   --  frameOval
      Expect_Fixed (16#0060#, 12);  --  frameArc
      Expect_Fixed (16#0067#, 12);  --  reserved, an arc
      Expect_Fixed (16#0068#, 4);   --  frameSameArc
      Expect_Fixed (16#006F#, 4);   --  reserved, a same arc
      Expect_Fixed (16#0078#, 0);   --  frameSamePoly
      Expect_Fixed (16#0088#, 0);   --  frameSameRgn
      Expect_Fixed (16#00A0#, 2);   --  ShortComment
      Expect_Fixed (16#00B0#, 0);   --  reserved
      Expect_Fixed (16#00CF#, 0);   --  reserved
      Expect_Fixed (16#0100#, 2);   --  reserved, 2 bytes per high byte
      Expect_Fixed (16#01FF#, 2);
      Expect_Fixed (16#0200#, 4);
      Expect_Fixed (16#0C00#, 24);  --  HeaderOp
      Expect_Fixed (16#7F00#, 254);
      Expect_Fixed (16#7FFF#, 254);
      Expect_Fixed (16#8000#, 0);   --  reserved
      Expect_Fixed (16#80FF#, 0);
   end Fixed_Lengths;

   procedure Structured_Rules (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Expect_Rule (16#0001#, Op.Region_Data);
      Expect_Rule (16#0011#, Op.Version_Data);
      Expect_Rule (16#0012#, Op.Pixel_Pattern_Data);
      Expect_Rule (16#0014#, Op.Pixel_Pattern_Data);
      Expect_Rule (16#0024#, Op.Word_Length_Data);
      Expect_Rule (16#002C#, Op.Word_Length_Data);
      Expect_Rule (16#002F#, Op.Word_Length_Data);
      Expect_Rule (16#0070#, Op.Polygon_Data);
      Expect_Rule (16#0077#, Op.Polygon_Data);
      Expect_Rule (16#0080#, Op.Region_Data);
      Expect_Rule (16#0087#, Op.Region_Data);
      Expect_Rule (16#0090#, Op.Bits_Data);
      Expect_Rule (16#0091#, Op.Bits_Data);
      Expect_Rule (16#0092#, Op.Word_Length_Data);
      Expect_Rule (16#0098#, Op.Bits_Data);
      Expect_Rule (16#009B#, Op.Bits_Data);
      Expect_Rule (16#009C#, Op.Word_Length_Data);
      Expect_Rule (16#00A1#, Op.Long_Comment_Data);
      Expect_Rule (16#00A2#, Op.Word_Length_Data);
      Expect_Rule (16#00AF#, Op.Word_Length_Data);
      Expect_Rule (16#00D0#, Op.Long_Length_Data);
      Expect_Rule (16#00FE#, Op.Long_Length_Data);
      Expect_Rule (16#00FF#, Op.End_Of_Picture);
      Expect_Rule (16#8100#, Op.Long_Length_Data);
      Expect_Rule (16#8200#, Op.Long_Length_Data);
      Expect_Rule (16#8201#, Op.Long_Length_Data);
      Expect_Rule (16#FFFF#, Op.Long_Length_Data);
      Assert (Op.Rule_For (16#0028#) = (Op.Text_Data, 4), "LongText carries a point first");
      Assert (Op.Rule_For (16#0029#) = (Op.Text_Data, 1), "DHText carries dh first");
      Assert (Op.Rule_For (16#002A#) = (Op.Text_Data, 1), "DVText carries dv first");
      Assert (Op.Rule_For (16#002B#) = (Op.Text_Data, 2), "DHDVText carries dh and dv first");
   end Structured_Rules;

   procedure Reserved_Ranges (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Reserved_Count : Natural := 0;
   begin
      for Code in Pictlib.Opcode loop
         if Op.Is_Reserved (Code) then
            Reserved_Count := Reserved_Count + 1;
         end if;
         Assert (Op.Is_Reserved (Code) = (Op.Name (Code) = "Reserved"),
                 "reserved flag and name disagree for opcode" & Code'Image);
      end loop;
      --  Every opcode above 16#00FF# is reserved except HeaderOp and the two QuickTime opcodes.
      Assert (not Op.Is_Reserved (16#0C00#) and then not Op.Is_Reserved (16#8200#)
              and then not Op.Is_Reserved (16#8201#), "defined high opcodes are not reserved");
      Assert (Op.Is_Reserved (16#0017#) and then Op.Is_Reserved (16#0035#) and then Op.Is_Reserved (16#003D#)
              and then Op.Is_Reserved (16#00A2#) and then Op.Is_Reserved (16#00FE#)
              and then Op.Is_Reserved (16#0100#) and then Op.Is_Reserved (16#FFFF#),
              "reserved ranges are not reserved");
      Assert (not Op.Is_Reserved (16#0000#) and then not Op.Is_Reserved (16#00A1#)
              and then not Op.Is_Reserved (16#00FF#) and then not Op.Is_Reserved (16#009B#),
              "defined opcodes are reserved");
      --  Below 16#100#: 16#17#..16#19#, 16#24#..16#27#, 16#2F#, three in each of the twelve shape half-groups,
      --  16#92#..16#97#, 16#9C#..16#9F# and 16#A2#..16#FE#. Above: all of 65_280 but three.
      Assert (Reserved_Count = 3 + 4 + 1 + 12 * 3 + 6 + 4 + 93 + 65_277,
              "reserved opcode count is" & Reserved_Count'Image);
   end Reserved_Ranges;

   procedure Names (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Op.Name (16#0011#) = "VersionOp", "VersionOp");
      Assert (Op.Name (16#0030#) = "frameRect", "frameRect");
      Assert (Op.Name (16#0034#) = "fillRect", "fillRect");
      Assert (Op.Name (16#003C#) = "fillSameRect", "fillSameRect");
      Assert (Op.Name (16#0043#) = "invertRRect", "invertRRect");
      Assert (Op.Name (16#0052#) = "eraseOval", "eraseOval");
      Assert (Op.Name (16#0061#) = "paintArc", "paintArc");
      Assert (Op.Name (16#0069#) = "paintSameArc", "paintSameArc");
      Assert (Op.Name (16#0071#) = "paintPoly", "paintPoly");
      Assert (Op.Name (16#0084#) = "fillRgn", "fillRgn");
      Assert (Op.Name (16#009A#) = "DirectBitsRect", "DirectBitsRect");
      Assert (Op.Name (16#00A1#) = "LongComment", "LongComment");
      Assert (Op.Name (16#00FF#) = "OpEndPic", "OpEndPic");
      Assert (Op.Name (16#0C00#) = "HeaderOp", "HeaderOp");
      Assert (Op.Name (16#8200#) = "CompressedQuickTime", "CompressedQuickTime");
   end Names;

   procedure Rect_Geometry (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Frame : constant Pictlib.Geometry.Rect := (Top => -10, Left => -20, Bottom => 30, Right => 40);
      Inverted : constant Pictlib.Geometry.Rect := (Top => 5, Left => 5, Bottom => 5, Right => 9);
      Extreme : constant Pictlib.Geometry.Rect := (Top => -32_768, Left => -32_768, Bottom => 32_767, Right => 32_767);
   begin
      Assert (Pictlib.Geometry.Width (Frame) = 60 and then Pictlib.Geometry.Height (Frame) = 40, "rect extent");
      Assert (not Pictlib.Geometry.Is_Empty (Frame), "a real rect is empty");
      Assert (Pictlib.Geometry.Is_Empty (Inverted), "a zero-height rect is not empty");
      Assert (Pictlib.Geometry.Width (Extreme) = 65_535, "extreme rect width overflowed");
   end Rect_Geometry;
end Pictlib_Testing.Test_Opcodes;
