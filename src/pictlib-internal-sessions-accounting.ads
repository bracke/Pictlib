--  The session's accounting: the drawing work of a render against Max_Drawing_Work, the allocations it admits
--  against Max_Allocation_Bytes and Max_Total_Allocation_Bytes, and the cost model storage is counted by.
package Pictlib.Internal.Sessions.Accounting is
   --  Drawing work: one counter per render, against Max_Drawing_Work.

   --  Start drawing.
   --  @param S Session about to render; no drawing work is done yet.
   procedure Start_Drawing (S : in out Session);
   --  Work left.
   --  @param S Session.
   --  @return The drawing work the budget still allows.
   function Work_Left (S : Session) return Pixel_Count;
   --  Charge work.
   --  @param S Session doing the work.
   --  @param Units Drawing work about to be done.
   --  @return Success, the work then counted, or Limit_Exceeded when it would cross the budget.
   function Charge_Work (S : in out Session; Units : Pixel_Count) return Results.Result;
   --  Charge work.
   --  @param S Session doing the work.
   --  @param Units Drawing work about to be done.
   --  @return As Charge_Work above.
   function Charge_Work (S : in out Session; Units : Natural) return Results.Result;
   --  Over work.
   --  @param S Session whose drawing budget was crossed.
   --  @param Units Work asked for beyond the work done.
   --  @return The Limit_Exceeded failure for drawing work, saturated: the one report of it.
   function Over_Work (S : Session; Units : Pixel_Count) return Results.Result;

   --  Allocations: each against Max_Allocation_Bytes, all of a session against Max_Total_Allocation_Bytes.

   --  Admit allocation.
   --  @param S Session about to allocate.
   --  @param Length Bytes of one allocation.
   --  @return Success, the bytes then counted against the session's total, or Limit_Exceeded when the
   --  allocation or the total would cross its limit.
   function Admit_Allocation (S : in out Session; Length : Byte_Count) return Results.Result;
   --  Admit aggregate.
   --  @param S Session about to hold storage that is not one allocation (vectors, copies).
   --  @param Length Bytes it is estimated at, by the cost model below.
   --  @return Success, the bytes then counted, or Limit_Exceeded when the session's total would cross its limit.
   function Admit_Aggregate (S : in out Session; Length : Byte_Count) return Results.Result;
   --  Shape work left.
   --  @param S Session.
   --  @return What building one shape may spend: the drawing work left, and no more than the spans the session's
   --  allocation total still admits.
   function Shape_Work_Left (S : Session) return Pixel_Count;

   --  The cost model: what storage that is not one allocation is counted at against the session's total.
   --  A retained metadata item or font name, besides its bytes.
   Item_Overhead_Bytes : constant := 128;
   --  A polygon point.
   Point_Cost_Bytes : constant := 8;
   --  A polygon edge while a filled polygon is scanned: its record in the edge and active lists, and its
   --  crossing.
   Polygon_Edge_Bytes : constant := 2 * 48 + 8;
   --  A unit of a region's size, for a copy of it.
   Region_Unit_Bytes : constant := 8;
   --  Each byte of a region read: its scanlines and inversion points, with capacity growth.
   Region_Payload_Factor : constant := 4;
   --  A unit of shape-building work: the spans it can make.
   Shape_Bytes_Per_Work_Unit : constant := 256;
end Pictlib.Internal.Sessions.Accounting;
