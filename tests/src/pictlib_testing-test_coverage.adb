with AUnit.Assertions;
with Pictlib;
with Pictlib.Internal.Coverage;
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

   --  Random sorted, disjoint spans within columns 0 .. 63, drawn from Generator.
   function Random_Spans (Generator : in out Pictlib_Testing.Random.Generator) return Span_List is
      function Random (Bound : Positive) return Natural is (Pictlib_Testing.Random.Next (Generator, Bound));
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
   procedure Line_Path (T : in out AUnit.Test_Cases.Test_Case'Class);

   overriding function Name (T : Test) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("coverage");
   end Name;

   overriding procedure Register_Tests (T : in out Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Span_Operations'Access, "coverage.span_operations");
      Register_Routine (T, Line_Path'Access, "coverage.line_path");
   end Register_Tests;

   --  Intersect and Subtract agree with column sets on 2,000 random pairs, and keep their result canonical.
   procedure Span_Operations (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Seeded here, so the pairs tested are the same however often and in whatever order the suite runs.
      Generator : Pictlib_Testing.Random.Generator := Pictlib_Testing.Random.Seeded;
   begin
      for Trial in 1 .. 2_000 loop
         declare
            Left : constant Span_List := Random_Spans (Generator);
            Right : constant Span_List := Random_Spans (Generator);
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

   --  A 1 x 1 pen's line covers the pixels of Bresenham's walk, stepped here a pixel at a time as an independent
   --  oracle (its x and y steps each decided on the error before either): every line between points of an 11 x 11
   --  grid, and 90 random long ones through a small window, which must cost only the rows they reach.
   procedure Line_Path (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      package Coverage renames Pictlib.Internal.Coverage;
      use type Pictlib.Pixel_Count;
      Window : constant Coverage.Area := (Top => -10, Left => -10, Bottom => 20, Right => 20);
      type Grid is array (Window.Top .. Window.Bottom - 1, Window.Left .. Window.Right - 1) of Boolean;

      function Walked (From, To : Coverage.Point) return Grid is
         Result : Grid := [others => [others => False]];
         X : Long_Long_Integer := Long_Long_Integer (From.H);
         Y : Long_Long_Integer := Long_Long_Integer (From.V);
         Dx : constant Long_Long_Integer := Long_Long_Integer (abs (To.H - From.H));
         Dy : constant Long_Long_Integer := -Long_Long_Integer (abs (To.V - From.V));
         Step_X : constant Long_Long_Integer := (if From.H < To.H then 1 else -1);
         Step_Y : constant Long_Long_Integer := (if From.V < To.V then 1 else -1);
         Error : Long_Long_Integer := Dx + Dy;
         Twice : Long_Long_Integer;
      begin
         loop
            if Y in Long_Long_Integer (Grid'First (1)) .. Long_Long_Integer (Grid'Last (1))
              and then X in Long_Long_Integer (Grid'First (2)) .. Long_Long_Integer (Grid'Last (2))
            then
               Result (Integer (Y), Integer (X)) := True;
            end if;
            exit when X = Long_Long_Integer (To.H) and then Y = Long_Long_Integer (To.V);
            Twice := 2 * Error;
            if Twice >= Dy then
               Error := Error + Dy;
               X := X + Step_X;
            end if;
            if Twice <= Dx then
               Error := Error + Dx;
               Y := Y + Step_Y;
            end if;
         end loop;
         return Result;
      end Walked;

      function Covered (Item : Coverage.Shape) return Grid is
         Result : Grid := [others => [others => False]];
      begin
         for Y in Grid'Range (1) loop
            for S of Coverage.Row (Item, Y) loop
               for X in S.Left .. S.Right - 1 loop
                  Result (Y, X) := True;
               end loop;
            end loop;
         end loop;
         return Result;
      end Covered;

      procedure Check (From, To : Coverage.Point) is
         Item : Coverage.Shape;
      begin
         Coverage.Start (Item, Window);
         Coverage.Line (Item, From, To, 1, 1);
         Assert (Covered (Item) = Walked (From, To),
                 "the line from" & From.H'Image & "," & From.V'Image & " to" & To.H'Image & "," & To.V'Image
                 & " left Bresenham's path");
         --  A few units for each row of the window, however long the line: its buffer, its path, its span.
         Assert (Coverage.Work (Item) <= 8 * Pictlib.Pixel_Count (Window.Bottom - Window.Top),
                 "the line from" & From.H'Image & "," & From.V'Image & " to" & To.H'Image & "," & To.V'Image
                 & " cost" & Coverage.Work (Item)'Image);
      end Check;

      Generator : Pictlib_Testing.Random.Generator := Pictlib_Testing.Random.Seeded;
      function Far return Integer is (Pictlib_Testing.Random.Next (Generator, 2 * 1_000_000) - 1_000_000);
      function Near return Integer is (Pictlib_Testing.Random.Next (Generator, 30) - 10);
   begin
      for From_V in -5 .. 5 loop
         for From_H in -5 .. 5 loop
            for To_V in -5 .. 5 loop
               for To_H in -5 .. 5 loop
                  Check ((From_H, From_V), (To_H, To_V));
               end loop;
            end loop;
         end loop;
      end loop;
      for Trial in 1 .. 30 loop
         --  Long and shallow, long and steep, and long both ways, each crossing the window.
         Check ((Far, Near), (Far, Near));
         Check ((Near, Far), (Near, Far));
         Check ((-1_000_000, -1_000_000 + Near), (1_000_000, 1_000_000 + Near));
      end loop;
   end Line_Path;
end Pictlib_Testing.Test_Coverage;
