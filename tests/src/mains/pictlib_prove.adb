--  The SPARK proof profile: gnatprove, through `alr exec`, on every proof-designated unit of
--  proof/pictlib_proof.gpr. The gnatprove is the one `alr install gnatprove` put under the Alire home, which matches
--  the pinned toolchain; one on PATH only when there is none. Fails on an unproved check, a severity diagnostic,
--  or a declared SPARK body that was skipped. Run from anywhere below the pictlib tree.
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Pictlib_Testing.Tools;
with Project_Tools.Processes;
with Project_Tools.Text;

procedure Pictlib_Prove is
   procedure Fail (Message : String) renames Pictlib_Testing.Tools.Fail;
   function Arg (Value : String) return Ada.Strings.Unbounded.Unbounded_String
     renames Project_Tools.Processes.Argument;
   use Ada.Strings.Unbounded;

   --  The units the profile proves; docs/proof_profile.md says what each proof covers.
   type Unit_List is array (Positive range <>) of Unbounded_String;
   Units : constant Unit_List :=
     [To_Unbounded_String ("pictlib-internal-checked_arithmetic.ads"),
      To_Unbounded_String ("pictlib-images.adb"),
      To_Unbounded_String ("pictlib-opcodes.adb"),
      To_Unbounded_String ("pictlib-internal-packbits.adb")];

   Root : constant String := Pictlib_Testing.Tools.Root;

   Prover : constant String := Pictlib_Testing.Tools.Gnatprove;

   --  Check gnatprove's merged output and status for Unit.
   procedure Check (Unit : String; Text : String; Status : Integer);

   procedure Prove (Unit : String) is
      Alr : constant String := Pictlib_Testing.Tools.Alr;
      Status : aliased Integer := 0;
   begin
      if Alr'Length = 0 then
         Fail ("alr is not on PATH");
         return;
      elsif Prover'Length = 0 then
         Fail ("gnatprove is neither on PATH nor installed by alr (alr install gnatprove)");
         return;
      end if;
      declare
         --  Standard error is captured with standard output: gnatprove reports unproved checks and skipped bodies
         --  there. It exits 0 for unproved checks unless asked, so both the status and the text decide.
         Output : constant String :=
           Project_Tools.Processes.Command_Output
             (Alr,
              Project_Tools.Processes.Arguments
                ([Arg ("--non-interactive"),
                  --  Attached: alr 2.1.1 refuses --chdir with its directory as the next argument.
                  Arg ("--chdir=" & Root), Arg ("exec"),
                  Arg ("--"),
                  Arg (Prover), Arg ("-P"),
                  Arg ("proof/pictlib_proof.gpr"),
                  Arg ("-u"), Arg (Unit),
                  Arg ("--checks-as-errors=on")]),
              Status => Status'Access,
              Err_To_Out => True);
      begin
         Check (Unit, Output, Status);
      end;
   end Prove;

   procedure Check (Unit : String; Text : String; Status : Integer) is
   begin
      --  What gnatprove said, whenever it is not a clean proof, so a failure can be read where it happened.
      if Status /= 0 or else Project_Tools.Text.Contains (Text, "might fail")
        or else Project_Tools.Text.Contains (Text, "medium:") or else Project_Tools.Text.Contains (Text, "high:")
        or else Project_Tools.Text.Contains (Text, "skipped; body is SPARK_Mode => Off")
      then
         Ada.Text_IO.Put_Line (Text);
      end if;
      if Status /= 0 then
         Fail (Unit & ": gnatprove exited with status" & Status'Image & ", unproved checks or an error");
      elsif Project_Tools.Text.Contains (Text, "might fail") then
         Fail (Unit & ": unproved checks remain");
      elsif Project_Tools.Text.Contains (Text, "medium:") or else Project_Tools.Text.Contains (Text, "high:") then
         Fail (Unit & ": proof severity diagnostics");
      elsif Project_Tools.Text.Contains (Text, "skipped; body is SPARK_Mode => Off") then
         Fail (Unit & ": a declared SPARK body was skipped");
      else
         Ada.Text_IO.Put_Line ("proved " & Unit);
      end if;
   end Check;
begin
   Pictlib_Testing.Tools.Start_Report ("pictlib_prove");
   if not Pictlib_Testing.Tools.Arguments_Known ([1 .. 0 => null]) then
      Pictlib_Testing.Tools.Finish_Report;
      return;
   end if;
   if Prover'Length > 0 then
      Pictlib_Testing.Tools.Report_Version ("gnatprove", Prover);
   end if;
   if Root'Length = 0 then
      Fail ("run below the pictlib tree");
   else
      for Unit of Units loop
         Prove (To_String (Unit));
      end loop;
   end if;
   Pictlib_Testing.Tools.Finish_Report;
end Pictlib_Prove;
