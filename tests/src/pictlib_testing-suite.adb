with AUnit.Test_Cases;
with Pictlib_Testing.Test_Bytes;
with Pictlib_Testing.Test_Container;
with Pictlib_Testing.Test_Decoder;
with Pictlib_Testing.Test_Encoding;
with Pictlib_Testing.Test_Enumeration;
with Pictlib_Testing.Test_External;
with Pictlib_Testing.Test_Foundation;
with Pictlib_Testing.Test_Hostile;
with Pictlib_Testing.Test_Images;
with Pictlib_Testing.Test_Opcodes;
with Pictlib_Testing.Test_PackBits;
with Pictlib_Testing.Test_QuickTime;
with Pictlib_Testing.Test_Rendering;
with Pictlib_Testing.Test_Shapes;
with Pictlib_Testing.Test_Stress;
with Pictlib_Testing.Test_Text;
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
      Images : constant AUnit.Test_Cases.Test_Case_Access :=
        new Pictlib_Testing.Test_Images.Test;
      PackBits : constant AUnit.Test_Cases.Test_Case_Access :=
        new Pictlib_Testing.Test_PackBits.Test;
      Rendering : constant AUnit.Test_Cases.Test_Case_Access :=
        new Pictlib_Testing.Test_Rendering.Test;
      External : constant AUnit.Test_Cases.Test_Case_Access :=
        new Pictlib_Testing.Test_External.Test;
      Shapes : constant AUnit.Test_Cases.Test_Case_Access :=
        new Pictlib_Testing.Test_Shapes.Test;
      Text : constant AUnit.Test_Cases.Test_Case_Access :=
        new Pictlib_Testing.Test_Text.Test;
      QuickTime : constant AUnit.Test_Cases.Test_Case_Access :=
        new Pictlib_Testing.Test_QuickTime.Test;
      Encoding : constant AUnit.Test_Cases.Test_Case_Access :=
        new Pictlib_Testing.Test_Encoding.Test;
      Stress : constant AUnit.Test_Cases.Test_Case_Access :=
        new Pictlib_Testing.Test_Stress.Test;
      Hostile : constant AUnit.Test_Cases.Test_Case_Access :=
        new Pictlib_Testing.Test_Hostile.Test;
   begin
      Suite.Add_Test (Foundation);
      Suite.Add_Test (Streams);
      Suite.Add_Test (Bytes);
      Suite.Add_Test (Opcodes);
      Suite.Add_Test (Container);
      Suite.Add_Test (Enumeration);
      Suite.Add_Test (Decoder);
      Suite.Add_Test (Images);
      Suite.Add_Test (PackBits);
      Suite.Add_Test (Rendering);
      Suite.Add_Test (External);
      Suite.Add_Test (Shapes);
      Suite.Add_Test (Text);
      Suite.Add_Test (QuickTime);
      Suite.Add_Test (Encoding);
      Suite.Add_Test (Stress);
      Suite.Add_Test (Hostile);
      return Suite;
   end All_Tests;
end Pictlib_Testing.Suite;
