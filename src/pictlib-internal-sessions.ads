with Ada.Unchecked_Deallocation;
with Interfaces;
with Pictlib.Errors;
with Pictlib.Geometry;
with Pictlib.Internal.Diagnostics;
with Pictlib.Internal.Metadata_Store;
with Pictlib.Internal.Picture_Stream;
with Pictlib.Limits;
with Pictlib.Metadata;
with Pictlib.Results;
with Pictlib.Streams;

--  One picture's decoding session: the bounded stream, the decoding policy, retained metadata and warnings,
--  and the budget-checked readers every opcode's data goes through.
package Pictlib.Internal.Sessions is
   type Session is limited record
      Stream : Picture_Stream.Reader;
      Version : PICT_Version := Version_1;
      Strictness : Strictness_Mode := Strict;
      Retention : Metadata.Retention_Policy;
      Budget : Limits.Limit_Set := Limits.Default_Limits;
      Store : Metadata_Store.Store;
      Log : Diagnostics.Warning_Log;
      Total_Allocation_Bytes : Byte_Count := 0;
      Next_Ordinal : Opcode_Ordinal := 0;
      --  Picture offset where the current opcode's data begins.
      Data_Start : Byte_Count := 0;
      --  An opcode the header reader read but did not consume.
      Has_Pending : Boolean := False;
      Pending_Op : Opcode := 0;
      Pending_Offset : Source_Offset := 0;
   end record;

   procedure Free is new Ada.Unchecked_Deallocation (Streams.Byte_Array, Streams.Byte_Array_Access);

   --  Clear.
   --  @param S Session whose stream binding, retained metadata, warnings and counters are discarded.
   procedure Clear (S : in out Session);

   --  Warn.
   --  @param S Session whose log records the warning.
   --  @param Code Warning code.
   --  @param Severity Warning severity.
   --  @param Context Diagnostic context; the current source offset when it names none.
   procedure Warn
     (S : in out Session;
      Code : Errors.Warning_Code;
      Severity : Errors.Warning_Severity;
      Context : Errors.Diagnostic_Context := (others => <>));

   --  Is lenient.
   --  @param S Session.
   --  @return True unless the session decodes strictly.
   function Is_Lenient (S : Session) return Boolean is (S.Strictness /= Strict);

   --  Is boundary end.
   --  @param Item Result of reading an opcode or its pad byte.
   --  @return True when the input ended before the first byte, i.e. between opcodes.
   function Is_Boundary_End (Item : Results.Result) return Boolean is
     (not Results.Succeeded (Item)
      and then Errors."=" (Item.First_Error.Code, Errors.Source_Unexpected_End)
      and then Item.First_Error.Context.Actual = 0);

   --  Fail.
   --  @param S Session whose source offset is recorded.
   --  @param Code Error code.
   --  @param Expected Expected count or value, for the diagnostic context.
   --  @param Actual Actual count or value, for the diagnostic context.
   --  @return The failure.
   function Fail (S : Session; Code : Errors.Error_Code; Expected, Actual : Byte_Count := 0) return Results.Result;

   --  Over limit.
   --  @param S Session whose source offset is recorded.
   --  @param Limit The budget crossed.
   --  @param Expected The budget.
   --  @param Actual The amount asked for.
   --  @return A Limit_Exceeded failure.
   function Over_Limit (S : Session; Limit : Limit_Kind; Expected, Actual : Byte_Count) return Results.Result;

   --  Over work.
   --  @param S Session whose drawing budget was crossed.
   --  @param Used Drawing work already done.
   --  @param Units Work asked for on top of it.
   --  @return The Limit_Exceeded failure for drawing work, Used + Units saturated: the one report of it.
   function Over_Work (S : Session; Used, Units : Pixel_Count) return Results.Result;

   function Admit_Allocation
     (S : in out Session;
      Length : Byte_Count) return Results.Result;
   function Admit_Aggregate
     (S : in out Session;
      Length : Byte_Count) return Results.Result;
   function Allocation_Allowance
     (S : Session;
      Bytes_Per_Unit : Positive) return Pixel_Count;

   --  Claim ordinal.
   --  @param S Session counting opcodes.
   --  @param Ordinal The next opcode ordinal.
   --  @return Success, or Limit_Exceeded when the opcode count limit is reached.
   function Claim_Ordinal (S : in out Session; Ordinal : out Opcode_Ordinal) return Results.Result;

   --  Admit data.
   --  @param S Session reading an opcode's data.
   --  @param More Bytes about to be read or skipped.
   --  @return Success, or Limit_Exceeded when the opcode's data would cross the per-opcode budget.
   function Admit_Data (S : Session; More : Byte_Count) return Results.Result;
   --  Skip data.
   --  @param S Session reading an opcode's data.
   --  @param Count Bytes to skip within the per-opcode budget.
   --  @return Operation result.
   function Skip_Data (S : in out Session; Count : Byte_Count) return Results.Result;
   --  Read payload.
   --  @param S Session reading an opcode's data.
   --  @param Length Bytes to read within the per-opcode and allocation budgets.
   --  @param Data Heap buffer holding them, which the caller frees; null on failure.
   --  @return Operation result.
   function Read_Payload
     (S : in out Session;
      Length : Byte_Count;
      Data : out Streams.Byte_Array_Access) return Results.Result;
   --  Read word.
   --  @param S Session reading an opcode's data.
   --  @param Value Big-endian word.
   --  @return Operation result.
   function Read_Word (S : in out Session; Value : out Interfaces.Unsigned_16) return Results.Result;
   --  Read count byte.
   --  @param S Session reading an opcode's data.
   --  @param Value The byte.
   --  @return Operation result.
   function Read_Count_Byte (S : in out Session; Value : out Byte) return Results.Result;
   --  Read long.
   --  @param S Session reading an opcode's data.
   --  @param Value Big-endian long.
   --  @return Operation result.
   function Read_Long (S : in out Session; Value : out Interfaces.Unsigned_32) return Results.Result;
   --  Read polygon size.
   --  @param S Session positioned at a polygon's size word.
   --  @param Points The number of points the polygon holds, after its bounding box.
   --  @return Success, Polygon_Invalid for a size that is not 10 bytes plus whole points, or Limit_Exceeded past
   --  Max_Polygon_Points.
   function Read_Polygon_Size (S : in out Session; Points : out Natural) return Results.Result;
   --  The bytes of a polygon's size word and bounding box.
   Smallest_Polygon : constant := 10;

   --  Read bounds.
   --  @param S Session reading an opcode's data.
   --  @param Value A Rect.
   --  @return Operation result.
   function Read_Bounds (S : in out Session; Value : out Geometry.Rect) return Results.Result;
   --  Read into.
   --  @param S Session reading an opcode's data.
   --  @param Buffer Filled completely within the per-opcode budget.
   --  @return Operation result.
   function Read_Into (S : in out Session; Buffer : out Streams.Byte_Array) return Results.Result;

   --  Admit item.
   --  @param S Session retaining metadata.
   --  @param Length Data bytes of the candidate item.
   --  @param Keep True when the item fits the metadata budgets.
   --  @return Success, also when a lenient session drops the item with a Data_Loss warning; the failure otherwise.
   function Admit_Item (S : in out Session; Length : Byte_Count; Keep : out Boolean) return Results.Result;
   --  Retain.
   --  @param S Session whose store receives the item.
   --  @param Info Item description.
   --  @param Length Data bytes to read from the stream into the item.
   --  @return Success (also when a lenient session drops the item with a Data_Loss warning), or the failure.
   function Retain (S : in out Session; Info : Metadata.Item_Info; Length : Byte_Count) return Results.Result;

   --  Skip rows.
   --  @param S Session reading pixel data.
   --  @param Row_Bytes The pixmap's row length; packed row counts are words above 250.
   --  @param Height Rows.
   --  @param Packed True when every row is prefixed by its packed byte count.
   --  @param Raw_Row_Length Bytes per unpacked row.
   --  @return Operation result, with the failing row in its context.
   function Skip_Rows
     (S : in out Session;
      Row_Bytes : Natural;
      Height : Natural;
      Packed : Boolean;
      Raw_Row_Length : Byte_Count) return Results.Result;

   --  Extent.
   --  @param S Session.
   --  @param Bounds A pixmap's bounds.
   --  @param Width Bounds width.
   --  @param Height Bounds height.
   --  @return Success, or Pixmap_Invalid for inverted bounds.
   function Extent (S : Session; Bounds : Geometry.Rect; Width, Height : out Natural) return Results.Result;
end Pictlib.Internal.Sessions;
