with Interfaces;
with Pictlib.Errors;
with Pictlib.Geometry;
with Pictlib.Internal.Bytes;
with Pictlib.Streams;

package body Pictlib.Internal.Region_Reader is
   use type Interfaces.Unsigned_16;

   function Read_Size (S : in out Sessions.Session; Size : out Interfaces.Unsigned_16) return Results.Result is
      Outcome : constant Results.Result := Sessions.Read_Word (S, Size);
   begin
      if not Results.Succeeded (Outcome) then
         return Outcome;
      elsif Size < Smallest_Region then
         return Sessions.Fail (S, Errors.Region_Invalid, Smallest_Region, Byte_Count (Size));
      elsif Byte_Count (Size) > S.Budget.Max_Region_Bytes then
         return Sessions.Over_Limit (S, Region_Byte_Limit, S.Budget.Max_Region_Bytes, Byte_Count (Size));
      end if;
      return Results.Success;
   end Read_Size;

   function Skip (S : in out Sessions.Session) return Results.Result is
      Size : Interfaces.Unsigned_16;
      Outcome : constant Results.Result := Read_Size (S, Size);
   begin
      if not Results.Succeeded (Outcome) then
         return Outcome;
      end if;
      return Sessions.Skip_Data (S, Byte_Count (Size) - 2);
   end Skip;

   function Read (S : in out Sessions.Session; Item : out Regions.Region) return Results.Result is
      Size : Interfaces.Unsigned_16;
      Rect : Geometry.Rect;
      Data : Streams.Byte_Array_Access;
      Outcome : Results.Result := Read_Size (S, Size);
   begin
      Item := Regions.Rectangle ((others => 0));
      if Results.Succeeded (Outcome) then
         Outcome := Sessions.Read_Bounds (S, Rect);
      end if;
      if not Results.Succeeded (Outcome) then
         return Outcome;
      elsif Size = Smallest_Region then
         Item := Regions.Rectangle (Regions.To_Area (Rect));
         return Results.Success;
      end if;
      Outcome := Sessions.Read_Payload (S, Byte_Count (Size) - Smallest_Region, Data);
      if not Results.Succeeded (Outcome) then
         return Outcome;
      end if;
      --  The scanlines and inversion points built from the payload, while it is still held.
      Outcome := Sessions.Admit_Aggregate (S, Sessions.Region_Payload_Factor * (Byte_Count (Size) - Smallest_Region));
      if Results.Succeeded (Outcome) and then not Regions.From_Scanlines (Regions.To_Area (Rect), Data.all, Item)
      then
         Outcome := Sessions.Fail (S, Errors.Region_Invalid, Actual => Byte_Count (Size));
      end if;
      Bytes.Free (Data);
      return Outcome;
   end Read;
end Pictlib.Internal.Region_Reader;
