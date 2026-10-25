with Ada.Containers.Vectors;
with Pictlib.Errors;

--  A bounded warning record. Once full, the last slot reports that later warnings were suppressed.
package Pictlib.Internal.Diagnostics is
   type Warning_Log is private;

   --  Clear.
   --  @param Log Log to empty.
   procedure Clear (Log : in out Warning_Log);
   --  Add.
   --  @param Log Log to append to.
   --  @param Item Warning to record.
   --  @param Max_Records Most warnings the log holds, Warnings_Suppressed included: past it the last record
   --  becomes Warnings_Suppressed, with the context of the first warning suppressed and their count as Actual;
   --  with 0, every warning is dropped and none records it.
   procedure Add (Log : in out Warning_Log; Item : Errors.Warning; Max_Records : Natural);
   --  Count.
   --  @param Log Log to inspect.
   --  @return Warnings recorded.
   function Count (Log : Warning_Log) return Natural;
   --  Element.
   --  @param Log Log to inspect.
   --  @param Index 1-based warning position.
   --  @return The warning.
   function Element (Log : Warning_Log; Index : Positive) return Errors.Warning
     with Pre => Index <= Count (Log);

private
   package Warning_Vectors is new Ada.Containers.Vectors (Positive, Errors.Warning, Errors."=");

   type Warning_Log is record
      Items : Warning_Vectors.Vector;
      Dropped : Natural := 0;
   end record;
end Pictlib.Internal.Diagnostics;
