with AUnit.Test_Cases;

--  Unit tests of internal span and shape code whose properties the public API cannot observe once rendering has
--  failed, or only through many pictures.
package Pictlib_Testing.Test_Coverage is
   type Test is new AUnit.Test_Cases.Test_Case with null record;

   overriding function Name (T : Test) return AUnit.Message_String;
   overriding procedure Register_Tests (T : in out Test);
end Pictlib_Testing.Test_Coverage;
