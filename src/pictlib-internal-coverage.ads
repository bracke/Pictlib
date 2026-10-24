with Ada.Containers.Vectors;
with Pictlib.Internal.Regions;

--  The pixels a shape covers, as sorted spans per row, kept only inside a window (the canvas, in picture
--  coordinates). A pixel x, y is the unit square from (x, y) to (x + 1, y + 1); shapes follow QuickDraw's
--  rules where those are documented and the rules in the specification where they are not.
package Pictlib.Internal.Coverage is
   subtype Area is Regions.Area;
   subtype Span_List is Regions.Span_Vectors.Vector;

   type Point is record
      H : Integer := 0;
      V : Integer := 0;
   end record;

   package Point_Vectors is new Ada.Containers.Vectors (Positive, Point);

   type Shape is private;

   --  Start.
   --  @param Item Shape to empty.
   --  @param Window Rows and columns outside it are not kept.
   --  @param Allowance Units of work building it may take; once they are spent, building stops and Work reports
   --  more than Allowance.
   procedure Start (Item : out Shape; Window : Area; Allowance : Pixel_Count := Pixel_Count'Last);
   --  Window of.
   --  @param Item Shape.
   --  @return Its window.
   function Window_Of (Item : Shape) return Area;
   --  Row.
   --  @param Item Shape.
   --  @param Y Row within the window.
   --  @return The row's spans, sorted and disjoint; none once the shape is exhausted, so an incomplete shape
   --  never paints.
   function Row (Item : Shape; Y : Integer) return Span_List;
   --  Work.
   --  @param Item Shape.
   --  @return Units of work building it took, for the drawing budget.
   function Work (Item : Shape) return Pixel_Count;
   --  Exhausted.
   --  @param Item Shape.
   --  @return True when building it spent its allowance; it then covers nothing.
   function Exhausted (Item : Shape) return Boolean;
   --  Remaining.
   --  @param Item Shape.
   --  @return The allowance building it has not spent.
   function Remaining (Item : Shape) return Pixel_Count;

   --  Rectangle: rows Top .. Bottom - 1, columns Left .. Right - 1.
   procedure Rectangle (Item : in out Shape; Bounds : Area);
   --  Oval: the pixels whose centers lie inside the ellipse inscribed in Bounds.
   procedure Oval (Item : in out Shape; Bounds : Area);
   --  Round rect: Bounds with each corner cut by a quarter of an Oval_Width x Oval_Height oval.
   procedure Round_Rect (Item : in out Shape; Bounds : Area; Oval_Width, Oval_Height : Integer);
   --  Wedge: the pixels of Item whose centers lie in the arc from Start_Angle through Arc_Angle degrees, 0 at
   --  12 o'clock, clockwise, with the angles stretched so that 45 degrees passes through the corner of Bounds.
   procedure Wedge (Item : in out Shape; Bounds : Area; Start_Angle, Arc_Angle : Integer);
   --  Polygon: the pixels whose centers lie inside the closed polygon, even-odd.
   procedure Polygon (Item : in out Shape; Points : Point_Vectors.Vector);
   --  Line: the pen rectangle Pen_Width x Pen_Height hanging below and right of each point of the Bresenham line
   --  from From to To, both included; added to what Item covers.
   procedure Line (Item : in out Shape; From, To : Point; Pen_Width, Pen_Height : Integer);
   --  From region: the region's pixels.
   procedure From_Region (Item : in out Shape; Source : in out Regions.Region);
   --  Region frame: the region's pixels less the region inset by Pen_Width horizontally and Pen_Height vertically.
   procedure Region_Frame (Item : in out Shape; Source : in out Regions.Region; Pen_Width, Pen_Height : Integer);
   --  Subtract: remove Other's pixels from Item; both have the same window.
   procedure Subtract (Item : in out Shape; Other : Shape);

private
   package Row_Vectors is new Ada.Containers.Vectors (Natural, Span_List, Regions.Span_Vectors."=");

   type Shape is record
      Window : Area;
      Rows : Row_Vectors.Vector;
      Units : Pixel_Count := 0;
      Allowance : Pixel_Count := Pixel_Count'Last;
      Spent : Boolean := False;
   end record;
end Pictlib.Internal.Coverage;
