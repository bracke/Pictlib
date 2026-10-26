--  The day-to-day gate: the library builds on its own, the sources keep the policy, and the AUnit suite passes.
--  The policy holds independent of what an incremental build recompiled: lines of at most 120 characters in
--  every Ada source of both crates, GNATdoc tags on every public subprogram of the public packages,
--  production units that depend only on Ada, Interfaces, GNAT, pictlib, jpeglib's public packages and
--  textrender, an invariant registry true to the suite, and a README whose example is the example program,
--  which runs. --policy-only checks the sources alone. Run from
--  anywhere below the pictlib tree, after `alr --chdir=tests build`.
with Ada.Directories;
with Ada.Exceptions;
with Ada.Strings.Unbounded;
with Pictlib_Testing.Source_Policy;
with Pictlib_Testing.Tools;
with Project_Tools.Processes;

procedure Pictlib_Check is
   procedure Fail (Message : String) renames Pictlib_Testing.Tools.Fail;
   use Ada.Strings.Unbounded;

   Root : constant String := Pictlib_Testing.Tools.Root;

   function Is_Ada (Name : String) return Boolean is
     (Ada.Directories.Extension (Name) in "ads" | "adb");

   procedure Check_Tree (Directory : String; Production : Boolean) is
   begin
      for Path of Pictlib_Testing.Tools.Files_Below (Directory) loop
         if Is_Ada (Path) then
            Pictlib_Testing.Source_Policy.Check_Line_Lengths (Path);
            if Production then
               Pictlib_Testing.Source_Policy.Check_Production_Unit (Path);
            end if;
         end if;
      end loop;
   end Check_Tree;
   Policy_Only : constant Boolean := Project_Tools.Processes.Has_Argument ("--policy-only");

   --  Run one policy step; one that raises is a finding, and the steps and the suite after it still run.
   procedure Policy_Step (Label : String; Step : not null access procedure) is
   begin
      Step.all;
   exception
      when Error : others =>
         Fail (Label & " stopped: " & Ada.Exceptions.Exception_Information (Error));
   end Policy_Step;

   procedure Check_Sources is
   begin
      Check_Tree (Root & "/src", Production => True);
      Check_Tree (Root & "/tests/src", Production => False);
   end Check_Sources;
   procedure Check_Registry is
   begin
      Pictlib_Testing.Source_Policy.Check_Registry (Root);
   end Check_Registry;
   procedure Check_Suite is
   begin
      Pictlib_Testing.Source_Policy.Check_Suite (Root);
   end Check_Suite;
   procedure Check_Tooling is
   begin
      Pictlib_Testing.Source_Policy.Check_Tooling (Root);
   end Check_Tooling;
   procedure Check_Readme is
   begin
      Pictlib_Testing.Source_Policy.Check_Readme (Root);
   end Check_Readme;

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
   if not Pictlib_Testing.Tools.Arguments_Known ([new String'("--policy-only")]) then
      Pictlib_Testing.Tools.Finish_Report;
      return;
   end if;
   if Root'Length = 0 then
      Fail ("run below the pictlib tree");
   else
      if not Policy_Only then
         --  The library alone, as a consumer builds it.
         declare
            Alr : constant String := Pictlib_Testing.Tools.Alr;
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
      Policy_Step ("the source checks", Check_Sources'Access);
      Policy_Step ("the registry check", Check_Registry'Access);
      Policy_Step ("the suite check", Check_Suite'Access);
      Policy_Step ("the tooling check", Check_Tooling'Access);
      Policy_Step ("the README check", Check_Readme'Access);
      --  The suite runs whatever the policy found, so a policy finding never hides a failing test.
      if not Policy_Only then
         Run ("unit tests", Root & "/tests",
              Root & "/tests/bin/pictlib_tests" & Pictlib_Testing.Tools.Executable_Suffix,
              [1 .. 0 => Null_Unbounded_String]);
         --  The README's example runs too, so what it shows is code that works, not only code that compiles.
         Run ("README example", Root & "/tests",
              Root & "/tests/bin/pictlib_example" & Pictlib_Testing.Tools.Executable_Suffix,
              [1 .. 0 => Null_Unbounded_String]);
      end if;
   end if;
   Pictlib_Testing.Tools.Finish_Report;
end Pictlib_Check;
