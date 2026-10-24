with Ada.Containers.Vectors;
with Pictlib.Geometry;
with Pictlib.Internal.Sessions;
with Pictlib.Results;

--  QuickDraw regions. After the size word and bounding box, a non-rectangular region lists scanlines: a y,
--  then the x of each inversion point on it, then 16#7FFF#; a final 16#7FFF# ends the list. A pixel is inside
--  when an odd number of inversion points lie at or above and at or left of it. Rows are walked top to bottom;
--  only the current set of inversion columns is held, so memory stays proportional to the region's data.
package Pictlib.Internal.Regions is
   --  Pixels Left .. Right - 1 of one row.
   type Span is record
      Left : Integer := 0;
      Right : Integer := 0;
   end record;

   package Span_Vectors is new Ada.Containers.Vectors (Positive, Span);

   --  A rectangle in picture coordinates, which the Origin opcode can move beyond QuickDraw's 16 bits.
   type Area is record
      Top : Integer := 0;
      Left : Integer := 0;
      Bottom : Integer := 0;
      Right : Integer := 0;
   end record;

   --  To area.
   --  @param Item QuickDraw rectangle.
   --  @param DX Added to the horizontal coordinates.
   --  @param DY Added to the vertical coordinates.
   --  @return Item moved by DX, DY.
   function To_Area (Item : Geometry.Rect; DX, DY : Integer := 0) return Area is
     ((Top => Integer (Item.Top) + DY, Left => Integer (Item.Left) + DX,
       Bottom => Integer (Item.Bottom) + DY, Right => Integer (Item.Right) + DX));
   --  Is empty.
   --  @param Item Area.
   --  @return True when Item encloses no pixel.
   function Is_Empty (Item : Area) return Boolean is (Item.Right <= Item.Left or else Item.Bottom <= Item.Top);

   type Region is private;

   --  Rectangle.
   --  @param Bounds Rectangle.
   --  @return The rectangular region Bounds.
   function Rectangle (Bounds : Area) return Region;
   --  Bounds.
   --  @param Item Region.
   --  @return Its bounding box.
   function Bounds (Item : Region) return Area;
   --  Is rectangular.
   --  @param Item Region.
   --  @return True when Item is its bounding box.
   function Is_Rectangular (Item : Region) return Boolean;
   --  Size.
   --  @param Item Region.
   --  @return Its scanlines and inversion points, the work of copying or moving it.
   function Size (Item : Region) return Natural;
   --  Translate.
   --  @param Item Region to move.
   --  @param DX Added to every horizontal coordinate.
   --  @param DY Added to every vertical coordinate.
   procedure Translate (Item : in out Region; DX, DY : Integer);

   --  Skip.
   --  @param S Session positioned at a region.
   --  @return Success, Region_Invalid for a size below 10, or Limit_Exceeded above the region budget.
   function Skip (S : in out Sessions.Session) return Results.Result;
   --  Read.
   --  @param S Session positioned at a region.
   --  @param Item The region; rectangular and empty on failure.
   --  @return Success, Region_Invalid for malformed scanlines, or Limit_Exceeded above the region budget.
   function Read (S : in out Sessions.Session; Item : out Region) return Results.Result;

   --  Row spans.
   --  @param Item Region; its row cursor moves to Y.
   --  @param Y Row.
   --  @param Spans Receives the row's spans, left to right.
   --  @param Work Units of work done, for the drawing budget.
   --  @param Allowance Work it may do: once Work passes it, walking stops, Spans are incomplete and the caller's
   --  charge of Work fails.
   procedure Row_Spans
     (Item : in out Region;
      Y : Integer;
      Spans : in out Span_Vectors.Vector;
      Work : out Pixel_Count;
      Allowance : Pixel_Count := Pixel_Count'Last);

   --  Intersect.
   --  @param Left Sorted, disjoint spans.
   --  @param Right Sorted, disjoint spans.
   --  @param Result Receives their intersection, sorted.
   procedure Intersect (Left, Right : Span_Vectors.Vector; Result : in out Span_Vectors.Vector);

   --  Subtract.
   --  @param Left Sorted, disjoint spans.
   --  @param Right Sorted, disjoint spans to take away.
   --  @param Result Receives Left less Right, sorted, in one pass over both.
   procedure Subtract (Left, Right : Span_Vectors.Vector; Result : in out Span_Vectors.Vector);

private
   package Integer_Vectors is new Ada.Containers.Vectors (Positive, Integer);

   type Scanline is record
      Y : Integer := 0;
      First : Positive := 1;
      Last : Natural := 0;
   end record;

   package Scanline_Vectors is new Ada.Containers.Vectors (Positive, Scanline);

   type Region is record
      Box : Area;
      Rectangular : Boolean := True;
      Lines : Scanline_Vectors.Vector;
      Points : Integer_Vectors.Vector;
      --  Row cursor: the inversion columns in effect after Lines (1 .. Next_Line - 1).
      Active : Integer_Vectors.Vector;
      Next_Line : Positive := 1;
      Cursor_Y : Integer := Integer'First;
   end record;
end Pictlib.Internal.Regions;
