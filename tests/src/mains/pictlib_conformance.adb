--  Encoder conformance: encode sample images, have independent PICT decoders read the pictures, and require
--  the source pixels exactly. Decoders:
--  * ImageMagick: version 7's `magick`, or version 6's `convert` (Pictlib_Testing.Tools.ImageMagick). Its PICT
--    reader reads only pictures with the 512-byte file header, misreads rows stored unpacked (rowBytes below 8)
--    and draws 1-bit BitMaps black; those pictures are not applicable.
--  * LibreOffice (`soffice`), through its own PICT import: the picture is exported as SVG, whose embedded PNG
--    is the decoded bitmap at its own size; ImageMagick only turns that PNG into a PPM.
--  A decoder that is not installed is reported as skipped; --require fails the run unless every decoder ran.
--  Runs from anywhere below the pictlib tree.
with Ada.Directories;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Ada.Unchecked_Deallocation;
with Pictlib;
with Pictlib.Encoding;
with Pictlib.Geometry;
with Pictlib.Images;
with Pictlib.Results;
with Pictlib.Streams;
with Pictlib_Testing.Files;
with Pictlib_Testing.Samples;
with Pictlib_Testing.Tools;
with Project_Tools.Processes;

procedure Pictlib_Conformance is
   use Ada.Strings.Unbounded;
   use type Pictlib.Images.RGB_Color;
   use type Pictlib.Encoding.Layout_Kind;
   use type Pictlib.Geometry.Fixed;

   package Encoding renames Pictlib.Encoding;
   package Processes renames Project_Tools.Processes;
   package Files renames Pictlib_Testing.Files;
   package Samples renames Pictlib_Testing.Samples;
   procedure Fail (Message : String) renames Pictlib_Testing.Tools.Fail;

   Directory : constant String := "artifacts/conformance";

   type Sample_Case is record
      Name : Unbounded_String;
      Item : Samples.Kind;
      Width, Height : Positive;
      Format : Pictlib.Pixel_Format := Pictlib.RGB_24;
      Settings : Encoding.Options;
   end record;

   function Case_Of
     (Name : String;
      Item : Samples.Kind;
      Width, Height : Positive;
      Settings : Encoding.Options;
      Format : Pictlib.Pixel_Format := Pictlib.RGB_24) return Sample_Case is
     ((To_Unbounded_String (Name), Item, Width, Height, Format, Settings));

   Cases : constant array (Positive range <>) of Sample_Case :=
     [Case_Of ("direct", Samples.Gradient, 37, 23, (Layout => Encoding.Direct_32, others => <>)),
      Case_Of ("direct_wide", Samples.Gradient, 300, 5, (Layout => Encoding.Direct_32, others => <>)),
      Case_Of ("direct_narrow", Samples.Gradient, 1, 6, (Layout => Encoding.Direct_32, others => <>)),
      Case_Of ("direct_bare", Samples.Gradient, 37, 23,
               (Layout => Encoding.Direct_32, File_Header => False, others => <>)),
      Case_Of ("indexed", Samples.Three_Colors, 37, 23, (Layout => Encoding.Indexed_8, others => <>)),
      Case_Of ("indexed_wide", Samples.Three_Colors, 300, 4, (Layout => Encoding.Indexed_8, others => <>)),
      Case_Of ("indexed_narrow", Samples.Three_Colors, 3, 5, (Layout => Encoding.Indexed_8, others => <>)),
      Case_Of ("mono", Samples.Black_And_White, 37, 23, (Layout => Encoding.Mono_1, others => <>)),
      Case_Of ("mono_wide", Samples.Black_And_White, 2100, 2, (Layout => Encoding.Mono_1, others => <>)),
      Case_Of ("mono_narrow", Samples.Black_And_White, 3, 5, (Layout => Encoding.Mono_1, others => <>)),
      --  Alpha kept as a fourth plane, packed and unpacked: a reader must still find the colors.
      Case_Of ("direct_alpha", Samples.Translucent, 37, 23, (Layout => Encoding.Direct_32, Keep_Alpha => True,
                                                            others => <>), Pictlib.RGBA_32),
      Case_Of ("direct_alpha_narrow", Samples.Translucent, 1, 6,
               (Layout => Encoding.Direct_32, Keep_Alpha => True, others => <>), Pictlib.ARGB_32),
      --  Auto's choice, for each kind of image.
      Case_Of ("auto_direct", Samples.Gradient, 37, 23, (Layout => Encoding.Auto, others => <>)),
      Case_Of ("auto_indexed", Samples.Three_Colors, 37, 23, (Layout => Encoding.Auto, others => <>)),
      Case_Of ("auto_mono", Samples.Black_And_White, 37, 23, (Layout => Encoding.Auto, others => <>)),
      --  The row-length boundaries: the last byte count and the first word count, and the widest rows.
      Case_Of ("indexed_250", Samples.Three_Colors, 250, 3, (Layout => Encoding.Indexed_8, others => <>)),
      Case_Of ("indexed_252", Samples.Three_Colors, 251, 3, (Layout => Encoding.Indexed_8, others => <>)),
      Case_Of ("direct_widest", Samples.Gradient, 4095, 2, (Layout => Encoding.Direct_32, others => <>)),
      Case_Of ("indexed_widest", Samples.Three_Colors, 16_382, 1, (Layout => Encoding.Indexed_8, others => <>)),
      --  A picture past 64 KiB, about 80 KB, whose picSize is its length's low 16 bits.
      Case_Of ("direct_large", Samples.Gradient, 1000, 40, (Layout => Encoding.Direct_32, others => <>)),
      --  A raised Mono_1 threshold, and sources in the other byte orders.
      Case_Of ("mono_threshold", Samples.Gray_Ramp, 37, 3,
               (Layout => Encoding.Mono_1, Mono_Threshold => 200, others => <>)),
      Case_Of ("direct_bgr", Samples.Gradient, 37, 23, (Layout => Encoding.Direct_32, others => <>), Pictlib.BGR_24),
      Case_Of ("direct_bgra", Samples.Gradient, 37, 23, (Layout => Encoding.Direct_32, others => <>),
               Pictlib.BGRA_32),
      --  A resolution other than 72 dpi labels the picture only: a reader must not scale it.
      Case_Of ("direct_144dpi", Samples.Gradient, 37, 23,
               (Layout => Encoding.Direct_32, Horizontal_Resolution => 2 * Pictlib.Geometry.Fixed_72,
                Vertical_Resolution => 2 * Pictlib.Geometry.Fixed_72, others => <>))];

   function Path (Name, Extension : String) return String is (Directory & "/" & Name & "." & Extension);

   --  Pixels of a binary PPM that differ from the case's expected raster; Natural'Last when unreadable.
   function Differences (Item : Sample_Case; File_Name : String) return Natural is
      Result : Files.Raster;
      Wrong : Natural := 0;
   begin
      if not Files.Read_Raster (File_Name, Result) or else Result.Kind /= '6' or else Result.Width /= Item.Width
        or else Result.Height /= Item.Height
      then
         return Natural'Last;
      end if;
      for Y in 0 .. Item.Height - 1 loop
         for X in 0 .. Item.Width - 1 loop
            if Files.Pixel (Result, X, Y)
              /= Samples.Expected_Color (Item.Item, X, Y, Item.Settings.Layout, Item.Settings.Mono_Threshold)
            then
               Wrong := Wrong + 1;
            end if;
         end loop;
      end loop;
      return Wrong;
   end Differences;

   --  The first PNG embedded in an SVG file, as a data URI, written to Target.
   type String_Access is access String;
   procedure Free is new Ada.Unchecked_Deallocation (String, String_Access);
   procedure Free is new Ada.Unchecked_Deallocation (Pictlib.Streams.Byte_Array, Pictlib.Streams.Byte_Array_Access);

   function Extract_PNG (SVG_File, Target : String) return Boolean is
      use Ada.Streams.Stream_IO;
      Marker : constant String := "data:image/png;base64,";
      File : File_Type;
   begin
      if not Ada.Directories.Exists (SVG_File) then
         return False;
      end if;
      declare
         Size : constant Natural := Natural (Ada.Directories.Size (SVG_File));
         --  On the heap: an SVG holding a large picture's PNG is larger than a stack holds.
         Text_Buffer : String_Access := new String (1 .. Size);
         Text : String renames Text_Buffer.all;
         Start : Natural := 0;
      begin
         Open (File, In_File, SVG_File);
         String'Read (Stream (File), Text);
         Close (File);
         for Index in Text'First .. Text'Last - Marker'Length + 1 loop
            if Text (Index .. Index + Marker'Length - 1) = Marker then
               Start := Index + Marker'Length;
               exit;
            end if;
         end loop;
         if Start = 0 then
            Free (Text_Buffer);
            return False;
         end if;
         declare
            Decoded_Buffer : Pictlib.Streams.Byte_Array_Access := new Pictlib.Streams.Byte_Array (1 .. Size);
            Decoded : Pictlib.Streams.Byte_Array renames Decoded_Buffer.all;
            Count : Natural := 0;
            Bits : Natural := 0;
            Held : Natural := 0;
            Index : Positive := Start;
         begin
            while Index <= Text'Last and then Text (Index) /= '"' loop
               declare
                  C : constant Character := Text (Index);
                  Value : constant Integer :=
                    (case C is
                        when 'A' .. 'Z' => Character'Pos (C) - Character'Pos ('A'),
                        when 'a' .. 'z' => Character'Pos (C) - Character'Pos ('a') + 26,
                        when '0' .. '9' => Character'Pos (C) - Character'Pos ('0') + 52,
                        when '+' => 62,
                        when '/' => 63,
                        when others => -1);
               begin
                  if Value >= 0 then
                     Bits := (Bits * 64 + Value) mod 2 ** 24;
                     Held := Held + 6;
                     if Held >= 8 then
                        Held := Held - 8;
                        Count := Count + 1;
                        Decoded (Count) := Pictlib.Byte ((Bits / 2 ** Held) mod 256);
                     end if;
                  end if;
               end;
               Index := Index + 1;
            end loop;
            Files.Save_Path (Target, Decoded (1 .. Count));
            Free (Decoded_Buffer);
            Free (Text_Buffer);
            return Count > 0;
         end;
      end;
   end Extract_PNG;

   --  Encode the case, writing its picture; Used is the layout the encoder chose.
   function Encode (Item : Sample_Case; Used : out Encoding.Layout_Kind) return Boolean is
      Picture : constant Samples.Encoded :=
        Samples.Encode (Item.Item, Item.Width, Item.Height, Item.Settings, Item.Format);
   begin
      Used := Picture.Layout;
      if not Pictlib.Results.Succeeded (Picture.Outcome) then
         Fail (To_String (Item.Name) & ": encode " & Picture.Outcome.First_Error.Code'Image);
         return False;
      end if;
      if To_String (Item.Name) = "direct_large" and then Picture.Data'Length <= 16#1_0000# then
         Fail ("direct_large:" & Picture.Data'Length'Image & " bytes, not past 64 KiB");
      end if;
      Files.Save_Path (Path (To_String (Item.Name), "pict"), Picture.Data.all);
      return True;
   end Encode;

   Magick : constant String := Pictlib_Testing.Tools.ImageMagick;
   Office : constant String := Processes.Locate_Command ("soffice");
   Skipped : Natural := 0;

   Not_Applicable : Natural := 0;

   procedure Report (Item : Sample_Case; Oracle, Result_File : String; Status : Integer) is
      Wrong : constant Natural := (if Status = 0 then Differences (Item, Result_File) else Natural'Last);
   begin
      if Wrong = 0 then
         Ada.Text_IO.Put_Line ("PASS " & To_String (Item.Name) & " " & Oracle);
      else
         Fail (To_String (Item.Name) & " " & Oracle & ": "
               & (if Wrong = Natural'Last then "no readable result" else Wrong'Image & " pixels differ"));
      end if;
   end Report;
   --  Every result a case reads is made in this run: what an earlier run left is removed first, so a tool
   --  that exits 0 without writing cannot pass on old output.
   procedure Discard (File : String) is
   begin
      if Ada.Directories.Exists (File) then
         Ada.Directories.Delete_File (File);
      end if;
   end Discard;
begin
   if not Pictlib_Testing.Tools.Enter_Tests_Directory then
      return;
   end if;
   Pictlib_Testing.Tools.Start_Report ("pictlib_conformance");
   if not Pictlib_Testing.Tools.Arguments_Known ([new String'("--require")]) then
      Pictlib_Testing.Tools.Finish_Report;
      return;
   end if;
   Ada.Directories.Create_Path (Directory);
   --  The oracles' versions, so a change in what they read can be traced to a change of version.
   if Magick'Length > 0 then
      Pictlib_Testing.Tools.Report_Version ("ImageMagick", Magick, "-version");
   end if;
   if Office'Length > 0 then
      Pictlib_Testing.Tools.Report_Version ("LibreOffice", Office);
   end if;
   if Magick'Length = 0 then
      Ada.Text_IO.Put_Line ("SKIP ImageMagick: neither magick nor ImageMagick 6's convert is installed");
      Skipped := Skipped + 1;
   end if;
   if Office'Length = 0 or else Magick'Length = 0 then
      Ada.Text_IO.Put_Line ("SKIP LibreOffice: soffice (and ImageMagick, to read its PNG) are needed");
      Skipped := Skipped + 1;
   end if;
   for Listed of Cases loop
      declare
         Used : Encoding.Layout_Kind;
         Encoded : constant Boolean := Encode (Listed, Used);
         --  The case as written: an Auto case is checked as the layout chosen.
         Item : constant Sample_Case := (Listed with delta Settings => (Listed.Settings with delta Layout => Used));
      begin
         if Encoded then
            declare
               Name : constant String := To_String (Item.Name);
            begin
               Discard (Path (Name, "magick.ppm"));
               Discard (Path (Name, "svg"));
               Discard (Path (Name, "png"));
               Discard (Path (Name, "soffice.ppm"));
               if Magick'Length > 0
                 and then (not Item.Settings.File_Header or else Item.Settings.Layout = Encoding.Mono_1
                           or else Samples.Row_Bytes (Item.Settings.Layout, Item.Width) < 8)
               then
                  Not_Applicable := Not_Applicable + 1;
                  Ada.Text_IO.Put_Line ("N/A  " & Name & " ImageMagick: a known ImageMagick reader limitation");
               elsif Magick'Length > 0 then
                  Report (Item, "ImageMagick", Path (Name, "magick.ppm"),
                          Processes.Run_Status
                            ("magick", ".", Magick,
                             Processes.Arguments
                               ([Processes.Argument (Path (Name, "pict")), Processes.Argument ("-depth"),
                                 Processes.Argument ("8"), Processes.Argument (Path (Name, "magick.ppm"))]),
                             Quiet => True));
               end if;
               if Office'Length > 0 and then Magick'Length > 0 then
                  declare
                     Status : Integer :=
                       Processes.Run_Status
                         ("soffice", ".", Office,
                          Processes.Arguments
                            ([Processes.Argument ("--headless"), Processes.Argument ("--convert-to"),
                              Processes.Argument ("svg"), Processes.Argument ("--outdir"),
                              Processes.Argument (Directory), Processes.Argument (Path (Name, "pict"))]),
                          Quiet => True);
                  begin
                     if Status = 0 and then not Extract_PNG (Path (Name, "svg"), Path (Name, "png")) then
                        Status := 1;
                     end if;
                     if Status = 0 then
                        Status :=
                          Processes.Run_Status
                            ("magick", ".", Magick,
                             Processes.Arguments
                               ([Processes.Argument (Path (Name, "png")), Processes.Argument ("-alpha"),
                                 Processes.Argument ("off"), Processes.Argument ("-depth"), Processes.Argument ("8"),
                                 Processes.Argument (Path (Name, "soffice.ppm"))]),
                             Quiet => True);
                     end if;
                     Report (Item, "LibreOffice", Path (Name, "soffice.ppm"), Status);
                  end;
               end if;
            end;
         end if;
      end;
   end loop;
   Ada.Text_IO.Put_Line
     (Natural'Image (Cases'Length) & " pictures," & Pictlib_Testing.Tools.Failures'Image & " failures,"
      & Not_Applicable'Image & " not applicable," & Skipped'Image & " decoders skipped");
   if Processes.Has_Argument ("--require") and then Skipped > 0 then
      Fail ("--require: a decoder was skipped");
   end if;
   Pictlib_Testing.Tools.Finish_Report;
end Pictlib_Conformance;
