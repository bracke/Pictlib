with Ada.Strings.Bounded;

package Pictlib.Errors is
   pragma Preelaborate;

   package Identifiers is new Ada.Strings.Bounded.Generic_Bounded_Length (Max => 96);

   type Error_Code is
     (No_Error,
      Source_Read_Failed,
      Source_Unexpected_End,
      Source_Zero_Progress,
      Destination_Write_Failed,
      Destination_Zero_Progress,
      Header_Invalid,
      Version_Invalid,
      Opcode_Invalid,
      Opcode_Length_Invalid,
      Region_Invalid,
      Polygon_Invalid,
      Pixmap_Invalid,
      PackBits_Invalid,
      Color_Table_Invalid,
      Pattern_Invalid,
      Transfer_Mode_Invalid,
      Embedded_Image_Failed,
      Font_Unavailable,
      Too_Many_Colors,
      Missing_End_Opcode,
      Trailing_Data,
      Unsupported_Feature,
      Invalid_State,
      Invalid_Argument,
      Integer_Overflow,
      Limit_Exceeded,
      Operation_Cancelled,
      Internal_Invariant_Failed);

   type Warning_Code is
     (Generic_Warning,
      Compatibility_Issue,
      Recovery_Applied,
      Reserved_Opcode_Skipped,
      Approximated_Rendering,
      Partial_Picture,
      Data_Loss,
      Warnings_Suppressed);

   --  How much a warning matters: a note, a picture read as an old reader would, a failure recovered from, or
   --  something not drawn or kept. Severity_Of gives each code's.
   type Warning_Severity is (Informational, Compatibility, Recovery, Data_Loss);

   --  Where a failure or warning arose and what it judged.
   type Diagnostic_Context is record
      --  The source offset where reading stood, or of the opcode judged as a whole.
      Source : Source_Offset := 0;
      --  The encoder's destination offset.
      Destination : Destination_Offset := 0;
      --  The opcode whose data was read, when Has_Opcode.
      Op : Opcode := 0;
      Has_Opcode : Boolean := False;
      --  The opcode's position in the picture's opcode stream.
      Ordinal : Opcode_Ordinal := 0;
      --  The row of a copy's pixel data, from 0, when Has_Row.
      Row : Row_Index := 0;
      --  Whether Row names a row: row 0 is a row too.
      Has_Row : Boolean := False;
      --  The bound or requirement a value was checked against: a limit, what the format requires, or the length
      --  of what must hold it (an opcode, a view, a caller's buffer or storage).
      Expected : Byte_Count := 0;
      --  What the input, content or request came to.
      Actual : Byte_Count := 0;
      --  The limit exceeded, for Limit_Exceeded.
      Limit : Limit_Kind := No_Limit;
      --  A dependency's own code, when Has_Underlying_Code: jpeglib's Error_Code position for an embedded JPEG.
      Underlying_Code : Long_Long_Integer := 0;
      Has_Underlying_Code : Boolean := False;
   end record;

   --  A failure, or No_Error, as Make builds it.
   type Error is record
      Code : Error_Code := No_Error;
      --  Identifier_For (Code), a stable dotted string.
      Identifier : Identifiers.Bounded_String := Identifiers.To_Bounded_String ("pict.ok");
      Context : Diagnostic_Context;
   end record;

   --  A warning, as Make_Warning builds it.
   type Warning is record
      Code : Warning_Code := Generic_Warning;
      --  Identifier_For (Code), a stable dotted string.
      Identifier : Identifiers.Bounded_String := Identifiers.To_Bounded_String ("pict.warning");
      --  Severity_Of (Code).
      Severity : Warning_Severity := Informational;
      Context : Diagnostic_Context;
   end record;

   --  Identifier for.
   --  @param Code Error code to name.
   --  @return Stable dotted identifier of Code.
   function Identifier_For (Code : Error_Code) return String;
   --  Identifier for.
   --  @param Code Warning code to name.
   --  @return Stable dotted identifier of Code.
   function Identifier_For (Code : Warning_Code) return String;
   --  Make.
   --  @param Code Error code.
   --  @param Context Diagnostic context recorded with the error.
   --  @return Error carrying Code, its identifier and Context.
   function Make (Code : Error_Code; Context : Diagnostic_Context := (others => <>)) return Error;
   --  Severity of.
   --  @param Code Warning code.
   --  @return The severity every warning of Code has: Informational for a reserved opcode skipped and the
   --  default Generic_Warning, Compatibility for a compatibility issue, Recovery for a recovery applied, and
   --  Data_Loss for the rest.
   function Severity_Of (Code : Warning_Code) return Warning_Severity;
   --  Make warning.
   --  @param Code Warning code.
   --  @param Context Diagnostic context recorded with the warning.
   --  @return Warning carrying Code, its identifier, its fixed severity and Context.
   function Make_Warning (Code : Warning_Code; Context : Diagnostic_Context := (others => <>)) return Warning;
   --  Is fatal.
   --  @param Item Error to inspect.
   --  @return True when Item reports a failure.
   function Is_Fatal (Item : Error) return Boolean is (Item.Code /= No_Error);
end Pictlib.Errors;
