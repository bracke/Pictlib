package body Pictlib_Testing.Random is
   use type Interfaces.Unsigned_64;

   function Seeded (Seed : Interfaces.Unsigned_64 := 16#9E37_79B9_7F4A_7C15#) return Generator is
     ((State => Seed));

   function Next (Item : in out Generator; Bound : Positive) return Natural is
   begin
      Item.State := Item.State xor Interfaces.Shift_Right (Item.State, 12);
      Item.State := Item.State xor Interfaces.Shift_Left (Item.State, 25);
      Item.State := Item.State xor Interfaces.Shift_Right (Item.State, 27);
      --  The product's high half: xorshift64*'s low bits are its weakest.
      return Natural
        (Interfaces.Shift_Right (Item.State * 16#2545_F491_4F6C_DD1D#, 32) mod Interfaces.Unsigned_64 (Bound));
   end Next;
end Pictlib_Testing.Random;
