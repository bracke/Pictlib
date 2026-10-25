with AUnit.Assertions;

with Pictlib;
with Pictlib.Capabilities;
with Pictlib.Errors;
with Pictlib.Limits;
with Pictlib.Results;
with Pictlib.Decoding;
with Pictlib.Images;
with Pictlib.Streams;
with Pictlib.Version;
with Pictlib_API_Consumer;
with Pictlib_Testing.Builders;
with Pictlib_Testing.Canvases;
with Pictlib_Testing.Files;
with Pictlib_Testing.Fonts;
with Pictlib_Testing.Recorders;
with Pictlib_Testing.Samples;

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

   --  Each capability is advertised exactly when a probe of its feature, through the public API, works: an
   --  advertised feature that fails, or a working one left unadvertised, is a mismatch.
   procedure Capabilities_Match_Implementation (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      use Pictlib_Testing.Builders;
      use type Pictlib.Images.RGB_Color;
      use type Pictlib.PICT_Version;
      use type Pictlib.Streams.Byte_Array;

      --  Render Input, Width x Height, strictly with the test fonts; Output receives its letters.
      function Renders (Input : aliased Bytes; Width, Height : Positive; Output : out Pictlib.Images.Mutable_Image_View)
        return Boolean
      is
         Storage : constant Pictlib.Streams.Byte_Array_Access := new Bytes'[1 .. 3 * Width * Height => 0];
         Decoder : Pictlib.Decoding.Decoder;
         Outcome : Pictlib.Results.Result;
      begin
         Output := Canvases.View (Storage, Width, Height);
         Canvases.Render (Input, Decoder, Output, Outcome, (Fonts => Fonts.Test_Table, others => <>));
         return Pictlib.Results.Succeeded (Outcome);
      end Renders;

      Painted : aliased constant Bytes := Pic (4, 1, Op_Rect (16#31#, 0, 0, 1, 2));
      Copied : aliased constant Bytes := Pic (8, 2, Bitmap_2x8);
      --  LongText "Hi" at (15, 2), padded to an even length.
      Written : aliased constant Bytes :=
        Pic (24, 20, W (16#28#) & W (15) & W (2) & B (2) & Text ("Hi") & B (0));
      Compressed : aliased constant Bytes :=
        Pic (8, 6, QuickTime ("jpeg", 8, 6, Files.Load ("external/small.jpg").all));
      Commented : aliased constant Bytes := Pic (4, 1, W (16#A0#) & W (200));
      Output : Pictlib.Images.Mutable_Image_View;

      function Container_Works return Boolean is
         Decoder : Pictlib.Decoding.Decoder;
      begin
         Recorders.Start (Painted, Decoder);
         return Pictlib.Results.Succeeded (Pictlib.Decoding.Read_Header (Decoder))
           and then Pictlib.Decoding.Header (Decoder).Version = Pictlib.Extended_Version_2;
      end Container_Works;

      function Enumeration_Works return Boolean is
         Decoder : Pictlib.Decoding.Decoder;
         Events : Recorders.Recorder;
         Outcome : Pictlib.Results.Result;
      begin
         Recorders.Decode (Painted, Decoder, Events, Outcome);
         return Pictlib.Results.Succeeded (Outcome)
           and then (for some Item of Events.Events => Item.Op = 16#31#);
      end Enumeration_Works;

      function Metadata_Works return Boolean is
         Decoder : Pictlib.Decoding.Decoder;
         Events : Recorders.Recorder;
         Outcome : Pictlib.Results.Result;
      begin
         Recorders.Decode (Commented, Decoder, Events, Outcome);
         return Pictlib.Results.Succeeded (Outcome) and then Pictlib.Decoding.Metadata_Count (Decoder) = 1;
      end Metadata_Works;

      function Text_Works return Boolean is
      begin
         return Renders (Written, 24, 20, Output)
           and then (for some Y in 0 .. 19 =>
                       (for some X in 0 .. 23 => Canvases.Pixel (Output, X, Y) /= Pictlib.Images.White));
      end Text_Works;

      function JPEG_Works return Boolean is
      begin
         --  The fixture is not one color, so a drawn image leaves no white canvas behind.
         return Renders (Compressed, 8, 6, Output)
           and then (for some X in 0 .. 7 => Canvases.Pixel (Output, X, 0) /= Canvases.Pixel (Output, 0, 5));
      end JPEG_Works;

      function Encoding_Works return Boolean is
         Picture : constant Samples.Encoded := Samples.Encode (Samples.Three_Colors, 4, 4);
      begin
         return Pictlib.Results.Succeeded (Picture.Outcome)
           and then Renders (Picture.Data.all, 4, 4, Output)
           and then (for all Y in 0 .. 3 =>
                       (for all X in 0 .. 3 =>
                          Canvases.Pixel (Output, X, Y) = Samples.Color (Samples.Three_Colors, X, Y)));
      end Encoding_Works;
   begin
      Assert (Pictlib.Capabilities.Foundation_API, "foundation capability must be advertised");
      Assert (Pictlib.Capabilities.Memory_Streams and then Pictlib_API_Consumer.Streams_Available,
              "memory streams must be advertised, to a consumer too");
      Assert (Pictlib.Capabilities.Container_Decoding = Container_Works, "container decoding is misadvertised");
      Assert (Pictlib.Capabilities.Opcode_Enumeration = Enumeration_Works, "opcode enumeration is misadvertised");
      Assert (Pictlib.Capabilities.Raster_Decoding
              = (Renders (Copied, 8, 2, Output) and then Canvases.Picture_Of (Output) = "BWBWWBWB/WWWWBBBB"),
              "raster decoding is misadvertised");
      Assert (Pictlib.Capabilities.Vector_Rendering
              = (Renders (Painted, 4, 1, Output) and then Canvases.Picture_Of (Output) = "BBWW"),
              "vector rendering is misadvertised");
      Assert (Pictlib.Capabilities.Text_Rendering = Text_Works, "text rendering is misadvertised");
      Assert (Pictlib.Capabilities.QuickTime_JPEG_Decoding = JPEG_Works, "QuickTime JPEG is misadvertised");
      Assert (Pictlib.Capabilities.Metadata_Retention = Metadata_Works, "metadata retention is misadvertised");
      Assert (Pictlib.Capabilities.Raster_Encoding = Encoding_Works, "raster encoding is misadvertised");
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
         Has_Row => True,
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
      Assert (L.Max_Output_Bytes >= 4 * Pictlib.Byte_Count (L.Max_Canvas_Pixels),
              "the output limit cannot hold the RGBA view the canvas pixel limit allows");
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
      Assert (L.Max_Total_Allocation_Bytes = Pictlib.Byte_Count'Last, "the session allocation total is limited");
      Assert (L.Max_Output_Bytes > 0, "output limit disabled");
      Assert (L.Max_Embedded_Image_Bytes > 0, "embedded image byte limit disabled");
      Assert (L.Max_Embedded_Image_Pixels > 0, "embedded image pixel limit disabled");
      Assert (L.Max_Warning_Records > 0, "warning limit disabled");
   end Defaults_Cover_Every_Limit;
end Pictlib_Testing.Test_Foundation;
