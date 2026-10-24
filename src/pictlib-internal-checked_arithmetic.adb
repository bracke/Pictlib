with Pictlib.Errors;

package body Pictlib.Internal.Checked_Arithmetic is
   function Add (Left, Right : Byte_Count) return Count_Result is
   begin
      if Right > Byte_Count'Last - Left then
         return (Outcome => Results.Failure (Errors.Integer_Overflow), Value => 0);
      end if;
      return (Outcome => Results.Success, Value => Left + Right);
   end Add;

   function Multiply (Left, Right : Byte_Count) return Count_Result is
   begin
      if Left /= 0 and then Right > Byte_Count'Last / Left then
         return (Outcome => Results.Failure (Errors.Integer_Overflow), Value => 0);
      end if;
      return (Outcome => Results.Success, Value => Left * Right);
   end Multiply;
end Pictlib.Internal.Checked_Arithmetic;
