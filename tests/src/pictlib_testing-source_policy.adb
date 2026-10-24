with Ada.Characters.Handling;
with Ada.Containers.Indefinite_Ordered_Sets;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Pictlib_Testing.Tools;
with Project_Tools.Ada_Source;

package body Pictlib_Testing.Source_Policy is
   use Ada.Strings.Unbounded;

   procedure Fail (Message : String) renames Pictlib_Testing.Tools.Fail;

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

   procedure Check_Line_Lengths (Path : String) is
      File : Ada.Text_IO.File_Type;
      Number : Natural := 0;
   begin
      Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Path);
      while not Ada.Text_IO.End_Of_File (File) loop
         declare
            Line : constant String := Ada.Text_IO.Get_Line (File);
         begin
            Number := Number + 1;
            if Line'Length > Longest_Line then
               Fail (Path & ":" & Number'Image & ": line of" & Line'Length'Image & " characters");
            end if;
         end;
      end loop;
      Ada.Text_IO.Close (File);
   end Check_Line_Lengths;

   procedure Check_Production_Unit (Path : String) is
      None : constant Project_Tools.Ada_Source.String_List := [1 .. 0 => Null_Unbounded_String];
      Name : constant String := Ada.Directories.Simple_Name (Path);
   begin
      Check_Dependencies (Path);
      --  The project_tools checks raise on what they find: a finding, not the end of the gate.
      begin
         Project_Tools.Ada_Source.Require_Only_Allowed_With_Clauses
           (Path, "Jpeglib.",
            [To_Unbounded_String ("Jpeglib.Decoding"), To_Unbounded_String ("Jpeglib.Errors"),
             To_Unbounded_String ("Jpeglib.Images"), To_Unbounded_String ("Jpeglib.Limits"),
             To_Unbounded_String ("Jpeglib.Results"), To_Unbounded_String ("Jpeglib.Streams")]);
         Project_Tools.Ada_Source.Require_Only_Allowed_With_Clauses (Path, "Jpeglib.Internal", None);
         Project_Tools.Ada_Source.Require_Only_Allowed_With_Clauses (Path, "AUnit", None);
         Project_Tools.Ada_Source.Require_Only_Allowed_With_Clauses (Path, "Project_Tools", None);
         Project_Tools.Ada_Source.Require_Only_Allowed_With_Clauses (Path, "Pictlib_Testing", None);
         if Ada.Directories.Extension (Name) = "ads" and then Ada.Strings.Fixed.Index (Name, "-internal") = 0 then
            Project_Tools.Ada_Source.Require_Public_GNATdoc_Tags (Path);
         end if;
      exception
         when Error : others =>
            Fail (Path & ": " & Ada.Exceptions.Exception_Message (Error));
      end;
   end Check_Production_Unit;

   package Name_Sets is new Ada.Containers.Indefinite_Ordered_Sets (String);

   function Read_Whole (Path : String) return String is
      File : Ada.Text_IO.File_Type;
      Text : Unbounded_String;
   begin
      Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Path);
      while not Ada.Text_IO.End_Of_File (File) loop
         Append (Text, Ada.Text_IO.Get_Line (File) & ASCII.LF);
      end loop;
      Ada.Text_IO.Close (File);
      return To_String (Text);
   end Read_Whole;

   --  Each file of Directory with Extension, in turn.
   generic
      with procedure Each (Path : String);
   procedure For_Files (Directory, Extension : String);

   procedure For_Files (Directory, Extension : String) is
      use Ada.Directories;
      Search : Search_Type;
      Item : Directory_Entry_Type;
   begin
      Start_Search (Search, Directory, "*." & Extension, [Ordinary_File => True, others => False]);
      while More_Entries (Search) loop
         Get_Next_Entry (Search, Item);
         Each (Full_Name (Item));
      end loop;
      End_Search (Search);
   end For_Files;

   procedure Check_Registry (Root : String) is
      Routines, Tools_Found : Name_Sets.Set;
      Registry : constant String := Root & "/docs/invariants.md";

      --  Every routine name: the first string literal after each Register_Routine.
      procedure Collect_Routines (Path : String) is
         Text : constant String := Read_Whole (Path);
         From : Natural := Text'First;
      begin
         loop
            From := Ada.Strings.Fixed.Index (Text (From .. Text'Last), "Register_Routine");
            exit when From = 0;
            declare
               Open : constant Natural := Ada.Strings.Fixed.Index (Text (From .. Text'Last), """");
               Close : constant Natural :=
                 (if Open = 0 then 0 else Ada.Strings.Fixed.Index (Text (Open + 1 .. Text'Last), """"));
            begin
               exit when Close = 0;
               Routines.Include (Text (Open + 1 .. Close - 1));
               From := Close + 1;
            end;
         end loop;
      end Collect_Routines;
      procedure Collect_Tool (Path : String) is
      begin
         Tools_Found.Include (Ada.Directories.Base_Name (Path));
      end Collect_Tool;
      procedure Each_Body is new For_Files (Collect_Routines);
      procedure Each_Main is new For_Files (Collect_Tool);

      function Covered (Name : String) return Boolean is
      begin
         if Name'Length > 2 and then Name (Name'Last - 1 .. Name'Last) = ".*" then
            for Routine of Routines loop
               if Routine'Length >= Name'Length - 1
                 and then Routine (Routine'First .. Routine'First + Name'Length - 2)
                          = Name (Name'First .. Name'Last - 1)
               then
                  return True;
               end if;
            end loop;
            return False;
         end if;
         return Routines.Contains (Name) or else Tools_Found.Contains (Name);
      end Covered;

      function Is_Name (Item : String) return Boolean is
        (Item'Length > 0 and then Item (Item'First) in 'a' .. 'z'
         and then (for all C of Item => C in 'a' .. 'z' | '0' .. '9' | '_' | '.' | '*')
         and then (Ada.Strings.Fixed.Index (Item, ".") > 0
                   or else (Item'Length > 8 and then Item (Item'First .. Item'First + 7) = "pictlib_")));

      Text : constant String := Read_Whole (Registry);
      Listed : Name_Sets.Set;
      Position : Natural := Text'First;
   begin
      Each_Body (Root & "/tests/src", "adb");
      Each_Main (Root & "/tests/src/mains", "adb");
      loop
         declare
            Open : constant Natural := Ada.Strings.Fixed.Index (Text (Position .. Text'Last), "`");
            Close : constant Natural :=
              (if Open = 0 then 0 else Ada.Strings.Fixed.Index (Text (Open + 1 .. Text'Last), "`"));
         begin
            exit when Close = 0;
            declare
               Item : constant String := Text (Open + 1 .. Close - 1);
            begin
               if Is_Name (Item) and then not Covered (Item) then
                  Fail (Registry & ": `" & Item & "` is no registered test routine or tool");
               end if;
               Listed.Include (Item);
            end;
            Position := Close + 1;
         end;
      end loop;
      --  Every capability constant has a row of its own.
      declare
         Capabilities : constant String := Read_Whole (Root & "/src/pictlib-capabilities.ads");
         From : Natural := Capabilities'First;
      begin
         loop
            From := Ada.Strings.Fixed.Index (Capabilities (From .. Capabilities'Last), " : constant Boolean");
            exit when From = 0;
            declare
               Start : Natural := From;
            begin
               while Start > Capabilities'First and then Capabilities (Start - 1) /= ' ' loop
                  Start := Start - 1;
               end loop;
               if Ada.Strings.Fixed.Index (Text, "| `" & Capabilities (Start .. From - 1) & "` |") = 0 then
                  Fail (Registry & ": capability " & Capabilities (Start .. From - 1) & " has no row");
               end if;
            end;
            From := From + 1;
         end loop;
      end;
   end Check_Registry;
end Pictlib_Testing.Source_Policy;
