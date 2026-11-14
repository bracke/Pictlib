with Pictlib.Internal.Divisions;
with Pictlib.Internal.Checked_Arithmetic;
package body Pictlib.Internal.Coverage is
   use Pictlib.Internal.Divisions;
   type Wide is range -2 ** 126 .. 2 ** 126;

   --  sin (k degrees) * 2 ** 30, k = 0 .. 90, rounded.
   Sine_Table : constant array (0 .. 90) of Wide :=
     [0, 18_739_379, 37_473_049, 56_195_305, 74_900_443, 93_582_766,
      112_236_583, 130_856_211, 149_435_979, 167_970_228, 186_453_311, 204_879_599,
      223_243_478, 241_539_355, 259_761_657, 277_904_834, 295_963_357, 313_931_728,
      331_804_471, 349_576_144, 367_241_333, 384_794_656, 402_230_767, 419_544_355,
      436_730_145, 453_782_903, 470_697_435, 487_468_587, 504_091_252, 520_560_366,
      536_870_912, 553_017_922, 568_996_477, 584_801_711, 600_428_808, 615_873_009,
      631_129_609, 646_193_961, 661_061_475, 675_727_625, 690_187_940, 704_438_018,
      718_473_518, 732_290_163, 745_883_746, 759_250_125, 772_385_229, 785_285_058,
      797_945_680, 810_363_241, 822_533_958, 834_454_122, 846_120_104, 857_528_349,
      868_675_383, 879_557_810, 890_172_315, 900_515_665, 910_584_710, 920_376_381,
      929_887_697, 939_115_760, 948_057_759, 956_710_970, 965_072_759, 973_140_576,
      980_911_966, 988_384_560, 995_556_083, 1_002_424_350, 1_008_987_269, 1_015_242_840,
      1_021_189_159, 1_026_824_413, 1_032_146_887, 1_037_154_959, 1_041_847_103, 1_046_221_891,
      1_050_277_989, 1_054_014_162, 1_057_429_273, 1_060_522_280, 1_063_292_242, 1_065_738_315,
      1_067_859_754, 1_069_655_912, 1_071_126_243, 1_072_270_298, 1_073_087_729, 1_073_578_288,
      1_073_741_824];

   function Sine (Degrees : Integer) return Wide is
      A : constant Integer := Degrees mod 360;
   begin
      case A is
         when 0 .. 90 => return Sine_Table (A);
         when 91 .. 180 => return Sine_Table (180 - A);
         when 181 .. 270 => return -Sine_Table (A - 180);
         when others => return -Sine_Table (360 - A);
      end case;
   end Sine;

   function Cosine (Degrees : Integer) return Wide is (Sine (Degrees + 90));

   function Square_Root (Value : Long_Long_Integer) return Long_Long_Integer is
      Guess : Long_Long_Integer;
      Next : Long_Long_Integer;
   begin
      if Value < 2 then
         return Value;
      end if;
      --  Newton's method from any guess at least the root ends on the root; the smallest power of two that is
      --  ends there in a few steps, where Value itself took one a bit.
      Guess := 1;
      while Guess < Value / Guess loop
         Guess := 2 * Guess;
      end loop;
      loop
         Next := (Guess + Value / Guess) / 2;
         exit when Next >= Guess;
         Guess := Next;
      end loop;
      return Guess;
   end Square_Root;

   procedure Start (Item : out Shape; Window : Area; Allowance : Pixel_Count := Pixel_Count'Last) is
   begin
      Item.Window := Window;
      Item.Units := 0;
      Item.Allowance := Allowance;
      Item.Spent := False;
      Item.Top := Window.Top;
      Item.Rows.Clear;
      Item.Pool.Clear;
      Item.Abandoned := 0;
   end Start;

   function Window_Of (Item : Shape) return Area is (Item.Window);

   function First_Row (Item : Shape) return Integer is (Item.Top);

   function Last_Row (Item : Shape) return Integer is (Item.Top + Natural (Item.Rows.Length) - 1);

   function Slot_Of (Item : Shape; Y : Integer) return Row_Slot is (Item.Rows.Element (Y - Item.Top));

   --  Row Y's spans appended to Into.
   procedure Append_Row (Item : Shape; Y : Integer; Into : in out Span_List) is
      Slot : constant Row_Slot := Slot_Of (Item, Y);
   begin
      for Index in Slot.First .. Slot.First + Slot.Count - 1 loop
         Into.Append (Item.Pool.Element (Index));
      end loop;
   end Append_Row;

   procedure Copy_Row (Item : Shape; Y : Integer; Into : in out Span_List) is
   begin
      Into.Clear;
      if not Item.Spent and then Y in First_Row (Item) .. Last_Row (Item) then
         Append_Row (Item, Y, Into);
      end if;
   end Copy_Row;

   function Row (Item : Shape; Y : Integer) return Span_List is
      Result : Span_List;
   begin
      Copy_Row (Item, Y, Result);
      return Result;
   end Row;

   function Work (Item : Shape) return Pixel_Count is (Item.Units);

   function Exhausted (Item : Shape) return Boolean is (Item.Spent);

   function Remaining (Item : Shape) return Pixel_Count is
     (if Item.Units >= Item.Allowance then 0 else Item.Allowance - Item.Units);

   procedure Add_Work (Item : in out Shape; Units : Pixel_Count) is
   begin
      Item.Units := Checked_Arithmetic.Saturating_Add (Item.Units, Units);
      if Item.Units > Item.Allowance then
         Item.Spent := True;
      end if;
   end Add_Work;

   procedure Charge (Item : in out Shape; Units : Natural) is
   begin
      Add_Work (Item, Pixel_Count (Units));
   end Charge;

   --  Hold row Y, inside the window, charging a unit for every row added. Builders mostly go down the rows, so
   --  rows are appended; a row above the first moves those held, which is charged too.
   procedure Hold (Item : in out Shape; Y : Integer) is
      Empty : constant Row_Slot := (others => <>);
   begin
      if Item.Rows.Is_Empty then
         Item.Top := Y;
         Item.Rows.Append (Empty);
         Charge (Item, 1);
      elsif Y > Last_Row (Item) then
         Charge (Item, Y - Last_Row (Item));
         Item.Rows.Append (Empty, Ada.Containers.Count_Type (Y - Last_Row (Item)));
      elsif Y < Item.Top then
         --  The held rows' slots move down, a unit a row; their spans stay where they are in the pool.
         Charge (Item, Item.Top - Y + Natural (Item.Rows.Length));
         Item.Rows.Prepend (Empty, Ada.Containers.Count_Type (Item.Top - Y));
         Item.Top := Y;
      end if;
   end Hold;

   --  The pool rewritten with only what rows hold, each with no room to spare: once rows have left more behind
   --  than they hold, so the work is no more than the moves that left it.
   procedure Compact (Item : in out Shape) is
      Kept : Span_List;
   begin
      Kept.Reserve_Capacity (Ada.Containers.Count_Type (Natural (Item.Pool.Length) - Item.Abandoned));
      for Index in Item.Rows.First_Index .. Item.Rows.Last_Index loop
         declare
            Slot : constant Row_Slot := Item.Rows.Element (Index);
            Moved : constant Row_Slot := (First => Natural (Kept.Length) + 1, Count => Slot.Count, Room => Slot.Count);
         begin
            for At_Span in Slot.First .. Slot.First + Slot.Count - 1 loop
               Kept.Append (Item.Pool.Element (At_Span));
            end loop;
            Item.Rows.Replace_Element (Index, Moved);
         end;
      end loop;
      Item.Pool.Move (Kept);
      Item.Abandoned := 0;
   end Compact;

   --  Row Y's spans become Spans: in its room when they fit, else at the pool's end with as much again to spare,
   --  so a row that keeps growing moves a number of times only logarithmic in its spans.
   procedure Place (Item : in out Shape; Y : Integer; Spans : Span_List) is
      Slot : Row_Slot := Slot_Of (Item, Y);
      Count : constant Natural := Natural (Spans.Length);
   begin
      if Count > Slot.Room then
         Item.Abandoned := Item.Abandoned + Slot.Room;
         Slot := (First => Natural (Item.Pool.Length) + 1, Count => 0, Room => 2 * Count);
         Item.Pool.Append (Regions.Span'(0, 0), Ada.Containers.Count_Type (Slot.Room));
      end if;
      for Index in 0 .. Count - 1 loop
         Item.Pool.Replace_Element (Slot.First + Index, Spans.Element (Spans.First_Index + Index));
      end loop;
      Slot.Count := Count;
      Item.Rows.Replace_Element (Y - Item.Top, Slot);
      if Item.Abandoned > Natural (Item.Pool.Length) / 2 then
         Compact (Item);
      end if;
   end Place;

   --  Room for rows down to Last, from First when none is held, so appending them does not grow the rows a step
   --  at a time, each step copying every span held; never for more rows than the allowance left pays for.
   procedure Expect_Rows (Item : in out Shape; First, Last : Integer) is
      Held : constant Long_Long_Integer := Long_Long_Integer (Item.Rows.Length);
      Below : constant Long_Long_Integer :=
        (if Item.Rows.Is_Empty then Long_Long_Integer (Last) - Long_Long_Integer (First) + 1
         else Long_Long_Integer (Last) - Long_Long_Integer (Last_Row (Item)));
      Wanted : constant Long_Long_Integer :=
        Held + Long_Long_Integer'Min (Long_Long_Integer'Max (Below, 0), Long_Long_Integer (Remaining (Item)));
   begin
      if Wanted > Long_Long_Integer (Item.Rows.Capacity) then
         Item.Rows.Reserve_Capacity (Ada.Containers.Count_Type (Wanted));
      end if;
      --  A span a row at least, as most shapes have, so the pool does not grow a step at a time either.
      if Wanted - Held + Long_Long_Integer (Item.Pool.Length) > Long_Long_Integer (Item.Pool.Capacity) then
         Item.Pool.Reserve_Capacity (Ada.Containers.Count_Type (Wanted - Held + Long_Long_Integer (Item.Pool.Length)));
      end if;
   end Expect_Rows;

   --  Add pixels Left .. Right - 1 of row Y, merging with what the row holds.
   procedure Add (Item : in out Shape; Y, Left, Right : Integer) is
      First : constant Integer := Integer'Max (Left, Item.Window.Left);
      Last : constant Integer := Integer'Min (Right, Item.Window.Right);
   begin
      if Y not in Item.Window.Top .. Item.Window.Bottom - 1 or else First >= Last then
         return;
      end if;
      Hold (Item, Y);
      Charge (Item, 1);
      --  Spans mostly arrive left to right: append, or widen the last span, in place.
      declare
         Slot : Row_Slot := Slot_Of (Item, Y);
         Last_Index : constant Natural := Slot.First + Slot.Count - 1;
         At_End : constant Boolean := Slot.First + Slot.Room - 1 = Natural (Item.Pool.Length);
      begin
         if Slot.Count = 0 or else Item.Pool.Element (Last_Index).Right < First then
            if Slot.Count < Slot.Room then
               Item.Pool.Replace_Element (Slot.First + Slot.Count, Regions.Span'(First, Last));
               Slot.Count := Slot.Count + 1;
               Item.Rows.Replace_Element (Y - Item.Top, Slot);
               return;
            elsif At_End or else Slot.Room = 0 then
               --  At the pool's end, or a row with no spans yet, which starts there.
               if Slot.Room = 0 then
                  Slot.First := Natural (Item.Pool.Length) + 1;
               end if;
               Item.Pool.Append (Regions.Span'(First, Last));
               Slot.Count := Slot.Count + 1;
               Slot.Room := Slot.Room + 1;
               Item.Rows.Replace_Element (Y - Item.Top, Slot);
               return;
            end if;
            --  A row full and away from the end moves there with the span, still charged as an append.
            declare
               Grown : Span_List;
            begin
               Append_Row (Item, Y, Grown);
               Grown.Append (Regions.Span'(First, Last));
               Place (Item, Y, Grown);
            end;
            return;
         elsif Item.Pool.Element (Last_Index).Left <= First then
            declare
               Widened : constant Regions.Span := Item.Pool.Element (Last_Index);
            begin
               Item.Pool.Replace_Element (Last_Index, Regions.Span'(Widened.Left, Integer'Max (Widened.Right, Last)));
            end;
            return;
         end if;
      end;
      declare
         Merged : Span_List;
         Pending : Regions.Span := (First, Last);
         Placed : Boolean := False;
         Slot : constant Row_Slot := Slot_Of (Item, Y);
      begin
         for Index in Slot.First .. Slot.First + Slot.Count - 1 loop
            declare
               S : constant Regions.Span := Item.Pool.Element (Index);
            begin
               if S.Right < Pending.Left then
                  Merged.Append (S);
               elsif Pending.Right < S.Left then
                  if not Placed then
                     Merged.Append (Pending);
                     Placed := True;
                  end if;
                  Merged.Append (S);
               else
                  Pending := (Integer'Min (S.Left, Pending.Left), Integer'Max (S.Right, Pending.Right));
               end if;
            end;
         end loop;
         if not Placed then
            Merged.Append (Pending);
         end if;
         Charge (Item, Natural (Merged.Length));
         Place (Item, Y, Merged);
      end;
   end Add;

   --  The window rows Bounds covers; none when Bounds lies wholly left or right of the window, so a shape
   --  there walks no rows.
   function Row_Range (Item : Shape; Bounds : Area; First, Last : out Integer) return Boolean is
   begin
      First := Integer'Max (Bounds.Top, Item.Window.Top);
      Last := Integer'Min (Bounds.Bottom, Item.Window.Bottom) - 1;
      return First <= Last and then not Regions.Is_Empty (Bounds)
        and then Bounds.Left < Item.Window.Right and then Item.Window.Left < Bounds.Right;
   end Row_Range;

   procedure Rectangle (Item : in out Shape; Bounds : Area) is
      First, Last : Integer;
   begin
      if Row_Range (Item, Bounds, First, Last) then
         Expect_Rows (Item, First, Last);
         for Y in First .. Last loop
            exit when Item.Spent;
            Charge (Item, 1);
            Add (Item, Y, Bounds.Left, Bounds.Right);
         end loop;
      end if;
   end Rectangle;

   --  Columns of row Y of the oval inscribed in Bounds: pixels whose centers satisfy
   --  (dx / width) ** 2 + (dy / height) ** 2 <= 1, with dx, dy the center's offsets doubled.
   function Oval_Row (Bounds : Area; Y : Integer; Left, Right : out Integer) return Boolean is
      Width : constant Long_Long_Integer := Long_Long_Integer (Bounds.Right - Bounds.Left);
      Height : constant Long_Long_Integer := Long_Long_Integer (Bounds.Bottom - Bounds.Top);
      Dy : constant Long_Long_Integer := 2 * Long_Long_Integer (Y) + 1 - Long_Long_Integer (Bounds.Top + Bounds.Bottom);
      Sum : constant Long_Long_Integer := Long_Long_Integer (Bounds.Left) + Long_Long_Integer (Bounds.Right);
   begin
      Left := 0;
      Right := 0;
      if Width <= 0 or else Height <= 0 or else abs Dy >= Height then
         return False;
      end if;
      declare
         --  The same quotient in 64 bits when the box is at most 2 ** 15 on each side, as its product then is
         --  below 2 ** 60; in 128 otherwise.
         Limit : constant Long_Long_Integer :=
           (if Width <= 2 ** 15 and then Height <= 2 ** 15
            then Width ** 2 * (Height ** 2 - Dy ** 2) / Height ** 2
            else Long_Long_Integer (Wide (Width) ** 2 * (Wide (Height) ** 2 - Wide (Dy) ** 2) / Wide (Height) ** 2));
         Reach : constant Long_Long_Integer := Square_Root (Limit);
         From : constant Long_Long_Integer := Ceiling_Divide (Sum - Reach - 1, 2);
         To : constant Long_Long_Integer := Floor_Divide (Sum + Reach - 1, 2);
      begin
         if From > To then
            return False;
         end if;
         Left := Integer (From);
         Right := Integer (To) + 1;
         return True;
      end;
   end Oval_Row;

   procedure Oval (Item : in out Shape; Bounds : Area) is
      First, Last, Left, Right : Integer;
   begin
      if Row_Range (Item, Bounds, First, Last) then
         Expect_Rows (Item, First, Last);
         for Y in First .. Last loop
            exit when Item.Spent;
            --  Every row walked is charged, whether or not any of it lands in the window.
            Charge (Item, 1);
            if Oval_Row (Bounds, Y, Left, Right) then
               Add (Item, Y, Left, Right);
            end if;
         end loop;
      end if;
   end Oval;

   procedure Round_Rect (Item : in out Shape; Bounds : Area; Oval_Width, Oval_Height : Integer) is
      Width : constant Integer := Integer'Min (Oval_Width, Bounds.Right - Bounds.Left);
      Height : constant Integer := Integer'Min (Oval_Height, Bounds.Bottom - Bounds.Top);
      First, Last, Left, Right : Integer;
   begin
      if Width <= 0 or else Height <= 0 then
         Rectangle (Item, Bounds);
         return;
      elsif not Row_Range (Item, Bounds, First, Last) then
         return;
      end if;
      Expect_Rows (Item, First, Last);
      declare
         Corner : constant Area := (0, 0, Height, Width);
      begin
         for Y in First .. Last loop
            exit when Item.Spent;
            Charge (Item, 1);
            declare
               Oval_Y : constant Integer :=
                 (if Y < Bounds.Top + Height / 2 then Y - Bounds.Top
                  elsif Y >= Bounds.Bottom - (Height - Height / 2) then Y - (Bounds.Bottom - Height)
                  else -1);
            begin
               if Oval_Y < 0 then
                  Add (Item, Y, Bounds.Left, Bounds.Right);
               else
                  --  A corner row the oval holds no pixel centre of is cut to the corners' meeting point, never
                  --  away: the straight edge between the two corners stays.
                  if not Oval_Row (Corner, Oval_Y, Left, Right) then
                     Left := Width / 2;
                     Right := Width - Width / 2;
                  end if;
                  Add (Item, Y, Bounds.Left + Left, Bounds.Right - (Width - Right));
               end if;
            end;
         end loop;
      end;
   end Round_Rect;

   procedure Wedge (Item : in out Shape; Bounds : Area; Start_Angle, Arc_Angle : Integer) is
      From : Integer := Start_Angle;
      Sweep : Integer := Arc_Angle;
      Width : constant Wide := Wide (Bounds.Right - Bounds.Left);
      Height : constant Wide := Wide (Bounds.Bottom - Bounds.Top);
   begin
      if Sweep >= 360 or else Sweep <= -360 then
         return;
      elsif Sweep < 0 then
         From := From + Sweep;
         Sweep := -Sweep;
      end if;
      From := From mod 360;
      declare
         S1 : constant Wide := Sine (From);
         C1 : constant Wide := Cosine (From);
         S2 : constant Wide := Sine (From + Sweep);
         C2 : constant Wide := Cosine (From + Sweep);

         --  Doubled offsets from the center, stretched so that Bounds becomes a square; F > 0 when the point
         --  lies clockwise of the direction at that angle (y grows downward, 0 degrees points up).
         function Inside (X, Y : Integer) return Boolean is
            U : constant Wide := (2 * Wide (X) + 1 - Wide (Bounds.Left) - Wide (Bounds.Right)) * Height;
            V : constant Wide := (2 * Wide (Y) + 1 - Wide (Bounds.Top) - Wide (Bounds.Bottom)) * Width;
            F1 : constant Wide := S1 * V + C1 * U;
            F2 : constant Wide := S2 * V + C2 * U;
         begin
            if Sweep = 0 then
               return False;
            elsif Sweep <= 180 then
               return F1 >= 0 and then F2 <= 0;
            end if;
            return not (F2 > 0 and then F1 < 0);
         end Inside;
      begin
         for Index in 0 .. Natural (Item.Rows.Length) - 1 loop
            exit when Item.Spent;
            declare
               Y : constant Integer := Item.Top + Index;
               Spans : Span_List;
               Kept : Span_List;
            begin
               Append_Row (Item, Y, Spans);
               for At_Span in Spans.First_Index .. Spans.Last_Index loop
                  declare
                     S : constant Regions.Span := Spans.Element (At_Span);
                     Run_Start : Integer := S.Left;
                  begin
                     --  The span is charged before it is tested, so a spent shape tests no more of it.
                     Charge (Item, S.Right - S.Left);
                     exit when Item.Spent;
                     for X in S.Left .. S.Right - 1 loop
                        if not Inside (X, Y) then
                           if Run_Start < X then
                              Kept.Append (Regions.Span'(Run_Start, X));
                           end if;
                           Run_Start := X + 1;
                        end if;
                     end loop;
                     if Run_Start < S.Right then
                        Kept.Append (Regions.Span'(Run_Start, S.Right));
                     end if;
                  end;
               end loop;
               Place (Item, Y, Kept);
            end;
         end loop;
      end;
   end Wedge;

   --  A polygon edge, its ends doubled so pixel centers are integers. It crosses the centers of rows First ..
   --  Last: 2y + 1 in [Low, High) of its doubled ends.
   type Edge is record
      X0, Y0, X1, Y1 : Long_Long_Integer := 0;
      First, Last : Long_Long_Integer := 0;
   end record;

   function Starts_Before (Left, Right : Edge) return Boolean is (Left.First < Right.First);

   package Edge_Vectors is new Ada.Containers.Vectors (Positive, Edge);
   package Edge_Sorting is new Edge_Vectors.Generic_Sorting (Starts_Before);
   package Boundary_Vectors is new Ada.Containers.Vectors (Positive, Long_Long_Integer);
   package Boundary_Sorting is new Boundary_Vectors.Generic_Sorting;

   --  The edges of the closed polygon through Points that cross a row's center, sorted by the first they cross.
   procedure Build_Edges (Points : Point_Vectors.Vector; Edges : out Edge_Vectors.Vector) is
      Count : constant Natural := Natural (Points.Length);
   begin
      Edges.Clear;
      Edges.Reserve_Capacity (Ada.Containers.Count_Type (Count));
      for Index in 1 .. Count loop
         declare
            P : constant Point := Points (Index);
            Q : constant Point := Points (if Index = Count then 1 else Index + 1);
            Y0 : constant Long_Long_Integer := 2 * Long_Long_Integer (P.V);
            Y1 : constant Long_Long_Integer := 2 * Long_Long_Integer (Q.V);
            Low : constant Long_Long_Integer := Long_Long_Integer'Min (Y0, Y1);
            High : constant Long_Long_Integer := Long_Long_Integer'Max (Y0, Y1);
            First : constant Long_Long_Integer := Ceiling_Divide (Low - 1, 2);
            Last : constant Long_Long_Integer := Ceiling_Divide (High - 1, 2) - 1;
         begin
            if First <= Last then
               Edges.Append (Edge'(2 * Long_Long_Integer (P.H), Y0, 2 * Long_Long_Integer (Q.H), Y1, First, Last));
            end if;
         end;
      end loop;
      Edge_Sorting.Sort (Edges);
   end Build_Edges;

   --  Where E crosses the row whose doubled center is Center: the first pixel whose center is at or right of it.
   function Crossing (E : Edge; Center : Long_Long_Integer) return Long_Long_Integer is
      Den : Long_Long_Integer := E.Y1 - E.Y0;
      Num : Long_Long_Integer := E.X0 * Den + (Center - E.Y0) * (E.X1 - E.X0);
   begin
      if Den < 0 then
         Den := -Den;
         Num := -Num;
      end if;
      return Ceiling_Divide (Num - Den, 2 * Den);
   end Crossing;

   procedure Polygon (Item : in out Shape; Points : Point_Vectors.Vector) is
      Count : constant Natural := Natural (Points.Length);
      Edges, Active : Edge_Vectors.Vector;
      --  A row's crossings and the edges still active below it, kept across rows so their storage is reused.
      Boundaries : Boundary_Vectors.Vector;
      Kept : Edge_Vectors.Vector;
      Next_Edge : Positive := 1;
   begin
      if Count < 3 then
         return;
      end if;
      --  The edges are charged before they are built and sorted.
      Charge (Item, Count);
      if Item.Spent then
         return;
      end if;
      Build_Edges (Points, Edges);
      if Edges.Is_Empty then
         return;
      end if;
      --  Every list holds at most every edge: reserved exactly, as the allocation total counts them, where
      --  appending alone would let each grow to twice that.
      Active.Reserve_Capacity (Edges.Length);
      Kept.Reserve_Capacity (Edges.Length);
      Boundaries.Reserve_Capacity (Edges.Length);
      declare
         Lowest : Long_Long_Integer := Edges.First_Element.Last;
      begin
         for Index in Edges.First_Index .. Edges.Last_Index loop
            Lowest := Long_Long_Integer'Max (Lowest, Edges.Element (Index).Last);
         end loop;
         Expect_Rows
           (Item, Integer (Long_Long_Integer'Max (Long_Long_Integer (Item.Window.Top), Edges.First_Element.First)),
            Integer (Long_Long_Integer'Min (Long_Long_Integer (Item.Window.Bottom - 1), Lowest)));
      end;

      --  From the first row an edge crosses, not the window's top.
      for Y in Integer (Long_Long_Integer'Max (Long_Long_Integer (Item.Window.Top), Edges.First_Element.First))
        .. Item.Window.Bottom - 1
      loop
         exit when Item.Spent;
         declare
            Row : constant Long_Long_Integer := Long_Long_Integer (Y);
            Center : constant Long_Long_Integer := 2 * Row + 1;
         begin
            Boundaries.Clear;
            Kept.Clear;
            --  Edges are read through Element, a copy, not by indexing, whose reference GNAT guards with a
            --  controlled lock finalized at every read.
            while Next_Edge <= Natural (Edges.Length) and then Edges.Element (Next_Edge).First <= Row loop
               Active.Append (Edges.Element (Next_Edge));
               Next_Edge := Next_Edge + 1;
            end loop;
            exit when Active.Is_Empty and then Next_Edge > Natural (Edges.Length);
            for Index in Active.First_Index .. Active.Last_Index loop
               declare
                  E : constant Edge := Active.Element (Index);
               begin
                  if E.Last >= Row then
                     Kept.Append (E);
                     Boundaries.Append (Crossing (E, Center));
                  end if;
               end;
            end loop;
            Active.Move (Kept);
            Charge (Item, Natural (Active.Length) + 1);
            Boundary_Sorting.Sort (Boundaries);
            declare
               Index : Positive := 1;
            begin
               while Index + 1 <= Natural (Boundaries.Length) loop
                  Add (Item, Y, Integer (Boundaries.Element (Index)), Integer (Boundaries.Element (Index + 1)));
                  Index := Index + 2;
               end loop;
            end;
         end;
      end loop;
   end Polygon;

   package Column_Vectors is new Ada.Containers.Vectors (Natural, Integer);

   --  The path from From to To is the one Bresenham's walk takes, a pixel a step, its x and y steps each decided
   --  on the error before either: rows Kept_Top .. Kept_Bottom record their leftmost and rightmost columns in
   --  Low_X and High_X, indexed from Kept_Top, a unit a row. Each row's columns are found directly, so a line
   --  that is mostly outside the window costs only the rows that reach it.
   --  Along a shallow path (Dx >= Dy) every step moves a column: row R holds the columns after the last of row
   --  R - 1 up to the first column N at which the error, Dx * (1 + R) - Dy * (1 + N), is at most Dx / 2. Along
   --  a steep one every step moves a row, and row R's one column is the number of columns C whose error first
   --  reaches -Dy / 2 in an earlier row: those with Dy * (1 + 2 C) <= 2 Dx R.
   procedure Walk
     (Item : in out Shape;
      From, To : Point;
      Kept_Top, Kept_Bottom : Integer;
      Low_X, High_X : in out Column_Vectors.Vector)
   is
      --  Steps of the path, in 64 bits: the products below stay under 2 ** 52 within reach.
      subtype Long is Long_Long_Integer;
      Dx : constant Long := Long (abs (To.H - From.H));
      Dy : constant Long := Long (abs (To.V - From.V));
      Step_X : constant Integer := (if From.H < To.H then 1 else -1);

      --  The last column of shallow row R: the first N with 2 Dy (1 + N) >= Dx (1 + 2 R), and To's on the last.
      function Last_Of (R : Long) return Long is
        (if R >= Dy then Dx else Long'Min (Dx, Ceiling_Divide (Dx * (1 + 2 * R), 2 * Dy) - 1));

      function Column (N : Long) return Integer is (From.H + Step_X * Integer (N));
   begin
      for Y in Kept_Top .. Kept_Bottom loop
         Charge (Item, 1);
         exit when Item.Spent;
         declare
            R : constant Long := Long (abs (Y - From.V));
            First, Last : Long;
         begin
            if Dx >= Dy then
               First := (if R = 0 then 0 else Last_Of (R - 1) + 1);
               Last := Last_Of (R);
            else
               First := Long'Min (Dx, Long'Max (0, Floor_Divide (2 * Dx * R - Dy, 2 * Dy) + 1));
               Last := First;
            end if;
            Low_X (Y - Kept_Top) := Integer'Min (Column (First), Column (Last));
            High_X (Y - Kept_Top) := Integer'Max (Column (First), Column (Last));
         end;
      end loop;
   end Walk;

   procedure Line (Item : in out Shape; From, To : Point; Pen_Width, Pen_Height : Integer) is
      Top : constant Integer := Integer'Min (From.V, To.V);
      Bottom : constant Integer := Integer'Max (From.V, To.V);
      --  Only the path rows whose pen reaches the window are kept.
      Kept_Top : constant Integer := Integer'Max (Top, Item.Window.Top - Pen_Height + 1);
      Kept_Bottom : constant Integer := Integer'Min (Bottom, Item.Window.Bottom - 1);
      Low_X, High_X : Column_Vectors.Vector;
      --  Along a line the columns move one way as the rows go down.
      Increasing : constant Boolean := (To.H >= From.H) = (To.V >= From.V);
   begin
      --  A spent shape takes no more work, not even this line's row buffers.
      if Item.Spent or else Pen_Width <= 0 or else Pen_Height <= 0 or else Kept_Top > Kept_Bottom then
         return;
      end if;
      --  The row buffers are charged before they are made, a unit a row.
      Charge (Item, Kept_Bottom - Kept_Top + 1);
      if Item.Spent then
         return;
      end if;
      Low_X.Set_Length (Ada.Containers.Count_Type (Kept_Bottom - Kept_Top + 1));
      High_X.Set_Length (Ada.Containers.Count_Type (Kept_Bottom - Kept_Top + 1));
      for Index in 0 .. Kept_Bottom - Kept_Top loop
         Low_X (Index) := Integer'Last;
         High_X (Index) := Integer'First;
      end loop;
      Walk (Item, From, To, Kept_Top, Kept_Bottom, Low_X, High_X);
      if Item.Spent then
         return;
      end if;
      --  Row Y is covered by the pen at every path row from Y - Pen_Height + 1 to Y, the extremes at the ends.
      Expect_Rows
        (Item, Integer'Max (Kept_Top, Item.Window.Top),
         Integer'Min (Kept_Bottom + Pen_Height, Item.Window.Bottom) - 1);
      for Y in Integer'Max (Kept_Top, Item.Window.Top) .. Integer'Min (Kept_Bottom + Pen_Height, Item.Window.Bottom) - 1
      loop
         exit when Item.Spent;
         Charge (Item, 1);
         declare
            First : constant Integer := Integer'Max (Kept_Top, Y - Pen_Height + 1) - Kept_Top;
            Last : constant Integer := Integer'Min (Kept_Bottom, Y) - Kept_Top;
            Left : constant Integer := (if Increasing then Low_X (First) else Low_X (Last));
            Right : constant Integer := (if Increasing then High_X (Last) else High_X (First));
         begin
            Add (Item, Y, Left, Right + Pen_Width);
         end;
      end loop;
   end Line;

   procedure From_Region (Item : in out Shape; Source : in out Regions.Region) is
      Box : constant Area := Regions.Bounds (Source);
      First, Last : Integer;
      Spans : Span_List;
      Units : Pixel_Count;
   begin
      if Row_Range (Item, Box, First, Last) then
         Expect_Rows (Item, First, Last);
         for Y in First .. Last loop
            exit when Item.Spent;
            Regions.Row_Spans (Source, Y, Spans, Units, Remaining (Item));
            Add_Work (Item, Units);
            for Index in Spans.First_Index .. Spans.Last_Index loop
               Add (Item, Y, Spans.Element (Index).Left, Spans.Element (Index).Right);
            end loop;
         end loop;
      end if;
   end From_Region;

   --  By doubling, row r of Rows becomes the intersection of rows r .. r + Reach - 1, Reach the largest power of
   --  two within Window, in log2 (Reach) passes, each row of each pass charged before it is made; any Window
   --  rows are then the intersection of two of those. Stops as soon as Item is spent, Rows then part done.
   procedure Intersect_Runs
     (Item : in out Shape;
      Rows : in out Row_Vectors.Vector;
      Window : Positive;
      Reach : out Positive) is
   begin
      Reach := 1;
      while Reach <= Window / 2 loop
         declare
            Next : Row_Vectors.Vector;
            Scratch : Span_List;
         begin
            for R in 0 .. Natural (Rows.Length) - Reach - 1 loop
               --  An intersection walks both its rows.
               Charge (Item, Natural (Rows (R).Length) + Natural (Rows (R + Reach).Length) + 1);
               if Item.Spent then
                  return;
               end if;
               Regions.Intersect (Rows (R), Rows (R + Reach), Scratch);
               Next.Append (Scratch);
            end loop;
            Rows.Move (Next);
         end;
         Reach := 2 * Reach;
      end loop;
   end Intersect_Runs;

   procedure Region_Frame (Item : in out Shape; Source : in out Regions.Region; Pen_Width, Pen_Height : Integer) is
      Box : constant Area := Regions.Bounds (Source);
      First, Last : Integer;
   begin
      if Pen_Width <= 0 or else Pen_Height <= 0 or else not Row_Range (Item, Box, First, Last) then
         return;
      end if;
      Expect_Rows (Item, First, Last);
      declare
         --  Every region row an output row's inset depends on.
         Low : constant Integer := Integer'Max (Box.Top, First - Pen_Height);
         High : constant Integer := Integer'Min (Box.Bottom - 1, Last + Pen_Height);
         Whole, Narrowed : Row_Vectors.Vector;
         Spans : Span_List;
         Units : Pixel_Count;
      begin
         for Y in Low .. High loop
            exit when Item.Spent;
            Regions.Row_Spans (Source, Y, Spans, Units, Remaining (Item));
            Add_Work (Item, Units);
            Whole.Append (Spans);
            declare
               Inset : Span_List;
            begin
               for Index in Spans.First_Index .. Spans.Last_Index loop
                  declare
                     S : constant Regions.Span := Spans.Element (Index);
                  begin
                     if S.Left + Pen_Width < S.Right - Pen_Width then
                        Inset.Append (Regions.Span'(S.Left + Pen_Width, S.Right - Pen_Width));
                     end if;
                  end;
               end loop;
               Narrowed.Append (Inset);
            end;
         end loop;
         --  A row's eroded part is the intersection of the 2 x Pen_Height + 1 narrowed rows around it.
         declare
            Reach : Positive;
         begin
            Intersect_Runs (Item, Narrowed, 2 * Pen_Height + 1, Reach);
            --  A part-eroded shape is never used.
            if Item.Spent then
               return;
            end if;
            for Y in First .. Last loop
               exit when Item.Spent;
               declare
                  Eroded : Span_List;
               begin
                  if Y - Pen_Height >= Box.Top and then Y + Pen_Height <= Box.Bottom - 1 then
                     Regions.Intersect
                       (Narrowed (Y - Pen_Height - Low), Narrowed (Y + Pen_Height - Reach + 1 - Low), Eroded);
                     Charge (Item, Natural (Eroded.Length) + 1);
                     if Item.Spent then
                        return;
                     end if;
                  end if;
                  --  The frame is the row less its eroded part.
                  declare
                     Kept : Span_List;
                  begin
                     Regions.Subtract (Whole (Y - Low), Eroded, Kept);
                     Charge (Item, Natural (Kept.Length) + 1);
                     for Index in Kept.First_Index .. Kept.Last_Index loop
                        Add (Item, Y, Kept.Element (Index).Left, Kept.Element (Index).Right);
                     end loop;
                  end;
               end;
            end loop;
         end;
      end;
   end Region_Frame;

   procedure Subtract (Item : in out Shape; Other : Shape) is
   begin
      --  Taking away an incomplete shape leaves an incomplete one.
      Add_Work (Item, Other.Units);
      Item.Spent := Item.Spent or else Other.Spent;
      if Item.Spent then
         return;
      end if;
      declare
         --  Scratch lists for every row, their buffers kept from row to row.
         Mine, Theirs, Kept : Span_List;
      begin
         for Index in 0 .. Natural (Item.Rows.Length) - 1 loop
            exit when Item.Spent;
            declare
               Y : constant Integer := Item.Top + Index;
            begin
               --  A row Other does not reach keeps all it has.
               if Y in First_Row (Other) .. Last_Row (Other) then
                  Mine.Clear;
                  Theirs.Clear;
                  Append_Row (Item, Y, Mine);
                  Append_Row (Other, Y, Theirs);
                  Regions.Subtract (Mine, Theirs, Kept);
                  Place (Item, Y, Kept);
               end if;
               Charge (Item, Slot_Of (Item, Y).Count + 1);
            end;
         end loop;
      end;
   end Subtract;
end Pictlib.Internal.Coverage;
