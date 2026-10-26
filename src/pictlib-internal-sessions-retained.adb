with Pictlib.Internal.Bytes;
with Pictlib.Errors;
with Pictlib.Internal.Checked_Arithmetic;
with Pictlib.Internal.Sessions.Accounting;

package body Pictlib.Internal.Sessions.Retained is
   function Metadata_Count (S : Session) return Natural is (Metadata_Store.Count (S.Kept.Store));
   function Metadata_Item (S : Session; Index : Positive) return Metadata.Item_Info is
     (Metadata_Store.Info (S.Kept.Store, Index));
   function Copy_Metadata
     (S : Session;
      Index : Positive;
      Buffer : out Streams.Byte_Array;
      Count : out Byte_Count) return Results.Result is
     (Metadata_Store.Copy_Data (S.Kept.Store, Index, Buffer, Count));

   --  Decide whether an item of Length bytes may be kept, admitting it to the allocation budget when it is. When
   --  the metadata budgets have no room a strict session fails and a lenient one records Data_Loss and sets Keep
   --  to False; the session's allocation limit is never recovered.
   function Admit_Item (S : in out Session; Length : Byte_Count; Keep : out Boolean) return Results.Result is
      Admission : constant Results.Result := Metadata_Store.Admits (S.Kept.Store, Length, S.Budget);
   begin
      Keep := False;
      if not Results.Succeeded (Admission) then
         return Reject_Or_Warn
           (S, Admission.First_Error.Code, Errors.Data_Loss, Errors.Data_Loss,
            (Admission.First_Error.Context with delta Source => S.Stream.Offset));
      end if;
      Keep := True;
      return Accounting.Admit_Aggregate (S, Checked_Arithmetic.Saturating_Add (Length, Accounting.Item_Overhead_Bytes));
   end Admit_Item;

   function Retain
     (S : in out Session;
      Info : Metadata.Item_Info;
      Length : Byte_Count;
      In_Opcode : Boolean := True) return Results.Result
   is
      Keep : Boolean;
      --  The opcode's own budget first, so whether metadata is retained never changes which pictures its budgets
      --  fail; a kept item is then admitted against the allocation budgets, which keeping can cross.
      Outcome : Results.Result := (if In_Opcode then Admit_Data (S, Length) else Results.Success);
      Data : Streams.Byte_Array_Access;
   begin
      if Results.Succeeded (Outcome) then
         Outcome := Admit_Item (S, Length, Keep);
      end if;
      if not Results.Succeeded (Outcome) then
         return Outcome;
      elsif not Keep then
         return (if In_Opcode then Skip_Data (S, Length) else Streams.Skip_Exact (S.Stream, Length));
      end if;
      Outcome := Read_Payload (S, Length, Data, In_Opcode);
      if Results.Succeeded (Outcome) then
         Metadata_Store.Append (S.Kept.Store, Info, Data.all);
         Bytes.Free (Data);
      end if;
      return Outcome;
   end Retain;

   function Retain_Bytes (S : in out Session; Info : Metadata.Item_Info; Data : Streams.Byte_Array)
     return Results.Result
   is
      Keep : Boolean;
      Outcome : constant Results.Result := Admit_Item (S, Data'Length, Keep);
   begin
      if Results.Succeeded (Outcome) and then Keep then
         Metadata_Store.Append (S.Kept.Store, Info, Data);
      end if;
      return Outcome;
   end Retain_Bytes;
end Pictlib.Internal.Sessions.Retained;
