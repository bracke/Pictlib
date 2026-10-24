package body Pictlib.Internal.Coverage is
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

   function Floor_Divide (Left, Right : Long_Long_Integer) return Long_Long_Integer is
     (if Left >= 0 then Left / Right else -((-Left + Right - 1) / Right))
     with Pre => Right > 0;

   function Ceiling_Divide (Left, Right : Long_Long_Integer) return Long_Long_Integer is
     (-Floor_Divide (-Left, Right))
     with Pre => Right > 0;

   function Square_Root (Value : Long_Long_Integer) return Long_Long_Integer is
      Guess : Long_Long_Integer;
      Next : Long_Long_Integer;
   begin
      if Value < 2 then
         return Value;
      end if;
      Guess := Value;
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
   end Start;

   function Window_Of (Item : Shape) return Area is (Item.Window);

   function First_Row (Item : Shape) return Integer is (Item.Top);

   function Last_Row (Item : Shape) return Integer is (Item.Top + Natural (Item.Rows.Length) - 1);

   function Row (Item : Shape; Y : Integer) return Span_List is
     (if not Item.Spent and then Y in First_Row (Item) .. Last_Row (Item) then Item.Rows (Y - Item.Top)
      else Regions.Span_Vectors.Empty_Vector);

   function Work (Item : Shape) return Pixel_Count is (Item.Units);

   function Exhausted (Item : Shape) return Boolean is (Item.Spent);

   function Remaining (Item : Shape) return Pixel_Count is
     (if Item.Units >= Item.Allowance then 0 else Item.Allowance - Item.Units);

   procedure Add_Work (Item : in out Shape; Units : Pixel_Count) is
   begin
      Item.Units := (if Pixel_Count'Last - Item.Units < Units then Pixel_Count'Last else Item.Units + Units);
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
      Empty : Span_List;
   begin
      if Item.Rows.Is_Empty then
         Item.Top := Y;
         Item.Rows.Append (Empty);
         Charge (Item, 1);
      elsif Y > Last_Row (Item) then
         Charge (Item, Y - Last_Row (Item));
         Item.Rows.Append (Empty, Ada.Containers.Count_Type (Y - Last_Row (Item)));
      elsif Y < Item.Top then
         Charge (Item, Item.Top - Y + Natural (Item.Rows.Length));
         Item.Rows.Prepend (Empty, Ada.Containers.Count_Type (Item.Top - Y));
         Item.Top := Y;
      end if;
   end Hold;

   --  Add pixels Left .. Right - 1 of row Y, merging with what the row holds.
   procedure Add (Item : in out Shape; Y, Left, Right : Integer) is
      First : constant Integer := Integer'Max (Left, Item.Window.Left);
      Last : constant Integer := Integer'Min (Right, Item.Window.Right);
   begin
      if Y not in Item.Window.Top .. Item.Window.Bottom - 1 or else First >= Last then
         return;
      end if;
      Hold (Item, Y);
      --  Spans mostly arrive left to right: append, or widen the last span, in place.
      declare
         Row : Span_List renames Item.Rows.Reference (Y - Item.Top).Element.all;
      begin
         Charge (Item, 1);
         if Row.Is_Empty or else Row.Last_Element.Right < First then
            Row.Append (Regions.Span'(First, Last));
            return;
         elsif Row.Last_Element.Left <= First then
            Row.Replace_Element
              (Row.Last_Index, Regions.Span'(Row.Last_Element.Left, Integer'Max (Row.Last_Element.Right, Last)));
            return;
         end if;
      end;
      declare
         Old : constant Span_List := Item.Rows (Y - Item.Top);
         Merged : Span_List;
         Pending : Regions.Span := (First, Last);
         Placed : Boolean := False;
      begin
         for S of Old loop
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
         end loop;
         if not Placed then
            Merged.Append (Pending);
         end if;
         Item.Rows.Replace_Element (Y - Item.Top, Merged);
         Charge (Item, Natural (Merged.Length));
      end;
   end Add;

   function Row_Range (Item : Shape; Bounds : Area; First, Last : out Integer) return Boolean is
   begin
      First := Integer'Max (Bounds.Top, Item.Window.Top);
      Last := Integer'Min (Bounds.Bottom, Item.Window.Bottom) - 1;
      return First <= Last and then not Regions.Is_Empty (Bounds);
   end Row_Range;

   procedure Rectangle (Item : in out Shape; Bounds : Area) is
      First, Last : Integer;
   begin
      if Row_Range (Item, Bounds, First, Last) then
         for Y in First .. Last loop
            exit when Item.Spent;
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
         Limit : constant Long_Long_Integer :=
           Long_Long_Integer (Wide (Width) ** 2 * (Wide (Height) ** 2 - Wide (Dy) ** 2) / Wide (Height) ** 2);
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
         for Y in First .. Last loop
            exit when Item.Spent;
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
      declare
         Corner : constant Area := (0, 0, Height, Width);
      begin
         for Y in First .. Last loop
            exit when Item.Spent;
            declare
               Oval_Y : constant Integer :=
                 (if Y < Bounds.Top + Height / 2 then Y - Bounds.Top
                  elsif Y >= Bounds.Bottom - (Height - Height / 2) then Y - (Bounds.Bottom - Height)
                  else -1);
            begin
               if Oval_Y < 0 then
                  Add (Item, Y, Bounds.Left, Bounds.Right);
               elsif Oval_Row (Corner, Oval_Y, Left, Right) then
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
               Old : constant Span_List := Item.Rows (Index);
               Kept : Span_List;
            begin
               for S of Old loop
                  declare
                     Run_Start : Integer := S.Left;
                  begin
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
                     Charge (Item, S.Right - S.Left);
                  end;
               end loop;
               Item.Rows.Replace_Element (Index, Kept);
            end;
         end loop;
      end;
   end Wedge;

   procedure Polygon (Item : in out Shape; Points : Point_Vectors.Vector) is
      --  An edge crosses the centers of rows First .. Last: 2y + 1 in [Low, High) of its doubled ends.
      type Edge is record
         X0, Y0, X1, Y1 : Long_Long_Integer := 0;
         First, Last : Long_Long_Integer := 0;
      end record;

      function Starts_Before (Left, Right : Edge) return Boolean is (Left.First < Right.First);

      package Edge_Vectors is new Ada.Containers.Vectors (Positive, Edge);
      package Edge_Sorting is new Edge_Vectors.Generic_Sorting (Starts_Before);
      package Boundary_Vectors is new Ada.Containers.Vectors (Positive, Long_Long_Integer);
      package Boundary_Sorting is new Boundary_Vectors.Generic_Sorting;

      Count : constant Natural := Natural (Points.Length);
      Edges, Active : Edge_Vectors.Vector;
      Next_Edge : Positive := 1;
   begin
      if Count < 3 then
         return;
      end if;
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
      Charge (Item, Count);
      Edge_Sorting.Sort (Edges);
      if Edges.Is_Empty then
         return;
      end if;

      --  From the first row an edge crosses, not the window's top.
      for Y in Integer (Long_Long_Integer'Max (Long_Long_Integer (Item.Window.Top), Edges.First_Element.First))
        .. Item.Window.Bottom - 1
      loop
         exit when Item.Spent;
         declare
            Row : constant Long_Long_Integer := Long_Long_Integer (Y);
            Center : constant Long_Long_Integer := 2 * Row + 1;
            Boundaries : Boundary_Vectors.Vector;
            Kept : Edge_Vectors.Vector;
         begin
            while Next_Edge <= Natural (Edges.Length) and then Edges (Next_Edge).First <= Row loop
               Active.Append (Edges (Next_Edge));
               Next_Edge := Next_Edge + 1;
            end loop;
            exit when Active.Is_Empty and then Next_Edge > Natural (Edges.Length);
            for E of Active loop
               if E.Last >= Row then
                  Kept.Append (E);
                  declare
                     Den : Long_Long_Integer := E.Y1 - E.Y0;
                     Num : Long_Long_Integer := E.X0 * Den + (Center - E.Y0) * (E.X1 - E.X0);
                  begin
                     if Den < 0 then
                        Den := -Den;
                        Num := -Num;
                     end if;
                     --  The first pixel whose center is at or right of the crossing.
                     Boundaries.Append (Ceiling_Divide (Num - Den, 2 * Den));
                  end;
               end if;
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

   procedure Line (Item : in out Shape; From, To : Point; Pen_Width, Pen_Height : Integer) is
      package Integer_Vectors is new Ada.Containers.Vectors (Natural, Integer);
      Top : constant Integer := Integer'Min (From.V, To.V);
      Bottom : constant Integer := Integer'Max (From.V, To.V);
      --  Only the path rows whose pen reaches the window are kept.
      Kept_Top : constant Integer := Integer'Max (Top, Item.Window.Top - Pen_Height + 1);
      Kept_Bottom : constant Integer := Integer'Min (Bottom, Item.Window.Bottom - 1);
      Low_X, High_X : Integer_Vectors.Vector;
      --  Along a line the columns move one way as the rows go down.
      Increasing : constant Boolean := (To.H >= From.H) = (To.V >= From.V);
   begin
      if Pen_Width <= 0 or else Pen_Height <= 0 or else Kept_Top > Kept_Bottom then
         return;
      end if;
      Low_X.Set_Length (Ada.Containers.Count_Type (Kept_Bottom - Kept_Top + 1));
      High_X.Set_Length (Ada.Containers.Count_Type (Kept_Bottom - Kept_Top + 1));
      for Index in 0 .. Kept_Bottom - Kept_Top loop
         Low_X (Index) := Integer'Last;
         High_X (Index) := Integer'First;
      end loop;
      declare
         X : Integer := From.H;
         Y : Integer := From.V;
         Dx : constant Integer := abs (To.H - From.H);
         Dy : constant Integer := -abs (To.V - From.V);
         Step_X : constant Integer := (if From.H < To.H then 1 else -1);
         Step_Y : constant Integer := (if From.V < To.V then 1 else -1);
         Error : Integer := Dx + Dy;
      begin
         loop
            if Y in Kept_Top .. Kept_Bottom then
               Low_X (Y - Kept_Top) := Integer'Min (Low_X (Y - Kept_Top), X);
               High_X (Y - Kept_Top) := Integer'Max (High_X (Y - Kept_Top), X);
            end if;
            Charge (Item, 1);
            exit when Item.Spent or else (X = To.H and then Y = To.V);
            if 2 * Error >= Dy then
               Error := Error + Dy;
               X := X + Step_X;
            end if;
            if 2 * Error <= Dx then
               Error := Error + Dx;
               Y := Y + Step_Y;
            end if;
         end loop;
      end;
      if Item.Spent then
         return;
      end if;
      --  Row Y is covered by the pen at every path row from Y - Pen_Height + 1 to Y, the extremes at the ends.
      for Y in Integer'Max (Kept_Top, Item.Window.Top) .. Integer'Min (Kept_Bottom + Pen_Height, Item.Window.Bottom) - 1
      loop
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
      Units : Natural;
   begin
      if Row_Range (Item, Box, First, Last) then
         for Y in First .. Last loop
            exit when Item.Spent;
            Regions.Row_Spans (Source, Y, Spans, Units);
            Charge (Item, Units);
            for S of Spans loop
               Add (Item, Y, S.Left, S.Right);
            end loop;
         end loop;
      end if;
   end From_Region;

   procedure Region_Frame (Item : in out Shape; Source : in out Regions.Region; Pen_Width, Pen_Height : Integer) is
      Box : constant Area := Regions.Bounds (Source);
      First, Last : Integer;
   begin
      if Pen_Width <= 0 or else Pen_Height <= 0 or else not Row_Range (Item, Box, First, Last) then
         return;
      end if;
      declare
         --  Every region row an output row's inset depends on.
         Low : constant Integer := Integer'Max (Box.Top, First - Pen_Height);
         High : constant Integer := Integer'Min (Box.Bottom - 1, Last + Pen_Height);
         Whole, Narrowed : Row_Vectors.Vector;
         Spans : Span_List;
         Units : Natural;
      begin
         for Y in Low .. High loop
            exit when Item.Spent;
            Regions.Row_Spans (Source, Y, Spans, Units);
            Charge (Item, Units);
            Whole.Append (Spans);
            declare
               Inset : Span_List;
            begin
               for S of Spans loop
                  if S.Left + Pen_Width < S.Right - Pen_Width then
                     Inset.Append (Regions.Span'(S.Left + Pen_Width, S.Right - Pen_Width));
                  end if;
               end loop;
               Narrowed.Append (Inset);
            end;
         end loop;
         for Y in First .. Last loop
            exit when Item.Spent;
            declare
               Eroded : Span_List;
               Scratch : Span_List;
            begin
               if Y - Pen_Height >= Box.Top and then Y + Pen_Height <= Box.Bottom - 1 then
                  Eroded := Narrowed (Y - Pen_Height - Low);
                  for R in Y - Pen_Height + 1 .. Y + Pen_Height loop
                     Regions.Intersect (Eroded, Narrowed (R - Low), Scratch);
                     Eroded := Scratch;
                     Charge (Item, Natural (Eroded.Length) + 1);
                     --  A part-eroded row is never used.
                     if Item.Spent then
                        return;
                     end if;
                  end loop;
               end if;
               --  The frame is the row less its eroded part.
               declare
                  Kept : Span_List := Whole (Y - Low);
               begin
                  for Cut of Eroded loop
                     declare
                        Next : Span_List;
                     begin
                        for S of Kept loop
                           if S.Right <= Cut.Left or else Cut.Right <= S.Left then
                              Next.Append (S);
                           else
                              if S.Left < Cut.Left then
                                 Next.Append (Regions.Span'(S.Left, Cut.Left));
                              end if;
                              if Cut.Right < S.Right then
                                 Next.Append (Regions.Span'(Cut.Right, S.Right));
                              end if;
                           end if;
                        end loop;
                        Kept := Next;
                     end;
                  end loop;
                  for S of Kept loop
                     Add (Item, Y, S.Left, S.Right);
                  end loop;
               end;
            end;
         end loop;
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
      for Index in 0 .. Natural (Item.Rows.Length) - 1 loop
         exit when Item.Spent;
         declare
            Kept : Span_List := Item.Rows (Index);
         begin
            for Cut of Row (Other, Item.Top + Index) loop
               declare
                  Next : Span_List;
               begin
                  for S of Kept loop
                     if S.Right <= Cut.Left or else Cut.Right <= S.Left then
                        Next.Append (S);
                     else
                        if S.Left < Cut.Left then
                           Next.Append (Regions.Span'(S.Left, Cut.Left));
                        end if;
                        if Cut.Right < S.Right then
                           Next.Append (Regions.Span'(Cut.Right, S.Right));
                        end if;
                     end if;
                  end loop;
                  Kept := Next;
               end;
            end loop;
            Item.Rows.Replace_Element (Index, Kept);
            Charge (Item, Natural (Kept.Length) + 1);
         end;
      end loop;
   end Subtract;
end Pictlib.Internal.Coverage;
