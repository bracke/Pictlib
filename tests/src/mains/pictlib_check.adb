--  The day-to-day gate: the library builds on its own, the sources keep the policy, and the AUnit suite passes.
--  The policy holds independent of what an incremental build recompiled: lines of at most 120 characters in
--  every Ada source of both crates, GNATdoc tags on every public subprogram of the public packages, and
--  production units that depend only on Ada, Interfaces, GNAT, pictlib, jpeglib's public packages and
--  textrender. --policy-only checks the sources alone. Run from anywhere below the pictlib tree, after
--  `alr --chdir tests build`.
with Ada.Command_Line;
with Ada.Characters.Handling;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Project_Tools.Ada_Source;
with Pictlib_Testing.Tools;
with Project_Tools.Files;
with Project_Tools.Processes;

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

   --  Production units depend only on Ada, Interfaces (not Interfaces.C), GNAT, System, pictlib, jpeglib and
   --  textrender, and bind no foreign code: no Import, Export or Convention C. Context clauses are read a line
   --  at a time, as the sources write them.
   procedure Check_Dependencies (Path : String) is
      use Ada.Characters.Handling;
      File : Ada.Text_IO.File_Type;
      Number : Natural := 0;
      --  Context clauses end where the unit begins; a later "with" is an aspect specification.
      In_Context : Boolean := True;

      function Starts (Line, Word : String) return Boolean is
        (Line'Length >= Word'Length and then Line (Line'First .. Line'First + Word'Length - 1) = Word);

      function Allowed (Unit : String) return Boolean is
         Root_End : Natural := Unit'Last;
      begin
         for Index in Unit'Range loop
            if Unit (Index) = '.' then
               Root_End := Index - 1;
               exit;
            end if;
         end loop;
         return Unit (Unit'First .. Root_End) in "ada" | "interfaces" | "gnat" | "system" | "pictlib" | "jpeglib"
                                                 | "textrender"
           and then Unit /= "interfaces.c" and then not (Unit'Length > 13 and then Unit (Unit'First .. Unit'First + 12)
                                                        = "interfaces.c.");
      end Allowed;

      function Contains (Text, Part : String) return Boolean is
        (Index (To_Unbounded_String (Text), Part) > 0);
   begin
      Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Path);
      while not Ada.Text_IO.End_Of_File (File) loop
         declare
            Raw : constant String := To_Lower (Ada.Text_IO.Get_Line (File));
            First : Positive := Raw'First;
         begin
            Number := Number + 1;
            while First <= Raw'Last and then Raw (First) = ' ' loop
               First := First + 1;
            end loop;
            declare
               Line : constant String := Raw (First .. Raw'Last);
               Units_First : constant Natural :=
                 (if not In_Context then 0
                  elsif Line'Length > 5 and then Line (Line'First .. Line'First + 4) = "with " then Line'First + 5
                  elsif Line'Length > 13 and then Line (Line'First .. Line'First + 12) = "limited with "
                  then Line'First + 13
                  elsif Line'Length > 13 and then Line (Line'First .. Line'First + 12) = "private with "
                  then Line'First + 13
                  else 0);
            begin
               if Starts (Line, "package ") or else Starts (Line, "procedure ") or else Starts (Line, "function ")
                 or else Starts (Line, "generic") or else Starts (Line, "separate")
                 or else Starts (Line, "private package ")
               then
                  In_Context := False;
               end if;
               if Units_First > 0 then
                  declare
                     Start : Positive := Units_First;
                  begin
                     for Index in Units_First .. Line'Last loop
                        if Line (Index) in ',' | ';' then
                           declare
                              Unit : constant String :=
                                Ada.Strings.Unbounded.To_String
                                  (Ada.Strings.Unbounded.Trim
                                     (To_Unbounded_String (Line (Start .. Index - 1)), Ada.Strings.Both));
                           begin
                              if Unit'Length > 0 and then not Allowed (Unit) then
                                 Fail (Path & ":" & Number'Image & ": production code depends on " & Unit);
                              end if;
                           end;
                           Start := Index + 1;
                           exit when Line (Index) = ';';
                        end if;
                     end loop;
                  end;
               end if;
               if Contains (Line, "pragma import") or else Contains (Line, "pragma export")
                 or else Contains (Line, "pragma interface") or else Contains (Line, "import => true")
                 or else Contains (Line, "export => true") or else Contains (Line, "convention => c")
                 or else Contains (Line, "pragma convention")
               then
                  Fail (Path & ":" & Number'Image & ": production code binds foreign code");
               end if;
            end;
         end;
      end loop;
      Ada.Text_IO.Close (File);
   end Check_Dependencies;

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
                  Check_Dependencies (Path);
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
   if Failures > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Pictlib_Check;
