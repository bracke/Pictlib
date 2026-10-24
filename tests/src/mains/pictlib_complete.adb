--  The library-complete gate: every check pictlib has, in order, each required to pass -- the source policy,
--  the AUnit suite, the real-world corpus, a fuzzing run, the SPARK proof profile and encoder conformance against
--  ImageMagick and LibreOffice. Run from the tests directory after `alr build`.
with Ada.Command_Line;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
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
      Step_Of ("pictlib_tests"),
      Step_Of ("pictlib_real_world"),
      Step_Of ("pictlib_fuzz", [Processes.Argument ("20000")]),
      Step_Of ("pictlib_prove"),
      Step_Of ("pictlib_conformance", [Processes.Argument ("--require")])];

   Failed : Natural := 0;
begin
   for Item of Steps loop
      declare
         Name : constant String := To_String (Item.Program);
         Status : constant Integer :=
           Processes.Run_Status (Name, ".", "./bin/" & Name, Item.Arguments, Quiet => True);
      begin
         if Status = 0 then
            Ada.Text_IO.Put_Line ("PASS " & Name);
         else
            Failed := Failed + 1;
            Ada.Text_IO.Put_Line ("FAIL " & Name & " (status" & Status'Image & ")");
         end if;
      end;
   end loop;
   Ada.Text_IO.Put_Line (Natural'Image (Steps'Length) & " gates," & Failed'Image & " failed");
   if Failed > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Pictlib_Complete;
