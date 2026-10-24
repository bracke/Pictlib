with Pictlib.Internal.Checked_Arithmetic;
with Interfaces;
with Pictlib.Internal.Bytes;

package body Pictlib.Internal.Regions is
   use type Interfaces.Unsigned_16;

   End_Mark : constant := 16#7FFF#;

   function Rectangle (Bounds : Area) return Region is ((Box => Bounds, others => <>));

   function Bounds (Item : Region) return Area is (Item.Box);

   function Is_Rectangular (Item : Region) return Boolean is (Item.Rectangular);

   function Size (Item : Region) return Natural is (Natural (Item.Lines.Length) + Natural (Item.Points.Length) + 1);

   procedure Translate (Item : in out Region; DX, DY : Integer) is
   begin
      Item.Box := (Item.Box.Top + DY, Item.Box.Left + DX, Item.Box.Bottom + DY, Item.Box.Right + DX);
      for Line of Item.Lines loop
         Line.Y := Line.Y + DY;
      end loop;
      for Point of Item.Points loop
         Point := Point + DX;
      end loop;
      Item.Active.Clear;
      Item.Next_Line := 1;
      Item.Cursor_Y := Integer'First;
   end Translate;

   --  Check the scanline encoding and keep it: y strictly increasing within the box, inversion columns strictly
   --  increasing within the box and even in number on every line, and the terminators exactly at the end.
   function Parse (Data : Streams.Byte_Array; Item : in out Region) return Boolean is
      Words : constant Natural := Data'Length / 2;
      Index : Natural := 0;

      function Word (At_Index : Natural) return Integer is
        (Integer (Bytes.To_Coordinate
           (Interfaces.Shift_Left (Interfaces.Unsigned_16 (Data (Data'First + 2 * At_Index)), 8)
            or Interfaces.Unsigned_16 (Data (Data'First + 2 * At_Index + 1)))));

      Previous_Y : Integer := Integer'First;
   begin
      if Data'Length mod 2 /= 0 then
         return False;
      end if;
      loop
         if Index >= Words then
            return False;
         end if;
         declare
            Y : constant Integer := Word (Index);
            Line : Scanline;
            Previous_X : Integer := Integer'First;
         begin
            Index := Index + 1;
            exit when Y = End_Mark;
            if Y <= Previous_Y or else Y < Item.Box.Top or else Y > Item.Box.Bottom then
               return False;
            end if;
            Previous_Y := Y;
            Line := (Y => Y, First => Natural (Item.Points.Length) + 1, Last => Natural (Item.Points.Length));
            loop
               if Index >= Words then
                  return False;
               end if;
               declare
                  X : constant Integer := Word (Index);
               begin
                  Index := Index + 1;
                  exit when X = End_Mark;
                  if X <= Previous_X or else X < Item.Box.Left or else X > Item.Box.Right then
                     return False;
                  end if;
                  Previous_X := X;
                  Item.Points.Append (X);
                  Line.Last := Line.Last + 1;
               end;
            end loop;
            if (Line.Last - Line.First + 1) mod 2 /= 0 then
               return False;
            end if;
            Item.Lines.Append (Line);
         end;
      end loop;
      return Index = Words;
   end Parse;

   function From_Scanlines (Box : Area; Data : Streams.Byte_Array; Item : out Region) return Boolean is
   begin
      Item := (Box => Box, Rectangular => False, others => <>);
      if not Parse (Data, Item) then
         Item := (others => <>);
         return False;
      end if;
      return True;
   end From_Scanlines;

   --  Active := Active xor Points (Line), both sorted.
   procedure Invert (Item : in out Region; Line : Scanline) is
      Merged : Integer_Vectors.Vector;
      Left : Positive := 1;
      Right : Positive := Line.First;
   begin
      while Left <= Natural (Item.Active.Length) or else Right <= Line.Last loop
         if Right > Line.Last then
            Merged.Append (Item.Active (Left));
            Left := Left + 1;
         elsif Left > Natural (Item.Active.Length) then
            Merged.Append (Item.Points (Right));
            Right := Right + 1;
         elsif Item.Active (Left) < Item.Points (Right) then
            Merged.Append (Item.Active (Left));
            Left := Left + 1;
         elsif Item.Points (Right) < Item.Active (Left) then
            Merged.Append (Item.Points (Right));
            Right := Right + 1;
         else
            Left := Left + 1;
            Right := Right + 1;
         end if;
      end loop;
      Item.Active.Move (Merged);
   end Invert;

   procedure Row_Spans
     (Item : in out Region;
      Y : Integer;
      Spans : in out Span_Vectors.Vector;
      Work : out Pixel_Count;
      Allowance : Pixel_Count := Pixel_Count'Last)
   is
      Box : constant Area := Item.Box;
   begin
      Spans.Clear;
      Work := 1;
      if Y < Box.Top or else Y >= Box.Bottom or else Is_Empty (Box) then
         return;
      elsif Item.Rectangular then
         Spans.Append (Span'(Box.Left, Box.Right));
         return;
      end if;

      if Y < Item.Cursor_Y then
         Item.Active.Clear;
         Item.Next_Line := 1;
      end if;
      Item.Cursor_Y := Y;
      while Item.Next_Line <= Natural (Item.Lines.Length) and then Item.Lines (Item.Next_Line).Y <= Y loop
         Invert (Item, Item.Lines (Item.Next_Line));
         Work := Checked_Arithmetic.Saturating_Add (Work, Pixel_Count (Item.Active.Length) + 1);
         Item.Next_Line := Item.Next_Line + 1;
         --  The walk resumes from here at the next call; this one is over budget.
         if Work > Allowance then
            Spans.Clear;
            return;
         end if;
      end loop;

      declare
         Index : Positive := 1;
      begin
         while Index + 1 <= Natural (Item.Active.Length) loop
            declare
               Left : constant Integer := Integer'Max (Item.Active (Index), Box.Left);
               Right : constant Integer := Integer'Min (Item.Active (Index + 1), Box.Right);
            begin
               if Left < Right then
                  Spans.Append (Span'(Left, Right));
               end if;
            end;
            Index := Index + 2;
         end loop;
      end;
      Work := Checked_Arithmetic.Saturating_Add (Work, Pixel_Count (Item.Active.Length));
   end Row_Spans;

   procedure Intersect (Left, Right : Span_Vectors.Vector; Result : in out Span_Vectors.Vector) is
      L : Positive := 1;
      R : Positive := 1;
   begin
      Result.Clear;
      while L <= Natural (Left.Length) and then R <= Natural (Right.Length) loop
         declare
            A : constant Span := Left (L);
            B : constant Span := Right (R);
            First : constant Integer := Integer'Max (A.Left, B.Left);
            Last : constant Integer := Integer'Min (A.Right, B.Right);
         begin
            if First < Last then
               Result.Append (Span'(First, Last));
            end if;
            if A.Right < B.Right then
               L := L + 1;
            else
               R := R + 1;
            end if;
         end;
      end loop;
   end Intersect;

   procedure Subtract (Left, Right : Span_Vectors.Vector; Result : in out Span_Vectors.Vector) is
      R : Positive := 1;
   begin
      Result.Clear;
      for A of Left loop
         declare
            From : Integer := A.Left;
         begin
            --  Cuts wholly before this span are behind every later span too.
            while R <= Natural (Right.Length) and then Right (R).Right <= From loop
               R := R + 1;
            end loop;
            --  Cuts within the span; one that reaches past it is kept for the next span.
            declare
               Cut : Positive := R;
            begin
               while Cut <= Natural (Right.Length) and then Right (Cut).Left < A.Right loop
                  if Right (Cut).Left > From then
                     Result.Append (Span'(From, Right (Cut).Left));
                  end if;
                  From := Integer'Max (From, Right (Cut).Right);
                  exit when Right (Cut).Right >= A.Right;
                  Cut := Cut + 1;
               end loop;
            end;
            if From < A.Right then
               Result.Append (Span'(From, A.Right));
            end if;
         end;
      end loop;
   end Subtract;
end Pictlib.Internal.Regions;
