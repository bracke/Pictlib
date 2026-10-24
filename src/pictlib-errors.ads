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

   type Warning_Severity is (Informational, Compatibility, Recovery, Data_Loss);

   type Diagnostic_Context is record
      Source : Source_Offset := 0;
      Destination : Destination_Offset := 0;
      Op : Opcode := 0;
      Has_Opcode : Boolean := False;
      Ordinal : Opcode_Ordinal := 0;
      Row : Row_Index := 0;
      Expected : Byte_Count := 0;
      Actual : Byte_Count := 0;
      Limit : Limit_Kind := No_Limit;
      Underlying_Code : Long_Long_Integer := 0;
      Has_Underlying_Code : Boolean := False;
   end record;

   type Error is record
      Code : Error_Code := No_Error;
      Identifier : Identifiers.Bounded_String := Identifiers.To_Bounded_String ("pict.ok");
      Context : Diagnostic_Context;
   end record;

   type Warning is record
      Code : Warning_Code := Generic_Warning;
      Identifier : Identifiers.Bounded_String := Identifiers.To_Bounded_String ("pict.warning");
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
   --  Make warning.
   --  @param Code Warning code.
   --  @param Severity Warning severity.
   --  @param Context Diagnostic context recorded with the warning.
   --  @return Warning carrying Code, its identifier, Severity and Context.
   function Make_Warning
     (Code : Warning_Code;
      Severity : Warning_Severity;
      Context : Diagnostic_Context := (others => <>)) return Warning;
   --  Is fatal.
   --  @param Item Error to inspect.
   --  @return True when Item reports a failure.
   function Is_Fatal (Item : Error) return Boolean is (Item.Code /= No_Error);
end Pictlib.Errors;
