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
               --  As many of the run's units as the output has room for, written at once rather than a unit at a
               --  time; a run longer than that room overruns it.
               declare
                  Units : constant Natural := 257 - Flag;
                  Fits : constant Natural := Natural'Min (Units, (Output'Length - Written) / Size);
               begin
                  if Fits > 0 then
                     if Size = 1 then
                        Output (Output'First + Written .. Output'First + Written + Fits - 1) :=
                          [others => Packed (Next)];
                     else
                        for Index in 0 .. Fits - 1 loop
                           pragma Loop_Invariant (Written + Fits * Size <= Output'Length);
                           Output (Output'First + Written + 2 * Index) := Packed (Next);
                           Output (Output'First + Written + 2 * Index + 1) := Packed (Next + 1);
                        end loop;
                     end if;
                  end if;
                  Written := Written + Fits * Size;
                  if Fits < Units then
                     Status := Overrun;
                  end if;
               end;
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
               Put (Row (Row'First + Index));
               Index := Index + Run;
            end;
         else
            declare
               Literal : Natural := 1;
               --  A run starts at byte K when K equals K + 1 and K + 1 equals K + 2: whether K equals K + 1 is
               --  carried from one byte to the next, so each pair is compared once.
               Equal_Next : Boolean := Index + 2 < Length and then Same (Index + 1, Index + 2);
            begin
               while Index + Literal < Length and then Literal < 128 loop
                  declare
                     At_Byte : constant Natural := Index + Literal;
                     Equal_After : constant Boolean := At_Byte + 2 < Length and then Same (At_Byte + 1, At_Byte + 2);
                  begin
                     exit when At_Byte + 2 < Length and then Equal_Next and then Equal_After;
                     Equal_Next := Equal_After;
                  end;
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
