--  Regenerates the external-oracle fixtures: source rasters drawn by ImageMagick, written as PICT by two
--  independent encoders (Netpbm ppmtopict and ImageMagick), QuickTime pictures with embedded JPEGs and libjpeg's
--  decodings of those JPEGs. Test-time tooling only; the tools are run directly, never through a shell. Everything
--  is made in a staging directory first and copied into place only when every step succeeded. With --check,
--  nothing is copied: each product is compared with the committed fixture byte for byte, and any difference
--  fails, so a drift of ImageMagick, Netpbm or libjpeg shows. The tools' versions are printed either way.
--  Arguments: [--output DIR] [--check], fixtures/external by default. Runs from anywhere below the pictlib tree.
with Ada.Command_Line;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with GNAT.OS_Lib;
with Pictlib_Testing.Tools;
with Project_Tools.Files;
with Project_Tools.Processes;

procedure Pictlib_Generate is
   procedure Fail (Message : String) renames Pictlib_Testing.Tools.Fail;
   use Ada.Strings.Unbounded;
   package Processes renames Project_Tools.Processes;

   Staging : constant String := "artifacts/generate-staging";

   --  The files this tool makes, in the order it makes them.
   type Words is array (Positive range <>) of Unbounded_String;
   function "+" (Item : String) return Unbounded_String renames To_Unbounded_String;
   Products : constant Words :=
     [+"palette.ppm", +"truecolor.ppm", +"mono.pbm", +"palette_netpbm.pict", +"palette_magick.pict",
      +"truecolor_magick.pict", +"mono_magick.pict", +"truecolor_jpeg.pict", +"palette_jpeg.pict",
      +"truecolor_embedded.ppm", +"palette_embedded.ppm", +"small.jpg", +"small_decoded.ppm"];

   Target : Unbounded_String := +"fixtures/external";
   Check_Only : Boolean := False;
   Magick : constant String := Pictlib_Testing.Tools.ImageMagick;
   Ppmtopict : constant String := Processes.Locate_Command ("ppmtopict");

   procedure Read_Arguments is
      Index : Positive := 1;
   begin
      while Index <= Ada.Command_Line.Argument_Count loop
         if Ada.Command_Line.Argument (Index) = "--output" and then Index < Ada.Command_Line.Argument_Count then
            --  Relative to where the tool was run, before it moves to the tests directory.
            Target := +Ada.Directories.Full_Name (Ada.Command_Line.Argument (Index + 1));
            Index := Index + 2;
         elsif Ada.Command_Line.Argument (Index) = "--check" then
            Check_Only := True;
            Index := Index + 1;
         else
            Fail ("usage: pictlib_generate [--output DIR] [--check]");
            return;
         end if;
      end loop;
   end Read_Arguments;

   function Path (Name : String) return String is (Staging & "/" & Name);

   procedure Magick_Run (Arguments : Words) is
      Items : Processes.Argument_Vectors.Vector;
   begin
      if Pictlib_Testing.Tools.Failures > 0 then
         return;
      end if;
      for Item of Arguments loop
         Items.Append (Item);
      end loop;
      if Processes.Run_Status ("magick", Staging, Magick, Items, Quiet => True) /= 0 then
         Fail ("ImageMagick failed");
      end if;
   end Magick_Run;

   --  ppmtopict writes the picture to standard output.
   procedure Netpbm_Run (Source, Product : String) is
      Arguments : GNAT.OS_Lib.Argument_List := [1 => new String'(Path (Source))];
      Success : Boolean;
      Status : Integer;
   begin
      if Pictlib_Testing.Tools.Failures > 0 then
         GNAT.OS_Lib.Free (Arguments (1));
         return;
      end if;
      --  Spawned straight into the product file: ppmtopict writes the picture to standard output, and a file
      --  keeps its bytes exactly where a captured string could translate line ends.
      GNAT.OS_Lib.Spawn (Ppmtopict, Arguments, Path (Product), Success, Status, Err_To_Out => False);
      GNAT.OS_Lib.Free (Arguments (1));
      if not Success or else Status /= 0 then
         Fail ("ppmtopict failed");
      end if;
   end Netpbm_Run;

   --  The JPEG inside a QuickTime picture: from its first start-of-image marker to its last end-of-image marker.
   procedure Extract_JPEG (Picture, Product : String) is
      Start_Of_Image : constant String := [Character'Val (16#FF#), Character'Val (16#D8#), Character'Val (16#FF#)];
      End_Of_Image : constant String := [Character'Val (16#FF#), Character'Val (16#D9#)];
   begin
      if Pictlib_Testing.Tools.Failures > 0 then
         return;
      end if;
      declare
         Data : constant String := Project_Tools.Files.Read_Raw_File (Path (Picture));
         First : constant Natural := Ada.Strings.Fixed.Index (Data, Start_Of_Image);
         Last : constant Natural := Ada.Strings.Fixed.Index (Data, End_Of_Image, Going => Ada.Strings.Backward);
      begin
         if First = 0 or else Last <= First then
            Fail ("no JPEG in " & Picture);
            return;
         end if;
         Project_Tools.Files.Write_Raw_File (Path (Product), Data (First .. Last + 1));
      end;
   end Extract_JPEG;

   procedure Remove (Name : String) is
   begin
      Project_Tools.Files.Delete_File_If_Present (Path (Name));
   end Remove;
begin
   Pictlib_Testing.Tools.Start_Report ("pictlib_generate");
   Read_Arguments;
   if not Pictlib_Testing.Tools.Enter_Tests_Directory then
      return;
   end if;
   if Pictlib_Testing.Tools.Failures = 0 and then (Magick'Length = 0 or else Ppmtopict'Length = 0) then
      Fail ("needs ImageMagick (magick, or ImageMagick 6's convert) and Netpbm's ppmtopict");
   end if;
   if Pictlib_Testing.Tools.Failures = 0 then
      Pictlib_Testing.Tools.Report_Version ("ImageMagick", Magick, "-version");
      Pictlib_Testing.Tools.Report_Version ("ppmtopict", Ppmtopict);
      --  Nothing a run that stopped early left behind can stand in for a product of this one.
      if Ada.Directories.Exists (Staging) then
         Ada.Directories.Delete_Tree (Staging);
      end if;
      Ada.Directories.Create_Path (Staging);
   end if;

   --  Source rasters.
   Magick_Run ([+"-size", +"21x9", +"xc:white", +"-fill", +"red", +"-draw", +"rectangle 2,1 8,5",
                +"-fill", +"#0080ff", +"-draw", +"rectangle 12,2 18,7", +"-fill", +"black",
                +"-draw", +"point 20,8", +"-depth", +"8", +"palette.ppm"]);
   Magick_Run ([+"-size", +"37x23", +"xc:", +"-channel", +"R", +"-fx", +"i/w", +"-channel", +"G", +"-fx", +"j/h",
                +"-channel", +"B", +"-fx", +"(i*j)%7/7", +"+channel", +"-depth", +"8", +"truecolor.ppm"]);
   Magick_Run ([+"-size", +"30x30", +"xc:white", +"-fill", +"black", +"-draw", +"rectangle 3,3 20,20",
                +"-monochrome", +"mono.pbm"]);

   --  Independent PICT writers: an 8-bit PackBitsRect with header version -1, and 32-bit DirectBitsRects.
   Netpbm_Run ("palette.ppm", "palette_netpbm.pict");
   Magick_Run ([+"palette.ppm", +"palette_magick.pict"]);
   Magick_Run ([+"truecolor.ppm", +"truecolor_magick.pict"]);
   Magick_Run ([+"mono.pbm", +"mono_magick.pict"]);

   --  CompressedQuickTime pictures; their reference rasters are the embedded JPEGs decoded by libjpeg.
   Magick_Run ([+"truecolor.ppm", +"-compress", +"JPEG", +"-quality", +"95", +"truecolor_jpeg.pict"]);
   Magick_Run ([+"palette.ppm", +"-compress", +"JPEG", +"-quality", +"90", +"palette_jpeg.pict"]);
   for Picture of Words'[+"truecolor", +"palette"] loop
      declare
         Name : constant String := To_String (Picture);
      begin
         Extract_JPEG (Name & "_jpeg.pict", Name & "_embedded.jpg");
         Magick_Run ([+(Name & "_embedded.jpg"), +"-depth", +"8", +(Name & "_embedded.ppm")]);
         Remove (Name & "_embedded.jpg");
      end;
   end loop;

   --  A small JPEG the tests wrap in hand-built QuickTime opcodes, and its libjpeg decoding.
   Magick_Run ([+"-size", +"8x6", +"xc:", +"-channel", +"R", +"-fx", +"i/w", +"-channel", +"G", +"-fx", +"j/h",
                +"-channel", +"B", +"-fx", +"0.5", +"+channel", +"-depth", +"8", +"small.ppm"]);
   Magick_Run ([+"small.ppm", +"-quality", +"100", +"-sampling-factor", +"1x1", +"small.jpg"]);
   Magick_Run ([+"small.jpg", +"-depth", +"8", +"small_decoded.ppm"]);
   Remove ("small.ppm");

   --  Into place, all or nothing.
   if Pictlib_Testing.Tools.Failures = 0 then
      for Product of Products loop
         if not Ada.Directories.Exists (Path (To_String (Product))) then
            Fail ("missing " & To_String (Product));
         end if;
      end loop;
   end if;
   if Pictlib_Testing.Tools.Failures = 0 and then Check_Only then
      for Product of Products loop
         declare
            Name : constant String := To_String (Product);
            Committed : constant String := To_String (Target) & "/" & Name;
         begin
            if not Ada.Directories.Exists (Committed) then
               Fail (Committed & ": no committed fixture to compare");
            elsif Project_Tools.Files.Read_Raw_File (Path (Name)) /= Project_Tools.Files.Read_Raw_File (Committed)
            then
               Fail (Name & ": differs from the committed fixture");
            else
               Ada.Text_IO.Put_Line ("same " & Name);
            end if;
         end;
      end loop;
   elsif Pictlib_Testing.Tools.Failures = 0 then
      Ada.Directories.Create_Path (To_String (Target));
      for Product of Products loop
         begin
            Ada.Directories.Copy_File (Path (To_String (Product)), To_String (Target) & "/" & To_String (Product));
         exception
            when Error : others =>
               Fail ("copying " & To_String (Product) & " failed, the fixtures before it already replaced: "
                     & Ada.Exceptions.Exception_Message (Error));
               exit;
         end;
      end loop;
      if Pictlib_Testing.Tools.Failures = 0 then
         Ada.Text_IO.Put_Line ("generated the external fixtures in " & To_String (Target));
      end if;
   end if;
   if Ada.Directories.Exists (Staging) then
      Ada.Directories.Delete_Tree (Staging);
   end if;
   Pictlib_Testing.Tools.Finish_Report;
exception
   --  A tool that raised still leaves no staging behind, and fails.
   when Error : others =>
      if Ada.Directories.Exists (Staging) then
         Ada.Directories.Delete_Tree (Staging);
      end if;
      Fail ("stopped: " & Ada.Exceptions.Exception_Information (Error));
      Pictlib_Testing.Tools.Finish_Report;
end Pictlib_Generate;
