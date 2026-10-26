with Pictlib.Internal.Sessions.Accounting;
with Pictlib.Geometry;
with Pictlib.Internal.Coverage;
with Pictlib.Internal.Regions;
with Pictlib.Internal.Region_Reader;
with Pictlib.Internal.Transfer_Modes;

package body Pictlib.Internal.Shapes is
   package Accounting renames Pictlib.Internal.Sessions.Accounting;
   subtype Area is Regions.Area;
   subtype Point is Coverage.Point;

   function Read_Polygon (S : in out Sessions.Session; Points : out Coverage.Point_Vectors.Vector)
     return Results.Result
   is
      Count : Natural;
      Box : Geometry.Rect;
      Outcome : Results.Result := Sessions.Read_Polygon_Size (S, Count);
   begin
      Points.Clear;
      --  The points are kept, counted against the session's allocation total.
      if Results.Succeeded (Outcome) then
         Outcome := Accounting.Admit_Aggregate (S, Accounting.Point_Cost_Bytes * Byte_Count (Count));
      end if;
      if Results.Succeeded (Outcome) then
         Outcome := Sessions.Read_Bounds (S, Box);
      end if;
      for Index in 1 .. Count loop
         exit when not Results.Succeeded (Outcome);
         declare
            V, H : Integer;
         begin
            Outcome := Sessions.Read_Pair (S, V, H);
            --  Kept local; the origin applies when the polygon is drawn.
            Points.Append (Point'(H => H, V => V));
         end;
      end loop;
      return Outcome;
   end Read_Polygon;

   function Inset (Item : Area; Width, Height : Integer) return Area is
     ((Item.Top + Height, Item.Left + Width, Item.Bottom - Height, Item.Right - Width));

   --  A shape opcode is 16 times its kind (from 3), plus 8 for its "same" form, plus its verb. Verbs 5 .. 7 are
   --  reserved and never drawn.
   type Shape_Kind is (Rect_Shape, Round_Rect_Shape, Oval_Shape, Arc_Shape, Polygon_Shape, Region_Shape);
   subtype Rect_Like_Kind is Shape_Kind range Rect_Shape .. Arc_Shape;
   type Shape_Verb is (Framed, Painted, Erased, Inverted, Filled);

   function Has_Verb (Op : Opcode) return Boolean is (Natural (Op mod 8) <= Shape_Verb'Pos (Shape_Verb'Last));

   function Kind_Of (Op : Opcode) return Shape_Kind is (Shape_Kind'Val (Natural (Op / 16) - 3))
     with Pre => Op in Opcodes.First_Shape .. Opcodes.Last_Shape;
   function Verb_Of (Op : Opcode) return Shape_Verb is (Shape_Verb'Val (Natural (Op mod 8)))
     with Pre => Has_Verb (Op);
   function Is_Same (Op : Opcode) return Boolean is (Op mod 16 >= 8);

   --  How frame and paint (pen), erase (background pattern), invert and fill (fill pattern) change pixels.
   function Paint_For (P : Rendering.Painter; Verb : Shape_Verb) return Rendering.Paint is
     (case Verb is
         when Framed | Painted => (Rendering.Pattern_Paint, Rendering.Pen_Slot, P.Port.Pen_Mode),
         when Erased => (Rendering.Pattern_Paint, Rendering.Back_Slot, Transfer_Modes.Copy),
         when Inverted => (Rendering.Invert_Paint, Rendering.Pen_Slot, Transfer_Modes.Copy),
         when Filled => (Rendering.Pattern_Paint, Rendering.Fill_Slot, Transfer_Modes.Copy));

   --  The pixels a shape verb changes, for the rect, round rect, oval and arc kinds.
   procedure Rect_Like
     (P : Rendering.Painter;
      Kind : Rect_Like_Kind;
      Verb : Shape_Verb;
      Bounds : Area;
      Start_Angle, Arc_Angle : Integer;
      Shape : in out Coverage.Shape)
   is
      Frame : constant Boolean := Verb = Framed;
      Inner : Coverage.Shape;

      procedure Interior (Item : in out Coverage.Shape; Box : Area; Oval_Width, Oval_Height : Integer) is
      begin
         case Kind is
            when Rect_Shape => Coverage.Rectangle (Item, Box);
            when Round_Rect_Shape => Coverage.Round_Rect (Item, Box, Oval_Width, Oval_Height);
            when Oval_Shape | Arc_Shape => Coverage.Oval (Item, Box);
         end case;
      end Interior;
   begin
      if Frame and then (P.Port.Pen_Width <= 0 or else P.Port.Pen_Height <= 0) then
         return;
      end if;
      Interior (Shape, Bounds, P.Port.Oval_Width, P.Port.Oval_Height);
      if Frame then
         Coverage.Start (Inner, Coverage.Window_Of (Shape), Coverage.Remaining (Shape));
         Interior (Inner, Inset (Bounds, P.Port.Pen_Width, P.Port.Pen_Height),
                   P.Port.Oval_Width - 2 * P.Port.Pen_Width, P.Port.Oval_Height - 2 * P.Port.Pen_Height);
         Coverage.Subtract (Shape, Inner);
      end if;
      if Kind = Arc_Shape then
         Coverage.Wedge (Shape, Bounds, Start_Angle, Arc_Angle);
      end if;
   end Rect_Like;

   --  Each shape starts once its data is read and charged, so its allowance is what the budget has left.

   function Rect_Like_Coverage
     (P : in out Rendering.Painter;
      S : in out Sessions.Session;
      Kind : Rect_Like_Kind;
      Verb : Shape_Verb;
      Same : Boolean;
      Shape : in out Coverage.Shape) return Results.Result
   is
      Start_Angle, Arc_Angle : Integer := 0;
      Outcome : Results.Result := Results.Success;
   begin
      if not Same then
         Outcome := Sessions.Read_Bounds (S, P.Port.Last_Rect);
      end if;
      if Results.Succeeded (Outcome) and then Kind = Arc_Shape then
         Outcome := Sessions.Read_Pair (S, Start_Angle, Arc_Angle);
      end if;
      if Results.Succeeded (Outcome) then
         Coverage.Start (Shape, P.Window, Accounting.Shape_Work_Left (S));
         Rect_Like (P, Kind, Verb, Rendering.To_Picture (P, P.Port.Last_Rect), Start_Angle, Arc_Angle, Shape);
      end if;
      return Outcome;
   end Rect_Like_Coverage;

   function Polygon_Coverage
     (P : in out Rendering.Painter;
      S : in out Sessions.Session;
      Verb : Shape_Verb;
      Same : Boolean;
      Shape : in out Coverage.Shape) return Results.Result
   is
      Outcome : Results.Result := Results.Success;
      Points : Coverage.Point_Vectors.Vector;
   begin
      if not Same then
         Outcome := Read_Polygon (S, P.Port.Last_Polygon);
         if not Results.Succeeded (Outcome) then
            return Outcome;
         end if;
      end if;
      --  The polygon is copied for drawing, and a filled one keeps every edge while it is scanned: both count
      --  against the aggregate allocation quota. Walking the copy and the edges is shape work, charged as the
      --  shape is built.
      Outcome :=
        Accounting.Admit_Aggregate
          (S,
           (Accounting.Point_Cost_Bytes
            + (if Verb = Framed then 0 else Accounting.Polygon_Edge_Bytes))
           * Byte_Count (P.Port.Last_Polygon.Length));
      if not Results.Succeeded (Outcome) then
         return Outcome;
      end if;
      Coverage.Start (Shape, P.Window, Accounting.Shape_Work_Left (S));
      for Item of P.Port.Last_Polygon loop
         Points.Append (Point'(H => Item.H - P.Port.Origin_H, V => Item.V - P.Port.Origin_V));
      end loop;
      if Verb /= Framed then
         Coverage.Polygon (Shape, Points);
      elsif Natural (Points.Length) >= 2 then
         --  FramePoly draws the polygon's lines; it does not close the polygon.
         for Index in 1 .. Natural (Points.Length) - 1 loop
            exit when Coverage.Exhausted (Shape);
            Coverage.Line (Shape, Points (Index), Points (Index + 1), P.Port.Pen_Width, P.Port.Pen_Height);
         end loop;
      end if;
      return Results.Success;
   end Polygon_Coverage;

   function Region_Coverage
     (P : in out Rendering.Painter;
      S : in out Sessions.Session;
      Verb : Shape_Verb;
      Same : Boolean;
      Shape : in out Coverage.Shape) return Results.Result
   is
      Outcome : Results.Result := Results.Success;
   begin
      if not Same then
         Outcome := Region_Reader.Read (S, P.Port.Last_Region);
         if not Results.Succeeded (Outcome) then
            return Outcome;
         end if;
      end if;
      --  The region is copied and moved for drawing: work like drawing it, and storage by its size.
      Outcome := Accounting.Charge_Work (S, Regions.Size (P.Port.Last_Region));
      if Results.Succeeded (Outcome) then
         Outcome :=
           Accounting.Admit_Aggregate
             (S, Accounting.Region_Unit_Bytes * Byte_Count (Regions.Size (P.Port.Last_Region)));
      end if;
      if not Results.Succeeded (Outcome) then
         return Outcome;
      end if;
      declare
         Region : Regions.Region := P.Port.Last_Region;
      begin
         Coverage.Start (Shape, P.Window, Accounting.Shape_Work_Left (S));
         Regions.Translate (Region, -P.Port.Origin_H, -P.Port.Origin_V);
         if Verb = Framed then
            Coverage.Region_Frame (Shape, Region, P.Port.Pen_Width, P.Port.Pen_Height);
         else
            Coverage.From_Region (Shape, Region);
         end if;
      end;
      return Results.Success;
   end Region_Coverage;

   function Draw
     (P : in out Rendering.Painter;
      S : in out Sessions.Session;
      Event : Pictures.Opcode_Event) return Results.Result
   is
      Kind : constant Shape_Kind := Kind_Of (Event.Op);
      Verb : constant Shape_Verb := Verb_Of (Event.Op);
      Same : constant Boolean := Is_Same (Event.Op);
      Shape : Coverage.Shape;
      Outcome : constant Results.Result :=
        (case Kind is
            when Rect_Like_Kind => Rect_Like_Coverage (P, S, Kind, Verb, Same, Shape),
            when Polygon_Shape => Polygon_Coverage (P, S, Verb, Same, Shape),
            when Region_Shape => Region_Coverage (P, S, Verb, Same, Shape));
   begin
      return (if Results.Succeeded (Outcome) then Rendering.Fill (P, S, Shape, Paint_For (P, Verb)) else Outcome);
   end Draw;
end Pictlib.Internal.Shapes;
