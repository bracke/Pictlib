--  The SPARK proof profile: gnatprove, through `alr exec`, on every proof-designated unit of
--  proof/pictlib_proof.gpr. Fails on an unproved check, a severity diagnostic, or a declared SPARK body that was
--  skipped. Run from anywhere below the pictlib tree.
with Ada.Command_Line;
with Ada.Directories;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Project_Tools.Files;
with Project_Tools.Processes;
with Project_Tools.Text;

procedure Pictlib_Prove is
   use Ada.Strings.Unbounded;

   --  The units the profile proves; docs/proof_profile.md says what each proof covers.
   type Unit_List is array (Positive range <>) of Unbounded_String;
   Units : constant Unit_List :=
     [To_Unbounded_String ("pictlib-internal-checked_arithmetic.adb"),
      To_Unbounded_String ("pictlib-images.adb"),
      To_Unbounded_String ("pictlib-opcodes.adb"),
      To_Unbounded_String ("pictlib-internal-packbits.adb")];

   Root : constant String := Project_Tools.Files.Find_Root_Upward (Ada.Directories.Current_Directory, "pictlib.gpr");
   Failures : Natural := 0;

   procedure Fail (Message : String) is
   begin
      Failures := Failures + 1;
      Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, "pictlib_prove: " & Message);
   end Fail;

   procedure Prove (Unit : String) is
      Alr : constant String := Project_Tools.Processes.Locate_Command ("alr");
      Output : Unbounded_String;
      Status : Integer;
   begin
      if Alr'Length = 0 then
         Fail ("alr is not on PATH");
         return;
      end if;
      Status :=
        Project_Tools.Processes.Run_Status
          ("proof profile", Root, Alr,
           Project_Tools.Processes.Arguments
             ([Project_Tools.Processes.Argument ("exec"), Project_Tools.Processes.Argument ("--"),
               Project_Tools.Processes.Argument ("gnatprove"), Project_Tools.Processes.Argument ("-P"),
               Project_Tools.Processes.Argument ("proof/pictlib_proof.gpr"),
               Project_Tools.Processes.Argument ("-u"), Project_Tools.Processes.Argument (Unit),
               Project_Tools.Processes.Argument ("--level=0")]),
           Output);
      declare
         Text : constant String := To_String (Output);
      begin
         if Status /= 0 then
            Fail (Unit & ": gnatprove exited with status" & Status'Image);
         elsif Project_Tools.Text.Contains (Text, "might fail") then
            Fail (Unit & ": unproved checks remain");
         elsif Project_Tools.Text.Contains (Text, "medium:") or else Project_Tools.Text.Contains (Text, "high:") then
            Fail (Unit & ": proof severity diagnostics");
         elsif Project_Tools.Text.Contains (Text, "skipped; body is SPARK_Mode => Off") then
            Fail (Unit & ": a declared SPARK body was skipped");
         else
            Ada.Text_IO.Put_Line ("proved " & Unit);
         end if;
      end;
   end Prove;
begin
   if Root'Length = 0 then
      Fail ("run below the pictlib tree");
   else
      for Unit of Units loop
         Prove (To_String (Unit));
      end loop;
   end if;
   if Failures > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Pictlib_Prove;
