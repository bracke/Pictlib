with Ada.Command_Line;
with AUnit;
with AUnit.Reporter.Text;
with AUnit.Run;
with Pictlib_Testing.Suite;

procedure Pictlib_Tests is
   use type AUnit.Status;

   function Run is new AUnit.Run.Test_Runner_With_Status (Pictlib_Testing.Suite.All_Tests);
   Reporter : AUnit.Reporter.Text.Text_Reporter;
   Status : AUnit.Status;
begin
   Status := Run (Reporter);
   if Status /= AUnit.Success then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Pictlib_Tests;
