with Interfaces;

--  QuickDraw geometry. Rectangles keep QuickDraw's field order (top, left, bottom, right); a rectangle encloses
--  the grid lines between its coordinates, so its width is Right - Left.
package Pictlib.Geometry is
   pragma Pure;

   type Point is record
      V : Coordinate := 0;
      H : Coordinate := 0;
   end record;

   type Rect is record
      Top : Coordinate := 0;
      Left : Coordinate := 0;
      Bottom : Coordinate := 0;
      Right : Coordinate := 0;
   end record;

   --  A 16.16 signed fixed-point number.
   type Fixed is new Interfaces.Integer_32;

   Fixed_One : constant Fixed := 2 ** 16;
   Fixed_72 : constant Fixed := 72 * Fixed_One;

   type Fixed_Rect is record
      Top : Fixed := 0;
      Left : Fixed := 0;
      Bottom : Fixed := 0;
      Right : Fixed := 0;
   end record;

   --  Width.
   --  @param Item Rectangle.
   --  @return Right - Left, negative for an inverted rectangle.
   function Width (Item : Rect) return Integer is (Integer (Item.Right) - Integer (Item.Left));
   --  Height.
   --  @param Item Rectangle.
   --  @return Bottom - Top, negative for an inverted rectangle.
   function Height (Item : Rect) return Integer is (Integer (Item.Bottom) - Integer (Item.Top));
   --  Is empty.
   --  @param Item Rectangle.
   --  @return True when Item encloses no pixel.
   function Is_Empty (Item : Rect) return Boolean is (Width (Item) <= 0 or else Height (Item) <= 0);
end Pictlib.Geometry;
