with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Strings.Fixed;
with GNAT.OS_Lib;
with Project_Tools.Processes;

package body Pictlib_Testing.Tools is
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
