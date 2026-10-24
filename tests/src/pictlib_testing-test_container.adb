with AUnit.Assertions;
with Interfaces;

with Pictlib;
with Pictlib.Decoding;
with Pictlib.Errors;
with Pictlib.Geometry;
with Pictlib.Limits;
with Pictlib.Metadata;
with Pictlib.Pictures;
with Pictlib.Results;
with Pictlib.Streams;
with Pictlib_Testing.Builders;
with Pictlib_Testing.Recorders;

package body Pictlib_Testing.Test_Container is
   use AUnit.Assertions;
   use Pictlib_Testing.Builders;
   use type Interfaces.Unsigned_16;
   use type Pictlib.Byte_Count;
   use type Pictlib.Decoding.Decoder_State;
   use type Pictlib.Errors.Error_Code;
   use type Pictlib.Geometry.Fixed;
   use type Pictlib.Geometry.Fixed_Rect;
   use type Pictlib.Geometry.Rect;
   use type Pictlib.Limit_Kind;
   use type Pictlib.Metadata.Item_Kind;
   use type Pictlib.Opcode;
   use type Pictlib.Opcode_Ordinal;
   use type Pictlib.PICT_Version;
   use type Pictlib.Source_Offset;
   use type Pictlib.Streams.Byte_Array;

   package Decoding renames Pictlib.Decoding;

   V1_Bare : aliased constant Bytes := V1_Prefix (0, 0, 10, 20, Size => 45) & B (16#FF#);
   V1_In_File : aliased constant Bytes := Text ("PICT") & Zeros (508) & V1_Bare;
   V2_In_File : aliased constant Bytes := Zeros (512) & V2_Prefix (2, 4, 12, 24) & W (16#00FF#);
   V2_Fixed_Bounds : aliased constant Bytes :=
     W (0) & Rect (0, 0, 10, 20) & W (16#0011#) & W (16#02FF#) & W (16#0C00#)
     & L (16#FFFF_FFFF#) & L (0) & L (0) & L (20 * 16#1_0000#) & L (10 * 16#1_0000#) & L (0) & W (16#00FF#);
   High_Resolution : aliased constant Bytes :=
     W (0) & Rect (0, 0, 10, 20) & W (16#0011#) & W (16#02FF#) & W (16#0C00#)
     & W (-2) & W (0) & L (144 * 16#1_0000#) & L (300 * 16#1_0000#) & Rect (0, 0, 20, 40) & L (0) & W (16#00FF#);
   Zero_Resolution : aliased constant Bytes :=
     W (0) & Rect (0, 0, 10, 20) & W (16#0011#) & W (16#02FF#) & W (16#0C00#)
     & W (-2) & W (0) & L (0) & L (72 * 16#1_0000#) & Rect (0, 0, 10, 20) & L (0) & W (16#00FF#);
   Unknown_Header_Version : aliased constant Bytes :=
     W (0) & Rect (0, 0, 10, 20) & W (16#0011#) & W (16#02FF#) & W (16#0C00#) & W (7) & Zeros (22) & W (16#00FF#);
   No_Header_Op : aliased constant Bytes :=
     W (0) & Rect (0, 0, 10, 20) & W (16#0011#) & W (16#02FF#) & W (16#001E#) & W (16#00FF#);
   Empty_Frame : aliased constant Bytes := V1_Prefix (5, 5, 5, 9) & B (16#FF#);
   Inverted_Frame : aliased constant Bytes := V1_Prefix (10, 0, 0, 20) & B (16#FF#);
   Wide_Frame : aliased constant Bytes := V1_Prefix (0, -10_000, 10, 10_000) & B (16#FF#);
   No_Version : aliased constant Bytes := W (0) & Rect (0, 0, 10, 20) & B (16#12#) & B (16#01#) & B (16#FF#);
   Too_Short : aliased constant Bytes := W (0) & Rect (0, 0, 10, 20);
   Truncated_Header_Op : aliased constant Bytes :=
     W (0) & Rect (0, 0, 10, 20) & W (16#0011#) & W (16#02FF#) & W (16#0C00#) & W (-2) & W (0);

   procedure Read_Only_Header
     (Input : aliased Bytes;
      Decoder : in out Decoding.Decoder;
      Outcome : out Pictlib.Results.Result;
      Options : Decoding.Options := (others => <>);
      Budget : Pictlib.Limits.Limit_Set := Pictlib.Limits.Default_Limits)
   is
      Events : Recorders.Recorder := (Stop_After => 1, others => <>);
   begin
      Recorders.Decode (Input, Decoder, Events, Outcome, Options, Budget);
   end Read_Only_Header;

   procedure Version_1_Without_File_Header (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure File_Header_Detection (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Explicit_File_Header_Policies (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Version_2_Fixed_Bounds (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Extended_Version_2_Resolution (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Invalid_Header_Op (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Missing_Header_Op (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Invalid_Frames (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Missing_Version (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure File_Header_Retention (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Header_Edges (T : in out AUnit.Test_Cases.Test_Case'Class);

   overriding function Name (T : Test) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("container");
   end Name;

   overriding procedure Register_Tests (T : in out Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Version_1_Without_File_Header'Access, "container.v1.bare");
      Register_Routine (T, File_Header_Detection'Access, "container.file_header.auto");
      Register_Routine (T, Explicit_File_Header_Policies'Access, "container.file_header.explicit");
      Register_Routine (T, Version_2_Fixed_Bounds'Access, "container.v2.fixed_bounds");
      Register_Routine (T, Extended_Version_2_Resolution'Access, "container.v2_extended.resolution");
      Register_Routine (T, Invalid_Header_Op'Access, "container.header_op.invalid");
      Register_Routine (T, Missing_Header_Op'Access, "container.header_op.missing");
      Register_Routine (T, Invalid_Frames'Access, "container.frame.invalid");
      Register_Routine (T, Missing_Version'Access, "container.version.missing");
      Register_Routine (T, File_Header_Retention'Access, "container.file_header.retention");
      Register_Routine (T, Header_Edges'Access, "container.header_edges");
   end Register_Tests;

   procedure Version_1_Without_File_Header (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Decoder : Decoding.Decoder;
      Outcome : Pictlib.Results.Result;
      Info : Pictlib.Pictures.Header_Info;
   begin
      Read_Only_Header (V1_Bare, Decoder, Outcome);
      Assert (Pictlib.Results.Succeeded (Outcome), "v1 header was rejected");
      Info := Decoding.Header (Decoder);
      Assert (Info.Version = Pictlib.Version_1 and then not Info.Has_File_Header, "v1 detection is wrong");
      Assert (Info.Picture_Size = 45, "picSize is wrong");
      Assert (Info.Frame = (Top => 0, Left => 0, Bottom => 10, Right => 20), "frame is wrong");
      Assert (Info.Source_Rect = Info.Frame, "source rect of a v1 picture is its frame");
      Assert (Info.Horizontal_Resolution = Pictlib.Geometry.Fixed_72, "v1 resolution is 72 dpi");
      Assert (not Info.Has_Header_Opcode, "v1 has no HeaderOp");
   end Version_1_Without_File_Header;

   procedure File_Header_Detection (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Decoder : Decoding.Decoder;
      Events : Recorders.Recorder;
      Outcome : Pictlib.Results.Result;
   begin
      Recorders.Decode (V1_In_File, Decoder, Events, Outcome);
      Assert (Pictlib.Results.Succeeded (Outcome), "v1 file was rejected");
      Assert (Decoding.Header (Decoder).Has_File_Header, "the file header was not detected");
      Assert (Events.Count = 2 and then Events.Events (1).Offset = 512 + 10,
              "the version opcode offset ignores the file header");

      Events := (others => <>);
      Recorders.Decode (V2_In_File, Decoder, Events, Outcome);
      Assert (Pictlib.Results.Succeeded (Outcome), "v2 file was rejected");
      Assert (Decoding.Header (Decoder).Has_File_Header, "the v2 file header was not detected");
      Assert (Decoding.Header (Decoder).Version = Pictlib.Extended_Version_2, "v2 file version is wrong");
      Assert (Decoding.Header (Decoder).Frame = (Top => 2, Left => 4, Bottom => 12, Right => 24), "v2 frame");
      Assert (Events.Count = 3, "v2 file has three opcodes");
   end File_Header_Detection;

   procedure Explicit_File_Header_Policies (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Decoder : Decoding.Decoder;
      Outcome : Pictlib.Results.Result;
   begin
      Read_Only_Header (V1_In_File, Decoder, Outcome, (File_Header => Pictlib.Has_File_Header, others => <>));
      Assert (Pictlib.Results.Succeeded (Outcome) and then Decoding.Header (Decoder).Has_File_Header,
              "an explicit file header was not honored");
      Read_Only_Header (V1_Bare, Decoder, Outcome, (File_Header => Pictlib.Has_File_Header, others => <>));
      Assert (Outcome.First_Error.Code = Pictlib.Errors.Version_Invalid,
              "a bare picture was accepted as a file");
      Read_Only_Header (V1_Bare, Decoder, Outcome, (File_Header => Pictlib.No_File_Header, others => <>));
      Assert (Pictlib.Results.Succeeded (Outcome) and then not Decoding.Header (Decoder).Has_File_Header,
              "an explicit bare picture was not honored");
      Read_Only_Header (V2_In_File, Decoder, Outcome, (File_Header => Pictlib.No_File_Header, others => <>));
      Assert (Outcome.First_Error.Code = Pictlib.Errors.Version_Invalid,
              "a file was accepted as a bare picture");
      Assert (Decoding.State (Decoder) = Decoding.Failed, "a rejected header must fail the decoder");
   end Explicit_File_Header_Policies;

   procedure Version_2_Fixed_Bounds (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Decoder : Decoding.Decoder;
      Outcome : Pictlib.Results.Result;
      Info : Pictlib.Pictures.Header_Info;
   begin
      Read_Only_Header (V2_Fixed_Bounds, Decoder, Outcome);
      Assert (Pictlib.Results.Succeeded (Outcome), "a version -1 HeaderOp was rejected");
      Info := Decoding.Header (Decoder);
      Assert (Info.Version = Pictlib.Version_2 and then Info.Has_Header_Opcode, "version 2 detection is wrong");
      Assert (Info.Fixed_Bounds = (Top => 0, Left => 0, Bottom => 10 * 16#1_0000#, Right => 20 * 16#1_0000#),
              "fixed bounds are wrong");
      Assert (Info.Horizontal_Resolution = Pictlib.Geometry.Fixed_72, "version 2 resolution is 72 dpi");
      Assert (Info.Source_Rect = Info.Frame, "version 2 source rect is the frame");
   end Version_2_Fixed_Bounds;

   procedure Extended_Version_2_Resolution (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Decoder : Decoding.Decoder;
      Outcome : Pictlib.Results.Result;
      Info : Pictlib.Pictures.Header_Info;
   begin
      Read_Only_Header (High_Resolution, Decoder, Outcome);
      Assert (Pictlib.Results.Succeeded (Outcome), "an extended header was rejected");
      Info := Decoding.Header (Decoder);
      Assert (Info.Version = Pictlib.Extended_Version_2, "extended version 2 detection is wrong");
      Assert (Info.Horizontal_Resolution = 144 * Pictlib.Geometry.Fixed_One
              and then Info.Vertical_Resolution = 300 * Pictlib.Geometry.Fixed_One,
              "resolution is wrong");
      Assert (Info.Source_Rect = (Top => 0, Left => 0, Bottom => 20, Right => 40), "source rect is wrong");

      Read_Only_Header (Zero_Resolution, Decoder, Outcome);
      Assert (Outcome.First_Error.Code = Pictlib.Errors.Header_Invalid
              and then Outcome.First_Error.Context.Op = 16#0C00#,
              "a zero resolution was accepted strictly");
      Read_Only_Header (Zero_Resolution, Decoder, Outcome, (Strictness => Pictlib.Compatible, others => <>));
      Assert (Pictlib.Results.Succeeded (Outcome)
              and then Decoding.Header (Decoder).Horizontal_Resolution = Pictlib.Geometry.Fixed_72,
              "a compatible decoder did not fall back to 72 dpi");
      Assert (Recorders.Has_Warning (Decoder, Pictlib.Errors.Compatibility_Issue), "the fallback was not reported");
   end Extended_Version_2_Resolution;

   procedure Invalid_Header_Op (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Decoder : Decoding.Decoder;
      Events : Recorders.Recorder;
      Outcome : Pictlib.Results.Result;
   begin
      Read_Only_Header (Unknown_Header_Version, Decoder, Outcome);
      Assert (Outcome.First_Error.Code = Pictlib.Errors.Header_Invalid, "an unknown header version was accepted");
      Recorders.Decode (Unknown_Header_Version, Decoder, Events, Outcome,
                        (Strictness => Pictlib.Compatible, others => <>));
      Assert (Pictlib.Results.Succeeded (Outcome), "a compatible decoder rejected an unknown header version");
      Assert (Decoding.Header (Decoder).Version = Pictlib.Version_2, "an unknown header is treated as version 2");
      Assert (Events.Count = 3 and then Events.Events (3).Op = 16#00FF#, "the stream after it was lost");

      Read_Only_Header (Truncated_Header_Op, Decoder, Outcome, (Strictness => Pictlib.Recover_When_Safe, others => <>));
      Assert (Outcome.First_Error.Code = Pictlib.Errors.Source_Unexpected_End
              and then Outcome.First_Error.Context.Op = 16#0C00#,
              "a truncated HeaderOp was not reported with its opcode");
   end Invalid_Header_Op;

   procedure Missing_Header_Op (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Decoder : Decoding.Decoder;
      Events : Recorders.Recorder;
      Outcome : Pictlib.Results.Result;
   begin
      Read_Only_Header (No_Header_Op, Decoder, Outcome);
      Assert (Outcome.First_Error.Code = Pictlib.Errors.Header_Invalid
              and then Outcome.First_Error.Context.Op = 16#001E#,
              "a version 2 picture without HeaderOp was accepted strictly");

      Recorders.Decode (No_Header_Op, Decoder, Events, Outcome, (Strictness => Pictlib.Compatible, others => <>));
      Assert (Pictlib.Results.Succeeded (Outcome), "a compatible decoder rejected a missing HeaderOp");
      Assert (not Decoding.Header (Decoder).Has_Header_Opcode, "a HeaderOp was invented");
      Assert (Events.Count = 3, "the opcode read in place of HeaderOp was lost");
      Assert (Events.Events (2).Op = 16#001E# and then Events.Events (2).Offset = 14
              and then Events.Events (2).Ordinal = 1,
              "the opcode read in place of HeaderOp is reported wrongly");
      Assert (Events.Events (3).Op = 16#00FF# and then Events.Events (3).Offset = 16, "the end opcode is misplaced");
      Assert (Recorders.Has_Warning (Decoder, Pictlib.Errors.Compatibility_Issue),
              "the missing HeaderOp was not reported");
   end Missing_Header_Op;

   procedure Invalid_Frames (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Decoder : Decoding.Decoder;
      Outcome : Pictlib.Results.Result;
   begin
      Read_Only_Header (Empty_Frame, Decoder, Outcome, (Strictness => Pictlib.Recover_When_Safe, others => <>));
      Assert (Outcome.First_Error.Code = Pictlib.Errors.Header_Invalid, "an empty frame was accepted");
      Read_Only_Header (Inverted_Frame, Decoder, Outcome);
      Assert (Outcome.First_Error.Code = Pictlib.Errors.Header_Invalid, "an inverted frame was accepted");
      Read_Only_Header (Wide_Frame, Decoder, Outcome);
      Assert (Outcome.First_Error.Code = Pictlib.Errors.Limit_Exceeded
              and then Outcome.First_Error.Context.Limit = Pictlib.Frame_Width_Limit
              and then Outcome.First_Error.Context.Actual = 20_000,
              "a frame wider than the limit was accepted");
      Read_Only_Header
        (V1_Bare, Decoder, Outcome, Budget => (Pictlib.Limits.Default_Limits with delta Max_Frame_Height => 9));
      Assert (Outcome.First_Error.Code = Pictlib.Errors.Limit_Exceeded
              and then Outcome.First_Error.Context.Limit = Pictlib.Frame_Height_Limit,
              "a frame taller than the limit was accepted");
   end Invalid_Frames;

   procedure Missing_Version (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Decoder : Decoding.Decoder;
      Outcome : Pictlib.Results.Result;
   begin
      Read_Only_Header (No_Version, Decoder, Outcome, (Strictness => Pictlib.Recover_When_Safe, others => <>));
      Assert (Outcome.First_Error.Code = Pictlib.Errors.Version_Invalid, "a picture without version was accepted");
      Read_Only_Header (Too_Short, Decoder, Outcome);
      Assert (Outcome.First_Error.Code = Pictlib.Errors.Version_Invalid, "a picture without version was accepted");
   end Missing_Version;

   procedure File_Header_Retention (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Decoder : Decoding.Decoder;
      Outcome : Pictlib.Results.Result;
      Retain : constant Decoding.Options :=
        (Retention => (File_Headers => True, others => <>), others => <>);
      Data : Bytes (1 .. 512);
      Count : Pictlib.Byte_Count;
   begin
      Read_Only_Header (V1_In_File, Decoder, Outcome, Retain);
      Assert (Pictlib.Results.Succeeded (Outcome), "a retained file header failed");
      Assert (Decoding.Metadata_Count (Decoder) = 1
              and then Decoding.Metadata_Item (Decoder, 1).Kind = Pictlib.Metadata.File_Header
              and then Decoding.Metadata_Item (Decoder, 1).Data_Length = 512
              and then Decoding.Metadata_Item (Decoder, 1).Offset = 0,
              "the file header was not retained");
      Outcome := Decoding.Copy_Metadata (Decoder, 1, Data, Count);
      Assert (Pictlib.Results.Succeeded (Outcome) and then Count = 512 and then Data (1 .. 4) = Text ("PICT"),
              "the retained file header has the wrong bytes");

      Read_Only_Header (V1_In_File, Decoder, Outcome);
      Assert (Decoding.Metadata_Count (Decoder) = 0, "the file header is retained by default");

      Read_Only_Header (V1_In_File, Decoder, Outcome, Retain,
                        (Pictlib.Limits.Default_Limits with delta Max_Retained_Metadata_Bytes => 511));
      Assert (Outcome.First_Error.Code = Pictlib.Errors.Limit_Exceeded
              and then Outcome.First_Error.Context.Limit = Pictlib.Retained_Metadata_Byte_Limit,
              "a file header over the metadata budget was retained");
   end File_Header_Retention;

   procedure Header_Edges (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  A version 2 picture that ends right after its version opcode, at an opcode boundary.
      Version_Only : aliased constant Bytes := W (0) & Rect (0, 0, 10, 20) & W (16#0011#) & W (16#02FF#);
      --  A wrong picSize, 7 for a 13-byte picture: retained, never checked, in every mode.
      Wrong_Size : aliased constant Bytes := V1_Prefix (0, 0, 10, 20, Size => 7) & B (16#FF#);
      --  A picture exactly as long as the byte budget, then one trailing byte.
      Trailing : aliased constant Bytes := V1_Bare & B (0);
      Decoder : Decoding.Decoder;
      Events : Recorders.Recorder;
      Outcome : Pictlib.Results.Result;
      Budget : Pictlib.Limits.Limit_Set := Pictlib.Limits.Default_Limits;
   begin
      Recorders.Decode (Version_Only, Decoder, Events, Outcome);
      Assert (Outcome.First_Error.Code = Pictlib.Errors.Header_Invalid
              and then Outcome.First_Error.Context.Op = 16#0C00#
              and then Outcome.First_Error.Context.Ordinal = 1,
              "a version 2 picture ending after its version, strictly: " & Outcome.First_Error.Code'Image);
      Recorders.Decode (Version_Only, Decoder, Events, Outcome, (Strictness => Pictlib.Compatible, others => <>));
      Assert (Pictlib.Results.Succeeded (Outcome)
              and then Recorders.Has_Warning (Decoder, Pictlib.Errors.Compatibility_Issue),
              "a version 2 picture ending after its version, leniently: " & Outcome.First_Error.Code'Image);

      Recorders.Decode (Wrong_Size, Decoder, Events, Outcome);
      Assert (Pictlib.Results.Succeeded (Outcome) and then Decoding.Header (Decoder).Picture_Size = 7,
              "a wrong picSize was checked or not retained");

      Budget.Max_Picture_Bytes := V1_Bare'Length;
      Recorders.Decode (Trailing, Decoder, Events, Outcome, (Require_End_Of_Input => True, others => <>), Budget);
      Assert (Outcome.First_Error.Code = Pictlib.Errors.Trailing_Data,
              "a trailing byte after a picture that used its whole byte budget: " & Outcome.First_Error.Code'Image);

      --  A byte budget too small to see the version past a file header is the limit, not a bad version.
      Budget.Max_Picture_Bytes := 520;
      Read_Only_Header (V2_In_File, Decoder, Outcome, Budget => Budget);
      Assert (Outcome.First_Error.Code = Pictlib.Errors.Limit_Exceeded
              and then Outcome.First_Error.Context.Limit = Pictlib.Picture_Byte_Limit,
              "a byte budget that cuts the look-ahead short: " & Outcome.First_Error.Code'Image);

      --  A HeaderOp cut short names HeaderOp and its ordinal.
      Recorders.Decode (Truncated_Header_Op, Decoder, Events, Outcome);
      Assert (Outcome.First_Error.Code = Pictlib.Errors.Source_Unexpected_End
              and then Outcome.First_Error.Context.Has_Opcode and then Outcome.First_Error.Context.Op = 16#0C00#
              and then Outcome.First_Error.Context.Ordinal = 1,
              "a HeaderOp cut short is not attributed to it");
   end Header_Edges;
end Pictlib_Testing.Test_Container;
