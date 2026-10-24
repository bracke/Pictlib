with Interfaces;
with Pictlib.Errors;
with Pictlib.Internal.Bytes;
with Pictlib.Streams;

package body Pictlib.Internal.Regions is
   use type Interfaces.Unsigned_16;

   Smallest_Region : constant := 10;
   End_Mark : constant := 16#7FFF#;

   function Rectangle (Bounds : Area) return Region is ((Box => Bounds, others => <>));

   function Bounds (Item : Region) return Area is (Item.Box);

   function Is_Rectangular (Item : Region) return Boolean is (Item.Rectangular);

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

   function Read_Size (S : in out Sessions.Session; Size : out Interfaces.Unsigned_16) return Results.Result is
      Outcome : constant Results.Result := Sessions.Read_Word (S, Size);
   begin
      if not Results.Succeeded (Outcome) then
         return Outcome;
      elsif Size < Smallest_Region then
         return Sessions.Fail (S, Errors.Region_Invalid, Smallest_Region, Byte_Count (Size));
      elsif Byte_Count (Size) > S.Budget.Max_Region_Bytes then
         return Sessions.Over_Limit (S, Region_Byte_Limit, S.Budget.Max_Region_Bytes, Byte_Count (Size));
      end if;
      return Results.Success;
   end Read_Size;

   function Skip (S : in out Sessions.Session) return Results.Result is
      Size : Interfaces.Unsigned_16;
      Outcome : constant Results.Result := Read_Size (S, Size);
   begin
      if not Results.Succeeded (Outcome) then
         return Outcome;
      end if;
      return Sessions.Skip_Data (S, Byte_Count (Size) - 2);
   end Skip;

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

   function Read (S : in out Sessions.Session; Item : out Region) return Results.Result is
      Size : Interfaces.Unsigned_16;
      Rect : Geometry.Rect;
      Data : Streams.Byte_Array_Access;
      Outcome : Results.Result := Read_Size (S, Size);
   begin
      Item := (others => <>);
      if Results.Succeeded (Outcome) then
         Outcome := Sessions.Read_Bounds (S, Rect);
      end if;
      if not Results.Succeeded (Outcome) then
         return Outcome;
      end if;
      Item.Box := To_Area (Rect);
      if Size = Smallest_Region then
         return Results.Success;
      end if;
      Outcome := Sessions.Read_Payload (S, Byte_Count (Size) - Smallest_Region, Data);
      if not Results.Succeeded (Outcome) then
         return Outcome;
      end if;
      Item.Rectangular := False;
      if not Parse (Data.all, Item) then
         Sessions.Free (Data);
         Item := (others => <>);
         return Sessions.Fail (S, Errors.Region_Invalid, Actual => Byte_Count (Size));
      end if;
      Sessions.Free (Data);
      return Results.Success;
   end Read;

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

   procedure Row_Spans (Item : in out Region; Y : Integer; Spans : in out Span_Vectors.Vector; Work : out Natural) is
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
         Work := Work + Natural (Item.Active.Length) + 1;
         Item.Next_Line := Item.Next_Line + 1;
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
      Work := Work + Natural (Item.Active.Length);
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
end Pictlib.Internal.Regions;
