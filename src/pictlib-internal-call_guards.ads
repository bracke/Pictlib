with Ada.Finalization;

--  Guards a public call that runs caller code (a visitor, a source, a destination), which may raise, call back
--  into the object, or have the task aborted. Busy is held for the call, so a nested call can be refused. Caller
--  code that rebinds the object (Binds moves) leaves it as that code chose; otherwise a call that ends in the
--  state it began in did not return, since every return moves it on, and its object decides what that leaves.
package Pictlib.Internal.Call_Guards is
   type Guard
     (Busy : not null access Boolean;
      Binds : not null access constant Generation) is abstract new Ada.Finalization.Limited_Controlled
   with private;

   --  Rebound.
   --  @param Item Guard of the call.
   --  @return True when caller code the call ran rebound the object.
   function Rebound (Item : Guard'Class) return Boolean;

   --  Left unfinished: what a call that ended without being rebound leaves; it must not raise.
   --  @param Item Guard of the call.
   procedure Left_Unfinished (Item : in out Guard) is abstract;

   overriding procedure Initialize (Item : in out Guard);
   overriding procedure Finalize (Item : in out Guard);

private
   type Guard
     (Busy : not null access Boolean;
      Binds : not null access constant Generation) is abstract new Ada.Finalization.Limited_Controlled
   with record
      Binds_At_Start : Generation := 0;
   end record;
end Pictlib.Internal.Call_Guards;
