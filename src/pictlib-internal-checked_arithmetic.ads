with Pictlib.Results;

package Pictlib.Internal.Checked_Arithmetic
  with SPARK_Mode => On
is
   pragma Preelaborate;

   type Count_Result is record
      Outcome : Results.Result := Results.Success;
      Value : Byte_Count := 0;
   end record;

   --  Add.
   --  @param Left First addend.
   --  @param Right Second addend.
   --  @return The sum, or Integer_Overflow with Value 0.
   function Add (Left, Right : Byte_Count) return Count_Result;
   --  Multiply.
   --  @param Left First factor.
   --  @param Right Second factor.
   --  @return The product, or Integer_Overflow with Value 0.
   function Multiply (Left, Right : Byte_Count) return Count_Result;
end Pictlib.Internal.Checked_Arithmetic;
