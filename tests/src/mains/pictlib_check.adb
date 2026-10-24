--  The day-to-day gate: the library builds on its own, the sources keep the policy, and the AUnit suite passes.
--  The policy holds independent of what an incremental build recompiled: lines of at most 120 characters in
--  every Ada source of both crates, GNATdoc tags on every public subprogram of the public packages, and
--  production units that depend only on Ada, Interfaces, GNAT, pictlib, jpeglib's public packages and
--  textrender. --policy-only checks the sources alone. Run from anywhere below the pictlib tree, after
--  `alr --chdir tests build`.
with Ada.Directories;
with Ada.Exceptions;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Project_Tools.Ada_Source;
with Pictlib_Testing.Source_Policy;
with Pictlib_Testing.Tools;
with Project_Tools.Files;
with Project_Tools.Processes;

procedure Pictlib_Check is
   procedure Fail (Message : String) renames Pictlib_Testing.Tools.Fail;
   use Ada.Strings.Unbounded;

   Root : constant String :=
     Project_Tools.Files.Find_Root_Upward (Ada.Directories.Current_Directory, "pictlib.gpr");
   Longest : constant := 120;

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
                  Pictlib_Testing.Source_Policy.Check_Dependencies (Path);
                  --  The project_tools checks raise on what they find: a finding, not the end of the gate.
                  begin
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
                  exception
                     when Error : others =>
                        Fail (Path & ": " & Ada.Exceptions.Exception_Message (Error));
                  end;
               end if;
            end if;
         end;
      end loop;
      End_Search (Search);
   end Check_Tree;
   Policy_Only : constant Boolean := Project_Tools.Processes.Has_Argument ("--policy-only");

   procedure Run (Label, Directory, Program : String; Arguments : Project_Tools.Processes.Argument_Items) is
   begin
      if Project_Tools.Processes.Run_Status
           (Label, Directory, Program, Project_Tools.Processes.Arguments (Arguments)) /= 0
      then
         Fail (Label & " failed");
      end if;
   end Run;
begin
   Pictlib_Testing.Tools.Start_Report ("pictlib_check");
   if Root'Length = 0 then
      Fail ("run below the pictlib tree");
   else
      if not Policy_Only then
         --  The library alone, as a consumer builds it.
         declare
            Alr : constant String := Project_Tools.Processes.Locate_Command ("alr");
         begin
            if Alr'Length = 0 then
               Fail ("alr is not on PATH");
            else
               Run ("library build", Root, Alr,
                    [Project_Tools.Processes.Argument ("--non-interactive"),
                     Project_Tools.Processes.Argument ("build")]);
            end if;
         end;
      end if;
      Check_Tree (Root & "/src", Production => True);
      Check_Tree (Root & "/tests/src", Production => False);
      --  The suite runs whatever the policy found, so a policy finding never hides a failing test.
      if not Policy_Only then
         Run ("unit tests", Root & "/tests",
              Root & "/tests/bin/pictlib_tests" & Pictlib_Testing.Tools.Executable_Suffix,
              [1 .. 0 => Null_Unbounded_String]);
      end if;
   end if;
   Pictlib_Testing.Tools.Finish_Report;
end Pictlib_Check;
