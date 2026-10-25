with AUnit.Assertions;

with Pictlib;
with Pictlib.Decoding;
with Pictlib.Images;
with Pictlib.Results;
with Pictlib.Streams;
with Pictlib_Testing.Canvases;
with Pictlib_Testing.Files;

package body Pictlib_Testing.Test_External is
   use AUnit.Assertions;

   --  Render Picture_Name and require the pixels of Source_Name, each component within Tolerance.
   procedure Expect_Source (Picture_Name, Source_Name : String; Tolerance : Natural := 0) is
      Picture : constant Files.Bytes_Access := Files.Load ("external/" & Picture_Name);
      Source : constant Files.Raster := Files.Load_Raster ("external/" & Source_Name);
      Storage : aliased Pictlib.Streams.Byte_Array := [1 .. 3 * Source.Width * Source.Height => 16#EE#];
      Output : constant Pictlib.Images.Mutable_Image_View :=
        Canvases.View (Storage'Access, Source.Width, Source.Height);
      Decoder : Pictlib.Decoding.Decoder;
      Outcome : Pictlib.Results.Result;
      Wrong : Natural := 0;
      Largest : Natural := 0;
   begin
      Canvases.Render (Picture.all, Decoder, Output, Outcome);
      Assert (Pictlib.Results.Succeeded (Outcome),
              Picture_Name & ": render failed with " & Outcome.First_Error.Code'Image & " at opcode"
              & Outcome.First_Error.Context.Op'Image & " offset" & Outcome.First_Error.Context.Source'Image);
      for Y in 0 .. Source.Height - 1 loop
         for X in 0 .. Source.Width - 1 loop
            declare
               Got : constant Pictlib.Images.RGB_Color := Canvases.Pixel (Output, X, Y);
               Want : constant Pictlib.Images.RGB_Color := Files.Pixel (Source, X, Y);
               Difference : constant Natural := Canvases.Difference (Got, Want);
            begin
               Largest := Natural'Max (Largest, Difference);
               if Difference > Tolerance then
                  Wrong := Wrong + 1;
               end if;
            end;
         end loop;
      end loop;
      Assert (Wrong = 0, Picture_Name & ":" & Wrong'Image & " pixels differ from " & Source_Name
              & " by more than" & Tolerance'Image & "; largest difference" & Largest'Image);
   end Expect_Source;

   procedure Netpbm_Indexed (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure ImageMagick_Direct (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure ImageMagick_QuickTime (T : in out AUnit.Test_Cases.Test_Case'Class);

   overriding function Name (T : Test) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("external");
   end Name;

   overriding procedure Register_Tests (T : in out Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Netpbm_Indexed'Access, "external.netpbm.indexed");
      Register_Routine (T, ImageMagick_Direct'Access, "external.imagemagick.direct");
      Register_Routine (T, ImageMagick_QuickTime'Access, "external.imagemagick.quicktime_jpeg");
   end Register_Tests;

   procedure Netpbm_Indexed (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Expect_Source ("palette_netpbm.pict", "palette.ppm");
   end Netpbm_Indexed;

   procedure ImageMagick_Direct (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Expect_Source ("palette_magick.pict", "palette.ppm");
      Expect_Source ("truecolor_magick.pict", "truecolor.ppm");
      Expect_Source ("mono_magick.pict", "mono.pbm");
   end ImageMagick_Direct;

   procedure ImageMagick_QuickTime (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Expect_Source ("truecolor_jpeg.pict", "truecolor_embedded.ppm", Canvases.JPEG_Decoder_Tolerance);
      Expect_Source ("palette_jpeg.pict", "palette_embedded.ppm", Canvases.JPEG_Decoder_Tolerance);
   end ImageMagick_QuickTime;
end Pictlib_Testing.Test_External;
