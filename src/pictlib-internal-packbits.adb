package body Pictlib.Internal.PackBits
  with SPARK_Mode => On
is
   use type Streams.Byte_Array;

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
      Unit : Unit_Size;
      Output : out Streams.Byte_Array;
      Written : out Natural)
     with SPARK_Mode => Off
   is
      Size : constant Natural := Natural (Unit);
      Units : constant Natural := Row'Length / Size;

      function Same (Left, Right : Natural) return Boolean is
        (Row (Row'First + Left * Size .. Row'First + Left * Size + Size - 1)
         = Row (Row'First + Right * Size .. Row'First + Right * Size + Size - 1));

      procedure Put (Item : Byte) is
      begin
         Output (Output'First + Written) := Item;
         Written := Written + 1;
      end Put;

      procedure Put_Units (First, Count : Natural) is
      begin
         Output (Output'First + Written .. Output'First + Written + Count * Size - 1) :=
           Row (Row'First + First * Size .. Row'First + (First + Count) * Size - 1);
         Written := Written + Count * Size;
      end Put_Units;

      --  A run starts at three equal units; two equal units cost no more as part of a literal.
      function Starts_Run (At_Unit : Natural) return Boolean is
        (At_Unit + 2 < Units and then Same (At_Unit, At_Unit + 1) and then Same (At_Unit, At_Unit + 2));

      Index : Natural := 0;
   begin
      Output := [others => 0];
      Written := 0;
      while Index < Units loop
         if Starts_Run (Index) then
            declare
               Run : Natural := 3;
            begin
               while Index + Run < Units and then Run < 128 and then Same (Index, Index + Run) loop
                  Run := Run + 1;
               end loop;
               Put (Byte (257 - Run));
               Put_Units (Index, 1);
               Index := Index + Run;
            end;
         else
            declare
               Length : Natural := 1;
            begin
               while Index + Length < Units and then Length < 128 and then not Starts_Run (Index + Length) loop
                  Length := Length + 1;
               end loop;
               Put (Byte (Length - 1));
               Put_Units (Index, Length);
               Index := Index + Length;
            end;
         end if;
      end loop;
   end Pack;
end Pictlib.Internal.PackBits;
