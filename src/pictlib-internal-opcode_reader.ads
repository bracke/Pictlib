with Pictlib.Errors;
with Pictlib.Internal.Diagnostics;
with Pictlib.Internal.Metadata_Store;
with Pictlib.Internal.Picture_Stream;
with Pictlib.Limits;
with Pictlib.Metadata;
with Pictlib.Pictures;
with Pictlib.Results;

--  Steps through a picture's opcode stream: reads each opcode, consumes its data by the opcode's length
--  rule within the configured budgets, aligns version 2 opcodes, and retains the metadata the policy asks for.
package Pictlib.Internal.Opcode_Reader is
   type Session is limited record
      Stream : Picture_Stream.Reader;
      Version : PICT_Version := Version_1;
      Strictness : Strictness_Mode := Strict;
      Retention : Metadata.Retention_Policy;
      Budget : Limits.Limit_Set := Limits.Default_Limits;
      Store : Metadata_Store.Store;
      Log : Diagnostics.Warning_Log;
      Next_Ordinal : Opcode_Ordinal := 0;
      --  Picture offset where the current opcode's data begins.
      Data_Start : Byte_Count := 0;
      --  An opcode the header reader read but did not consume.
      Has_Pending : Boolean := False;
      Pending_Op : Opcode := 0;
      Pending_Offset : Source_Offset := 0;
   end record;

   --  Clear.
   --  @param S Session whose stream binding, retained metadata, warnings and counters are discarded.
   procedure Clear (S : in out Session);

   --  Warn.
   --  @param S Session whose log records the warning.
   --  @param Code Warning code.
   --  @param Severity Warning severity.
   --  @param Context Diagnostic context.
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

   --  Claim ordinal.
   --  @param S Session counting opcodes.
   --  @param Ordinal The next opcode ordinal.
   --  @return Success, or Limit_Exceeded when the opcode count limit is reached.
   function Claim_Ordinal (S : in out Session; Ordinal : out Opcode_Ordinal) return Results.Result;

   --  Retain.
   --  @param S Session whose store receives the item.
   --  @param Info Item description.
   --  @param Length Data bytes to read from the stream into the item.
   --  @return Success (also when a lenient session drops the item with a Data_Loss warning), or the failure.
   function Retain (S : in out Session; Info : Metadata.Item_Info; Length : Byte_Count) return Results.Result;

   --  Next.
   --  @param S Session positioned at an opcode boundary.
   --  @param Event The opcode read, after its data was consumed.
   --  @param At_End_Of_Input True when the input ended at the boundary; Event is then not meaningful.
   --  @return Success, or the failure with the opcode and ordinal in its context.
   function Next
     (S : in out Session;
      Event : out Pictures.Opcode_Event;
      At_End_Of_Input : out Boolean) return Results.Result;
end Pictlib.Internal.Opcode_Reader;
