with Pictlib.Internal.Bytes;
with Pictlib.Internal.Checked_Arithmetic;

package body Pictlib.Internal.Sessions is

   procedure Clear (S : in out Session) is
   begin
      Picture_Stream.Unbind (S.Stream);
      S.Version := Version_1;
      Metadata_Store.Clear (S.Store);
      Diagnostics.Clear (S.Log);
      S.Total_Allocation_Bytes := 0;
      S.Work_Used := 0;
      S.Next_Ordinal := 0;
      S.Data_Start := 0;
      S.Has_Pending := False;
      S.Pending_Op := 0;
      S.Pending_Offset := 0;
   end Clear;

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
      --  A warning is never dropped: Max_Warning_Records bounds the log, so it needs no allocation quota.
      Diagnostics.Add (S.Log, Errors.Make_Warning (Code, Severity, Item), S.Budget.Max_Warning_Records);
   end Warn;

   function Fail (S : Session; Code : Errors.Error_Code; Expected, Actual : Byte_Count := 0) return Results.Result
   is
     (Results.Failure
        (Errors.Make (Code, (Source => S.Stream.Offset, Expected => Expected, Actual => Actual, others => <>))));

   function Over_Limit (S : Session; Limit : Limit_Kind; Expected, Actual : Byte_Count) return Results.Result is
     (Results.Failure
        (Errors.Make
           (Errors.Limit_Exceeded,
            (Source => S.Stream.Offset, Expected => Expected, Actual => Actual, Limit => Limit, others => <>))));

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

   procedure Start_Drawing (S : in out Session) is
   begin
      S.Work_Used := 0;
   end Start_Drawing;

   function Over_Work (S : Session; Units : Pixel_Count) return Results.Result is
     (Over_Limit
        (S, Drawing_Work_Limit, Byte_Count (S.Budget.Max_Drawing_Work),
         Byte_Count (Checked_Arithmetic.Saturating_Add (S.Work_Used, Units))));

   function Charge_Work (S : in out Session; Units : Pixel_Count) return Results.Result is
   begin
      if Units > Work_Left (S) then
         return Over_Work (S, Units);
      end if;
      S.Work_Used := S.Work_Used + Units;
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
      Total : constant Byte_Count := Checked_Arithmetic.Saturating_Add (S.Total_Allocation_Bytes, Length);
   begin
      if Total > S.Budget.Max_Total_Allocation_Bytes then
         return Over_Limit (S, Total_Allocation_Byte_Limit, S.Budget.Max_Total_Allocation_Bytes, Total);
      end if;
      S.Total_Allocation_Bytes := Total;
      return Results.Success;
   end Admit_Aggregate;

   function Allocation_Units_Left (S : Session; Bytes_Per_Unit : Positive) return Pixel_Count is
     (Pixel_Count
        ((S.Budget.Max_Total_Allocation_Bytes
          - Byte_Count'Min (S.Total_Allocation_Bytes, S.Budget.Max_Total_Allocation_Bytes))
         / Byte_Count (Bytes_Per_Unit)));

   function Shape_Work_Left (S : Session) return Pixel_Count is
     (Pixel_Count'Min (Work_Left (S), Allocation_Units_Left (S, Shape_Bytes_Per_Work_Unit)));

   function Claim_Ordinal (S : in out Session; Ordinal : out Opcode_Ordinal) return Results.Result is
   begin
      Ordinal := S.Next_Ordinal;
      if S.Next_Ordinal >= S.Budget.Max_Opcodes then
         return Over_Limit
           (S, Opcode_Count_Limit, Byte_Count (S.Budget.Max_Opcodes), Byte_Count (S.Next_Ordinal) + 1);
      end if;
      S.Next_Ordinal := S.Next_Ordinal + 1;
      return Results.Success;
   end Claim_Ordinal;

   --  Admit More bytes of the current opcode's data against the per-opcode budget.
   function Admit_Data (S : Session; More : Byte_Count) return Results.Result is
      Used : constant Byte_Count := Picture_Stream.Picture_Offset (S.Stream) - S.Data_Start;
      Sum : constant Checked_Arithmetic.Count_Result := Checked_Arithmetic.Add (Used, More);
   begin
      if not Results.Succeeded (Sum.Outcome) or else Sum.Value > S.Budget.Max_Opcode_Bytes then
         return Over_Limit (S, Opcode_Byte_Limit, S.Budget.Max_Opcode_Bytes, Sum.Value);
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

   --  Read Length bytes into a heap buffer the caller frees.
   function Read_Payload
     (S : in out Session;
      Length : Byte_Count;
      Data : out Streams.Byte_Array_Access) return Results.Result
   is
      Outcome : Results.Result := Admit_Data (S, Length);
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
         Free (Data);
      end if;
      return Outcome;
   end Read_Payload;

   --  Decide whether an item of Length bytes may be kept: a strict session fails when it does not fit,
   --  a lenient one records Data_Loss and sets Keep to False.
   function Admit_Item (S : in out Session; Length : Byte_Count; Keep : out Boolean) return Results.Result is
      Admission : Results.Result := Metadata_Store.Admits (S.Store, Length, S.Budget);
   begin
      Keep := Results.Succeeded (Admission);
      if Keep then
         Admission := Admit_Aggregate (S, Checked_Arithmetic.Saturating_Add (Length, Item_Overhead_Bytes));
         Keep := Results.Succeeded (Admission);
      end if;
      if Keep then
         return Admission;
      elsif not Is_Lenient (S) then
         return Results.Failure
           ((Admission.First_Error with delta
               Context => (Admission.First_Error.Context with delta Source => S.Stream.Offset)));
      end if;
      Warn (S, Errors.Data_Loss, Errors.Data_Loss, Admission.First_Error.Context);
      return Results.Success;
   end Admit_Item;

   function Retain (S : in out Session; Info : Metadata.Item_Info; Length : Byte_Count) return Results.Result is
      Keep : Boolean;
      Outcome : Results.Result := Admit_Item (S, Length, Keep);
      Data : Streams.Byte_Array_Access;
   begin
      if not Results.Succeeded (Outcome) then
         return Outcome;
      elsif not Keep then
         return Skip_Data (S, Length);
      end if;
      Outcome := Read_Payload (S, Length, Data);
      if Results.Succeeded (Outcome) then
         Metadata_Store.Append (S.Store, Info, Data.all);
         Free (Data);
      end if;
      return Outcome;
   end Retain;

   function Read_Polygon_Size (S : in out Session; Points : out Natural) return Results.Result is
      use type Interfaces.Unsigned_16;
      Size : Interfaces.Unsigned_16 := 0;
      Outcome : constant Results.Result := Read_Word (S, Size);
   begin
      Points := 0;
      if not Results.Succeeded (Outcome) then
         return Outcome;
      elsif Size < Smallest_Polygon or else (Size - Smallest_Polygon) mod 4 /= 0 then
         return Fail (S, Errors.Polygon_Invalid, Smallest_Polygon, Byte_Count (Size));
      elsif Natural (Size - Smallest_Polygon) / 4 > S.Budget.Max_Polygon_Points then
         return Over_Limit
           (S, Polygon_Point_Limit, Byte_Count (S.Budget.Max_Polygon_Points), Byte_Count (Size - Smallest_Polygon) / 4);
      end if;
      Points := Natural (Size - Smallest_Polygon) / 4;
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

   --  Pixel data: unpacked rows of Raw_Row_Length bytes, or rows each prefixed by its packed byte count,
   --  a byte when Row_Bytes <= 250 and a word otherwise.
   function Read_Into (S : in out Session; Buffer : out Streams.Byte_Array) return Results.Result is
      Outcome : constant Results.Result := Admit_Data (S, Buffer'Length);
   begin
      Buffer := [others => 0];
      if not Results.Succeeded (Outcome) or else Buffer'Length = 0 then
         return Outcome;
      end if;
      return Streams.Read_Exact (S.Stream, Buffer);
   end Read_Into;

   function Skip_Rows
     (S : in out Session;
      Row_Bytes : Natural;
      Height : Natural;
      Packed : Boolean;
      Raw_Row_Length : Byte_Count) return Results.Result
   is
      Outcome : Results.Result;
   begin
      if not Packed then
         declare
            Total : constant Checked_Arithmetic.Count_Result :=
              Checked_Arithmetic.Multiply (Raw_Row_Length, Byte_Count (Height));
         begin
            if not Results.Succeeded (Total.Outcome) then
               return Over_Limit (S, Opcode_Byte_Limit, S.Budget.Max_Opcode_Bytes, Byte_Count'Last);
            end if;
            return Skip_Data (S, Total.Value);
         end;
      end if;
      for Row in 0 .. Height - 1 loop
         declare
            Count : Byte_Count;
         begin
            if Row_Bytes > Byte_Count_Row_Bytes then
               declare
                  Word : Interfaces.Unsigned_16;
               begin
                  Outcome := Read_Word (S, Word);
                  Count := Byte_Count (Word);
               end;
            else
               declare
                  Small : Byte;
               begin
                  Outcome := Read_Count_Byte (S, Small);
                  Count := Byte_Count (Small);
               end;
            end if;
            if Results.Succeeded (Outcome) then
               Outcome := Skip_Data (S, Count);
            end if;
            if not Results.Succeeded (Outcome) then
               return Results.Failure
                 ((Outcome.First_Error with delta
                     Context => (Outcome.First_Error.Context with delta Row => Row_Index (Row))));
            end if;
         end;
      end loop;
      return Results.Success;
   end Skip_Rows;

   function Extent (S : Session; Bounds : Geometry.Rect; Width, Height : out Natural) return Results.Result is
   begin
      Width := 0;
      Height := 0;
      if Geometry.Width (Bounds) < 0 or else Geometry.Height (Bounds) < 0 then
         return Fail (S, Errors.Pixmap_Invalid);
      end if;
      Width := Geometry.Width (Bounds);
      Height := Geometry.Height (Bounds);
      return Results.Success;
   end Extent;

end Pictlib.Internal.Sessions;
