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

   type Region is private;

   --  Rectangle.
   --  @param Bounds Rectangle.
   --  @return The rectangular region Bounds.
   function Rectangle (Bounds : Geometry.Rect) return Region;
   --  Bounds.
   --  @param Item Region.
   --  @return Its bounding box.
   function Bounds (Item : Region) return Geometry.Rect;

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
   procedure Row_Spans (Item : in out Region; Y : Integer; Spans : in out Span_Vectors.Vector; Work : out Natural);

   --  Intersect.
   --  @param Left Sorted, disjoint spans.
   --  @param Right Sorted, disjoint spans.
   --  @param Result Receives their intersection, sorted.
   procedure Intersect (Left, Right : Span_Vectors.Vector; Result : in out Span_Vectors.Vector);

private
   package Integer_Vectors is new Ada.Containers.Vectors (Positive, Integer);

   type Scanline is record
      Y : Integer := 0;
      First : Positive := 1;
      Last : Natural := 0;
   end record;

   package Scanline_Vectors is new Ada.Containers.Vectors (Positive, Scanline);

   type Region is record
      Box : Geometry.Rect;
      Rectangular : Boolean := True;
      Lines : Scanline_Vectors.Vector;
      Points : Integer_Vectors.Vector;
      --  Row cursor: the inversion columns in effect after Lines (1 .. Next_Line - 1).
      Active : Integer_Vectors.Vector;
      Next_Line : Positive := 1;
      Cursor_Y : Integer := Integer'First;
   end record;
end Pictlib.Internal.Regions;
