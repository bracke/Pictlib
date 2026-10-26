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

--  One picture's decoding session: the bounded stream, the decoding policy, warnings, the strictness rule and
--  the budget-checked readers every opcode's data goes through. Its children keep the rest: Accounting the
--  drawing work and allocations admitted, Retained the metadata kept.
package Pictlib.Internal.Sessions is
   --  What a session counts, kept by this package alone: allocations, drawing work, opcodes, and where the
   --  current opcode's data begins.
   type Counters is private;
   --  What a session keeps for its caller, reached only through this package: retained metadata and warnings.
   type Records is limited private;

   --  Tagged so its operations read as S.Budget, S.Version and the like.
   type Session is tagged limited private;

   --  Stream: the session's reader, for what is read outside an opcode's budget-checked data -- the header,
   --  the opcode words and pad bytes -- and for offsets.
   --  @param S Session.
   --  @return Its picture reader.
   function Stream (S : aliased in out Session) return not null access Picture_Stream.Reader;
   --  Offset.
   --  @param S Session.
   --  @return The source offset its reader has reached.
   function Offset (S : Session) return Source_Offset;
   --  Picture offset.
   --  @param S Session.
   --  @return The offset its reader has reached in the picture, after any file header.
   function Picture_Offset (S : Session) return Byte_Count;
   --  Budget.
   --  @param S Session.
   --  @return The limits it decodes under.
   function Budget (S : Session) return Limits.Limit_Set;
   --  Set budget.
   --  @param S Session, before it starts a picture.
   --  @param Budget The limits it decodes under.
   procedure Set_Budget (S : in out Session; Budget : Limits.Limit_Set);
   --  Version.
   --  @param S Session.
   --  @return The picture's version, once the header says it.
   function Version (S : Session) return PICT_Version;
   --  Set version.
   --  @param S Session reading the header.
   --  @param Version The version it found.
   procedure Set_Version (S : in out Session; Version : PICT_Version);
   --  Strictness.
   --  @param S Session.
   --  @return How deviations are treated.
   function Strictness (S : Session) return Strictness_Mode;
   --  Retention.
   --  @param S Session.
   --  @return What metadata it keeps.
   function Retention (S : Session) return Metadata.Retention_Policy;

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
   function Is_Lenient (S : Session) return Boolean;

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
   --  @return Outcome; a failure naming no opcode, or Event's, names Event's opcode and ordinal; one naming
   --  another opcode keeps it.
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

   --  Claim ordinal.
   --  @param S Session counting opcodes.
   --  @param Ordinal The next opcode ordinal.
   --  @return Success, or Limit_Exceeded when the opcode count limit is reached.
   function Claim_Ordinal (S : in out Session; Ordinal : out Opcode_Ordinal) return Results.Result;
   --  Opcodes read.
   --  @param S Session.
   --  @return The opcodes claimed so far: the ordinal the next one gets.
   function Opcodes_Read (S : Session) return Opcode_Ordinal;

   --  Begin opcode data: the current opcode's data, which the per-opcode budget bounds, begins here, and until
   --  End_Opcode_Data a warning that names no opcode names Event's.
   --  @param S Session positioned after an opcode.
   --  @param Event The opcode, with its ordinal.
   procedure Begin_Opcode_Data (S : in out Session; Event : Pictures.Opcode_Event);
   --  End opcode data: warnings no longer name the opcode Begin_Opcode_Data was given.
   --  @param S Session.
   procedure End_Opcode_Data (S : in out Session);
   --  Opcode data length.
   --  @param S Session.
   --  @return The bytes of the current opcode's data read or skipped since Begin_Opcode_Data.
   function Opcode_Data_Length (S : Session) return Byte_Count;

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
   --  @param In_Opcode False for data outside any opcode, which the per-opcode byte budget does not cover.
   --  @return Operation result.
   function Read_Payload
     (S : in out Session;
      Length : Byte_Count;
      Data : out Streams.Byte_Array_Access;
      In_Opcode : Boolean := True) return Results.Result;
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
   --  Read pair: a (v, h) pair of signed coordinates as read, without the origin: pen and oval sizes, angles,
   --  polygon points.
   --  @param S Session reading an opcode's data.
   --  @param V The first word.
   --  @param H The second.
   --  @return Operation result.
   function Read_Pair (S : in out Session; V, H : out Integer) return Results.Result;
   --  Read into.
   --  @param S Session reading an opcode's data.
   --  @param Buffer Filled completely within the per-opcode budget.
   --  @return Operation result.
   function Read_Into (S : in out Session; Buffer : out Streams.Byte_Array) return Results.Result;

   --  Warning count.
   --  @param S Session.
   --  @return Warnings recorded.
   function Warning_Count (S : Session) return Natural;
   --  Warning at.
   --  @param S Session.
   --  @param Index Warning index.
   --  @return The warning.
   function Warning_At (S : Session; Index : Positive) return Errors.Warning
     with Pre => Index <= Warning_Count (S);

private
   type Session is tagged limited record
      Stream : aliased Picture_Stream.Reader;
      Version : PICT_Version := Version_1;
      Strictness : Strictness_Mode := Strict;
      Retention : Metadata.Retention_Policy;
      Budget : Limits.Limit_Set := Limits.Default_Limits;
      Kept : Records;
      Counts : Counters;
   end record;

   type Records is limited record
      Store : Metadata_Store.Store;
      Log : Diagnostics.Warning_Log;
   end record;

   type Counters is record
      --  Allocations admitted this session, never given back.
      Total_Allocation_Bytes : Byte_Count := 0;
      --  Drawing work done in the current render.
      Work_Used : Pixel_Count := 0;
      Next_Ordinal : Opcode_Ordinal := 0;
      --  Picture offset where the current opcode's data begins.
      Data_Start : Byte_Count := 0;
      --  The opcode whose data is being read, between Begin_Opcode_Data and End_Opcode_Data.
      In_Opcode : Boolean := False;
      Current_Op : Opcode := 0;
      Current_Ordinal : Opcode_Ordinal := 0;
      --  An opcode the header reader read but did not consume.
      Has_Pending : Boolean := False;
      Pending_Op : Opcode := 0;
      Pending_Offset : Source_Offset := 0;
   end record;

   function Opcodes_Read (S : Session) return Opcode_Ordinal is (S.Counts.Next_Ordinal);
   function Stream (S : aliased in out Session) return not null access Picture_Stream.Reader is (S.Stream'Access);
   function Offset (S : Session) return Source_Offset is (S.Stream.Offset);
   function Picture_Offset (S : Session) return Byte_Count is (Picture_Stream.Picture_Offset (S.Stream));
   function Budget (S : Session) return Limits.Limit_Set is (S.Budget);
   function Version (S : Session) return PICT_Version is (S.Version);
   function Strictness (S : Session) return Strictness_Mode is (S.Strictness);
   function Retention (S : Session) return Metadata.Retention_Policy is (S.Retention);
   function Is_Lenient (S : Session) return Boolean is (S.Strictness /= Strict);
   function Warning_Count (S : Session) return Natural is (Diagnostics.Count (S.Kept.Log));
   function Warning_At (S : Session; Index : Positive) return Errors.Warning is
     (Diagnostics.Element (S.Kept.Log, Index));
end Pictlib.Internal.Sessions;
