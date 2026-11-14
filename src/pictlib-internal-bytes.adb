with Pictlib.Internal.Replies;

package body Pictlib.Internal.Bytes is
   procedure Fill
     (Object : in out Streams.Source'Class;
      Buffer : out Streams.Byte_Array;
      Outcome : in out Results.Result)
   is
      Completed : Natural := 0;
   begin
      while Completed < Buffer'Length loop
         declare
            Step : constant Streams.Source_Result := Object.Read (Buffer (Buffer'First + Completed .. Buffer'Last));
         begin
            if not Replies.Sound_Step (Step, Byte_Count (Buffer'Length - Completed)) then
               Outcome := Replies.Step_Failure (Object, Step, Byte_Count (Buffer'Length), Byte_Count (Completed));
               return;
            end if;
            Completed := Completed + Natural (Step.Count);
         end;
      end loop;
   end Fill;

   procedure Read_Byte
     (Object : in out Streams.Source'Class;
      Value : out Byte;
      Outcome : in out Results.Result)
   is
      Buffer : Streams.Byte_Array (1 .. 1);
   begin
      Value := 0;
      Fill (Object, Buffer, Outcome);
      if Results.Succeeded (Outcome) then
         Value := Buffer (1);
      end if;
   end Read_Byte;

   procedure Read_U16_BE
     (Object : in out Streams.Source'Class;
      Value : out Interfaces.Unsigned_16;
      Outcome : in out Results.Result)
   is
      Buffer : Streams.Byte_Array (1 .. 2);
   begin
      Value := 0;
      Fill (Object, Buffer, Outcome);
      if Results.Succeeded (Outcome) then
         Value := Word_At (Buffer, Buffer'First);
      end if;
   end Read_U16_BE;

   procedure Read_U32_BE
     (Object : in out Streams.Source'Class;
      Value : out Interfaces.Unsigned_32;
      Outcome : in out Results.Result)
   is
      Buffer : Streams.Byte_Array (1 .. 4);
   begin
      Value := 0;
      Fill (Object, Buffer, Outcome);
      if Results.Succeeded (Outcome) then
         Value := Long_At (Buffer, Buffer'First);
      end if;
   end Read_U32_BE;

   procedure Read_Rect
     (Object : in out Streams.Source'Class;
      Value : out Geometry.Rect;
      Outcome : in out Results.Result)
   is
      --  Each coordinate its own read, as before, so a cut rectangle fails where the coordinate it cuts begins.
      procedure Coordinate_Of (Into : out Coordinate) is
         Raw : Interfaces.Unsigned_16;
      begin
         Read_U16_BE (Object, Raw, Outcome);
         Into := To_Coordinate (Raw);
      end Coordinate_Of;
   begin
      Value := (others => 0);
      Coordinate_Of (Value.Top);
      if Results.Succeeded (Outcome) then
         Coordinate_Of (Value.Left);
      end if;
      if Results.Succeeded (Outcome) then
         Coordinate_Of (Value.Bottom);
      end if;
      if Results.Succeeded (Outcome) then
         Coordinate_Of (Value.Right);
      end if;
      if not Results.Succeeded (Outcome) then
         Value := (others => 0);
      end if;
   end Read_Rect;

   function Read_Byte
     (Object : in out Streams.Source'Class;
      Value : out Byte) return Results.Result
   is
      Outcome : Results.Result := Results.Success;
   begin
      Read_Byte (Object, Value, Outcome);
      return Outcome;
   end Read_Byte;

   function Read_U16_BE
     (Object : in out Streams.Source'Class;
      Value : out Interfaces.Unsigned_16) return Results.Result
   is
      Outcome : Results.Result := Results.Success;
   begin
      Read_U16_BE (Object, Value, Outcome);
      return Outcome;
   end Read_U16_BE;

   function Read_U32_BE
     (Object : in out Streams.Source'Class;
      Value : out Interfaces.Unsigned_32) return Results.Result
   is
      Outcome : Results.Result := Results.Success;
   begin
      Read_U32_BE (Object, Value, Outcome);
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
      Outcome : Results.Result := Results.Success;
   begin
      Read_Rect (Object, Value, Outcome);
      return Outcome;
   end Read_Rect;
end Pictlib.Internal.Bytes;
