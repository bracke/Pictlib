with AUnit.Assertions;
with Pictlib.Internal.Regions;
with Pictlib_Testing.Random;

package body Pictlib_Testing.Test_Coverage is
   use AUnit.Assertions;

   package Regions renames Pictlib.Internal.Regions;
   subtype Span_List is Regions.Span_Vectors.Vector;

   --  Columns 0 .. 63, a bit each: the oracle the span operations are checked against.
   type Columns is array (0 .. 63) of Boolean;

   function To_Columns (Spans : Span_List) return Columns is
      Result : Columns := [others => False];
   begin
      for S of Spans loop
         for X in S.Left .. S.Right - 1 loop
            Result (X) := True;
         end loop;
      end loop;
      return Result;
   end To_Columns;

   --  Sorted and disjoint, with no empty span: what every span operation must produce.
   function Is_Canonical (Spans : Span_List) return Boolean is
      Previous : Integer := Integer'First;
   begin
      for S of Spans loop
         if S.Left >= S.Right or else S.Left <= Previous then
            return False;
         end if;
         Previous := S.Right;
      end loop;
      return True;
   end Is_Canonical;

   Generator : Pictlib_Testing.Random.Generator := Pictlib_Testing.Random.Seeded;

   function Random (Bound : Positive) return Natural is (Pictlib_Testing.Random.Next (Generator, Bound));

   --  Random sorted, disjoint spans within columns 0 .. 63.
   function Random_Spans return Span_List is
      Result : Span_List;
      X : Natural := Random (4);
   begin
      while X < 63 loop
         declare
            Right : constant Natural := Natural'Min (64, X + 1 + Random (8));
         begin
            Result.Append (Regions.Span'(X, Right));
            X := Right + 1 + Random (6);
         end;
      end loop;
      return Result;
   end Random_Spans;

   procedure Span_Operations (T : in out AUnit.Test_Cases.Test_Case'Class);

   overriding function Name (T : Test) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("coverage");
   end Name;

   overriding procedure Register_Tests (T : in out Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Span_Operations'Access, "coverage.span_operations");
   end Register_Tests;

   --  Intersect and Subtract agree with column sets on 2,000 random pairs, and keep their result canonical.
   procedure Span_Operations (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      for Trial in 1 .. 2_000 loop
         declare
            Left : constant Span_List := Random_Spans;
            Right : constant Span_List := Random_Spans;
            Both, Less : Span_List;
            A : constant Columns := To_Columns (Left);
            B : constant Columns := To_Columns (Right);
            Want_Both, Want_Less : Columns;
         begin
            for X in Columns'Range loop
               Want_Both (X) := A (X) and B (X);
               Want_Less (X) := A (X) and not B (X);
            end loop;
            Regions.Intersect (Left, Right, Both);
            Regions.Subtract (Left, Right, Less);
            Assert (Is_Canonical (Both) and then To_Columns (Both) = Want_Both,
                    "Intersect is wrong on trial" & Trial'Image);
            Assert (Is_Canonical (Less) and then To_Columns (Less) = Want_Less,
                    "Subtract is wrong on trial" & Trial'Image);
         end;
      end loop;
   end Span_Operations;
end Pictlib_Testing.Test_Coverage;
