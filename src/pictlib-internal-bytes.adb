with Pictlib.Errors;

package body Pictlib.Internal.Bytes is
   use type Interfaces.Unsigned_16;
   use type Interfaces.Unsigned_32;

   function With_Context (Item : Results.Result; Context : Opcode_Context) return Results.Result is
      Revised : Errors.Error;
   begin
      if Results.Succeeded (Item) or else not Context.Present then
         return Item;
      end if;
      Revised := Item.First_Error;
      Revised.Context.Op := Context.Op;
      Revised.Context.Has_Opcode := True;
      return Results.Failure (Revised);
   end With_Context;

   function Read_Byte
     (Object : in out Streams.Source'Class;
      Value : out Byte;
      Context : Opcode_Context := No_Opcode) return Results.Result
   is
      Buffer : Streams.Byte_Array (1 .. 1);
      Outcome : Results.Result;
   begin
      Value := 0;
      Outcome := Streams.Read_Exact (Object, Buffer);
      if Results.Succeeded (Outcome) then
         Value := Buffer (1);
      end if;
      return With_Context (Outcome, Context);
   end Read_Byte;

   function Read_U16_BE
     (Object : in out Streams.Source'Class;
      Value : out Interfaces.Unsigned_16;
      Context : Opcode_Context := No_Opcode) return Results.Result
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
      return With_Context (Outcome, Context);
   end Read_U16_BE;

   function Read_U32_BE
     (Object : in out Streams.Source'Class;
      Value : out Interfaces.Unsigned_32;
      Context : Opcode_Context := No_Opcode) return Results.Result
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
      return With_Context (Outcome, Context);
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
      Value : out Coordinate;
      Context : Opcode_Context := No_Opcode) return Results.Result
   is
      Raw : Interfaces.Unsigned_16;
      Outcome : constant Results.Result := Read_U16_BE (Object, Raw, Context);
   begin
      Value := To_Coordinate (Raw);
      return Outcome;
   end Read_Coordinate;

   function Write_Byte
     (Object : in out Streams.Destination'Class;
      Value : Byte;
      Context : Opcode_Context := No_Opcode) return Results.Result
   is
      Buffer : constant Streams.Byte_Array := [1 => Value];
   begin
      return With_Context (Streams.Write_All (Object, Buffer), Context);
   end Write_Byte;

   function Write_U16_BE
     (Object : in out Streams.Destination'Class;
      Value : Interfaces.Unsigned_16;
      Context : Opcode_Context := No_Opcode) return Results.Result
   is
      Buffer : constant Streams.Byte_Array :=
        [Byte (Interfaces.Shift_Right (Value, 8)), Byte (Value and 16#FF#)];
   begin
      return With_Context (Streams.Write_All (Object, Buffer), Context);
   end Write_U16_BE;

   function Write_U32_BE
     (Object : in out Streams.Destination'Class;
      Value : Interfaces.Unsigned_32;
      Context : Opcode_Context := No_Opcode) return Results.Result
   is
      Buffer : constant Streams.Byte_Array :=
        [Byte (Interfaces.Shift_Right (Value, 24)),
         Byte (Interfaces.Shift_Right (Value, 16) and 16#FF#),
         Byte (Interfaces.Shift_Right (Value, 8) and 16#FF#),
         Byte (Value and 16#FF#)];
   begin
      return With_Context (Streams.Write_All (Object, Buffer), Context);
   end Write_U32_BE;

   function Write_Coordinate
     (Object : in out Streams.Destination'Class;
      Value : Coordinate;
      Context : Opcode_Context := No_Opcode) return Results.Result
   is
   begin
      return Write_U16_BE (Object, From_Coordinate (Value), Context);
   end Write_Coordinate;
end Pictlib.Internal.Bytes;
