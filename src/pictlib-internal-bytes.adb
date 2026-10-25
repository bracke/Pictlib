package body Pictlib.Internal.Bytes is
   function Read_Byte
     (Object : in out Streams.Source'Class;
      Value : out Byte) return Results.Result
   is
      Buffer : Streams.Byte_Array (1 .. 1);
      Outcome : Results.Result;
   begin
      Value := 0;
      Outcome := Streams.Read_Exact (Object, Buffer);
      if Results.Succeeded (Outcome) then
         Value := Buffer (1);
      end if;
      return Outcome;
   end Read_Byte;

   function Read_U16_BE
     (Object : in out Streams.Source'Class;
      Value : out Interfaces.Unsigned_16) return Results.Result
   is
      Buffer : Streams.Byte_Array (1 .. 2);
      Outcome : Results.Result;
   begin
      Value := 0;
      Outcome := Streams.Read_Exact (Object, Buffer);
      if Results.Succeeded (Outcome) then
         Value := Interfaces.Shift_Left (Interfaces.Unsigned_16 (Buffer (1)), 8)
           or Interfaces.Unsigned_16 (Buffer (2));
      end if;
      return Outcome;
   end Read_U16_BE;

   function Read_U32_BE
     (Object : in out Streams.Source'Class;
      Value : out Interfaces.Unsigned_32) return Results.Result
   is
      Buffer : Streams.Byte_Array (1 .. 4);
      Outcome : Results.Result;
   begin
      Value := 0;
      Outcome := Streams.Read_Exact (Object, Buffer);
      if Results.Succeeded (Outcome) then
         for Item of Buffer loop
            Value := Interfaces.Shift_Left (Value, 8) or Interfaces.Unsigned_32 (Item);
         end loop;
      end if;
      return Outcome;
   end Read_U32_BE;

   function To_Coordinate (Value : Interfaces.Unsigned_16) return Coordinate is
   begin
      if Value >= 16#8000# then
         return Coordinate (Integer (Value) - 16#1_0000#);
      else
         return Coordinate (Value);
      end if;
   end To_Coordinate;

   function From_Coordinate (Value : Coordinate) return Interfaces.Unsigned_16 is
   begin
      if Value < 0 then
         return Interfaces.Unsigned_16 (Integer (Value) + 16#1_0000#);
      else
         return Interfaces.Unsigned_16 (Value);
      end if;
   end From_Coordinate;

   function Read_Coordinate
     (Object : in out Streams.Source'Class;
      Value : out Coordinate) return Results.Result
   is
      Raw : Interfaces.Unsigned_16;
      Outcome : constant Results.Result := Read_U16_BE (Object, Raw);
   begin
      Value := To_Coordinate (Raw);
      return Outcome;
   end Read_Coordinate;

   function Read_Fixed
     (Object : in out Streams.Source'Class;
      Value : out Geometry.Fixed) return Results.Result
   is
      Raw : Interfaces.Unsigned_32;
      Outcome : constant Results.Result := Read_U32_BE (Object, Raw);
   begin
      Value := Geometry.Fixed (To_Signed_32 (Raw));
      return Outcome;
   end Read_Fixed;

   function Read_Rect
     (Object : in out Streams.Source'Class;
      Value : out Geometry.Rect) return Results.Result
   is
      Outcome : Results.Result;
   begin
      Value := (others => 0);
      Outcome := Read_Coordinate (Object, Value.Top);
      if Results.Succeeded (Outcome) then
         Outcome := Read_Coordinate (Object, Value.Left);
      end if;
      if Results.Succeeded (Outcome) then
         Outcome := Read_Coordinate (Object, Value.Bottom);
      end if;
      if Results.Succeeded (Outcome) then
         Outcome := Read_Coordinate (Object, Value.Right);
      end if;
      if not Results.Succeeded (Outcome) then
         Value := (others => 0);
      end if;
      return Outcome;
   end Read_Rect;
end Pictlib.Internal.Bytes;
