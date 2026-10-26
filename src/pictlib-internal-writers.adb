with Pictlib.Errors;
with Pictlib.Internal.Bytes;
with Pictlib.Internal.Failures;

package body Pictlib.Internal.Writers is
   use type Interfaces.Unsigned_32;

   procedure Start (Object : out Writer; Output : access Streams.Destination'Class; Max_Bytes : Byte_Count) is
   begin
      Object.Output := (if Output = null then null else Output.all'Unchecked_Access);
      Object.Total := 0;
      Object.Origin := 0;
      Object.Max_Bytes := Max_Bytes;
      Object.Base := (if Output = null then 0 else Output.Offset);
      Object.Failure := Results.Success;
      Object.Watched := null;
      Object.Watched_At := 0;
   end Start;

   procedure Watch (Object : in out Writer; Counter : not null access constant Generation) is
   begin
      Object.Watched := Counter.all'Unchecked_Access;
      Object.Watched_At := Counter.all;
   end Watch;

   function Count (Object : Writer) return Byte_Count is (Object.Total);

   procedure Start_Picture (Object : in out Writer) is
   begin
      Object.Origin := Object.Total;
   end Start_Picture;

   function Picture_Count (Object : Writer) return Byte_Count is (Object.Total - Object.Origin);

   function Put (Object : in out Writer; Data : Streams.Byte_Array) return Results.Result is
   begin
      if not Results.Succeeded (Object.Failure) then
         return Object.Failure;
      elsif Object.Watched /= null and then Object.Watched.all /= Object.Watched_At then
         Object.Failure := Results.Failure (Errors.Invalid_State);
         return Object.Failure;
      elsif Byte_Count (Data'Length) > Object.Max_Bytes - Object.Total then
         Object.Failure :=
           Failures.Over_Limit
             (Output_Byte_Limit, Object.Max_Bytes, Object.Total + Data'Length,
              Destination => Destination_Offset (Object.Total));
         return Object.Failure;
      elsif Object.Output /= null and then Data'Length > 0 then
         Object.Failure := Streams.Write_All (Object.Output.all, Data);
      end if;
      if Results.Succeeded (Object.Failure) then
         Object.Total := Object.Total + Data'Length;
      else
         --  Count what the destination took of Data before it failed, as far as its offset says.
         declare
            Moved : constant Destination_Offset := Object.Output.Offset;
            Taken : constant Byte_Count :=
              (if Moved <= Object.Base then 0 else Byte_Count (Moved - Object.Base));
         begin
            Object.Total := Byte_Count'Min (Object.Total + Data'Length, Byte_Count'Max (Object.Total, Taken));
         end;
      end if;
      return Object.Failure;
   end Put;

   function Put_Byte (Object : in out Writer; Value : Natural) return Results.Result is
     (Put (Object, [1 => Byte (Value)]));

   function Put_Word (Object : in out Writer; Value : Integer) return Results.Result is
      Raw : constant Natural := (if Value < 0 then Value + 16#1_0000# else Value);
   begin
      return Put (Object, [Byte (Raw / 256), Byte (Raw mod 256)]);
   end Put_Word;

   function Put_Long (Object : in out Writer; Value : Interfaces.Unsigned_32) return Results.Result is
     (Put (Object,
           [Byte (Interfaces.Shift_Right (Value, 24)), Byte (Interfaces.Shift_Right (Value, 16) and 16#FF#),
            Byte (Interfaces.Shift_Right (Value, 8) and 16#FF#), Byte (Value and 16#FF#)]));

   function Put_Rect (Object : in out Writer; Value : Geometry.Rect) return Results.Result is
      type Sides is array (1 .. 4) of Coordinate;
      Outcome : Results.Result := Results.Success;
   begin
      for Side of Sides'[Value.Top, Value.Left, Value.Bottom, Value.Right] loop
         exit when not Results.Succeeded (Outcome);
         Outcome := Put_Word (Object, Integer (Bytes.From_Coordinate (Side)));
      end loop;
      return Outcome;
   end Put_Rect;

   function Align (Object : in out Writer) return Results.Result is
     (if Picture_Count (Object) mod 2 = 1 then Put_Byte (Object, 0) else Results.Success);
end Pictlib.Internal.Writers;
