with Pictlib.Internal.Regions;
with Pictlib.Internal.Sessions;
with Pictlib.Results;

--  Regions read from or skipped in a picture, under the region and allocation budgets; Regions itself knows no
--  session.
package Pictlib.Internal.Region_Reader is

   --  Skip.
   --  @param S Session positioned at a region.
   --  @return Success, Region_Invalid for a size below 10, or Limit_Exceeded above the region budget.
   function Skip (S : in out Sessions.Session) return Results.Result;
   --  Read.
   --  @param S Session positioned at a region.
   --  @param Item The region; rectangular and empty on failure.
   --  @param Exact_Size Whether the region must give itself Expected_Size: one that does not is refused before
   --  anything past its size word is read.
   --  @param Expected_Size The size, when Exact_Size.
   --  @return Success, Region_Invalid for malformed scanlines or, with Exact_Size, a size other than
   --  Expected_Size, or Limit_Exceeded above the region or allocation budgets.
   function Read
     (S : in out Sessions.Session;
      Item : out Regions.Region;
      Exact_Size : Boolean := False;
      Expected_Size : Byte_Count := 0) return Results.Result;
end Pictlib.Internal.Region_Reader;
