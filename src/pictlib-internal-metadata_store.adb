with Pictlib.Errors;
with Pictlib.Internal.Checked_Arithmetic;
with Pictlib.Internal.Failures;

package body Pictlib.Internal.Metadata_Store is
   --  Emptied vectors keep their storage, so the store is replaced by empty ones: what it held is released.
   procedure Clear (Object : in out Store) is
   begin
      Object.Infos := Info_Vectors.Empty_Vector;
      Object.Data := Data_Vectors.Empty_Vector;
      Object.Bytes := 0;
   end Clear;

   function Admits (Object : Store; Length : Byte_Count; Budget : Limits.Limit_Set) return Results.Result is
   begin
      --  The caller places the failure in the stream.
      if Natural (Object.Infos.Length) >= Budget.Max_Metadata_Items then
         return Failures.Over_Limit
           (Metadata_Item_Limit, Byte_Count (Budget.Max_Metadata_Items), Byte_Count (Object.Infos.Length) + 1);
      elsif Length
        > Budget.Max_Retained_Metadata_Bytes - Byte_Count'Min (Object.Bytes, Budget.Max_Retained_Metadata_Bytes)
      then
         return Failures.Over_Limit
           (Retained_Metadata_Byte_Limit, Budget.Max_Retained_Metadata_Bytes,
            Checked_Arithmetic.Saturating_Add (Object.Bytes, Length));
      end if;
      return Results.Success;
   end Admits;

   procedure Append (Object : in out Store; Info : Metadata.Item_Info; Data : Streams.Byte_Array) is
      Item : Metadata.Item_Info := Info;
   begin
      Item.Data_Length := Data'Length;
      Object.Infos.Append (Item);
      Object.Data.Append (Data);
      Object.Bytes := Object.Bytes + Data'Length;
   end Append;

   function Count (Object : Store) return Natural is (Natural (Object.Infos.Length));

   function Info (Object : Store; Index : Positive) return Metadata.Item_Info is (Object.Infos.Element (Index));

   function Copy_Data
     (Object : Store;
      Index : Positive;
      Buffer : out Streams.Byte_Array;
      Count : out Byte_Count) return Results.Result
   is
   begin
      Buffer := [others => 0];
      Count := 0;
      if Index > Natural (Object.Infos.Length) then
         return Results.Failure
           (Errors.Make
              (Errors.Invalid_Argument,
               (Expected => Byte_Count (Object.Infos.Length), Actual => Byte_Count (Index), others => <>)));
      end if;
      declare
         --  A reference, not a copy: an item may be as large as the retained metadata budget.
         Item : Streams.Byte_Array renames Object.Data.Constant_Reference (Index).Element.all;
      begin
         if Item'Length > Buffer'Length then
            return Results.Failure
              (Errors.Make
                 (Errors.Limit_Exceeded,
                  (Expected => Buffer'Length, Actual => Item'Length, Limit => Output_Byte_Limit, others => <>)));
         end if;
         Buffer (Buffer'First .. Buffer'First + Item'Length - 1) := Item;
         Count := Item'Length;
      end;
      return Results.Success;
   end Copy_Data;
end Pictlib.Internal.Metadata_Store;
