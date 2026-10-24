package body Pictlib.Internal.PackBits is
   use type Streams.Byte_Array;

   function Unpack
     (Packed : Streams.Byte_Array;
      Unit : Unit_Size;
      Output : out Streams.Byte_Array;
      Written : out Natural) return Unpack_Status
   is
      Size : constant Natural := Natural (Unit);
      Next : Natural := Packed'First;
      Status : Unpack_Status := Exact;
   begin
      Output := [others => 0];
      Written := 0;
      while Next <= Packed'Last loop
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
                  Output (Output'First + Written .. Output'First + Written + Room - 1) :=
                    Packed (Next .. Next + Room - 1);
                  Written := Written + Room;
                  Next := Next + Taken;
                  if Taken < Bytes then
                     return Truncated;
                  elsif Room < Taken then
                     Status := Overrun;
                  end if;
               end;
            elsif Flag >= 129 then
               if Packed'Last - Next + 1 < Size then
                  return Truncated;
               end if;
               declare
                  Count : constant Natural := 257 - Flag;
               begin
                  for Repeat in 1 .. Count loop
                     if Written + Size > Output'Length then
                        Status := Overrun;
                        exit;
                     end if;
                     Output (Output'First + Written .. Output'First + Written + Size - 1) :=
                       Packed (Next .. Next + Size - 1);
                     Written := Written + Size;
                  end loop;
                  Next := Next + Size;
               end;
            end if;
         end;
      end loop;
      if Status = Exact and then Written < Output'Length then
         return Underrun;
      end if;
      return Status;
   end Unpack;

   procedure Pack
     (Row : Streams.Byte_Array;
      Unit : Unit_Size;
      Output : out Streams.Byte_Array;
      Written : out Natural)
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
