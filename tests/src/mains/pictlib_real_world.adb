--  Real-world corpus: every picture under fixtures/real_world is enumerated strictly and rendered compatibly
--  and recoverably, with the test fonts. An exception escaping pictlib is a defect. Each outcome is printed as
--  "<file> <strict enumerate> <compatible render> <recovering render>" and compared with
--  fixtures/real_world/expected.txt; --update rewrites that file. Runs from anywhere below the pictlib tree.
with Pictlib_Testing.Canvases;
with Pictlib_Testing.Files;
with Pictlib_Testing.Fonts;
with Pictlib_Testing.Tools;
with Ada.Containers.Indefinite_Ordered_Maps;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Unchecked_Deallocation;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Pictlib;
with Pictlib.Decoding;
with Pictlib.Errors;
with Pictlib.Fonts;
with Pictlib.Geometry;
with Pictlib.Images;
with Pictlib.Opcodes;
with Pictlib.Pictures;
with Pictlib.Results;
with Pictlib.Streams;
with Project_Tools.Processes;

procedure Pictlib_Real_World is
   use Ada.Strings.Unbounded;

   package Outcome_Maps is new Ada.Containers.Indefinite_Ordered_Maps (String, String);

   Root : constant String := "fixtures/real_world";
   Expected_File : constant String := Root & "/expected.txt";
   Results_Now : Outcome_Maps.Map;
   Defects : Natural := 0;

   subtype Bytes_Access is Pictlib.Streams.Byte_Array_Access;
   procedure Free is new Ada.Unchecked_Deallocation (Pictlib.Streams.Byte_Array, Pictlib.Streams.Byte_Array_Access);

   --  With --opcodes, each picture's opcodes are counted and printed.
   Count_Opcodes : constant Boolean := Project_Tools.Processes.Has_Argument ("--opcodes");
   type Opcode_Counts is array (Pictlib.Opcode) of Natural;

   --  Counts each opcode it visits.
   type Opcode_Counter is new Pictlib.Decoding.Opcode_Visitor with record
      Counts : Opcode_Counts := [others => 0];
   end record;
   overriding function Visit (Object : in out Opcode_Counter; Event : Pictlib.Pictures.Opcode_Event)
     return Pictlib.Decoding.Visit_Action;
   overriding function Visit (Object : in out Opcode_Counter; Event : Pictlib.Pictures.Opcode_Event)
     return Pictlib.Decoding.Visit_Action is
   begin
      Object.Counts (Event.Op) := Object.Counts (Event.Op) + 1;
      return Pictlib.Decoding.Continue;
   end Visit;

   function Code_Of (Outcome : Pictlib.Results.Result) return String is
     (if Pictlib.Results.Succeeded (Outcome) then "ok"
      else Pictlib.Errors.Identifiers.To_String (Outcome.First_Error.Identifier));

   function Enumerate (Data : Bytes_Access) return String is
      Source : aliased Pictlib.Streams.Memory_Source;
      Decoder : Pictlib.Decoding.Decoder;
      Visitor : Opcode_Counter;
      Outcome : Pictlib.Results.Result;
   begin
      Pictlib.Streams.Open (Source, Pictlib.Streams.Const_Byte_Array_Access (Data));
      Pictlib.Decoding.Initialize (Decoder, Source'Access);
      Outcome := Pictlib.Decoding.Read_Header (Decoder);
      if Pictlib.Results.Succeeded (Outcome) then
         Outcome := Pictlib.Decoding.Enumerate (Decoder, Visitor);
      end if;
      if Count_Opcodes then
         for Op in Visitor.Counts'Range loop
            if Visitor.Counts (Op) > 0 then
               Ada.Text_IO.Put_Line ("  " & Pictlib.Opcodes.Name (Op) & Op'Image & ":" & Visitor.Counts (Op)'Image);
            end if;
         end loop;
      end if;
      return Code_Of (Outcome);
   end Enumerate;

   --  Render Data, and when Reference names a raster, require the render to match it within the JPEG decoders'
   --  tolerance, pixel for pixel.
   function Render (Data : Bytes_Access; Strictness : Pictlib.Strictness_Mode; Reference : String := "")
     return String
   is
      Source : aliased Pictlib.Streams.Memory_Source;
      Decoder : Pictlib.Decoding.Decoder;
      Table : constant Pictlib.Fonts.Font_Table := Pictlib_Testing.Fonts.Test_Table;
      Outcome : Pictlib.Results.Result;
   begin
      Pictlib.Streams.Open (Source, Pictlib.Streams.Const_Byte_Array_Access (Data));
      Pictlib.Decoding.Initialize (Decoder, Source'Access, (Strictness => Strictness, Fonts => Table, others => <>));
      Outcome := Pictlib.Decoding.Read_Header (Decoder);
      if not Pictlib.Results.Succeeded (Outcome) then
         return Code_Of (Outcome);
      end if;
      declare
         Frame : constant Pictlib.Geometry.Rect := Pictlib.Decoding.Header (Decoder).Frame;
         Width : constant Positive := Pictlib.Geometry.Width (Frame);
         Height : constant Positive := Pictlib.Geometry.Height (Frame);
         Storage : Pictlib.Streams.Byte_Array_Access :=
           new Pictlib.Streams.Byte_Array (1 .. Pictlib_Testing.Canvases.Frame_Bytes (Decoder));
         View : constant Pictlib.Images.Mutable_Image_View := Pictlib_Testing.Canvases.Frame_View (Decoder, Storage);
      begin
         Outcome := Pictlib.Decoding.Render (Decoder, View);
         if Pictlib.Results.Succeeded (Outcome) and then Reference'Length > 0 then
            declare
               Raster : Pictlib_Testing.Files.Raster;
               Wrong : Natural := 0;
            begin
               if not Pictlib_Testing.Files.Read_Raster (Reference, Raster)
                 or else Raster.Width /= Width or else Raster.Height /= Height
               then
                  Pictlib_Testing.Tools.Fail (Reference & ": not a raster of the picture's frame");
               else
                  for Y in 0 .. Height - 1 loop
                     for X in 0 .. Width - 1 loop
                        if Pictlib_Testing.Canvases.Difference
                             (Pictlib_Testing.Canvases.Pixel (View, X, Y), Pictlib_Testing.Files.Pixel (Raster, X, Y))
                           > Pictlib_Testing.Canvases.JPEG_Decoder_Tolerance
                        then
                           Wrong := Wrong + 1;
                        end if;
                     end loop;
                  end loop;
                  if Wrong > 0 then
                     Pictlib_Testing.Tools.Fail
                       (Reference & ":" & Wrong'Image & " pixels differ from the reference");
                  end if;
               end if;
            end;
         end if;
         Free (Storage);
         if Pictlib.Results.Succeeded (Outcome) then
            for Index in 1 .. Pictlib.Decoding.Warning_Count (Decoder) loop
               if Pictlib.Errors."=" (Pictlib.Decoding.Warning_At (Decoder, Index).Code, Pictlib.Errors.Partial_Picture)
               then
                  return "partial";
               end if;
            end loop;
         end if;
         return Code_Of (Outcome);
      end;
   end Render;

   procedure Visit (Directory : String) is
      use Ada.Directories;
      Search : Search_Type;
      Item : Directory_Entry_Type;
   begin
      Start_Search (Search, Directory, "*");
      while More_Entries (Search) loop
         Get_Next_Entry (Search, Item);
         declare
            Name : constant String := Simple_Name (Item);
            Path : constant String := Full_Name (Item);
            Relative : constant String := Directory (Directory'First + Root'Length + 1 .. Directory'Last) & "/" & Name;
         begin
            if Name (Name'First) = '.' then
               null;
            elsif Kind (Item) = Ada.Directories.Directory then
               Visit (Directory & "/" & Name);
            elsif Extension (Name) in "pct" | "pict" | "PCT" | "PICT" then
               declare
                  Data : Bytes_Access := Pictlib_Testing.Files.Load_Path (Path);
                  Line : Unbounded_String;
               begin
                  Line := To_Unbounded_String (Enumerate (Data));
                  Append (Line, " " & Render
                            (Data, Pictlib.Compatible,
                             (if Exists (Path & ".reference.ppm") then Path & ".reference.ppm" else "")));
                  Append (Line, " " & Render (Data, Pictlib.Recover_When_Safe));
                  Results_Now.Include (Relative, To_String (Line));
                  Free (Data);
               exception
                  when Error : others =>
                     Defects := Defects + 1;
                     Results_Now.Include (Relative, "exception " & Ada.Exceptions.Exception_Name (Error));
               end;
            end if;
         end;
      end loop;
      End_Search (Search);
   end Visit;

   Expected : Outcome_Maps.Map;
   Mismatches : Natural := 0;
begin
   if not Pictlib_Testing.Tools.Enter_Tests_Directory then
      return;
   end if;
   Pictlib_Testing.Tools.Start_Report ("pictlib_real_world");
   Visit (Root);
   if Ada.Directories.Exists (Expected_File) then
      declare
         File : Ada.Text_IO.File_Type;
      begin
         Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Expected_File);
         while not Ada.Text_IO.End_Of_File (File) loop
            declare
               Line : constant String := Ada.Text_IO.Get_Line (File);
            begin
               for Index in Line'Range loop
                  if Line (Index) = ' ' then
                     Expected.Include (Line (Line'First .. Index - 1), Line (Index + 1 .. Line'Last));
                     exit;
                  end if;
               end loop;
            end;
         end loop;
         Ada.Text_IO.Close (File);
      end;
   end if;
   for Position in Results_Now.Iterate loop
      declare
         Name : constant String := Outcome_Maps.Key (Position);
         Got : constant String := Outcome_Maps.Element (Position);
         Want : constant String := (if Expected.Contains (Name) then Expected.Element (Name) else "(none)");
      begin
         if Got = Want then
            Ada.Text_IO.Put_Line ("PASS " & Name & " " & Got);
         else
            Mismatches := Mismatches + 1;
            Ada.Text_IO.Put_Line ("FAIL " & Name & " " & Got & "; expected " & Want);
         end if;
      end;
   end loop;
   --  A recorded picture that is no longer on disk is a mismatch too: a corpus that lost files must not pass.
   for Position in Expected.Iterate loop
      if not Results_Now.Contains (Outcome_Maps.Key (Position)) then
         Mismatches := Mismatches + 1;
         Ada.Text_IO.Put_Line ("FAIL " & Outcome_Maps.Key (Position) & " is recorded but missing");
      end if;
   end loop;
   if Project_Tools.Processes.Has_Argument ("--update") and then Defects = 0 then
      declare
         File : Ada.Text_IO.File_Type;
      begin
         Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Expected_File);
         for Position in Results_Now.Iterate loop
            Ada.Text_IO.Put_Line (File, Outcome_Maps.Key (Position) & " " & Outcome_Maps.Element (Position));
         end loop;
         Ada.Text_IO.Close (File);
      end;
      Ada.Text_IO.Put_Line ("updated " & Expected_File);
   elsif Mismatches > 0 then
      Pictlib_Testing.Tools.Fail (Mismatches'Image & " pictures differ from " & Expected_File);
   end if;
   if Defects > 0 then
      Pictlib_Testing.Tools.Fail (Defects'Image & " pictures raised an exception");
   end if;
   Ada.Text_IO.Put_Line (Natural'Image (Natural (Results_Now.Length)) & " pictures," & Defects'Image & " defects,"
                         & Mismatches'Image & " mismatches");
   Pictlib_Testing.Tools.Finish_Report;
end Pictlib_Real_World;
