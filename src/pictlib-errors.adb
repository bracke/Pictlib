package body Pictlib.Errors is
   function Identifier_For (Code : Error_Code) return String is
   begin
      case Code is
         when No_Error                  => return "pict.ok";
         when Source_Read_Failed        => return "pict.source.read_failed";
         when Source_Unexpected_End     => return "pict.source.unexpected_end";
         when Source_Zero_Progress      => return "pict.source.zero_progress";
         when Destination_Write_Failed  => return "pict.destination.write_failed";
         when Destination_Zero_Progress => return "pict.destination.zero_progress";
         when Header_Invalid            => return "pict.header.invalid";
         when Version_Invalid           => return "pict.version.invalid";
         when Opcode_Invalid            => return "pict.opcode.invalid";
         when Opcode_Length_Invalid     => return "pict.opcode.length_invalid";
         when Region_Invalid            => return "pict.region.invalid";
         when Polygon_Invalid           => return "pict.polygon.invalid";
         when Pixmap_Invalid            => return "pict.pixmap.invalid";
         when PackBits_Invalid          => return "pict.packbits.invalid";
         when Color_Table_Invalid       => return "pict.color_table.invalid";
         when Pattern_Invalid           => return "pict.pattern.invalid";
         when Transfer_Mode_Invalid     => return "pict.transfer_mode.invalid";
         when Embedded_Image_Failed     => return "pict.embedded_image.failed";
         when Font_Unavailable          => return "pict.font.unavailable";
         when Too_Many_Colors           => return "pict.encoder.too_many_colors";
         when Missing_End_Opcode        => return "pict.opcode.missing_end";
         when Trailing_Data             => return "pict.trailing_data";
         when Unsupported_Feature       => return "pict.feature.unsupported";
         when Invalid_State             => return "pict.state.invalid";
         when Invalid_Argument          => return "pict.argument.invalid";
         when Integer_Overflow          => return "pict.security.integer_overflow";
         when Limit_Exceeded            => return "pict.limit.exceeded";
         when Operation_Cancelled       => return "pict.operation.cancelled";
         when Internal_Invariant_Failed => return "pict.internal.invariant_failed";
      end case;
   end Identifier_For;

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
         Identifier => Identifiers.To_Bounded_String (Identifier_For (Code)),
         Context => Context);
   end Make;

   function Make_Warning
     (Code : Warning_Code;
      Severity : Warning_Severity;
      Context : Diagnostic_Context := (others => <>)) return Warning
   is
   begin
      return
        (Code => Code,
         Identifier => Identifiers.To_Bounded_String (Identifier_For (Code)),
         Severity => Severity,
         Context => Context);
   end Make_Warning;
end Pictlib.Errors;
