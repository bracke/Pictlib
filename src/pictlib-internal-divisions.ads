--  Integer division rounded toward either infinity, for the sampling and coverage arithmetic.
package Pictlib.Internal.Divisions is
   pragma Pure;

   --  Floor divide.
   --  @param Left Dividend, of either sign.
   --  @param Right Divisor.
   --  @return Left / Right rounded toward minus infinity.
   function Floor_Divide (Left, Right : Long_Long_Integer) return Long_Long_Integer is
     (if Left >= 0 then Left / Right else -((-Left + Right - 1) / Right))
     with Pre => Right > 0;
   --  Ceiling divide.
   --  @param Left Dividend, of either sign.
   --  @param Right Divisor.
   --  @return Left / Right rounded toward plus infinity.
   function Ceiling_Divide (Left, Right : Long_Long_Integer) return Long_Long_Integer is
     (-Floor_Divide (-Left, Right))
     with Pre => Right > 0;
end Pictlib.Internal.Divisions;
