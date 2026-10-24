with Ada.Unchecked_Deallocation;
with Interfaces;
with Pictlib.Errors;
with Pictlib.Geometry;
with Pictlib.Images;
with Pictlib.Internal.Diagnostics;
with Pictlib.Internal.Metadata_Store;
with Pictlib.Internal.Picture_Stream;
with Pictlib.Limits;
with Pictlib.Metadata;
with Pictlib.Pictures;
with Pictlib.Results;
with Pictlib.Streams;

--  One picture's decoding session: the bounded stream, the decoding policy, retained metadata and warnings,
--  the budget-checked readers every opcode's data goes through, and the session's accounting: the drawing work
--  done, the allocations admitted, and the one place each overrun is reported.
package Pictlib.Internal.Sessions is
   type Session is limited record
      Stream : Picture_Stream.Reader;
      Version : PICT_Version := Version_1;
      Strictness : Strictness_Mode := Strict;
      Retention : Metadata.Retention_Policy;
      Budget : Limits.Limit_Set := Limits.Default_Limits;
      Store : Metadata_Store.Store;
      Log : Diagnostics.Warning_Log;
      --  Allocations admitted this session, never given back.
      Total_Allocation_Bytes : Byte_Count := 0;
      --  Drawing work done in the current render.
      Work_Used : Pixel_Count := 0;
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
   --  Start: a session cleared and bound to a new picture.
   --  @param S Session; its budget is kept.
   --  @param Input The picture's source.
   --  @param Strictness How deviations are treated.
   --  @param Retention What metadata is kept.
   procedure Start
     (S : in out Session;
      Input : not null access Streams.Source'Class;
      Strictness : Strictness_Mode;
      Retention : Metadata.Retention_Policy);

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

   --  Context of.
   --  @param Event An opcode.
   --  @return A diagnostic context naming it: its offset, opcode and ordinal.
   function Context_Of (Event : Pictures.Opcode_Event) return Errors.Diagnostic_Context is
     ((Source => Event.Offset, Op => Event.Op, Has_Opcode => True, Ordinal => Event.Ordinal, others => <>));

   --  Reject or warn: the strictness rule for a deviation a lenient session tolerates.
   --  @param S Session whose strictness decides and whose log records the warning.
   --  @param Code The error a strict session fails with.
   --  @param Warning The warning a lenient one records instead.
   --  @param Severity The warning's severity.
   --  @param Context Diagnostic context of either; the current source offset when it names none.
   --  @return The failure strictly, Success otherwise.
   function Reject_Or_Warn
     (S : in out Session;
      Code : Errors.Error_Code;
      Warning : Errors.Warning_Code;
      Severity : Errors.Warning_Severity;
      Context : Errors.Diagnostic_Context) return Results.Result;

   --  Attributed: a failure while an opcode is read names that opcode.
   --  @param Outcome A result.
   --  @param Event The opcode being read.
   --  @return Outcome; a failure naming no opcode, or Event's without its ordinal, names Event's opcode and
   --  ordinal.
   function Attributed (Outcome : Results.Result; Event : Pictures.Opcode_Event) return Results.Result;

   --  Defer opcode: the header reader read an opcode it does not consume.
   --  @param S Session.
   --  @param Op The opcode read.
   --  @param Offset Its source offset.
   procedure Defer_Opcode (S : in out Session; Op : Opcode; Offset : Source_Offset);
   --  Take deferred.
   --  @param S Session; its deferred opcode, if any, is taken.
   --  @param Op The deferred opcode.
   --  @param Offset Its source offset.
   --  @return True when an opcode was deferred; Op and Offset are then the next opcode's.
   function Take_Deferred (S : in out Session; Op : out Opcode; Offset : out Source_Offset) return Boolean;

   --  Drawing work: one counter per render, against Max_Drawing_Work.

   --  Start drawing.
   --  @param S Session about to render; no drawing work is done yet.
   procedure Start_Drawing (S : in out Session);
   --  Work left.
   --  @param S Session.
   --  @return The drawing work the budget still allows.
   function Work_Left (S : Session) return Pixel_Count is
     (S.Budget.Max_Drawing_Work - Pixel_Count'Min (S.Work_Used, S.Budget.Max_Drawing_Work));
   --  Charge work.
   --  @param S Session doing the work.
   --  @param Units Drawing work about to be done.
   --  @return Success, the work then counted, or Limit_Exceeded when it would cross the budget.
   function Charge_Work (S : in out Session; Units : Pixel_Count) return Results.Result;
   --  Charge work.
   --  @param S Session doing the work.
   --  @param Units Drawing work about to be done.
   --  @return As Charge_Work above.
   function Charge_Work (S : in out Session; Units : Natural) return Results.Result;
   --  Over work.
   --  @param S Session whose drawing budget was crossed.
   --  @param Units Work asked for beyond the work done.
   --  @return The Limit_Exceeded failure for drawing work, saturated: the one report of it.
   function Over_Work (S : Session; Units : Pixel_Count) return Results.Result;

   --  Allocations: each against Max_Allocation_Bytes, all of a session against Max_Total_Allocation_Bytes.

   --  Admit allocation.
   --  @param S Session about to allocate.
   --  @param Length Bytes of one allocation.
   --  @return Success, the bytes then counted against the session's total, or Limit_Exceeded when the
   --  allocation or the total would cross its limit.
   function Admit_Allocation (S : in out Session; Length : Byte_Count) return Results.Result;
   --  Admit aggregate.
   --  @param S Session about to hold storage that is not one allocation (vectors, copies).
   --  @param Length Bytes it is estimated at, by the cost model below.
   --  @return Success, the bytes then counted, or Limit_Exceeded when the session's total would cross its limit.
   function Admit_Aggregate (S : in out Session; Length : Byte_Count) return Results.Result;
   --  Shape work left.
   --  @param S Session.
   --  @return What building one shape may spend: the drawing work left, and no more than the spans the session's
   --  allocation total still admits.
   function Shape_Work_Left (S : Session) return Pixel_Count;

   --  The cost model: what storage that is not one allocation is counted at against the session's total.
   --  A retained metadata item or font name, besides its bytes.
   Item_Overhead_Bytes : constant := 128;
   --  A polygon point.
   Point_Cost_Bytes : constant := 8;
   --  A unit of a region's size, for a copy of it.
   Region_Unit_Bytes : constant := 8;
   --  Each byte of a region read: its scanlines and inversion points, with capacity growth.
   Region_Payload_Factor : constant := 4;
   --  A unit of shape-building work: the spans it can make.
   Shape_Bytes_Per_Work_Unit : constant := 256;

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
   --  Read RGB: an RGBColor, three 16-bit components.
   --  @param S Session reading an opcode's data.
   --  @param Color The high byte of each component.
   --  @return Operation result.
   function Read_RGB (S : in out Session; Color : out Images.RGB_Color) return Results.Result;
   --  Read polygon size.
   --  @param S Session positioned at a polygon's size word.
   --  @param Points The number of points the polygon holds, after its bounding box.
   --  @return Success, Polygon_Invalid for a size that is not 10 bytes plus whole points, or Limit_Exceeded past
   --  Max_Polygon_Points.
   function Read_Polygon_Size (S : in out Session; Points : out Natural) return Results.Result;

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

end Pictlib.Internal.Sessions;
