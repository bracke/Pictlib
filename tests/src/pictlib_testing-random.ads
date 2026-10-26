with Interfaces;

--  The tests crate's one pseudo-random generator, xorshift64*: deterministic for a seed on every platform, so a
--  failing case can be replayed.
package Pictlib_Testing.Random is
   type Generator is private;

   --  Seeded.
   --  @param Seed Any value but 0, which the generator never leaves.
   --  @return A generator starting from Seed.
   function Seeded (Seed : Interfaces.Unsigned_64 := 16#9E37_79B9_7F4A_7C15#) return Generator
     with Pre => Interfaces."/=" (Seed, 0);
   --  Next.
   --  @param Item Generator, advanced.
   --  @param Bound Values to choose from.
   --  @return A value in 0 .. Bound - 1.
   function Next (Item : in out Generator; Bound : Positive) return Natural;

private
   type Generator is record
      State : Interfaces.Unsigned_64 := 16#9E37_79B9_7F4A_7C15#;
   end record;
end Pictlib_Testing.Random;
