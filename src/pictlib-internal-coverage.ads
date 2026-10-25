with Ada.Containers.Vectors;
with Pictlib.Internal.Regions;

--  The pixels a shape covers, as sorted spans per row, kept only inside a window (the canvas, in picture
--  coordinates) and only for the rows the shape reaches, so an empty or small shape costs little whatever the
--  window. A pixel x, y is the unit square from (x, y) to (x + 1, y + 1); shapes follow QuickDraw's
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
   --  Copy row: Row (Item, Y), assigned to Into without an intermediate copy.
   --  @param Item Shape.
   --  @param Y Row within the window.
   --  @param Into Receives the row's spans.
   procedure Copy_Row (Item : Shape; Y : Integer; Into : in out Span_List);
   --  First row.
   --  @param Item Shape.
   --  @return The first row it holds; above Last_Row when it holds none.
   function First_Row (Item : Shape) return Integer;
   --  Last row.
   --  @param Item Shape.
   --  @return The last row it holds.
   function Last_Row (Item : Shape) return Integer;
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
   --  @param Item Started shape; the rectangle is added to it.
   --  @param Bounds Rectangle.
   procedure Rectangle (Item : in out Shape; Bounds : Area);
   --  Oval: the pixels whose centers lie inside the ellipse inscribed in Bounds.
   --  @param Item Started shape; the oval is added to it.
   --  @param Bounds The oval's bounding rectangle.
   procedure Oval (Item : in out Shape; Bounds : Area);
   --  Round rect: Bounds with each corner cut by a quarter of an Oval_Width x Oval_Height oval.
   --  @param Item Started shape; the round rect is added to it.
   --  @param Bounds Rectangle.
   --  @param Oval_Width Width of the corner oval.
   --  @param Oval_Height Height of the corner oval.
   procedure Round_Rect (Item : in out Shape; Bounds : Area; Oval_Width, Oval_Height : Integer);
   --  Wedge: the pixels of Item whose centers lie in the arc from Start_Angle through Arc_Angle degrees, 0 at
   --  12 o'clock, clockwise, with the angles stretched so that 45 degrees passes through the corner of Bounds.
   --  @param Item Shape narrowed to the wedge.
   --  @param Bounds The arc's oval's bounding rectangle.
   --  @param Start_Angle First angle, in degrees.
   --  @param Arc_Angle Extent, in degrees; negative counterclockwise.
   procedure Wedge (Item : in out Shape; Bounds : Area; Start_Angle, Arc_Angle : Integer);
   --  Polygon: the pixels whose centers lie inside the closed polygon, even-odd.
   --  @param Item Started shape; the polygon is added to it.
   --  @param Points Its vertices, in picture coordinates.
   procedure Polygon (Item : in out Shape; Points : Point_Vectors.Vector);
   --  Line: the pen rectangle Pen_Width x Pen_Height hanging below and right of each point of the Bresenham line
   --  from From to To, both included; added to what Item covers.
   --  @param Item Started shape.
   --  @param From First point.
   --  @param To Last point.
   --  @param Pen_Width Pen width.
   --  @param Pen_Height Pen height.
   procedure Line (Item : in out Shape; From, To : Point; Pen_Width, Pen_Height : Integer);
   --  From region: the region's pixels.
   --  @param Item Started shape; the region is added to it.
   --  @param Source Region in picture coordinates; its row cursor moves.
   procedure From_Region (Item : in out Shape; Source : in out Regions.Region);
   --  Region frame: the region's pixels less the region inset by Pen_Width horizontally and Pen_Height vertically.
   --  @param Item Started shape; the frame is added to it.
   --  @param Source Region in picture coordinates; its row cursor moves.
   --  @param Pen_Width Pen width.
   --  @param Pen_Height Pen height.
   procedure Region_Frame (Item : in out Shape; Source : in out Regions.Region; Pen_Width, Pen_Height : Integer);
   --  Subtract: remove Other's pixels from Item; both have the same window.
   --  @param Item Shape to cut.
   --  @param Other Pixels to remove.
   procedure Subtract (Item : in out Shape; Other : Shape);


private
   package Row_Vectors is new Ada.Containers.Vectors (Natural, Span_List, Regions.Span_Vectors."=");

   type Shape is record
      Window : Area;
      --  Rows Top .. Top + Rows.Length - 1, each charged as it is added.
      Top : Integer := 0;
      Rows : Row_Vectors.Vector;
      Units : Pixel_Count := 0;
      Allowance : Pixel_Count := Pixel_Count'Last;
      Spent : Boolean := False;
   end record;
end Pictlib.Internal.Coverage;
