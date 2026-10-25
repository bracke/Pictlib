with Pictlib.Internal.Bytes;
with Pictlib.Internal.Checked_Arithmetic;

package body Pictlib.Internal.Sessions is
   procedure Set_Budget (S : in out Session; Budget : Limits.Limit_Set) is
   begin
      S.Budget := Budget;
   end Set_Budget;

   procedure Set_Version (S : in out Session; Version : PICT_Version) is
   begin
      S.Version := Version;
   end Set_Version;


   procedure Clear (S : in out Session) is
   begin
      Picture_Stream.Unbind (S.Stream);
      S.Version := Version_1;
      Metadata_Store.Clear (S.Kept.Store);
      Diagnostics.Clear (S.Kept.Log);
      S.Counts := (others => <>);
   end Clear;

   procedure Start
     (S : in out Session;
      Input : not null access Streams.Source'Class;
      Strictness : Strictness_Mode;
      Retention : Metadata.Retention_Policy) is
   begin
      Clear (S);
      Picture_Stream.Bind (S.Stream, Input, S.Budget.Max_Picture_Bytes);
      S.Strictness := Strictness;
      S.Retention := Retention;
   end Start;

   procedure Warn
     (S : in out Session;
      Code : Errors.Warning_Code;
      Severity : Errors.Warning_Severity;
      Context : Errors.Diagnostic_Context := (others => <>))
   is
      Item : Errors.Diagnostic_Context := Context;
   begin
      if Item.Source = 0 then
         Item.Source := S.Stream.Offset;
      end if;
      --  Max_Warning_Records bounds the log, so it needs no allocation quota; past it the last record says how
      --  many warnings were suppressed.
      Diagnostics.Add (S.Kept.Log, Errors.Make_Warning (Code, Severity, Item), S.Budget.Max_Warning_Records);
   end Warn;

   function Fail (S : Session; Code : Errors.Error_Code; Expected, Actual : Byte_Count := 0) return Results.Result
   is
     (Results.Failure
        (Errors.Make (Code, (Source => S.Stream.Offset, Expected => Expected, Actual => Actual, others => <>))));

   function Over_Limit (S : Session; Limit : Limit_Kind; Expected, Actual : Byte_Count) return Results.Result is
     (Failures.Over_Limit (Limit, Expected, Actual, S.Stream.Offset));

   function Reject_Or_Warn
     (S : in out Session;
      Code : Errors.Error_Code;
      Warning : Errors.Warning_Code;
      Severity : Errors.Warning_Severity;
      Context : Errors.Diagnostic_Context) return Results.Result
   is
      Item : constant Errors.Diagnostic_Context :=
        (if Context.Source = 0 then (Context with delta Source => S.Stream.Offset) else Context);
   begin
      if not Is_Lenient (S) then
         return Results.Failure (Errors.Make (Code, Item));
      end if;
      Warn (S, Warning, Severity, Item);
      return Results.Success;
   end Reject_Or_Warn;

   function Attributed (Outcome : Results.Result; Event : Pictures.Opcode_Event) return Results.Result is
      Item : Errors.Error;
   begin
      if Results.Succeeded (Outcome) then
         return Outcome;
      end if;
      Item := Outcome.First_Error;
      --  A failure that names no opcode is the event's; one that names another keeps it.
      if not Item.Context.Has_Opcode or else Item.Context.Op = Event.Op then
         Item.Context.Op := Event.Op;
         Item.Context.Has_Opcode := True;
         Item.Context.Ordinal := Event.Ordinal;
      end if;
      return Results.Failure (Item);
   end Attributed;

   procedure Defer_Opcode (S : in out Session; Op : Opcode; Offset : Source_Offset) is
   begin
      S.Counts.Has_Pending := True;
      S.Counts.Pending_Op := Op;
      S.Counts.Pending_Offset := Offset;
   end Defer_Opcode;

   function Take_Deferred (S : in out Session; Op : out Opcode; Offset : out Source_Offset) return Boolean is
      Deferred : constant Boolean := S.Counts.Has_Pending;
   begin
      Op := S.Counts.Pending_Op;
      Offset := S.Counts.Pending_Offset;
      S.Counts.Has_Pending := False;
      return Deferred;
   end Take_Deferred;

   procedure Start_Drawing (S : in out Session) is
   begin
      S.Counts.Work_Used := 0;
   end Start_Drawing;

   function Over_Work (S : Session; Units : Pixel_Count) return Results.Result is
     (Over_Limit
        (S, Drawing_Work_Limit, Byte_Count (S.Budget.Max_Drawing_Work),
         Byte_Count (Checked_Arithmetic.Saturating_Add (S.Counts.Work_Used, Units))));

   function Charge_Work (S : in out Session; Units : Pixel_Count) return Results.Result is
   begin
      if Units > Work_Left (S) then
         return Over_Work (S, Units);
      end if;
      S.Counts.Work_Used := S.Counts.Work_Used + Units;
      return Results.Success;
   end Charge_Work;

   function Charge_Work (S : in out Session; Units : Natural) return Results.Result is
     (Charge_Work (S, Pixel_Count (Units)));

   function Admit_Allocation (S : in out Session; Length : Byte_Count) return Results.Result is
   begin
      if Length > S.Budget.Max_Allocation_Bytes then
         return Over_Limit (S, Allocation_Byte_Limit, S.Budget.Max_Allocation_Bytes, Length);
      end if;
      return Admit_Aggregate (S, Length);
   end Admit_Allocation;

   function Admit_Aggregate (S : in out Session; Length : Byte_Count) return Results.Result is
      Total : constant Byte_Count := Checked_Arithmetic.Saturating_Add (S.Counts.Total_Allocation_Bytes, Length);
   begin
      if Total > S.Budget.Max_Total_Allocation_Bytes then
         return Over_Limit (S, Total_Allocation_Byte_Limit, S.Budget.Max_Total_Allocation_Bytes, Total);
      end if;
      S.Counts.Total_Allocation_Bytes := Total;
      return Results.Success;
   end Admit_Aggregate;

   function Allocation_Units_Left (S : Session; Bytes_Per_Unit : Positive) return Pixel_Count is
     (Pixel_Count
        ((S.Budget.Max_Total_Allocation_Bytes
          - Byte_Count'Min (S.Counts.Total_Allocation_Bytes, S.Budget.Max_Total_Allocation_Bytes))
         / Byte_Count (Bytes_Per_Unit)));

   function Shape_Work_Left (S : Session) return Pixel_Count is
     (Pixel_Count'Min (Work_Left (S), Allocation_Units_Left (S, Shape_Bytes_Per_Work_Unit)));

   function Claim_Ordinal (S : in out Session; Ordinal : out Opcode_Ordinal) return Results.Result is
   begin
      Ordinal := S.Counts.Next_Ordinal;
      if S.Counts.Next_Ordinal >= S.Budget.Max_Opcodes then
         return Over_Limit
           (S, Opcode_Count_Limit, Byte_Count (S.Budget.Max_Opcodes), Byte_Count (S.Counts.Next_Ordinal) + 1);
      end if;
      S.Counts.Next_Ordinal := S.Counts.Next_Ordinal + 1;
      return Results.Success;
   end Claim_Ordinal;

   procedure Begin_Opcode_Data (S : in out Session) is
   begin
      S.Counts.Data_Start := Picture_Stream.Picture_Offset (S.Stream);
   end Begin_Opcode_Data;

   function Opcode_Data_Length (S : Session) return Byte_Count is
     (Picture_Stream.Picture_Offset (S.Stream) - S.Counts.Data_Start);

   --  Admit More bytes of the current opcode's data against the per-opcode budget.
   function Admit_Data (S : Session; More : Byte_Count) return Results.Result is
      Used : constant Byte_Count := Opcode_Data_Length (S);
      Sum : constant Byte_Count := Checked_Arithmetic.Saturating_Add (Used, More);
   begin
      if Sum > S.Budget.Max_Opcode_Bytes then
         return Over_Limit (S, Opcode_Byte_Limit, S.Budget.Max_Opcode_Bytes, Sum);
      end if;
      return Results.Success;
   end Admit_Data;

   function Skip_Data (S : in out Session; Count : Byte_Count) return Results.Result is
      Outcome : constant Results.Result := Admit_Data (S, Count);
   begin
      if not Results.Succeeded (Outcome) or else Count = 0 then
         return Outcome;
      end if;
      return Streams.Skip_Exact (S.Stream, Count);
   end Skip_Data;

   function Read_Payload
     (S : in out Session;
      Length : Byte_Count;
      Data : out Streams.Byte_Array_Access;
      In_Opcode : Boolean := True) return Results.Result
   is
      Outcome : Results.Result := (if In_Opcode then Admit_Data (S, Length) else Results.Success);
   begin
      Data := null;
      if not Results.Succeeded (Outcome) then
         return Outcome;
      elsif Length > Byte_Count (Natural'Last) then
         return Over_Limit (S, Allocation_Byte_Limit, Byte_Count (Natural'Last), Length);
      end if;
      Outcome := Admit_Allocation (S, Length);
      if not Results.Succeeded (Outcome) then
         return Outcome;
      end if;
      Data := new Streams.Byte_Array (1 .. Natural (Length));
      Outcome := Streams.Read_Exact (S.Stream, Data.all);
      if not Results.Succeeded (Outcome) then
         Bytes.Free (Data);
      end if;
      return Outcome;
   end Read_Payload;

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
      return Admit_Aggregate (S, Checked_Arithmetic.Saturating_Add (Length, Item_Overhead_Bytes));
   end Admit_Item;

   function Retain
     (S : in out Session;
      Info : Metadata.Item_Info;
      Length : Byte_Count;
      In_Opcode : Boolean := True) return Results.Result
   is
      Keep : Boolean;
      --  The opcode's own budget first, so whether the item is kept never changes which pictures fail.
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

   function Read_Polygon_Size (S : in out Session; Points : out Natural) return Results.Result is
      use type Interfaces.Unsigned_16;
      Size : Interfaces.Unsigned_16 := 0;
      Outcome : constant Results.Result := Read_Word (S, Size);
   begin
      Points := 0;
      if not Results.Succeeded (Outcome) then
         return Outcome;
      elsif Size < Smallest_Polygon or else (Size - Smallest_Polygon) mod Polygon_Point_Bytes /= 0 then
         return Fail (S, Errors.Polygon_Invalid, Smallest_Polygon, Byte_Count (Size));
      end if;
      declare
         Stored : constant Natural := Natural (Size - Smallest_Polygon) / Polygon_Point_Bytes;
      begin
         if Stored > S.Budget.Max_Polygon_Points then
            return Over_Limit (S, Polygon_Point_Limit, Byte_Count (S.Budget.Max_Polygon_Points), Byte_Count (Stored));
         end if;
         Points := Stored;
      end;
      return Results.Success;
   end Read_Polygon_Size;

   function Read_Word (S : in out Session; Value : out Interfaces.Unsigned_16) return Results.Result is
      Outcome : constant Results.Result := Admit_Data (S, 2);
   begin
      Value := 0;
      if not Results.Succeeded (Outcome) then
         return Outcome;
      end if;
      return Bytes.Read_U16_BE (S.Stream, Value);
   end Read_Word;

   function Read_Count_Byte (S : in out Session; Value : out Byte) return Results.Result is
      Outcome : constant Results.Result := Admit_Data (S, 1);
   begin
      Value := 0;
      if not Results.Succeeded (Outcome) then
         return Outcome;
      end if;
      return Bytes.Read_Byte (S.Stream, Value);
   end Read_Count_Byte;

   function Read_RGB (S : in out Session; Color : out Images.RGB_Color) return Results.Result is
      Data : Streams.Byte_Array (1 .. RGB_Color_Bytes);
      Outcome : constant Results.Result := Read_Into (S, Data);
   begin
      Color := (Data (1), Data (3), Data (5));
      return Outcome;
   end Read_RGB;

   function Read_Long (S : in out Session; Value : out Interfaces.Unsigned_32) return Results.Result is
      Outcome : constant Results.Result := Admit_Data (S, 4);
   begin
      Value := 0;
      if not Results.Succeeded (Outcome) then
         return Outcome;
      end if;
      return Bytes.Read_U32_BE (S.Stream, Value);
   end Read_Long;

   function Read_Bounds (S : in out Session; Value : out Geometry.Rect) return Results.Result is
      Outcome : constant Results.Result := Admit_Data (S, 8);
   begin
      Value := (others => 0);
      if not Results.Succeeded (Outcome) then
         return Outcome;
      end if;
      return Bytes.Read_Rect (S.Stream, Value);
   end Read_Bounds;

   function Read_Into (S : in out Session; Buffer : out Streams.Byte_Array) return Results.Result is
      Outcome : constant Results.Result := Admit_Data (S, Buffer'Length);
   begin
      Buffer := [others => 0];
      if not Results.Succeeded (Outcome) or else Buffer'Length = 0 then
         return Outcome;
      end if;
      return Streams.Read_Exact (S.Stream, Buffer);
   end Read_Into;
end Pictlib.Internal.Sessions;
