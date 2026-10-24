with AUnit.Assertions;
with Jpeglib;
with Jpeglib.Decoding;
with Jpeglib.Images;
with Jpeglib.Limits;
with Jpeglib.Results;
with Jpeglib.Streams;

with Pictlib;
with Pictlib.Decoding;
with Pictlib.Errors;
with Pictlib.Images;
with Pictlib.Limits;
with Pictlib.Results;
with Pictlib.Streams;
with Pictlib_Testing.Builders;
with Pictlib_Testing.Canvases;
with Pictlib_Testing.Files;
with Pictlib_Testing.Recorders;

package body Pictlib_Testing.Test_QuickTime is
   use AUnit.Assertions;
   use Pictlib_Testing.Builders;
   use type Pictlib.Errors.Error_Code;
   use type Pictlib.Images.RGB_Color;
   use type Pictlib.Limit_Kind;
   use type Pictlib.Streams.Byte_Array;

   package Errors renames Pictlib.Errors;

   --  small.jpg is 8x6; small_decoded.ppm is libjpeg's decoding of it.
   Image_Width : constant := 8;
   Image_Height : constant := 6;
   Decoder_Tolerance : constant := 2;

   function JPEG return Bytes is (Files.Load ("external/small.jpg").all);

   --  The expected pixel at X, Y: the reference at Map (X, Y), or white where nothing is drawn.
   type Mapping is access function (X, Y : Natural; Source_X, Source_Y : out Natural) return Boolean;

   procedure Expect
     (Input : aliased Bytes;
      Width, Height : Positive;
      Map : Mapping;
      Label : String;
      Options : Pictlib.Decoding.Options := (others => <>))
   is
      Reference : constant Files.Raster := Files.Load_Raster ("external/small_decoded.ppm");
      Storage : aliased Bytes := [1 .. 3 * Width * Height => 16#EE#];
      Output : constant Pictlib.Images.Mutable_Image_View := Canvases.View (Storage'Access, Width, Height);
      Decoder : Pictlib.Decoding.Decoder;
      Outcome : Pictlib.Results.Result;
      Wrong : Natural := 0;
   begin
      Canvases.Render (Input, Decoder, Output, Outcome, Options);
      Assert (Pictlib.Results.Succeeded (Outcome), Label & ": render failed with " & Outcome.First_Error.Code'Image);
      for Y in 0 .. Height - 1 loop
         for X in 0 .. Width - 1 loop
            declare
               Source_X, Source_Y : Natural;
               Got : constant Pictlib.Images.RGB_Color := Canvases.Pixel (Output, X, Y);
            begin
               if Map (X, Y, Source_X, Source_Y) then
                  declare
                     Want : constant Pictlib.Images.RGB_Color := Files.Pixel (Reference, Source_X, Source_Y);
                  begin
                     if abs (Integer (Got.Red) - Integer (Want.Red)) > Decoder_Tolerance
                       or else abs (Integer (Got.Green) - Integer (Want.Green)) > Decoder_Tolerance
                       or else abs (Integer (Got.Blue) - Integer (Want.Blue)) > Decoder_Tolerance
                     then
                        Wrong := Wrong + 1;
                     end if;
                  end;
               elsif Got /= Pictlib.Images.White then
                  Wrong := Wrong + 1;
               end if;
            end;
         end loop;
      end loop;
      Assert (Wrong = 0, Label & ":" & Wrong'Image & " pixels wrong");
   end Expect;

   function Identity (X, Y : Natural; Source_X, Source_Y : out Natural) return Boolean is
   begin
      Source_X := X;
      Source_Y := Y;
      return X < Image_Width and then Y < Image_Height;
   end Identity;

   function Moved (X, Y : Natural; Source_X, Source_Y : out Natural) return Boolean is
      Inside : constant Boolean := X in 2 .. 2 + Image_Width - 1 and then Y in 1 .. Image_Height;
   begin
      Source_X := (if Inside then X - 2 else 0);
      Source_Y := (if Inside then Y - 1 else 0);
      return Inside;
   end Moved;

   function Doubled (X, Y : Natural; Source_X, Source_Y : out Natural) return Boolean is
   begin
      Source_X := X / 2;
      Source_Y := Y / 2;
      return True;
   end Doubled;

   function Top_Left (X, Y : Natural; Source_X, Source_Y : out Natural) return Boolean is
   begin
      Source_X := X;
      Source_Y := Y;
      return X < 4 and then Y < 3;
   end Top_Left;

   function Top_Rows (X, Y : Natural; Source_X, Source_Y : out Natural) return Boolean is
   begin
      Source_X := X;
      Source_Y := Y;
      return Y < 3;
   end Top_Rows;

   function Nothing (X, Y : Natural; Source_X, Source_Y : out Natural) return Boolean is
   begin
      Source_X := X;
      Source_Y := Y;
      return False;
   end Nothing;

   function Image (Data : Bytes; Width, Height : Positive; Extra : Bytes := [1 .. 0 => 0]) return Bytes is
     (V2_Picture (0, 0, Height, Width, Data & Extra));
   function Plain (Data : Bytes := JPEG) return Bytes is
     (QuickTime ("jpeg", Image_Width, Image_Height, Data));

   procedure Placement (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Masks_And_Modes (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Placeholder_Bitmap (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Unsupported_Images (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Broken_Images (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Limits (T : in out AUnit.Test_Cases.Test_Case'Class);

   overriding function Name (T : Test) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("quicktime");
   end Name;

   overriding procedure Register_Tests (T : in out Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Placement'Access, "quicktime.placement");
      Register_Routine (T, Masks_And_Modes'Access, "quicktime.masks_and_modes");
      Register_Routine (T, Placeholder_Bitmap'Access, "quicktime.placeholder_bitmap");
      Register_Routine (T, Unsupported_Images'Access, "quicktime.unsupported");
      Register_Routine (T, Broken_Images'Access, "quicktime.broken");
      Register_Routine (T, Limits'Access, "quicktime.limits");
   end Register_Tests;

   procedure Placement (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Identity_Picture : aliased constant Bytes := Image (Plain, Image_Width, Image_Height);
      Moved_Picture : aliased constant Bytes :=
        Image (QuickTime ("jpeg", Image_Width, Image_Height, JPEG, Move_H => 2 * 16#1_0000#,
                          Move_V => 16#1_0000#), 12, 8);
      Doubled_Picture : aliased constant Bytes :=
        Image (QuickTime ("jpeg", Image_Width, Image_Height, JPEG, Scale_H => 2 * 16#1_0000#,
                          Scale_V => 2 * 16#1_0000#), 16, 12);
      Part_Picture : aliased constant Bytes :=
        Image (QuickTime ("jpeg", Image_Width, Image_Height, JPEG, Source => Rect (0, 0, 3, 4)), 8, 6);
      Origin_Picture : aliased constant Bytes :=
        Image (W (16#0C#) & W (-2) & W (-1) & Plain, 12, 8);
      Longer_Description : aliased constant Bytes :=
        Image (QuickTime ("jpeg", Image_Width, Image_Height, JPEG, Description_Size => 90), 8, 6);
      Trailing_Bytes : aliased constant Bytes := Image (Plain (JPEG & Zeros (4)), 8, 6);
   begin
      Expect (Identity_Picture, Image_Width, Image_Height, Identity'Access, "identity matrix");
      Expect (Moved_Picture, 12, 8, Moved'Access, "translation");
      Expect (Doubled_Picture, 16, 12, Doubled'Access, "scaling");
      Expect (Part_Picture, 8, 6, Top_Left'Access, "srcRect");
      Expect (Origin_Picture, 12, 8, Moved'Access, "the origin moves the image");
      Expect (Longer_Description, 8, 6, Identity'Access, "a longer ImageDescription");
      Expect (Trailing_Bytes, 8, 6, Identity'Access, "bytes after the JPEG");
   end Placement;

   procedure Masks_And_Modes (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Masked : aliased constant Bytes :=
        Image (QuickTime ("jpeg", Image_Width, Image_Height, JPEG, Mask => Region (0, 0, 3, 8)), 8, 6);
      Clipped : aliased constant Bytes := Image (W (16#01#) & Region (0, 0, 3, 8) & Plain, 8, 6);
      Copied : aliased constant Bytes :=
        Image (QuickTime ("jpeg", Image_Width, Image_Height, JPEG, Mode => 0), 8, 6);
      Bad_Mode : aliased constant Bytes :=
        Image (QuickTime ("jpeg", Image_Width, Image_Height, JPEG, Mode => 20), 8, 6);
      Short_Mask : aliased constant Bytes :=
        Image (QuickTime ("jpeg", Image_Width, Image_Height, JPEG, Mask => Region (0, 0, 3, 8) & Zeros (2)), 8, 6);
   begin
      Expect (Masked, 8, 6, Top_Rows'Access, "mask region");
      Expect (Clipped, 8, 6, Top_Rows'Access, "clip region");
      Expect (Copied, 8, 6, Identity'Access, "srcCopy");
      Canvases.Expect_Failure (Bad_Mode, 8, 6, Errors.Transfer_Mode_Invalid, "mode 20", 16#8200#);
      Canvases.Expect_Failure (Short_Mask, 8, 6, Errors.Region_Invalid, "maskSize disagrees", 16#8200#);
   end Masks_And_Modes;

   --  A black placeholder BitMap after the image, as QuickTime writes for systems without the codec.
   procedure Placeholder_Bitmap (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Placeholder : constant Bytes :=
        W (16#98#) & W (2) & Rect (0, 0, 6, 8) & Rect (0, 0, 6, 8) & Rect (0, 0, 6, 8) & W (0)
        & [1 .. 12 => 16#FF#];
      After_Image : aliased constant Bytes := Image (Plain & Placeholder, 8, 6);
      After_Unsupported : aliased constant Bytes :=
        Image (QuickTime ("rle ", Image_Width, Image_Height, [1, 2, 3]) & Placeholder, 8, 6);
      Not_Next : aliased constant Bytes := Image (Plain & W (16#00A0#) & W (0) & Placeholder, 8, 6);
      --  An image drawn, then one that is not: only the second one's placeholder follows, and it is drawn.
      Drawn_Then_Not : aliased constant Bytes :=
        Image (Plain & QuickTime ("rle ", Image_Width, Image_Height, [1, 2, 3]) & Placeholder, 8, 6);
   begin
      Expect (After_Image, 8, 6, Identity'Access, "the placeholder after an image is skipped");
      Canvases.Expect_Raster (After_Unsupported, 8, 6, "BBBBBBBB/BBBBBBBB/BBBBBBBB/BBBBBBBB/BBBBBBBB/BBBBBBBB",
                              "the placeholder stands in for an image not drawn",
                              (Strictness => Pictlib.Compatible, others => <>));
      Canvases.Expect_Raster (Not_Next, 8, 6, "BBBBBBBB/BBBBBBBB/BBBBBBBB/BBBBBBBB/BBBBBBBB/BBBBBBBB",
                              "only the opcode right after the image is skipped");
      --  The placeholder's six rows are skipped at a unit each, whatever the image cost.
      declare
         Alone : aliased constant Bytes := Image (Plain, 8, 6);
         Storage : aliased Bytes := [1 .. 3 * 48 => 0];
         Decoder : Pictlib.Decoding.Decoder;
         Outcome : Pictlib.Results.Result;
         Budget : Pictlib.Limits.Limit_Set := Pictlib.Limits.Default_Limits;
         Low : Pictlib.Pixel_Count := 0;
         High : Pictlib.Pixel_Count := 1_000_000;
         use type Pictlib.Pixel_Count;
      begin
         while Low < High loop
            Budget.Max_Drawing_Work := (Low + High) / 2;
            Canvases.Render (Alone, Decoder, Canvases.View (Storage'Access, 8, 6), Outcome, Budget => Budget);
            if Pictlib.Results.Succeeded (Outcome) then
               High := Budget.Max_Drawing_Work;
            else
               Low := Budget.Max_Drawing_Work + 1;
            end if;
         end loop;
         Budget.Max_Drawing_Work := High + 5;
         Canvases.Render (After_Image, Decoder, Canvases.View (Storage'Access, 8, 6), Outcome, Budget => Budget);
         Assert (Outcome.First_Error.Code = Errors.Limit_Exceeded, "the placeholder cost less than its rows");
         Budget.Max_Drawing_Work := High + 6;
         Canvases.Render (After_Image, Decoder, Canvases.View (Storage'Access, 8, 6), Outcome, Budget => Budget);
         Assert (Pictlib.Results.Succeeded (Outcome), "the placeholder cost more than its rows: "
                 & Outcome.First_Error.Code'Image);
      end;
      Canvases.Expect_Raster (Drawn_Then_Not, 8, 6, "BBBBBBBB/BBBBBBBB/BBBBBBBB/BBBBBBBB/BBBBBBBB/BBBBBBBB",
                              "a drawn image does not hide a later placeholder",
                              (Strictness => Pictlib.Compatible, others => <>));
   end Placeholder_Bitmap;

   procedure Unsupported_Images (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Other_Codec : aliased constant Bytes := Image (QuickTime ("rle ", 8, 6, [1, 2, 3]), 8, 6);
      Rotated : aliased constant Bytes :=
        Image (QuickTime ("jpeg", Image_Width, Image_Height, JPEG, Skew => 16#1_0000#), 8, 6);
      With_Matte : aliased constant Bytes :=
        Image (QuickTime ("jpeg", Image_Width, Image_Height, JPEG, Matte => Zeros (8)), 8, 6);
      Storage : aliased Bytes := [1 .. 3 * 48 => 0];
      Decoder : Pictlib.Decoding.Decoder;
      Outcome : Pictlib.Results.Result;
   begin
      Canvases.Expect_Failure (Other_Codec, 8, 6, Errors.Unsupported_Feature, "codec rle", 16#8200#);
      Canvases.Expect_Failure (Rotated, 8, 6, Errors.Unsupported_Feature, "a skewing matrix", 16#8200#);
      Canvases.Expect_Failure (With_Matte, 8, 6, Errors.Unsupported_Feature, "a matte", 16#8200#);
      Expect (Other_Codec, 8, 6, Nothing'Access, "codec rle, skipped",
              (Strictness => Pictlib.Compatible, others => <>));
      Expect (With_Matte, 8, 6, Identity'Access, "a matte, ignored", (Strictness => Pictlib.Compatible, others => <>));
      Canvases.Render (Other_Codec, Decoder, Canvases.View (Storage'Access, 8, 6), Outcome,
                       (Strictness => Pictlib.Compatible, others => <>));
      Assert (Recorders.Has_Warning (Decoder, Errors.Approximated_Rendering), "a skipped image was not reported");
   end Unsupported_Images;

   procedure Broken_Images (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Whole : constant Bytes := JPEG;
      Truncated : aliased constant Bytes := Image (Plain (Whole (1 .. 100)), 8, 6);
      Garbage : aliased constant Bytes := Image (Plain (Text ("not a JPEG")), 8, 6);
      Wrong_Size : aliased constant Bytes := Image (QuickTime ("jpeg", 9, 6, Whole), 9, 6);
      Short_Description : aliased constant Bytes :=
        Image (QuickTime ("jpeg", Image_Width, Image_Height, Whole, Description_Size => 80), 8, 6);
      Overlong : constant Bytes := Plain (Whole);
      --  dataSize claims more than the opcode holds.
      Past_The_Opcode : aliased constant Bytes :=
        Image (Overlong (1 .. 6 + 68 + 44) & L (100_000) & Overlong (6 + 68 + 49 .. Overlong'Last), 8, 6);
      Storage : aliased Bytes := [1 .. 3 * 48 => 0];
      Decoder : Pictlib.Decoding.Decoder;
      Outcome : Pictlib.Results.Result;
   begin
      Canvases.Expect_Failure (Truncated, 8, 6, Errors.Embedded_Image_Failed, "truncated JPEG", 16#8200#);
      Canvases.Expect_Failure (Garbage, 8, 6, Errors.Embedded_Image_Failed, "not a JPEG", 16#8200#);
      Canvases.Expect_Failure (Wrong_Size, 9, 6, Errors.Embedded_Image_Failed, "description size disagrees",
                               16#8200#);
      Canvases.Expect_Failure (Short_Description, 8, 6, Errors.Opcode_Length_Invalid, "idSize 80", 16#8200#);
      Canvases.Expect_Failure (Past_The_Opcode, 8, 6, Errors.Opcode_Length_Invalid, "dataSize too large", 16#8200#);
      Canvases.Render (Truncated, Decoder, Canvases.View (Storage'Access, 8, 6), Outcome,
                       (Strictness => Pictlib.Recover_When_Safe, others => <>));
      Assert (Pictlib.Results.Succeeded (Outcome) and then Recorders.Has_Warning (Decoder, Errors.Partial_Picture),
              "a broken JPEG did not leave a partial picture");
      Assert (Pictlib.Decoding.Last_Error (Decoder).Code = Errors.No_Error, "a recovered picture reports failure");
   end Broken_Images;

   procedure Limits (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Picture : aliased constant Bytes := Image (Plain, 8, 6);
      Defaults : constant Pictlib.Limits.Limit_Set := Pictlib.Limits.Default_Limits;
      Storage : aliased Bytes := [1 .. 3 * 48 => 0];
      Decoder : Pictlib.Decoding.Decoder;
      Outcome : Pictlib.Results.Result;
   begin
      Canvases.Render (Picture, Decoder, Canvases.View (Storage'Access, 8, 6), Outcome,
                       Budget => (Defaults with delta Max_Embedded_Image_Pixels => 47));
      Assert (Outcome.First_Error.Code = Errors.Limit_Exceeded
              and then Outcome.First_Error.Context.Limit = Pictlib.Embedded_Image_Pixel_Limit,
              "the embedded pixel limit was not enforced");
      Canvases.Render (Picture, Decoder, Canvases.View (Storage'Access, 8, 6), Outcome,
                       Budget => (Defaults with delta Max_Embedded_Image_Bytes => 100));
      Assert (Outcome.First_Error.Code = Errors.Limit_Exceeded
              and then Outcome.First_Error.Context.Limit = Pictlib.Embedded_Image_Byte_Limit,
              "the embedded byte limit was not enforced");
      Canvases.Render (Picture, Decoder, Canvases.View (Storage'Access, 8, 6), Outcome,
                       Budget => (Defaults with delta Max_Allocation_Bytes => 100));
      Assert (Outcome.First_Error.Code = Errors.Limit_Exceeded
              and then Outcome.First_Error.Context.Limit = Pictlib.Allocation_Byte_Limit,
              "the allocation limit was not enforced");
      --  The decoded pixels and jpeglib's own buffers share the one budget: the least budget the picture renders
      --  under is the least jpeglib decodes the JPEG under, measured through jpeglib's own API, plus the 144
      --  bytes of pixels, where jpeglib used to be given the whole budget again.
      declare
         use type Pictlib.Byte_Count;
         use type Jpeglib.Byte_Count;
         Data : constant Jpeglib.Streams.Const_Byte_Array_Access :=
           new Jpeglib.Streams.Byte_Array'([for Item of JPEG => Jpeglib.Byte (Item)]);
         Pixels : constant Jpeglib.Streams.Byte_Array_Access := new Jpeglib.Streams.Byte_Array (1 .. 144);

         function Jpeglib_Decodes (Budget : Jpeglib.Byte_Count) return Boolean is
            Source : aliased Jpeglib.Streams.Memory_Source;
            Alone : Jpeglib.Decoding.Decoder;
            Result : Jpeglib.Results.Result;
            View : Jpeglib.Images.Mutable_Image_View :=
              (Descriptor => (Width => 8, Height => 6, Format => Jpeglib.Images.RGB_24, Stride => 24,
                              Accessible_Bytes => 144),
               Storage => Pixels);
         begin
            Jpeglib.Streams.Open (Source, Data);
            Jpeglib.Decoding.Initialize
              (Alone, Source'Unchecked_Access, (Output_Format => Jpeglib.Images.RGB_24, others => <>),
               (Jpeglib.Limits.Default_Limits with delta Max_Allocation_Bytes => Budget));
            Result := Jpeglib.Decoding.Read_Header (Alone);
            if Jpeglib.Results.Succeeded (Result) then
               Result := Jpeglib.Decoding.Decode_Image (Alone, View);
            end if;
            Jpeglib.Decoding.Finalize (Alone);
            return Jpeglib.Results.Succeeded (Result);
         end Jpeglib_Decodes;

         function Pictlib_Renders (Budget : Pictlib.Byte_Count) return Boolean is
         begin
            Canvases.Render (Picture, Decoder, Canvases.View (Storage'Access, 8, 6), Outcome,
                             Budget => (Defaults with delta Max_Allocation_Bytes => Budget));
            return Pictlib.Results.Succeeded (Outcome);
         end Pictlib_Renders;

         Low, High, Middle : Jpeglib.Byte_Count;
         Least_Jpeglib : Jpeglib.Byte_Count;
      begin
         Low := 0;
         High := 1_048_576;
         while Low < High loop
            Middle := (Low + High) / 2;
            if Jpeglib_Decodes (Middle) then
               High := Middle;
            else
               Low := Middle + 1;
            end if;
         end loop;
         Least_Jpeglib := High;
         Assert (Pictlib_Renders (Pictlib.Byte_Count (Least_Jpeglib) + 144)
                 and then not Pictlib_Renders (Pictlib.Byte_Count (Least_Jpeglib) + 143),
                 "the pixels and jpeglib do not share the allocation budget (jpeglib alone needs"
                 & Least_Jpeglib'Image & ")");
      end;
   end Limits;
end Pictlib_Testing.Test_QuickTime;
