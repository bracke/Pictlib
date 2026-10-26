with Pictlib.Metadata;
with Pictlib.Streams;

--  The metadata a session retains, under the item and byte budgets and the allocation budgets.
package Pictlib.Internal.Sessions.Retained is
   --  Retain: an item read from the stream, or skipped when a lenient session has no room for it.
   --  @param S Session whose store receives the item.
   --  @param Info Item description.
   --  @param Length Data bytes to read from the stream into the item.
   --  @param In_Opcode False for data outside any opcode, which the per-opcode byte budget does not cover.
   --  @return Success (also when a lenient session drops the item with a Data_Loss warning), or the failure.
   function Retain
     (S : in out Session;
      Info : Metadata.Item_Info;
      Length : Byte_Count;
      In_Opcode : Boolean := True) return Results.Result;
   --  Retain bytes: an item whose data was already read.
   --  @param S Session whose store receives the item.
   --  @param Info Item description.
   --  @param Data The item's data.
   --  @return Success (also when a lenient session drops the item with a Data_Loss warning), or the failure.
   function Retain_Bytes (S : in out Session; Info : Metadata.Item_Info; Data : Streams.Byte_Array)
     return Results.Result;

   --  Metadata count.
   --  @param S Session.
   --  @return Items retained.
   function Metadata_Count (S : Session) return Natural;
   --  Metadata item.
   --  @param S Session.
   --  @param Index Item index.
   --  @return Its description.
   function Metadata_Item (S : Session; Index : Positive) return Metadata.Item_Info
     with Pre => Index <= Metadata_Count (S);
   --  Copy metadata.
   --  @param S Session.
   --  @param Index Item index.
   --  @param Buffer Receives the item's data.
   --  @param Count Bytes written.
   --  @return Success, or Invalid_Argument for an index out of range or a Buffer shorter than the item.
   function Copy_Metadata
     (S : Session;
      Index : Positive;
      Buffer : out Streams.Byte_Array;
      Count : out Byte_Count) return Results.Result;
end Pictlib.Internal.Sessions.Retained;
