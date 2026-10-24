--  Regenerates the external-oracle fixtures: source rasters drawn by ImageMagick, written as PICT by two
--  independent encoders (Netpbm ppmtopict and ImageMagick), QuickTime pictures with embedded JPEGs and libjpeg's
--  decodings of those JPEGs. Test-time tooling only; the tools are run directly, never through a shell.
--  Arguments: [--output DIR], fixtures/external by default. Run from the tests directory.
with Ada.Command_Line;
with Ada.Directories;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with GNAT.OS_Lib;
with Pictlib.Streams;
with Project_Tools.Processes;

procedure Pictlib_Generate is
   use Ada.Strings.Unbounded;
   use type Pictlib.Byte;
   package Processes renames Project_Tools.Processes;

   function Output_Directory return String is
   begin
      for Index in 1 .. Ada.Command_Line.Argument_Count - 1 loop
         if Ada.Command_Line.Argument (Index) = "--output" then
            return Ada.Command_Line.Argument (Index + 1);
         end if;
      end loop;
      return "fixtures/external";
   end Output_Directory;

   Directory : constant String := Output_Directory;
   Magick : constant String := Processes.Locate_Command ("magick");
   Ppmtopict : constant String := Processes.Locate_Command ("ppmtopict");
   Failed : Boolean := False;

   function Path (Name : String) return String is (Directory & "/" & Name);

   type Words is array (Positive range <>) of Unbounded_String;
   function "+" (Item : String) return Unbounded_String renames To_Unbounded_String;

   procedure Magick_Run (Arguments : Words) is
      Items : Processes.Argument_Vectors.Vector;
   begin
      if Failed then
         return;
      end if;
      for Item of Arguments loop
         Items.Append (Item);
      end loop;
      if Processes.Run_Status ("magick", Directory, Magick, Items, Quiet => True) /= 0 then
         Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, "pictlib_generate: magick failed");
         Failed := True;
      end if;
   end Magick_Run;

   --  ppmtopict writes the picture to standard output.
   procedure Netpbm_Run (Source, Target : String) is
      Arguments : GNAT.OS_Lib.Argument_List := [1 => new String'(Path (Source))];
      Success : Boolean;
      Status : Integer;
   begin
      if Failed then
         return;
      end if;
      GNAT.OS_Lib.Spawn (Ppmtopict, Arguments, Path (Target), Success, Status, Err_To_Out => False);
      GNAT.OS_Lib.Free (Arguments (1));
      if not Success or else Status /= 0 then
         Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, "pictlib_generate: ppmtopict failed");
         Failed := True;
      end if;
   end Netpbm_Run;

   --  The JPEG inside a QuickTime picture: from its first start-of-image marker to its last end-of-image marker.
   procedure Extract_JPEG (Picture, Target : String) is
      use Ada.Streams.Stream_IO;
      File : File_Type;
      Data : Pictlib.Streams.Byte_Array (1 .. Natural (Ada.Directories.Size (Path (Picture))));
      First, Last : Natural := 0;
   begin
      if Failed then
         return;
      end if;
      Open (File, In_File, Path (Picture));
      Pictlib.Streams.Byte_Array'Read (Stream (File), Data);
      Close (File);
      for Index in Data'First .. Data'Last - 2 loop
         if Data (Index) = 16#FF# and then Data (Index + 1) = 16#D8# and then Data (Index + 2) = 16#FF# then
            First := Index;
            exit;
         end if;
      end loop;
      for Index in reverse Data'First .. Data'Last - 1 loop
         if Data (Index) = 16#FF# and then Data (Index + 1) = 16#D9# then
            Last := Index + 1;
            exit;
         end if;
      end loop;
      if First = 0 or else Last <= First then
         Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, "pictlib_generate: no JPEG in " & Picture);
         Failed := True;
         return;
      end if;
      Create (File, Out_File, Path (Target));
      Pictlib.Streams.Byte_Array'Write (Stream (File), Data (First .. Last));
      Close (File);
   end Extract_JPEG;

   procedure Remove (Name : String) is
   begin
      if Ada.Directories.Exists (Path (Name)) then
         Ada.Directories.Delete_File (Path (Name));
      end if;
   end Remove;
begin
   if Magick'Length = 0 or else Ppmtopict'Length = 0 then
      Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, "pictlib_generate: needs magick and ppmtopict");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      return;
   end if;
   Ada.Directories.Create_Path (Directory);

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

   if Failed then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   else
      Ada.Text_IO.Put_Line ("generated the external fixtures in " & Directory);
   end if;
end Pictlib_Generate;
