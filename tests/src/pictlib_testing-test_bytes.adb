with AUnit.Assertions;
with Interfaces;

with Pictlib;
with Pictlib.Errors;
with Pictlib.Internal.Bytes;
with Pictlib.Internal.Checked_Arithmetic;
with Pictlib.Internal.Writers;
with Pictlib.Results;
with Pictlib.Streams;

package body Pictlib_Testing.Test_Bytes is
   use AUnit.Assertions;
   use type Interfaces.Unsigned_16;
   use type Interfaces.Unsigned_32;
   use type Pictlib.Byte;
   use type Pictlib.Byte_Count;
   use type Pictlib.Coordinate;
   use type Pictlib.Errors.Error_Code;
   use type Pictlib.Limit_Kind;
   use type Pictlib.Opcode;
   use type Pictlib.Source_Offset;
   use type Pictlib.Streams.Byte_Array;

   package Bytes renames Pictlib.Internal.Bytes;
   package Arithmetic renames Pictlib.Internal.Checked_Arithmetic;
   package Writers renames Pictlib.Internal.Writers;

   procedure Big_Endian_Reads (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Truncated_Reads_Carry_Opcode (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Big_Endian_Writes (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Coordinates_Are_Twos_Complement (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Arithmetic_Rejects_Overflow (T : in out AUnit.Test_Cases.Test_Case'Class);

   overriding function Name (T : Test) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("bytes");
   end Name;

   overriding procedure Register_Tests (T : in out Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Big_Endian_Reads'Access, "bytes.read.big_endian");
      Register_Routine (T, Truncated_Reads_Carry_Opcode'Access, "bytes.read.truncated_opcode_context");
      Register_Routine (T, Big_Endian_Writes'Access, "bytes.write.big_endian");
      Register_Routine (T, Coordinates_Are_Twos_Complement'Access, "bytes.coordinates");
      Register_Routine (T, Arithmetic_Rejects_Overflow'Access, "arithmetic.overflow");
   end Register_Tests;

   procedure Big_Endian_Reads (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Input : aliased constant Pictlib.Streams.Byte_Array :=
        [16#11#, 16#00#, 16#11#, 16#02#, 16#FF#, 16#00#, 16#00#, 16#00#, 16#FF#, 16#FF#, 16#F6#];
      Source : Pictlib.Streams.Memory_Source;
      Value_8 : Pictlib.Byte;
      Value_16 : Interfaces.Unsigned_16;
      Value_32 : Interfaces.Unsigned_32;
      Point : Pictlib.Coordinate;
      Outcome : Pictlib.Results.Result;
   begin
      --  One byte per transfer: every multi-byte read must assemble across short reads.
      Pictlib.Streams.Open (Source, Input'Unchecked_Access, Max_Transfer => 1);
      Outcome := Bytes.Read_Byte (Source, Value_8);
      Assert (Pictlib.Results.Succeeded (Outcome) and then Value_8 = 16#11#, "byte read is wrong");
      Outcome := Bytes.Read_U16_BE (Source, Value_16);
      Assert (Pictlib.Results.Succeeded (Outcome) and then Value_16 = 16#0011#, "version opcode read is wrong");
      Outcome := Bytes.Read_U16_BE (Source, Value_16);
      Assert (Pictlib.Results.Succeeded (Outcome) and then Value_16 = 16#02FF#, "version word read is wrong");
      Outcome := Bytes.Read_U32_BE (Source, Value_32);
      Assert (Pictlib.Results.Succeeded (Outcome) and then Value_32 = 16#0000_00FF#, "baseAddr read is wrong");
      Outcome := Bytes.Read_Coordinate (Source, Point);
      Assert (Pictlib.Results.Succeeded (Outcome) and then Point = -10, "negative coordinate read is wrong");
      Assert (Source.Offset = 11, "reads consumed the wrong byte count");
   end Big_Endian_Reads;

   procedure Truncated_Reads_Carry_Opcode (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Input : aliased constant Pictlib.Streams.Byte_Array := [16#00#, 16#98#, 16#80#];
      Source : Pictlib.Streams.Memory_Source;
      Value_16 : Interfaces.Unsigned_16;
      Value_32 : Interfaces.Unsigned_32;
      Outcome : Pictlib.Results.Result;
   begin
      Pictlib.Streams.Open (Source, Input'Unchecked_Access);
      Outcome := Bytes.Read_U16_BE (Source, Value_16);
      Assert (Pictlib.Results.Succeeded (Outcome) and then Value_16 = 16#0098#, "opcode read is wrong");
      Outcome := Bytes.Read_U32_BE (Source, Value_32, Bytes.Within (16#0098#));
      Assert (Outcome.First_Error.Code = Pictlib.Errors.Source_Unexpected_End, "truncation has the wrong error");
      Assert (Value_32 = 0, "failed read must yield zero");
      Assert (Outcome.First_Error.Context.Has_Opcode and then Outcome.First_Error.Context.Op = 16#0098#,
              "truncation lost the opcode context");
      Assert (Outcome.First_Error.Context.Expected = 4 and then Outcome.First_Error.Context.Actual = 1,
              "truncation lost its counts");

      Pictlib.Streams.Open (Source, Input'Unchecked_Access);
      Outcome := Bytes.Read_U32_BE (Source, Value_32);
      Assert (not Outcome.First_Error.Context.Has_Opcode, "read outside an opcode claimed one");
   end Truncated_Reads_Carry_Opcode;

   procedure Big_Endian_Writes (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Storage : aliased Pictlib.Streams.Byte_Array := [1 .. 9 => 0];
      Destination : aliased Pictlib.Streams.Fixed_Buffer_Destination;
      Writer : Writers.Writer;
      Outcome : Pictlib.Results.Result;
   begin
      Pictlib.Streams.Open (Destination, Storage'Unchecked_Access, Max_Transfer => 1);
      Writers.Start (Writer, Destination'Access, Max_Bytes => 9);
      Outcome := Writers.Put_Byte (Writer, 16#FF#);
      Assert (Pictlib.Results.Succeeded (Outcome), "byte write failed");
      Outcome := Writers.Put_Word (Writer, 16#0C00#);
      Assert (Pictlib.Results.Succeeded (Outcome), "16-bit write failed");
      Outcome := Writers.Put_Long (Writer, 16#FFFE_0000#);
      Assert (Pictlib.Results.Succeeded (Outcome), "32-bit write failed");
      Outcome := Writers.Put_Word (Writer, -2);
      Assert (Pictlib.Results.Succeeded (Outcome), "coordinate write failed");
      Assert (Storage = [16#FF#, 16#0C#, 16#00#, 16#FF#, 16#FE#, 16#00#, 16#00#, 16#FF#, 16#FE#],
              "writes are not big-endian");
      Outcome := Writers.Put_Byte (Writer, 0);
      Assert (Outcome.First_Error.Code = Pictlib.Errors.Limit_Exceeded
              and then Outcome.First_Error.Context.Limit = Pictlib.Output_Byte_Limit,
              "a write past the writer's limit has the wrong error");
   end Big_Endian_Writes;

   procedure Coordinates_Are_Twos_Complement (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Bytes.To_Coordinate (16#0000#) = 0, "zero");
      Assert (Bytes.To_Coordinate (16#7FFF#) = 32_767, "largest positive");
      Assert (Bytes.To_Coordinate (16#8000#) = -32_768, "most negative");
      Assert (Bytes.To_Coordinate (16#FFFF#) = -1, "minus one");
      for Raw in Interfaces.Unsigned_16 loop
         Assert (Bytes.From_Coordinate (Bytes.To_Coordinate (Raw)) = Raw, "coordinate round trip failed");
      end loop;
   end Coordinates_Are_Twos_Complement;

   procedure Arithmetic_Rejects_Overflow (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      use type Pictlib.Pixel_Count;
      Top : constant Pictlib.Byte_Count := Pictlib.Byte_Count'Last;
   begin
      Assert (Arithmetic.Saturating_Add (Top - 1, 1) = Top, "largest sum");
      Assert (Arithmetic.Saturating_Add (Top, 1) = Top and then Arithmetic.Saturating_Add (Top, Top) = Top,
              "an overflowing sum did not saturate");
      Assert (Arithmetic.Saturating_Multiply (32_767, 32_767 * 4) = 32_767 * 32_767 * 4,
              "largest RGBA frame size");
      Assert (Arithmetic.Saturating_Multiply (2 ** 32, 2 ** 31) = Top, "an overflowing product did not saturate");
      Assert (Arithmetic.Saturating_Multiply (0, Top) = 0, "zero product");
      Assert (Arithmetic.Saturating_Add (Pictlib.Pixel_Count'Last, 1) = Pictlib.Pixel_Count'Last,
              "overflowing work did not saturate");
   end Arithmetic_Rejects_Overflow;
end Pictlib_Testing.Test_Bytes;
