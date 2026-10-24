with Ada.Directories;
with Ada.Streams.Stream_IO;
with AUnit.Assertions;

with Pictlib;
with Pictlib.Decoding;
with Pictlib.Images;
with Pictlib.Results;
with Pictlib.Streams;
with Pictlib_Testing.Canvases;

package body Pictlib_Testing.Test_External is
   use AUnit.Assertions;
   use type Pictlib.Images.RGB_Color;

   Fixtures : constant String := "fixtures/external/";

   type Bytes_Access is access Pictlib.Streams.Byte_Array;

   function Load (Name : String) return Bytes_Access is
      use Ada.Streams.Stream_IO;
      Path : constant String := Fixtures & Name;
      Size : constant Natural := Natural (Ada.Directories.Size (Path));
      Result : constant Bytes_Access := new Pictlib.Streams.Byte_Array (1 .. Size);
      File : File_Type;
   begin
      Open (File, In_File, Path);
      Pictlib.Streams.Byte_Array'Read (Stream (File), Result.all);
      Close (File);
      return Result;
   end Load;

   --  A binary Netpbm raster: P6 (8-bit RGB) or P4 (1-bit, 1 is black).
   procedure Parse_Netpbm (Data : Pictlib.Streams.Byte_Array; Width, Height : out Natural; Kind : out Character;
                           First_Pixel : out Positive) is
      Position : Positive := Data'First + 2;
      Fields : array (1 .. 3) of Natural := [others => 0];
      Wanted : constant Natural := (if Character'Val (Data (Data'First + 1)) = '6' then 3 else 2);
   begin
      Kind := Character'Val (Data (Data'First + 1));
      for Field in 1 .. Wanted loop
         while Character'Val (Data (Position)) not in '0' .. '9' loop
            Position := Position + 1;
         end loop;
         while Character'Val (Data (Position)) in '0' .. '9' loop
            Fields (Field) := Fields (Field) * 10 + Character'Pos (Character'Val (Data (Position))) - 48;
            Position := Position + 1;
         end loop;
      end loop;
      Width := Fields (1);
      Height := Fields (2);
      First_Pixel := Position + 1;  --  one whitespace byte ends the header
   end Parse_Netpbm;

   function Expected_Pixel (Data : Pictlib.Streams.Byte_Array; Kind : Character; First, Width, X, Y : Natural)
     return Pictlib.Images.RGB_Color is
   begin
      if Kind = '6' then
         declare
            At_Pixel : constant Positive := First + 3 * (Y * Width + X);
         begin
            return (Data (At_Pixel), Data (At_Pixel + 1), Data (At_Pixel + 2));
         end;
      end if;
      declare
         Row_Bytes : constant Natural := (Width + 7) / 8;
         Value : constant Natural := Natural (Data (First + Y * Row_Bytes + X / 8));
         Bit : constant Natural := (Value / 2 ** (7 - X mod 8)) mod 2;
      begin
         return (if Bit = 1 then Pictlib.Images.Black else Pictlib.Images.White);
      end;
   end Expected_Pixel;

   procedure Expect_Source (Picture_Name, Source_Name : String) is
      Picture : constant Bytes_Access := Load (Picture_Name);
      Source : constant Bytes_Access := Load (Source_Name);
      Width, Height : Natural;
      Kind : Character;
      First : Positive;
   begin
      Parse_Netpbm (Source.all, Width, Height, Kind, First);
      declare
         Storage : aliased Pictlib.Streams.Byte_Array := [1 .. 3 * Width * Height => 16#EE#];
         Output : constant Pictlib.Images.Mutable_Image_View := Canvases.View (Storage'Access, Width, Height);
         Decoder : Pictlib.Decoding.Decoder;
         Outcome : Pictlib.Results.Result;
         Wrong : Natural := 0;
      begin
         Canvases.Render (Picture.all, Decoder, Output, Outcome);
         Assert (Pictlib.Results.Succeeded (Outcome),
                 Picture_Name & ": render failed with " & Outcome.First_Error.Code'Image & " at opcode"
                 & Outcome.First_Error.Context.Op'Image & " offset" & Outcome.First_Error.Context.Source'Image);
         for Y in 0 .. Height - 1 loop
            for X in 0 .. Width - 1 loop
               if Canvases.Pixel (Output, X, Y) /= Expected_Pixel (Source.all, Kind, First, Width, X, Y) then
                  Wrong := Wrong + 1;
               end if;
            end loop;
         end loop;
         Assert (Wrong = 0, Picture_Name & ":" & Wrong'Image & " pixels differ from " & Source_Name);
      end;
   end Expect_Source;

   procedure Netpbm_Indexed (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure ImageMagick_Direct (T : in out AUnit.Test_Cases.Test_Case'Class);

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
end Pictlib_Testing.Test_External;
