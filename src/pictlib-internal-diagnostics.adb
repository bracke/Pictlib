package body Pictlib.Internal.Diagnostics is
   procedure Clear (Log : in out Warning_Log) is
   begin
      Log.Items.Clear;
      Log.Dropped := 0;
   end Clear;

   procedure Add (Log : in out Warning_Log; Item : Errors.Warning; Max_Records : Natural) is
   begin
      if Natural (Log.Items.Length) < Max_Records then
         Log.Items.Append (Item);
         return;
      end if;
      if Log.Dropped < Natural'Last then
         Log.Dropped := Log.Dropped + 1;
      end if;
      if Max_Records > 0 and then Log.Dropped = 1 then
         --  The displaced warning counts as suppressed too.
         Log.Dropped := 2;
         Log.Items.Replace_Element
           (Log.Items.Last_Index,
            Errors.Make_Warning (Errors.Warnings_Suppressed, Errors.Data_Loss, Item.Context));
      end if;
   end Add;

   function Count (Log : Warning_Log) return Natural is (Natural (Log.Items.Length));

   function Element (Log : Warning_Log; Index : Positive) return Errors.Warning is (Log.Items.Element (Index));
end Pictlib.Internal.Diagnostics;
