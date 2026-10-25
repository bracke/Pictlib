package body Pictlib.Internal.PackBits
  with SPARK_Mode => On
is
   procedure Unpack
     (Packed : Streams.Byte_Array;
      Unit : Unit_Size;
      Output : out Streams.Byte_Array;
      Written : out Natural;
      Status : out Unpack_Status)
   is
      Size : constant Natural := Natural (Unit);
      --  An empty Packed may have any first bound.
      Next : Integer := Packed'First;
   begin
      Output := [others => 0];
      Written := 0;
      Status := Exact;
      while Next <= Packed'Last loop
         pragma Loop_Invariant (Next >= Packed'First);
         pragma Loop_Invariant (Written <= Output'Length);
         pragma Loop_Invariant (Status in Exact | Overrun);
         declare
            Flag : constant Natural := Natural (Packed (Next));
         begin
            Next := Next + 1;
            if Flag <= 127 then
               declare
                  Bytes : constant Natural := (Flag + 1) * Size;
                  Available : constant Natural := Packed'Last - Next + 1;
                  Taken : constant Natural := Natural'Min (Bytes, Available);
                  Room : constant Natural := Natural'Min (Taken, Output'Length - Written);
               begin
                  if Room > 0 then
                     Output (Output'First + Written .. Output'First + Written + Room - 1) :=
                       Packed (Next .. Next + Room - 1);
                  end if;
                  Written := Written + Room;
                  if Taken < Bytes then
                     Status := Truncated;
                     return;
                  elsif Room < Taken then
                     Status := Overrun;
                  end if;
                  Next := Next + Taken;
               end;
            elsif Flag >= 129 then
               if Packed'Last - Next + 1 < Size then
                  Status := Truncated;
                  return;
               end if;
               for Repeat in 1 .. 257 - Flag loop
                  pragma Loop_Invariant (Written <= Output'Length);
                  if Output'Length - Written < Size then
                     Status := Overrun;
                     exit;
                  end if;
                  Output (Output'First + Written .. Output'First + Written + Size - 1) :=
                    Packed (Next .. Next + Size - 1);
                  Written := Written + Size;
               end loop;
               Next := Next + Size;
            end if;
         end;
      end loop;
      if Status = Exact and then Written < Output'Length then
         Status := Underrun;
      end if;
   end Unpack;

   procedure Pack
     (Row : Streams.Byte_Array;
      Output : out Streams.Byte_Array;
      Written : out Natural)
     with SPARK_Mode => Off
   is
      Length : constant Natural := Row'Length;

      function Same (Left, Right : Natural) return Boolean is (Row (Row'First + Left) = Row (Row'First + Right));

      procedure Put (Item : Byte) is
      begin
         Output (Output'First + Written) := Item;
         Written := Written + 1;
      end Put;

      procedure Put_Bytes (First, Count : Natural) is
      begin
         Output (Output'First + Written .. Output'First + Written + Count - 1) :=
           Row (Row'First + First .. Row'First + First + Count - 1);
         Written := Written + Count;
      end Put_Bytes;

      --  A run starts at three equal bytes; two equal bytes cost no more as part of a literal.
      function Starts_Run (At_Byte : Natural) return Boolean is
        (At_Byte + 2 < Length and then Same (At_Byte, At_Byte + 1) and then Same (At_Byte, At_Byte + 2));

      Index : Natural := 0;
   begin
      Output := [others => 0];
      Written := 0;
      while Index < Length loop
         if Starts_Run (Index) then
            declare
               Run : Natural := 3;
            begin
               while Index + Run < Length and then Run < 128 and then Same (Index, Index + Run) loop
                  Run := Run + 1;
               end loop;
               Put (Byte (257 - Run));
               Put_Bytes (Index, 1);
               Index := Index + Run;
            end;
         else
            declare
               Literal : Natural := 1;
            begin
               while Index + Literal < Length and then Literal < 128 and then not Starts_Run (Index + Literal) loop
                  Literal := Literal + 1;
               end loop;
               Put (Byte (Literal - 1));
               Put_Bytes (Index, Literal);
               Index := Index + Literal;
            end;
         end if;
      end loop;
      --  Every 128 literal bytes take one flag byte; a run takes two bytes for three or more.
      pragma Assert (Written <= Worst_Case (Row'Length));
   end Pack;
end Pictlib.Internal.PackBits;
