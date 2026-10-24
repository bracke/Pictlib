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
   --  textrender, and bind no foreign code. The unit is read whole, without comments, strings and character
   --  literals, and lower-cased: context clauses are taken clause by clause up to the unit itself, however
   --  they are laid out, and the words that interface foreign code (Import, Export, Convention, External_Name,
   --  Link_Name, Machine_Code, pragma Interface) are refused anywhere, however they are spaced.
   procedure Check_Dependencies (Path : String) is
      use Ada.Characters.Handling;
      Text : Unbounded_String;

      procedure Load is
         File : Ada.Text_IO.File_Type;
      begin
         Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Path);
         while not Ada.Text_IO.End_Of_File (File) loop
            declare
               Line : constant String := Ada.Text_IO.Get_Line (File);
               Kept : String (Line'Range) := [others => ' '];
               In_String : Boolean := False;
               Index : Natural := Line'First;
            begin
               while Index <= Line'Last loop
                  if In_String then
                     if Line (Index) = '"' then
                        In_String := False;
                     end if;
                  elsif Line (Index) = '"' then
                     In_String := True;
                  elsif Line (Index) = ''' and then Index + 2 <= Line'Last and then Line (Index + 2) = ''' then
                     --  A character literal is skipped whole, so a '"' or a '-' in one means nothing.
                     Index := Index + 2;
                  elsif Line (Index) = '-' and then Index < Line'Last and then Line (Index + 1) = '-' then
                     exit;
                  else
                     Kept (Index) := To_Lower (Line (Index));
                  end if;
                  Index := Index + 1;
               end loop;
               Append (Text, Kept & ' ');
            end;
         end loop;
         Ada.Text_IO.Close (File);
      end Load;

      function Is_Word (Item : Character) return Boolean is (Is_Alphanumeric (Item) or else Item in '_' | '.');

      --  The next word or symbol of Source from Index on, Index moved past it; empty at the end.
      procedure Next (Source : String; Index : in out Positive; Token : out Unbounded_String) is
      begin
         Token := Null_Unbounded_String;
         while Index <= Source'Last and then Source (Index) = ' ' loop
            Index := Index + 1;
         end loop;
         if Index > Source'Last then
            return;
         elsif Is_Word (Source (Index)) then
            while Index <= Source'Last and then Is_Word (Source (Index)) loop
               Append (Token, Source (Index));
               Index := Index + 1;
            end loop;
         else
            Token := To_Unbounded_String ([1 => Source (Index)]);
            Index := Index + 1;
         end if;
      end Next;

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
           and then Unit /= "interfaces.c"
           and then not (Unit'Length > 13 and then Unit (Unit'First .. Unit'First + 12) = "interfaces.c.");
      end Allowed;
   begin
      Load;
      declare
         Source : constant String := To_String (Text);
         Index : Positive := Source'First;
         Token, Previous : Unbounded_String;
         In_Context : Boolean := True;
         Clause_Start : Boolean := True;
         In_With : Boolean := False;
      begin
         loop
            if Length (Token) > 0 then
               Previous := Token;
            end if;
            Next (Source, Index, Token);
            exit when Length (Token) = 0;
            declare
               Word : constant String := To_String (Token);
            begin
               if Word in "import" | "export" | "convention" | "external_name" | "link_name" | "machine_code"
                         | "system.machine_code"
                 or else (Word = "interface" and then To_String (Previous) = "pragma")
               then
                  Fail (Path & ": production code binds foreign code (" & Word & ")");
               end if;
               --  Context clauses, one by one, until the unit begins.
               if In_Context then
                  if Clause_Start and then Word in "package" | "procedure" | "function" | "generic" | "separate"
                  then
                     In_Context := False;
                  elsif Word = ";" then
                     Clause_Start := True;
                     In_With := False;
                  elsif Clause_Start and then Word in "limited" | "private" then
                     null;
                  elsif Clause_Start and then Word = "with" then
                     Clause_Start := False;
                     In_With := True;
                  elsif In_With and then Word /= "," then
                     if not Allowed (Word) then
                        Fail (Path & ": production code depends on " & Word);
                     end if;
                  else
                     Clause_Start := False;
                  end if;
               end if;
            end;
         end loop;
      end;
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
