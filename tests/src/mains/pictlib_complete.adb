--  The library-complete gate: every check pictlib has, in order, each required to pass -- the day-to-day gate
--  (library build, source policy, AUnit suite), the real-world corpus, a fuzzing run, the SPARK proof profile and
--  encoder conformance against ImageMagick and LibreOffice. --without-conformance leaves out the last, for hosts
--  without those readers. Runs from anywhere below the pictlib tree after `alr build`.
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Pictlib_Testing.Tools;
with Project_Tools.Processes;

procedure Pictlib_Complete is
   use Ada.Strings.Unbounded;
   package Processes renames Project_Tools.Processes;

   type Step is record
      Program : Unbounded_String;
      Arguments : Processes.Argument_Vectors.Vector;
   end record;

   function Step_Of (Program : String; Arguments : Processes.Argument_Items := [1 .. 0 => Null_Unbounded_String])
     return Step is ((To_Unbounded_String (Program), Processes.Arguments (Arguments)));

   Steps : constant array (Positive range <>) of Step :=
     [Step_Of ("pictlib_check"),
      Step_Of ("pictlib_real_world"),
      Step_Of ("pictlib_fuzz", [Processes.Argument ("20000")]),
      Step_Of ("pictlib_prove"),
      Step_Of ("pictlib_conformance", [Processes.Argument ("--require")])];

   Without_Conformance : constant Boolean := Processes.Has_Argument ("--without-conformance");
   Suffix : constant String := Pictlib_Testing.Tools.Executable_Suffix;
   Ran : Natural := 0;
begin
   if not Pictlib_Testing.Tools.Enter_Tests_Directory then
      return;
   end if;
   Pictlib_Testing.Tools.Start_Report ("pictlib_complete");
   for Item of Steps loop
      declare
         Name : constant String := To_String (Item.Program);
      begin
         if Without_Conformance and then Name = "pictlib_conformance" then
            Ada.Text_IO.Put_Line ("SKIP " & Name);
         else
            Ran := Ran + 1;
            if Processes.Run_Status (Name, ".", "./bin/" & Name & Suffix, Item.Arguments, Quiet => True) = 0 then
               Ada.Text_IO.Put_Line ("PASS " & Name);
            else
               Pictlib_Testing.Tools.Fail ("FAIL " & Name);
            end if;
         end if;
      end;
   end loop;
   Ada.Text_IO.Put_Line (Ran'Image & " gates," & Pictlib_Testing.Tools.Failures'Image & " failed");
   Pictlib_Testing.Tools.Finish_Report;
end Pictlib_Complete;
