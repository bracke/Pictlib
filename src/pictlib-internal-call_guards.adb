package body Pictlib.Internal.Call_Guards is
   function Rebound (Item : Guard'Class) return Boolean is (Item.Binds.all /= Item.Binds_At_Start);

   overriding procedure Initialize (Item : in out Guard) is
   begin
      Item.Busy.all := True;
      Item.Binds_At_Start := Item.Binds.all;
   end Initialize;

   overriding procedure Finalize (Item : in out Guard) is
   begin
      Item.Busy.all := False;
      if not Rebound (Item) then
         Left_Unfinished (Guard'Class (Item));
      end if;
   end Finalize;
end Pictlib.Internal.Call_Guards;
