with AUnit.Assertions;

with Pictlib;
with Pictlib.Capabilities;
with Pictlib.Errors;
with Pictlib.Limits;
with Pictlib.Results;
with Pictlib.Version;
with Pictlib_API_Consumer;

package body Pictlib_Testing.Test_Foundation is
   use AUnit.Assertions;
   use type Pictlib.Byte_Count;
   use type Pictlib.Coordinate;
   use type Pictlib.Destination_Offset;
   use type Pictlib.Errors.Error_Code;
   use type Pictlib.Errors.Warning_Code;
   use type Pictlib.Errors.Warning_Severity;
   use type Pictlib.Image_Height;
   use type Pictlib.Image_Width;
   use type Pictlib.Limit_Kind;
   use type Pictlib.Limits.Limit_Set;
   use type Pictlib.Opcode;
   use type Pictlib.Opcode_Ordinal;
   use type Pictlib.Pixel_Count;
   use type Pictlib.Results.Status;
   use type Pictlib.Row_Index;
   use type Pictlib.Source_Offset;

   --  Facts about the root types that the compiler can decide on its own.
   pragma Compile_Time_Error (Pictlib.Version.Current /= "0.1.0-dev", "version string changed");
   pragma Compile_Time_Error
     (Pictlib.Image_Width'First /= 1 or else Pictlib.Image_Height'First /= 1, "image dimensions must be positive");
   pragma Compile_Time_Error
     (Pictlib.Coordinate'First /= -32_768 or else Pictlib.Coordinate'Last /= 32_767,
      "coordinates must span QuickDraw's signed 16-bit space");
   pragma Compile_Time_Error (Pictlib.Opcode'Last /= 16#FFFF#, "opcodes must span 16 bits");
   pragma Compile_Time_Error
     (16 not in Pictlib.Pixel_Depth or else 3 in Pictlib.Pixel_Depth, "pixel depths must be QuickDraw's");

   procedure Root_And_Consumer_Compile (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Capabilities_Match_Implementation (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Results_Preserve_First_Error (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Error_Identifiers_And_Context (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Warning_Identifiers (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Defaults_Cover_Every_Limit (T : in out AUnit.Test_Cases.Test_Case'Class);

   overriding function Name (T : Test) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("foundation");
   end Name;

   overriding procedure Register_Tests (T : in out Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Root_And_Consumer_Compile'Access, "foundation.public_consumer");
      Register_Routine (T, Capabilities_Match_Implementation'Access, "foundation.capabilities");
      Register_Routine (T, Results_Preserve_First_Error'Access, "foundation.results.status_and_error");
      Register_Routine (T, Error_Identifiers_And_Context'Access, "foundation.errors.context");
      Register_Routine (T, Warning_Identifiers'Access, "foundation.errors.warnings");
      Register_Routine (T, Defaults_Cover_Every_Limit'Access, "foundation.limits.defaults");
   end Register_Tests;

   procedure Root_And_Consumer_Compile (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Pictlib.Results.Succeeded (Pictlib_API_Consumer.Success), "consumer success is not a success");
      Assert (not Pictlib.Errors.Is_Fatal (Pictlib_API_Consumer.No_Error), "consumer no-error is fatal");
      Assert (Pictlib_API_Consumer.Default_Limits = Pictlib.Limits.Default_Limits,
              "consumer sees different default limits");
   end Root_And_Consumer_Compile;

   procedure Capabilities_Match_Implementation (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Pictlib.Capabilities.Foundation_API, "foundation capability must be advertised");
      Assert (Pictlib_API_Consumer.Streams_Available, "memory streams must be advertised");
      Assert (not Pictlib.Capabilities.Container_Decoding, "container decoding is not implemented yet");
      Assert (not Pictlib.Capabilities.Opcode_Enumeration, "opcode enumeration is not implemented yet");
      Assert (not Pictlib.Capabilities.Raster_Decoding, "raster decoding is not implemented yet");
      Assert (not Pictlib.Capabilities.Vector_Rendering, "vector rendering is not implemented yet");
      Assert (not Pictlib.Capabilities.Text_Rendering, "text rendering is not implemented yet");
      Assert (not Pictlib.Capabilities.QuickTime_JPEG_Decoding, "QuickTime JPEG is not implemented yet");
      Assert (not Pictlib.Capabilities.Metadata_Retention, "metadata retention is not implemented yet");
      Assert (not Pictlib.Capabilities.Raster_Encoding, "raster encoding is not implemented yet");
   end Capabilities_Match_Implementation;

   procedure Results_Preserve_First_Error (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Good : constant Pictlib.Results.Result := Pictlib.Results.Success;
      Context : constant Pictlib.Errors.Diagnostic_Context :=
        (Source => 19, Op => 16#0098#, Has_Opcode => True, Ordinal => 3, others => <>);
      Expected : constant Pictlib.Errors.Error := Pictlib.Errors.Make (Pictlib.Errors.PackBits_Invalid, Context);
      Bad : constant Pictlib.Results.Result := Pictlib.Results.Failure (Expected);
      By_Code : constant Pictlib.Results.Result := Pictlib.Results.Failure (Pictlib.Errors.Invalid_State);
   begin
      Assert (Good.State = Pictlib.Results.Ok and then Pictlib.Results.Succeeded (Good),
              "success has the wrong status");
      Assert (not Pictlib.Errors.Is_Fatal (Good.First_Error), "success carries a fatal error");
      Assert (Bad.State = Pictlib.Results.Failed and then not Pictlib.Results.Succeeded (Bad),
              "failure has the wrong status");
      Assert (Bad.First_Error.Code = Pictlib.Errors.PackBits_Invalid, "failure lost its error code");
      Assert (Bad.First_Error.Context.Source = 19, "failure lost its source offset");
      Assert (Bad.First_Error.Context.Op = 16#0098# and then Bad.First_Error.Context.Ordinal = 3,
              "failure lost its opcode context");
      Assert (By_Code.First_Error.Code = Pictlib.Errors.Invalid_State
              and then Pictlib.Errors.Identifiers.To_String (By_Code.First_Error.Identifier) = "pict.state.invalid",
              "failure by code lost its identifier");
   end Results_Preserve_First_Error;

   procedure Error_Identifiers_And_Context (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Context : constant Pictlib.Errors.Diagnostic_Context :=
        (Source => 31,
         Destination => 7,
         Op => 16#009A#,
         Has_Opcode => True,
         Ordinal => 12,
         Row => 4,
         Expected => 12,
         Actual => 13,
         Limit => Pictlib.Region_Byte_Limit,
         Underlying_Code => 5,
         Has_Underlying_Code => True);
      Item : constant Pictlib.Errors.Error := Pictlib.Errors.Make (Pictlib.Errors.Region_Invalid, Context);
   begin
      for Code in Pictlib.Errors.Error_Code loop
         declare
            Identifier : constant String := Pictlib.Errors.Identifier_For (Code);
         begin
            Assert (Identifier'Length > 5 and then Identifier (Identifier'First .. Identifier'First + 4) = "pict.",
                    "malformed stable identifier for " & Code'Image);
            for Other in Pictlib.Errors.Error_Code range Code .. Pictlib.Errors.Error_Code'Last loop
               Assert (Other = Code or else Pictlib.Errors.Identifier_For (Other) /= Identifier,
                       "identifier shared by " & Code'Image & " and " & Other'Image);
            end loop;
         end;
      end loop;
      Assert (Pictlib.Errors.Identifier_For (Pictlib.Errors.No_Error) = "pict.ok", "ok identifier changed");
      Assert (Pictlib.Errors.Identifier_For (Pictlib.Errors.Limit_Exceeded) = "pict.limit.exceeded",
              "limit identifier changed");
      Assert (Pictlib.Errors.Identifier_For (Pictlib.Errors.Embedded_Image_Failed) = "pict.embedded_image.failed",
              "embedded image identifier changed");
      Assert (Pictlib.Errors.Is_Fatal (Item), "an error code must be fatal");
      Assert (Item.Context.Source = 31 and then Item.Context.Destination = 7, "offset context was lost");
      Assert (Item.Context.Has_Opcode and then Item.Context.Op = 16#009A# and then Item.Context.Ordinal = 12,
              "opcode context was lost");
      Assert (Item.Context.Row = 4 and then Item.Context.Expected = 12 and then Item.Context.Actual = 13,
              "row or count context was lost");
      Assert (Item.Context.Limit = Pictlib.Region_Byte_Limit, "limit context was lost");
      Assert (Item.Context.Has_Underlying_Code and then Item.Context.Underlying_Code = 5,
              "underlying code was lost");
   end Error_Identifiers_And_Context;

   procedure Warning_Identifiers (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Item : constant Pictlib.Errors.Warning :=
        Pictlib.Errors.Make_Warning
          (Pictlib.Errors.Reserved_Opcode_Skipped, Pictlib.Errors.Compatibility, (Op => 16#0024#, others => <>));
   begin
      for Code in Pictlib.Errors.Warning_Code loop
         declare
            Identifier : constant String := Pictlib.Errors.Identifier_For (Code);
         begin
            Assert (Identifier'Length >= 12 and then Identifier (Identifier'First .. Identifier'First + 11)
                      = "pict.warning",
                    "malformed warning identifier for " & Code'Image);
         end;
      end loop;
      Assert (Item.Code = Pictlib.Errors.Reserved_Opcode_Skipped
              and then Item.Severity = Pictlib.Errors.Compatibility
              and then Item.Context.Op = 16#0024#,
              "warning lost its code, severity or context");
      Assert (Pictlib.Errors.Identifiers.To_String (Item.Identifier) = "pict.warning.reserved_opcode",
              "warning identifier changed");
   end Warning_Identifiers;

   procedure Defaults_Cover_Every_Limit (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      L : constant Pictlib.Limits.Limit_Set := Pictlib.Limits.Default_Limits;
   begin
      Assert (L.Max_Frame_Width = 16_384 and then L.Max_Frame_Height = 16_384, "frame limits changed");
      Assert (L.Max_Canvas_Pixels > 0, "canvas pixel limit disabled");
      Assert (L.Max_Canvas_Bytes >= 4 * Pictlib.Byte_Count (L.Max_Canvas_Pixels),
              "canvas bytes cannot hold the RGBA canvas the pixel limit allows");
      Assert (L.Max_Picture_Bytes > 0, "picture byte limit disabled");
      Assert (L.Max_Opcodes > 0, "opcode count limit disabled");
      Assert (L.Max_Opcode_Bytes > 0 and then L.Max_Opcode_Bytes <= L.Max_Picture_Bytes,
              "opcode byte limit disabled or larger than a picture");
      Assert (L.Max_Region_Bytes > 0, "region limit disabled");
      Assert (L.Max_Polygon_Points > 0, "polygon limit disabled");
      Assert (L.Max_Drawing_Work > 0, "drawing work limit disabled");
      Assert (L.Max_Retained_Metadata_Bytes > 0, "metadata byte limit disabled");
      Assert (L.Max_Metadata_Items > 0, "metadata item limit disabled");
      Assert (L.Max_Allocation_Bytes > 0, "allocation limit disabled");
      Assert (L.Max_Output_Bytes > 0, "output limit disabled");
      Assert (L.Max_Embedded_Image_Bytes > 0, "embedded image byte limit disabled");
      Assert (L.Max_Embedded_Image_Pixels > 0, "embedded image pixel limit disabled");
      Assert (L.Max_Warning_Records > 0, "warning limit disabled");
   end Defaults_Cover_Every_Limit;
end Pictlib_Testing.Test_Foundation;
