with AUnit.Test_Cases;
with Pictlib_Testing.Test_Bytes;
with Pictlib_Testing.Test_Foundation;
with Pictlib_Testing.Test_Streams;

package body Pictlib_Testing.Suite is
   function All_Tests return AUnit.Test_Suites.Access_Test_Suite is
      Suite : constant AUnit.Test_Suites.Access_Test_Suite := AUnit.Test_Suites.New_Suite;
      Foundation : constant AUnit.Test_Cases.Test_Case_Access :=
        new Pictlib_Testing.Test_Foundation.Test;
      Streams : constant AUnit.Test_Cases.Test_Case_Access :=
        new Pictlib_Testing.Test_Streams.Test;
      Bytes : constant AUnit.Test_Cases.Test_Case_Access :=
        new Pictlib_Testing.Test_Bytes.Test;
   begin
      Suite.Add_Test (Foundation);
      Suite.Add_Test (Streams);
      Suite.Add_Test (Bytes);
      return Suite;
   end All_Tests;
end Pictlib_Testing.Suite;
