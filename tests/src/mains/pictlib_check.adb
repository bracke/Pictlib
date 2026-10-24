--  Source policy, independent of what an incremental build recompiled: lines of at most 120 characters in every
--  Ada source of both crates, GNATdoc tags on every public subprogram of the public packages, and production
--  units that depend only on Ada, Interfaces, GNAT, pictlib, jpeglib's public packages and textrender.
--  Run from anywhere below the pictlib tree.
with Ada.Command_Line;
with Ada.Directories;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Project_Tools.Ada_Source;
with Project_Tools.Files;

procedure Pictlib_Check is
   use Ada.Strings.Unbounded;

   Root : constant String :=
     Project_Tools.Files.Find_Root_Upward (Ada.Directories.Current_Directory, "pictlib.gpr");
   Longest : constant := 120;
   Failures : Natural := 0;

   procedure Fail (Message : String) is
   begin
      Failures := Failures + 1;
      Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, "pictlib_check: " & Message);
   end Fail;

   function Is_Ada (Name : String) return Boolean is
     (Ada.Directories.Extension (Name) in "ads" | "adb");

   procedure Check_Lines (Path : String) is
      File : Ada.Text_IO.File_Type;
      Number : Natural := 0;
   begin
      Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Path);
      while not Ada.Text_IO.End_Of_File (File) loop
         declare
            Line : constant String := Ada.Text_IO.Get_Line (File);
         begin
            Number := Number + 1;
            if Line'Length > Longest then
               Fail (Path & ":" & Number'Image & ": line of" & Line'Length'Image & " characters");
            end if;
         end;
      end loop;
      Ada.Text_IO.Close (File);
   end Check_Lines;

   procedure Check_Tree (Directory : String; Production : Boolean) is
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
         begin
            if Name (Name'First) = '.' then
               null;
            elsif Kind (Item) = Ada.Directories.Directory then
               Check_Tree (Path, Production);
            elsif Is_Ada (Name) then
               Check_Lines (Path);
               if Production then
                  --  Production code reaches jpeglib only through its public packages, and never tests or tools.
                  Project_Tools.Ada_Source.Require_Only_Allowed_With_Clauses
                    (Path, "Jpeglib.",
                     [To_Unbounded_String ("Jpeglib.Decoding"), To_Unbounded_String ("Jpeglib.Errors"),
                      To_Unbounded_String ("Jpeglib.Images"), To_Unbounded_String ("Jpeglib.Limits"),
                      To_Unbounded_String ("Jpeglib.Results"), To_Unbounded_String ("Jpeglib.Streams")]);
                  Project_Tools.Ada_Source.Require_Only_Allowed_With_Clauses
                    (Path, "Jpeglib.Internal", [1 .. 0 => Null_Unbounded_String]);
                  Project_Tools.Ada_Source.Require_Only_Allowed_With_Clauses
                    (Path, "AUnit", [1 .. 0 => Null_Unbounded_String]);
                  Project_Tools.Ada_Source.Require_Only_Allowed_With_Clauses
                    (Path, "Project_Tools", [1 .. 0 => Null_Unbounded_String]);
                  Project_Tools.Ada_Source.Require_Only_Allowed_With_Clauses
                    (Path, "Pictlib_Testing", [1 .. 0 => Null_Unbounded_String]);
                  if Extension (Name) = "ads" and then Index (To_Unbounded_String (Name), "-internal") = 0 then
                     Project_Tools.Ada_Source.Require_Public_GNATdoc_Tags (Path);
                  end if;
               end if;
            end if;
         end;
      end loop;
      End_Search (Search);
   end Check_Tree;
begin
   if Root'Length = 0 then
      Fail ("run below the pictlib tree");
   else
      Check_Tree (Root & "/src", Production => True);
      Check_Tree (Root & "/tests/src", Production => False);
   end if;
   if Failures > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Pictlib_Check;
