with AUnit.Assertions;

with Pictlib;
with Pictlib.Internal.PackBits;
with Pictlib.Streams;
with Pictlib_Testing.Builders;
with Pictlib_Testing.Random;

package body Pictlib_Testing.Test_PackBits is
   use AUnit.Assertions;
   use Pictlib_Testing.Builders;
   use type Pictlib.Internal.PackBits.Unpack_Status;
   use type Pictlib.Streams.Byte_Array;

   package PackBits renames Pictlib.Internal.PackBits;

   --  Apple Technical Note TN1023, "Understanding PackBits".
   Apple_Packed : constant Bytes :=
     [16#FE#, 16#AA#, 16#02#, 16#80#, 16#00#, 16#2A#, 16#FD#, 16#AA#, 16#03#, 16#80#, 16#00#, 16#2A#, 16#22#,
      16#F7#, 16#AA#];
   Apple_Unpacked : constant Bytes :=
     [16#AA#, 16#AA#, 16#AA#, 16#80#, 16#00#, 16#2A#, 16#AA#, 16#AA#, 16#AA#, 16#AA#, 16#80#, 16#00#, 16#2A#,
      16#22#, 16#AA#, 16#AA#, 16#AA#, 16#AA#, 16#AA#, 16#AA#, 16#AA#, 16#AA#, 16#AA#, 16#AA#];

   function Unpack
     (Packed : Bytes;
      Unit : PackBits.Unit_Size;
      Output : out Bytes;
      Written : out Natural) return PackBits.Unpack_Status
   is
      Status : PackBits.Unpack_Status;
   begin
      PackBits.Unpack (Packed, Unit, Output, Written, Status);
      return Status;
   end Unpack;

   procedure Apple_Example (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Word_Units (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Mismatches (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Round_Trips (T : in out AUnit.Test_Cases.Test_Case'Class);

   overriding function Name (T : Test) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("packbits");
   end Name;

   overriding procedure Register_Tests (T : in out Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Apple_Example'Access, "packbits.apple_tn1023");
      Register_Routine (T, Word_Units'Access, "packbits.words");
      Register_Routine (T, Mismatches'Access, "packbits.mismatches");
      Register_Routine (T, Round_Trips'Access, "packbits.round_trips");
   end Register_Tests;

   procedure Apple_Example (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Output : Bytes (1 .. Apple_Unpacked'Length);
      Packed : Bytes (1 .. PackBits.Worst_Case (Apple_Unpacked'Length));
      Written : Natural;
   begin
      Assert (Unpack (Apple_Packed, 1, Output, Written) = PackBits.Exact
              and then Written = Output'Length and then Output = Apple_Unpacked,
              "Apple's example did not unpack");
      PackBits.Pack (Apple_Unpacked, Packed, Written);
      Assert (Packed (1 .. Written) = Apple_Packed, "Apple's example did not pack as Apple packs it");
   end Apple_Example;

   procedure Word_Units (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Output : Bytes (1 .. 8);
      Written : Natural;
      --  A run of two words, then a literal of two words.
      Packed : constant Bytes := B (16#FF#) & W (16#1234#) & B (1) & W (16#ABCD#) & W (16#00FF#);
   begin
      Assert (Unpack (Packed, 2, Output, Written) = PackBits.Exact
              and then Output = W (16#1234#) & W (16#1234#) & W (16#ABCD#) & W (16#00FF#),
              "word runs and literals did not unpack");
   end Word_Units;

   procedure Mismatches (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Output : Bytes (1 .. 4);
      Written : Natural;
   begin
      Assert (Unpack ([16#FD#, 7], 1, Output, Written) = PackBits.Exact and then Output = [7, 7, 7, 7],
              "a run did not unpack");
      Assert (Unpack ([16#80#, 16#FD#, 7], 1, Output, Written) = PackBits.Exact,
              "flag 128 is not a no-op");
      Assert (Unpack ([16#FE#, 7], 1, Output, Written) = PackBits.Underrun
              and then Written = 3 and then Output = [7, 7, 7, 0],
              "a short row was not reported or not zero-filled");
      Assert (Unpack ([16#FC#, 7], 1, Output, Written) = PackBits.Overrun
              and then Written = 4 and then Output = [7, 7, 7, 7],
              "a long run was not reported or overflowed");
      Assert (Unpack ([4, 1, 2, 3, 4, 5], 1, Output, Written) = PackBits.Overrun
              and then Output = [1, 2, 3, 4],
              "a long literal was not reported or overflowed");
      Assert (Unpack ([3, 1, 2], 1, Output, Written) = PackBits.Truncated and then Written = 2,
              "a cut literal was not reported");
      Assert (Unpack ([16#FD#], 1, Output, Written) = PackBits.Truncated, "a cut run was not reported");
      Assert (Unpack ([16#FF#, 16#12#], 2, Output, Written) = PackBits.Truncated,
              "a cut word run was not reported");
      Assert (Unpack ([1 .. 0 => 0], 1, Output, Written) = PackBits.Underrun and then Written = 0,
              "an empty packed row is not short");
   end Mismatches;

   procedure Round_Trips (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Generator : Pictlib_Testing.Random.Generator := Pictlib_Testing.Random.Seeded;

      --  Few distinct values so runs of every length occur.
      function Next_Byte return Pictlib.Byte is (Pictlib.Byte (Pictlib_Testing.Random.Next (Generator, 3)));
   begin
      --  One literal unit, then two equal units, repeated: the case that breaks a packer that runs at two.
      for Length in 1 .. 300 loop
         declare
            Row : Bytes (1 .. Length);
            Packed : Bytes (1 .. PackBits.Worst_Case (Length));
            Back : Bytes (1 .. Length);
            Written, Unpacked : Natural;
         begin
            for Index in Row'Range loop
               Row (Index) := (if Index mod 3 = 1 then Pictlib.Byte (Index mod 251) else 16#EE#);
            end loop;
            PackBits.Pack (Row, Packed, Written);
            Assert (Unpack (Packed (1 .. Written), 1, Back, Unpacked) = PackBits.Exact and then Back = Row,
                    "alternating round trip failed at" & Length'Image);
         end;
      end loop;
      for Length in 1 .. 300 loop
         declare
            Row : Bytes (1 .. Length);
            Packed : Bytes (1 .. PackBits.Worst_Case (Length));
            Back : Bytes (1 .. Length);
            Written, Unpacked : Natural;
         begin
            for Item of Row loop
               Item := Next_Byte;
            end loop;
            PackBits.Pack (Row, Packed, Written);
            Assert (Unpack (Packed (1 .. Written), 1, Back, Unpacked) = PackBits.Exact and then Back = Row,
                    "round trip failed at" & Length'Image & " random bytes");
         end;
      end loop;
   end Round_Trips;
end Pictlib_Testing.Test_PackBits;
