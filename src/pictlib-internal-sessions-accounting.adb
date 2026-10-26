with Pictlib.Internal.Checked_Arithmetic;

package body Pictlib.Internal.Sessions.Accounting is
   function Work_Left (S : Session) return Pixel_Count is
     (S.Budget.Max_Drawing_Work - Pixel_Count'Min (S.Counts.Work_Used, S.Budget.Max_Drawing_Work));

   procedure Start_Drawing (S : in out Session) is
   begin
      S.Counts.Work_Used := 0;
   end Start_Drawing;

   function Over_Work (S : Session; Units : Pixel_Count) return Results.Result is
     (Over_Limit
        (S, Drawing_Work_Limit, Byte_Count (S.Budget.Max_Drawing_Work),
         Byte_Count (Checked_Arithmetic.Saturating_Add (S.Counts.Work_Used, Units))));

   function Charge_Work (S : in out Session; Units : Pixel_Count) return Results.Result is
   begin
      if Units > Work_Left (S) then
         return Over_Work (S, Units);
      end if;
      S.Counts.Work_Used := S.Counts.Work_Used + Units;
      return Results.Success;
   end Charge_Work;

   function Charge_Work (S : in out Session; Units : Natural) return Results.Result is
     (Charge_Work (S, Pixel_Count (Units)));

   function Admit_Allocation (S : in out Session; Length : Byte_Count) return Results.Result is
   begin
      if Length > S.Budget.Max_Allocation_Bytes then
         return Over_Limit (S, Allocation_Byte_Limit, S.Budget.Max_Allocation_Bytes, Length);
      end if;
      return Admit_Aggregate (S, Length);
   end Admit_Allocation;

   function Admit_Aggregate (S : in out Session; Length : Byte_Count) return Results.Result is
      Total : constant Byte_Count := Checked_Arithmetic.Saturating_Add (S.Counts.Total_Allocation_Bytes, Length);
   begin
      if Total > S.Budget.Max_Total_Allocation_Bytes then
         return Over_Limit (S, Total_Allocation_Byte_Limit, S.Budget.Max_Total_Allocation_Bytes, Total);
      end if;
      S.Counts.Total_Allocation_Bytes := Total;
      return Results.Success;
   end Admit_Aggregate;

   function Allocation_Units_Left (S : Session; Bytes_Per_Unit : Positive) return Pixel_Count is
     (Pixel_Count
        ((S.Budget.Max_Total_Allocation_Bytes
          - Byte_Count'Min (S.Counts.Total_Allocation_Bytes, S.Budget.Max_Total_Allocation_Bytes))
         / Byte_Count (Bytes_Per_Unit)));

   function Shape_Work_Left (S : Session) return Pixel_Count is
     (Pixel_Count'Min (Work_Left (S), Allocation_Units_Left (S, Shape_Bytes_Per_Work_Unit)));
end Pictlib.Internal.Sessions.Accounting;
