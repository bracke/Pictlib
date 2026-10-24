with AUnit.Test_Cases;
with Pictlib_Testing.Test_Bytes;
with Pictlib_Testing.Test_Container;
with Pictlib_Testing.Test_Decoder;
with Pictlib_Testing.Test_Enumeration;
with Pictlib_Testing.Test_Foundation;
with Pictlib_Testing.Test_Opcodes;
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
      Opcodes : constant AUnit.Test_Cases.Test_Case_Access :=
        new Pictlib_Testing.Test_Opcodes.Test;
      Container : constant AUnit.Test_Cases.Test_Case_Access :=
        new Pictlib_Testing.Test_Container.Test;
      Enumeration : constant AUnit.Test_Cases.Test_Case_Access :=
        new Pictlib_Testing.Test_Enumeration.Test;
      Decoder : constant AUnit.Test_Cases.Test_Case_Access :=
        new Pictlib_Testing.Test_Decoder.Test;
   begin
      Suite.Add_Test (Foundation);
      Suite.Add_Test (Streams);
      Suite.Add_Test (Bytes);
      Suite.Add_Test (Opcodes);
      Suite.Add_Test (Container);
      Suite.Add_Test (Enumeration);
      Suite.Add_Test (Decoder);
      return Suite;
   end All_Tests;
end Pictlib_Testing.Suite;
