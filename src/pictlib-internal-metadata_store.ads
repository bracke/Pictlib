with Ada.Containers.Indefinite_Vectors;
with Ada.Containers.Vectors;
with Pictlib.Limits;
with Pictlib.Metadata;
with Pictlib.Results;
with Pictlib.Streams;

--  Library-owned retained metadata, bounded by the item and byte limits. Valid until cleared.
package Pictlib.Internal.Metadata_Store is
   type Store is private;

   --  Clear.
   --  @param Object Store to empty.
   procedure Clear (Object : in out Store);
   --  Admits.
   --  @param Object Store to inspect.
   --  @param Length Data bytes of a candidate item.
   --  @param Budget Limits whose item and byte budgets apply.
   --  @return Success, or Limit_Exceeded naming the budget the item would cross.
   function Admits (Object : Store; Length : Byte_Count; Budget : Limits.Limit_Set) return Results.Result;
   --  Append.
   --  @param Object Store to append to; the caller checked Admits first.
   --  @param Info Item description; its Data_Length is set from Data.
   --  @param Data Item bytes, copied.
   procedure Append (Object : in out Store; Info : Metadata.Item_Info; Data : Streams.Byte_Array);
   --  Count.
   --  @param Object Store to inspect.
   --  @return Items retained.
   function Count (Object : Store) return Natural;
   --  Total bytes.
   --  @param Object Store to inspect.
   --  @return Data bytes retained.
   function Total_Bytes (Object : Store) return Byte_Count;
   --  Info.
   --  @param Object Store to inspect.
   --  @param Index 1-based item position.
   --  @return Item description.
   function Info (Object : Store; Index : Positive) return Metadata.Item_Info
     with Pre => Index <= Count (Object);
   --  Copy data.
   --  @param Object Store to read.
   --  @param Index 1-based item position.
   --  @param Buffer Receives the item data from Buffer'First.
   --  @param Count Bytes copied; 0 on failure.
   --  @return Success, Invalid_Argument for an index out of range, or Limit_Exceeded when Buffer is short.
   function Copy_Data
     (Object : Store;
      Index : Positive;
      Buffer : out Streams.Byte_Array;
      Count : out Byte_Count) return Results.Result;

private
   use type Metadata.Item_Info;
   use type Streams.Byte_Array;

   package Info_Vectors is new Ada.Containers.Vectors (Positive, Metadata.Item_Info);
   package Data_Vectors is new Ada.Containers.Indefinite_Vectors (Positive, Streams.Byte_Array);

   type Store is record
      Infos : Info_Vectors.Vector;
      Data : Data_Vectors.Vector;
      Bytes : Byte_Count := 0;
   end record;
end Pictlib.Internal.Metadata_Store;
