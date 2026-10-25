--  The source policy pictlib_check enforces; every finding is reported through Tools.Fail.
package Pictlib_Testing.Source_Policy is
   --  Longest source line.
   Longest_Line : constant := 120;

   --  Check line lengths.
   --  @param Path An Ada source of either crate; each line longer than Longest_Line is a finding.
   procedure Check_Line_Lengths (Path : String);

   --  Check production unit: Check_Dependencies, jpeglib reached only through its public packages, no test or
   --  tool package, and GNATdoc tags on every subprogram of a public spec.
   --  @param Path An Ada source of the library.
   procedure Check_Production_Unit (Path : String);

   --  Check registry: docs/invariants.md stays true to the suite. Every coverage name it cites is a registered
   --  test routine (one ending in ".*" stands for the routines it prefixes) or a tool of tests/src/mains, and
   --  its capability table lists every Pictlib.Capabilities constant.
   --  @param Root The pictlib tree.
   procedure Check_Registry (Root : String);

   --  Check readme: every Ada block of README.md is the example program's text, line for line, so the README
   --  shows code the tests crate builds.
   --  @param Root The pictlib tree.
   procedure Check_Readme (Root : String);

   --  Production units depend only on Ada, Interfaces (not Interfaces.C), GNAT, System, pictlib, jpeglib and
   --  textrender, and bind no foreign code. The unit is read whole, without comments, strings and character
   --  literals, and lower-cased: context clauses are taken clause by clause up to the unit itself, however
   --  they are laid out, and the words that interface foreign code (Import, Export, Convention, External_Name,
   --  Link_Name, Machine_Code, pragma Interface) are refused anywhere, however they are spaced.
   --  @param Path An Ada source of the library; each finding is reported through Tools.Fail.
   procedure Check_Dependencies (Path : String);
end Pictlib_Testing.Source_Policy;
