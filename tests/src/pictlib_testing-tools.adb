with Ada.Command_Line;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with GNAT.OS_Lib;
with Project_Tools.Files;
with Project_Tools.Processes;

package body Pictlib_Testing.Tools is
   Tool_Name : Ada.Strings.Unbounded.Unbounded_String;
   Failed : Natural := 0;

   function Root return String is
     (Project_Tools.Files.Find_Root_Upward (Ada.Directories.Current_Directory, "pictlib.gpr"));

   function Alr return String is (Project_Tools.Processes.Locate_Command ("alr"));

   function Enter_Tests_Directory return Boolean is
      Tree : constant String := Root;
   begin
      if Tree'Length = 0 then
         Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, "run below a pictlib tree");
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         return False;
      end if;
      Ada.Directories.Set_Directory (Tree & "/tests");
      return True;
   end Enter_Tests_Directory;

   procedure Start_Report (Tool : String) is
   begin
      Tool_Name := Ada.Strings.Unbounded.To_Unbounded_String (Tool);
      Failed := 0;
   end Start_Report;

   procedure Fail (Message : String) is
   begin
      Failed := Failed + 1;
      Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, Ada.Strings.Unbounded.To_String (Tool_Name) & ": " & Message);
   end Fail;

   function Failures return Natural is (Failed);

   procedure Finish_Report is
   begin
      if Failed > 0 then
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      end if;
   end Finish_Report;

   function Executable_Suffix return String is
      Suffix : GNAT.OS_Lib.String_Access := GNAT.OS_Lib.Get_Executable_Suffix;
      Result : constant String := Suffix.all;
   begin
      GNAT.OS_Lib.Free (Suffix);
      return Result;
   end Executable_Suffix;

   function ImageMagick return String is
      Seven : constant String := Project_Tools.Processes.Locate_Command ("magick");
      Six : constant String := Project_Tools.Processes.Locate_Command ("convert");
   begin
      if Seven'Length > 0 then
         return Seven;
      elsif Six'Length = 0 then
         return "";
      end if;
      declare
         Status : aliased Integer := -1;
         Version : constant String :=
           Project_Tools.Processes.Command_Output
             (Six, Project_Tools.Processes.Arguments ([Project_Tools.Processes.Argument ("-version")]),
              Status => Status'Access, Err_To_Out => True);
      begin
         return (if Status = 0 and then Ada.Strings.Fixed.Index (Version, "ImageMagick") > 0 then Six else "");
      end;
   end ImageMagick;

   package Name_Sorting is new Name_Vectors.Generic_Sorting;

   function Files_Below (Directory : String; Recursive : Boolean := True) return Name_Vectors.Vector is
      Result : Name_Vectors.Vector;

      procedure Collect (Path : String) is
         use Ada.Directories;
         Search : Search_Type;
         Item : Directory_Entry_Type;
      begin
         Start_Search (Search, Path, "*");
         while More_Entries (Search) loop
            Get_Next_Entry (Search, Item);
            declare
               Name : constant String := Simple_Name (Item);
            begin
               if Name (Name'First) = '.' then
                  null;
               elsif Kind (Item) = Ada.Directories.Directory then
                  if Recursive then
                     Collect (Full_Name (Item));
                  end if;
               elsif Kind (Item) = Ordinary_File then
                  Result.Append (Full_Name (Item));
               end if;
            end;
         end loop;
         End_Search (Search);
      end Collect;
   begin
      if Ada.Directories.Exists (Directory) then
         --  From the full name: an entry's full name is relative when its search's directory was.
         Collect (Ada.Directories.Full_Name (Directory));
         Name_Sorting.Sort (Result);
      end if;
      return Result;
   end Files_Below;

   function Arguments_Known (Flags : Option_List; Valued : Option_List := [1 .. 0 => null]) return Boolean is
      Index : Positive := 1;
   begin
      while Index <= Ada.Command_Line.Argument_Count loop
         declare
            Item : constant String := Ada.Command_Line.Argument (Index);
         begin
            if (for some Flag of Flags => Flag.all = Item) then
               Index := Index + 1;
            elsif (for some Option of Valued => Option.all = Item) then
               --  A value that is another option means the value was left out.
               if Index = Ada.Command_Line.Argument_Count
                 or else Ada.Strings.Fixed.Index (Ada.Command_Line.Argument (Index + 1), "--") = 1
               then
                  Fail (Item & " needs a value");
                  return False;
               end if;
               Index := Index + 2;
            else
               Fail ("unknown argument " & Item);
               return False;
            end if;
         end;
      end loop;
      return True;
   end Arguments_Known;

   function Version_Of (Program : String; Flag : String := "--version") return String is
      Status : aliased Integer := -1;
      Output : constant String :=
        Project_Tools.Processes.Command_Output
          (Program, Project_Tools.Processes.Arguments ([Project_Tools.Processes.Argument (Flag)]),
           Status => Status'Access, Err_To_Out => True);
      Line_End : constant Natural := Ada.Strings.Fixed.Index (Output, [1 => ASCII.LF]);
   begin
      if Status /= 0 then
         return "";
      end if;
      return Ada.Strings.Fixed.Trim
        ((if Line_End = 0 then Output else Output (Output'First .. Line_End - 1)), Ada.Strings.Both);
   end Version_Of;

   procedure Report_Version (Label, Program : String; Flag : String := "--version") is
      Version : constant String := Version_Of (Program, Flag);
   begin
      Ada.Text_IO.Put_Line
        (Label & ": " & Program & " (" & (if Version'Length = 0 then "version unknown" else Version) & ")");
   end Report_Version;

   function Gnatprove return String is
      Name : constant String := "gnatprove" & Executable_Suffix;

      --  The gnatprove `alr install` put under the home directory named by Variable, or "".
      function Installed_Under (Variable : String) return String is
      begin
         if Ada.Environment_Variables.Exists (Variable) then
            declare
               Path : constant String := Ada.Environment_Variables.Value (Variable) & "/.alire/bin/" & Name;
            begin
               if Ada.Directories.Exists (Path) then
                  return Path;
               end if;
            end;
         end if;
         return "";
      end Installed_Under;

      Home : constant String := Installed_Under ("HOME");
      Profile : constant String := Installed_Under ("USERPROFILE");
   begin
      --  An Alire-installed gnatprove matches the pinned toolchain; a PATH one may be a distribution's.
      if Home'Length > 0 then
         return Home;
      elsif Profile'Length > 0 then
         return Profile;
      end if;
      return Project_Tools.Processes.Locate_Command ("gnatprove");
   end Gnatprove;
end Pictlib_Testing.Tools;
