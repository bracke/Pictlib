with Ada.Characters.Handling;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Pictlib_Testing.Tools;

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
end Pictlib_Testing.Source_Policy;
