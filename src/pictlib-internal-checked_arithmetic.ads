--  Overflow-free counting: every size taken from a picture is added and multiplied with these, so a hostile
--  amount saturates at the top of its range and is then refused by the limit it exceeds.
package Pictlib.Internal.Checked_Arithmetic
  with SPARK_Mode => On
is
   pragma Preelaborate;

   --  Saturating add: budgets and quotas count with these, so a hostile amount stops at the top of the range
   --  instead of overflowing, and is then refused by the limit it exceeds.
   --  @param Left First addend.
   --  @param Right Second addend.
   --  @return The sum, or Byte_Count'Last.
   function Saturating_Add (Left, Right : Byte_Count) return Byte_Count is
     (if Right > Byte_Count'Last - Left then Byte_Count'Last else Left + Right);
   --  Saturating multiply.
   --  @param Left First factor.
   --  @param Right Second factor.
   --  @return The product, or Byte_Count'Last.
   function Saturating_Multiply (Left, Right : Byte_Count) return Byte_Count is
     (if Left /= 0 and then Right > Byte_Count'Last / Left then Byte_Count'Last else Left * Right);
   --  Saturating add of drawing work.
   --  @param Left First addend.
   --  @param Right Second addend.
   --  @return The sum, or Pixel_Count'Last.
   function Saturating_Add (Left, Right : Pixel_Count) return Pixel_Count is
     (if Right > Pixel_Count'Last - Left then Pixel_Count'Last else Left + Right);
end Pictlib.Internal.Checked_Arithmetic;
