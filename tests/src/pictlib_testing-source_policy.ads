--  The source policy pictlib_check enforces on production code, beside line length and GNATdoc tags.
package Pictlib_Testing.Source_Policy is
   --  Production units depend only on Ada, Interfaces (not Interfaces.C), GNAT, System, pictlib, jpeglib and
   --  textrender, and bind no foreign code. The unit is read whole, without comments, strings and character
   --  literals, and lower-cased: context clauses are taken clause by clause up to the unit itself, however
   --  they are laid out, and the words that interface foreign code (Import, Export, Convention, External_Name,
   --  Link_Name, Machine_Code, pragma Interface) are refused anywhere, however they are spaced.
   --  @param Path An Ada source of the library; each finding is reported through Tools.Fail.
   procedure Check_Dependencies (Path : String);
end Pictlib_Testing.Source_Policy;
