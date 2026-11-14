package body Pictlib.Errors is
   --  The identifier as a bounded string, built from its literal: a result is made for every call that
   --  succeeds, and going through an unconstrained String would put each on the secondary stack.
   function Identifier_Of (Code : Error_Code) return Identifiers.Bounded_String is
   begin
      case Code is
         when No_Error                  => return Identifiers.To_Bounded_String ("pict.ok");
         when Source_Read_Failed        => return Identifiers.To_Bounded_String ("pict.source.read_failed");
         when Source_Unexpected_End     => return Identifiers.To_Bounded_String ("pict.source.unexpected_end");
         when Source_Zero_Progress      => return Identifiers.To_Bounded_String ("pict.source.zero_progress");
         when Destination_Write_Failed  => return Identifiers.To_Bounded_String ("pict.destination.write_failed");
         when Destination_Zero_Progress => return Identifiers.To_Bounded_String ("pict.destination.zero_progress");
         when Header_Invalid            => return Identifiers.To_Bounded_String ("pict.header.invalid");
         when Version_Invalid           => return Identifiers.To_Bounded_String ("pict.version.invalid");
         when Opcode_Invalid            => return Identifiers.To_Bounded_String ("pict.opcode.invalid");
         when Opcode_Length_Invalid     => return Identifiers.To_Bounded_String ("pict.opcode.length_invalid");
         when Region_Invalid            => return Identifiers.To_Bounded_String ("pict.region.invalid");
         when Polygon_Invalid           => return Identifiers.To_Bounded_String ("pict.polygon.invalid");
         when Pixmap_Invalid            => return Identifiers.To_Bounded_String ("pict.pixmap.invalid");
         when PackBits_Invalid          => return Identifiers.To_Bounded_String ("pict.packbits.invalid");
         when Color_Table_Invalid       => return Identifiers.To_Bounded_String ("pict.color_table.invalid");
         when Pattern_Invalid           => return Identifiers.To_Bounded_String ("pict.pattern.invalid");
         when Transfer_Mode_Invalid     => return Identifiers.To_Bounded_String ("pict.transfer_mode.invalid");
         when Embedded_Image_Failed     => return Identifiers.To_Bounded_String ("pict.embedded_image.failed");
         when Font_Unavailable          => return Identifiers.To_Bounded_String ("pict.font.unavailable");
         when Too_Many_Colors           => return Identifiers.To_Bounded_String ("pict.encoder.too_many_colors");
         when Missing_End_Opcode        => return Identifiers.To_Bounded_String ("pict.opcode.missing_end");
         when Trailing_Data             => return Identifiers.To_Bounded_String ("pict.trailing_data");
         when Unsupported_Feature       => return Identifiers.To_Bounded_String ("pict.feature.unsupported");
         when Invalid_State             => return Identifiers.To_Bounded_String ("pict.state.invalid");
         when Invalid_Argument          => return Identifiers.To_Bounded_String ("pict.argument.invalid");
         when Integer_Overflow          => return Identifiers.To_Bounded_String ("pict.security.integer_overflow");
         when Limit_Exceeded            => return Identifiers.To_Bounded_String ("pict.limit.exceeded");
         when Operation_Cancelled       => return Identifiers.To_Bounded_String ("pict.operation.cancelled");
         when Internal_Invariant_Failed => return Identifiers.To_Bounded_String ("pict.internal.invariant_failed");
      end case;
   end Identifier_Of;

   function Identifier_For (Code : Error_Code) return String is (Identifiers.To_String (Identifier_Of (Code)));

   function Identifier_For (Code : Warning_Code) return String is
   begin
      case Code is
         when Generic_Warning         => return "pict.warning";
         when Compatibility_Issue     => return "pict.warning.compatibility";
         when Recovery_Applied        => return "pict.warning.recovery";
         when Reserved_Opcode_Skipped => return "pict.warning.reserved_opcode";
         when Approximated_Rendering  => return "pict.warning.approximated";
         when Partial_Picture         => return "pict.warning.partial_picture";
         when Data_Loss               => return "pict.warning.data_loss";
         when Warnings_Suppressed     => return "pict.warning.suppressed";
      end case;
   end Identifier_For;

   function Make (Code : Error_Code; Context : Diagnostic_Context := (others => <>)) return Error is
   begin
      return
        (Code => Code,
         Identifier => Identifier_Of (Code),
         Context => Context);
   end Make;

   function Severity_Of (Code : Warning_Code) return Warning_Severity is
     (case Code is
         when Generic_Warning | Reserved_Opcode_Skipped => Informational,
         when Compatibility_Issue => Compatibility,
         when Recovery_Applied => Recovery,
         when Approximated_Rendering | Partial_Picture | Data_Loss | Warnings_Suppressed => Data_Loss);

   function Make_Warning (Code : Warning_Code; Context : Diagnostic_Context := (others => <>)) return Warning is
   begin
      return
        (Code => Code,
         Identifier => Identifiers.To_Bounded_String (Identifier_For (Code)),
         Severity => Severity_Of (Code),
         Context => Context);
   end Make_Warning;
end Pictlib.Errors;
