with AUnit.Test_Cases;

package Pictlib_Testing.Test_Images is
   type Test is new AUnit.Test_Cases.Test_Case with null record;

   overriding function Name (T : Test) return AUnit.Message_String;
   overriding procedure Register_Tests (T : in out Test);
end Pictlib_Testing.Test_Images;
