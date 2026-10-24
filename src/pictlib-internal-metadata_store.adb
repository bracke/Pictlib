with Pictlib.Errors;

package body Pictlib.Internal.Metadata_Store is
   procedure Clear (Object : in out Store) is
   begin
      Object.Infos.Clear;
      Object.Data.Clear;
      Object.Bytes := 0;
   end Clear;

   function Admits (Object : Store; Length : Byte_Count; Budget : Limits.Limit_Set) return Results.Result is
   begin
      if Natural (Object.Infos.Length) >= Budget.Max_Metadata_Items then
         return Results.Failure
           (Errors.Make
              (Errors.Limit_Exceeded,
               (Expected => Byte_Count (Budget.Max_Metadata_Items),
                Actual => Byte_Count (Object.Infos.Length) + 1,
                Limit => Metadata_Item_Limit,
                others => <>)));
      elsif Length > Budget.Max_Retained_Metadata_Bytes - Byte_Count'Min (Object.Bytes, Budget.Max_Retained_Metadata_Bytes)
      then
         return Results.Failure
           (Errors.Make
              (Errors.Limit_Exceeded,
               (Expected => Budget.Max_Retained_Metadata_Bytes,
                Actual => Length,
                Limit => Retained_Metadata_Byte_Limit,
                others => <>)));
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

   function Total_Bytes (Object : Store) return Byte_Count is (Object.Bytes);

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
         Item : constant Streams.Byte_Array := Object.Data.Element (Index);
      begin
         if Item'Length > Buffer'Length then
            return Results.Failure
              (Errors.Make
                 (Errors.Limit_Exceeded,
                  (Expected => Item'Length, Actual => Buffer'Length, Limit => Output_Byte_Limit, others => <>)));
         end if;
         Buffer (Buffer'First .. Buffer'First + Item'Length - 1) := Item;
         Count := Item'Length;
      end;
      return Results.Success;
   end Copy_Data;
end Pictlib.Internal.Metadata_Store;
