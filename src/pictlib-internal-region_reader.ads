with Pictlib.Internal.Regions;
with Pictlib.Internal.Sessions;
with Pictlib.Results;

--  Regions read from or skipped in a picture, under the region and allocation budgets; Regions itself knows no
--  session.
package Pictlib.Internal.Region_Reader is
   --  The bytes of a region's size word and bounding box.
   Smallest_Region : constant := 10;

   --  Skip.
   --  @param S Session positioned at a region.
   --  @return Success, Region_Invalid for a size below 10, or Limit_Exceeded above the region budget.
   function Skip (S : in out Sessions.Session) return Results.Result;
   --  Read.
   --  @param S Session positioned at a region.
   --  @param Item The region; rectangular and empty on failure.
   --  @return Success, Region_Invalid for malformed scanlines, or Limit_Exceeded above the region or allocation
   --  budgets.
   function Read (S : in out Sessions.Session; Item : out Regions.Region) return Results.Result;
end Pictlib.Internal.Region_Reader;
