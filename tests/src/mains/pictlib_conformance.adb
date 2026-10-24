--  Encoder conformance: encode sample images, have independent PICT decoders read the pictures, and require
--  the source pixels exactly. Decoders:
--  * ImageMagick (`magick`). ImageMagick 7 reads only pictures with the 512-byte file header, misreads rows
--    stored unpacked (rowBytes below 8) and draws 1-bit BitMaps black; those pictures are not applicable.
--  * LibreOffice (`soffice`), through its own PICT import: the picture is exported as SVG, whose embedded PNG
--    is the decoded bitmap at its own size; ImageMagick only turns that PNG into a PPM.
--  A decoder that is not installed is reported as skipped; --require fails the run unless every decoder ran.
--  Run from the tests directory.
with Ada.Command_Line;
with Ada.Directories;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Pictlib;
with Pictlib.Encoding;
with Pictlib.Images;
with Pictlib.Results;
with Pictlib.Streams;
with Pictlib_Testing.Samples;
with Project_Tools.Processes;

procedure Pictlib_Conformance is
   use Ada.Strings.Unbounded;
   use type Pictlib.Images.RGB_Color;
   use type Pictlib.Encoding.Layout_Kind;

   package Encoding renames Pictlib.Encoding;
   package Processes renames Project_Tools.Processes;
   package Samples renames Pictlib_Testing.Samples;

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
      Case_Of ("mono_narrow", Samples.Black_And_White, 3, 5, (Layout => Encoding.Mono_1, others => <>))];

   function Path (Name, Extension : String) return String is (Directory & "/" & Name & "." & Extension);

   procedure Write (File_Name : String; Data : Pictlib.Streams.Byte_Array) is
      use Ada.Streams.Stream_IO;
      File : File_Type;
   begin
      Create (File, Out_File, File_Name);
      Pictlib.Streams.Byte_Array'Write (Stream (File), Data);
      Close (File);
   end Write;

   function Expected (Item : Sample_Case; X, Y : Natural) return Pictlib.Images.RGB_Color is
      Color : constant Pictlib.Images.RGB_Color := Samples.Color (Item.Item, X, Y);
   begin
      if Item.Settings.Layout = Encoding.Mono_1 then
         return (if (299 * Natural (Color.Red) + 587 * Natural (Color.Green) + 114 * Natural (Color.Blue)) / 1000
                    < Natural (Item.Settings.Mono_Threshold)
                 then Pictlib.Images.Black else Pictlib.Images.White);
      end if;
      return Color;
   end Expected;

   --  Pixels of a binary PPM that differ from the case's expected raster; Natural'Last when unreadable.
   function Differences (Item : Sample_Case; File_Name : String) return Natural is
      use Ada.Streams.Stream_IO;
      File : File_Type;
   begin
      if not Ada.Directories.Exists (File_Name) then
         return Natural'Last;
      end if;
      declare
         Size : constant Natural := Natural (Ada.Directories.Size (File_Name));
         Data : Pictlib.Streams.Byte_Array (1 .. Size);
         Position : Positive := 3;
         Fields : array (1 .. 3) of Natural := [others => 0];
         Wrong : Natural := 0;
      begin
         Open (File, In_File, File_Name);
         Pictlib.Streams.Byte_Array'Read (Stream (File), Data);
         Close (File);
         if Size < 2 or else Character'Val (Data (1)) /= 'P' or else Character'Val (Data (2)) /= '6' then
            return Natural'Last;
         end if;
         for Field in Fields'Range loop
            while Position <= Size and then Character'Val (Data (Position)) not in '0' .. '9' loop
               Position := Position + 1;
            end loop;
            while Position <= Size and then Character'Val (Data (Position)) in '0' .. '9' loop
               Fields (Field) := Fields (Field) * 10 + Character'Pos (Character'Val (Data (Position))) - 48;
               Position := Position + 1;
            end loop;
         end loop;
         if Fields (1) /= Item.Width or else Fields (2) /= Item.Height or else Fields (3) /= 255
           or else Size < Position + 3 * Item.Width * Item.Height
         then
            return Natural'Last;
         end if;
         for Y in 0 .. Item.Height - 1 loop
            for X in 0 .. Item.Width - 1 loop
               declare
                  At_Pixel : constant Positive := Position + 1 + 3 * (Y * Item.Width + X);
               begin
                  if Pictlib.Images.RGB_Color'(Data (At_Pixel), Data (At_Pixel + 1), Data (At_Pixel + 2))
                    /= Expected (Item, X, Y)
                  then
                     Wrong := Wrong + 1;
                  end if;
               end;
            end loop;
         end loop;
         return Wrong;
      end;
   end Differences;

   --  The first PNG embedded in an SVG file, as a data URI, written to Target.
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
         Text : String (1 .. Size);
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
            return False;
         end if;
         declare
            Decoded : Pictlib.Streams.Byte_Array (1 .. Size);
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
            Write (Target, Decoded (1 .. Count));
            return Count > 0;
         end;
      end;
   end Extract_PNG;

   --  rowBytes the encoder writes; below 8 the rows are stored unpacked.
   function Row_Bytes (Item : Sample_Case) return Natural is
     (case Item.Settings.Layout is
         when Encoding.Direct_32 => 4 * Item.Width,
         when Encoding.Indexed_8 => Item.Width + Item.Width mod 2,
         when others => ((Item.Width + 7) / 8 + 1) / 2 * 2);

   function Encode (Item : Sample_Case) return Boolean is
      Source : constant Samples.Bytes_Access := Samples.Make (Item.Item, Item.Width, Item.Height, Item.Format);
      Storage : constant Pictlib.Streams.Byte_Array_Access := new Pictlib.Streams.Byte_Array (1 .. 4_000_000);
      Output : aliased Pictlib.Streams.Fixed_Buffer_Destination;
      Encoder : Encoding.Encoder;
      Outcome : Pictlib.Results.Result;
   begin
      Pictlib.Streams.Open (Output, Storage);
      Encoding.Initialize (Encoder, Output'Access, Item.Settings);
      Outcome := Encoding.Encode (Encoder, Samples.View (Source, Item.Width, Item.Height, Item.Format));
      if Pictlib.Results.Succeeded (Outcome) then
         Outcome := Encoding.Finish (Encoder);
      end if;
      if not Pictlib.Results.Succeeded (Outcome) then
         Ada.Text_IO.Put_Line ("FAIL " & To_String (Item.Name) & ": encode " & Outcome.First_Error.Code'Image);
         return False;
      end if;
      Write (Path (To_String (Item.Name), "pict"), Storage (1 .. Natural (Output.Offset)));
      return True;
   end Encode;

   Magick : constant String := Processes.Locate_Command ("magick");
   Office : constant String := Processes.Locate_Command ("soffice");
   Failures : Natural := 0;
   Skipped : Natural := 0;

   Not_Applicable : Natural := 0;

   procedure Report (Item : Sample_Case; Oracle, Result_File : String; Status : Integer) is
      Wrong : constant Natural := (if Status = 0 then Differences (Item, Result_File) else Natural'Last);
   begin
      if Wrong = 0 then
         Ada.Text_IO.Put_Line ("PASS " & To_String (Item.Name) & " " & Oracle);
      else
         Failures := Failures + 1;
         Ada.Text_IO.Put_Line
           ("FAIL " & To_String (Item.Name) & " " & Oracle & ": "
            & (if Wrong = Natural'Last then "no readable result" else Wrong'Image & " pixels differ"));
      end if;
   end Report;
begin
   Ada.Directories.Create_Path (Directory);
   if Magick'Length = 0 then
      Ada.Text_IO.Put_Line ("SKIP ImageMagick: magick is not installed");
      Skipped := Skipped + 1;
   end if;
   if Office'Length = 0 or else Magick'Length = 0 then
      Ada.Text_IO.Put_Line ("SKIP LibreOffice: soffice (and magick, to read its PNG) are needed");
      Skipped := Skipped + 1;
   end if;
   for Item of Cases loop
      if not Encode (Item) then
         Failures := Failures + 1;
      else
         declare
            Name : constant String := To_String (Item.Name);
         begin
            if Magick'Length > 0
              and then (not Item.Settings.File_Header or else Item.Settings.Layout = Encoding.Mono_1
                        or else Row_Bytes (Item) < 8)
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
   end loop;
   Ada.Text_IO.Put_Line
     (Natural'Image (Cases'Length) & " pictures," & Failures'Image & " failures," & Not_Applicable'Image
      & " not applicable," & Skipped'Image & " decoders skipped");
   if Failures > 0 or else (Processes.Has_Argument ("--require") and then Skipped > 0) then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Pictlib_Conformance;
