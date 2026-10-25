with AUnit.Assertions;

with Pictlib;
with Pictlib.Decoding;
with Pictlib.Encoding;
with Pictlib.Errors;
with Pictlib.Fonts;
with Pictlib.Images;
with Pictlib.Limits;
with Pictlib.Results;
with Pictlib.Streams;
with Pictlib_Testing.Builders;
with Pictlib_Testing.Canvases;
with Pictlib_Testing.Files;
with Pictlib_Testing.Fonts;
with Pictlib_Testing.Recorders;
with Pictlib_Testing.Samples;

package body Pictlib_Testing.Test_Stress is
   use AUnit.Assertions;
   use Pictlib_Testing.Builders;
   use type Pictlib.Errors.Error_Code;
   use type Pictlib.Byte_Count;
   use type Pictlib.Limit_Kind;
   use type Pictlib.Row_Stride;
   use type Pictlib.Streams.Byte_Array;

   package Decoding renames Pictlib.Decoding;

   subtype Null_Visitor is Recorders.Null_Visitor;

   function Fonts return Pictlib.Fonts.Font_Table renames Pictlib_Testing.Fonts.Test_Table;

   --  A picture that exercises every renderer path: a copy, shapes, a pattern, text and a QuickTime JPEG.
   function Everything return Bytes is
     (V2_Picture
        (0, 0, 24, 48,
         W (16#01#) & Region (0, 0, 24, 48)
         & W (16#1A#) & W (16#FFFF#) & W (0) & W (0) & W (16#51#) & Rect (2, 2, 20, 30)
         & W (16#1A#) & W (0) & W (0) & W (0)
         & W (16#0A#) & Checker
         & W (16#34#) & Rect (4, 30, 20, 46)
         & Bitmap_2x8 (Destination => Rect (22, 0, 24, 8))
         & W (16#28#) & W (18) & W (4) & B (2) & Text ("Hi") & B (0)
         & QuickTime ("jpeg", 8, 6, Files.Load ("external/small.jpg").all, Move_H => 36 * 16#1_0000#,
                      Move_V => 16#1_0000#)));

   --  Render Input with a fresh decoder and source of its own, so tasks can render at once, returning the RGB
   --  pixels. Canvases.Render binds the one shared source of Recorders.Start, so concurrent tasks cannot use it.
   function Render (Input : Bytes; Width, Height : Positive) return Bytes is
      Data : aliased constant Bytes := Input;
      Source : aliased Pictlib.Streams.Memory_Source;
      Decoder : Decoding.Decoder;
      Storage : aliased Bytes := [1 .. 3 * Width * Height => 0];
      Outcome : Pictlib.Results.Result;
   begin
      Pictlib.Streams.Open (Source, Data'Unchecked_Access);
      Decoding.Initialize (Decoder, Source'Access, (Fonts => Fonts, others => <>));
      Outcome := Decoding.Read_Header (Decoder);
      if Pictlib.Results.Succeeded (Outcome) then
         Outcome := Decoding.Render (Decoder, Canvases.View (Storage'Access, Width, Height));
      end if;
      Assert (Pictlib.Results.Succeeded (Outcome), "render failed with " & Outcome.First_Error.Code'Image);
      return Storage;
   end Render;

   procedure Reuse (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Concurrency (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Limit_Matrix (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Large_Inputs (T : in out AUnit.Test_Cases.Test_Case'Class);

   overriding function Name (T : Test) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("stress");
   end Name;

   overriding procedure Register_Tests (T : in out Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Reuse'Access, "stress.reset_reuse");
      Register_Routine (T, Concurrency'Access, "stress.independent_decoders_in_tasks");
      Register_Routine (T, Limit_Matrix'Access, "stress.limit_matrix");
      Register_Routine (T, Large_Inputs'Access, "stress.large_inputs");
   end Register_Tests;

   --  One decoder, reset between pictures of every kind, renders as fresh decoders do.
   procedure Reuse (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Picture : aliased constant Bytes := Everything;
      Broken : aliased constant Bytes := V2_Prefix (0, 0, 24, 48) & W (16#0001#) & W (4);
      Expected : constant Bytes := Render (Picture, 48, 24);
      Source : aliased Pictlib.Streams.Memory_Source;
      Decoder : Decoding.Decoder;
      Storage : aliased Bytes := [1 .. 3 * 48 * 24 => 0];
      View : constant Pictlib.Images.Mutable_Image_View := Canvases.View (Storage'Access, 48, 24);
      Visitor : Null_Visitor;
      Outcome : Pictlib.Results.Result;
   begin
      Pictlib.Streams.Open (Source, Picture'Unchecked_Access);
      Decoding.Initialize (Decoder, Source'Access, (Fonts => Fonts, others => <>));
      for Round in 1 .. 30 loop
         case Round mod 3 is
            when 0 =>
               Pictlib.Streams.Open (Source, Broken'Unchecked_Access);
               Decoding.Reset (Decoder, Source'Access);
               Outcome := Decoding.Read_Header (Decoder);
               Outcome := Decoding.Enumerate (Decoder, Visitor);
               Assert (Outcome.First_Error.Code = Pictlib.Errors.Region_Invalid, "the broken picture changed");
            when 1 =>
               Pictlib.Streams.Open (Source, Picture'Unchecked_Access);
               Decoding.Reset (Decoder, Source'Access);
               Outcome := Decoding.Read_Header (Decoder);
               --  A sentinel, so a render that writes nothing cannot pass on the last round's pixels.
               Storage := [others => 16#EE#];
               Outcome := Decoding.Render (Decoder, View);
               Assert (Pictlib.Results.Succeeded (Outcome) and then Storage = Expected,
                       "a reused decoder rendered differently in round" & Round'Image);
            when others =>
               Pictlib.Streams.Open (Source, Picture'Unchecked_Access);
               Decoding.Reset (Decoder, Source'Access);
               Outcome := Decoding.Read_Header (Decoder);
               Decoding.Cancel (Decoder);
               Assert (Decoding.Render (Decoder, View).First_Error.Code = Pictlib.Errors.Operation_Cancelled,
                       "cancel was lost on reuse");
         end case;
      end loop;
      Decoding.Finalize (Decoder);
   end Reuse;

   --  Independent decoders share no state: four tasks render the same picture at once.
   procedure Concurrency (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Picture : constant Bytes := Everything;
      Expected : constant Bytes := Render (Picture, 48, 24);
      type Outcome_Array is array (1 .. 4) of Boolean;
      Same : Outcome_Array := [others => False];

      task type Worker is
         entry Start (Index : Positive);
      end Worker;

      task body Worker is
         Slot : Positive;
      begin
         accept Start (Index : Positive) do
            Slot := Index;
         end Start;
         declare
            Matches : Boolean := True;
         begin
            for Round in 1 .. 10 loop
               Matches := Matches and then Render (Picture, 48, 24) = Expected;
            end loop;
            Same (Slot) := Matches;
         end;
      end Worker;
   begin
      declare
         Workers : array (1 .. 4) of Worker;
      begin
         for Index in Workers'Range loop
            Workers (Index).Start (Index);
         end loop;
      end;
      Assert ((for all Item of Same => Item), "decoders in different tasks rendered differently");
   end Concurrency;

   --  Every limit kind is reported as itself by some input.
   procedure Limit_Matrix (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Defaults : constant Pictlib.Limits.Limit_Set := Pictlib.Limits.Default_Limits;
      Picture : constant Bytes := Everything;
      Retained : constant Decoding.Options :=
        (Fonts => Fonts, Retention => (others => True), others => <>);
      --  Warning_Record_Limit names a cap that is never crossed: its call checks the cap keeps nothing.
      Seen : array (Pictlib.Limit_Kind) of Boolean :=
        [Pictlib.No_Limit | Pictlib.Warning_Record_Limit => True, others => False];

      --  Decode under Budget, expecting Expected to be reported, or success when it is No_Limit.
      procedure Decode
        (Budget : Pictlib.Limits.Limit_Set;
         Options : Decoding.Options;
         Render_It : Boolean;
         Expected : Pictlib.Limit_Kind)
      is
         Data : aliased constant Bytes := Picture;
         Source : aliased Pictlib.Streams.Memory_Source;
         Decoder : Decoding.Decoder;
         Visitor : Null_Visitor;
         Storage : aliased Bytes := [1 .. 3 * 48 * 24 => 0];
         Outcome : Pictlib.Results.Result;
      begin
         Pictlib.Streams.Open (Source, Data'Unchecked_Access);
         Decoding.Initialize (Decoder, Source'Access, Options, Budget);
         Outcome := Decoding.Read_Header (Decoder);
         if Pictlib.Results.Succeeded (Outcome) then
            Outcome :=
              (if Render_It then Decoding.Render (Decoder, Canvases.View (Storage'Access, 48, 24))
               else Decoding.Enumerate (Decoder, Visitor));
         end if;
         if Expected = Pictlib.No_Limit then
            Assert (Pictlib.Results.Succeeded (Outcome),
                    "an unlimited decode failed: " & Outcome.First_Error.Code'Image);
         else
            Assert (Outcome.First_Error.Code = Pictlib.Errors.Limit_Exceeded
                    and then Outcome.First_Error.Context.Limit = Expected,
                    "a budget for " & Expected'Image & " reported " & Outcome.First_Error.Code'Image & " "
                    & Outcome.First_Error.Context.Limit'Image);
            Seen (Expected) := True;
         end if;
         if Budget.Max_Warning_Records = 0 then
            --  Warnings are capped, not failed: a zero cap keeps none.
            Assert (Decoding.Warning_Count (Decoder) = 0, "a zero warning cap kept a warning");
         end if;
      end Decode;

      procedure Encode (Budget : Pictlib.Limits.Limit_Set) is
         Source : constant Samples.Bytes_Access := Samples.Make (Samples.Gradient, 40, 4);
         Storage : constant Pictlib.Streams.Byte_Array_Access := new Bytes (1 .. 10_000);
         Output : aliased Pictlib.Streams.Fixed_Buffer_Destination;
         Encoder : Pictlib.Encoding.Encoder;
         Outcome : Pictlib.Results.Result;
      begin
         Pictlib.Streams.Open (Output, Storage);
         Pictlib.Encoding.Initialize (Encoder, Output'Access, Encode_Limits => Budget);
         Outcome := Pictlib.Encoding.Encode (Encoder, Samples.View (Source, 40, 4));
         Assert (Outcome.First_Error.Code = Pictlib.Errors.Limit_Exceeded
                 and then Outcome.First_Error.Context.Limit = Pictlib.Output_Byte_Limit,
                 "the encoder's output budget reported " & Outcome.First_Error.Context.Limit'Image);
      end Encode;
   begin
      Decode ((Defaults with delta Max_Frame_Width => 47), Retained, False, Pictlib.Frame_Width_Limit);
      Decode ((Defaults with delta Max_Frame_Height => 23), Retained, False, Pictlib.Frame_Height_Limit);
      Decode ((Defaults with delta Max_Canvas_Pixels => 100), Retained, True, Pictlib.Canvas_Pixel_Limit);
      Decode ((Defaults with delta Max_Picture_Bytes => 100), Retained, False, Pictlib.Picture_Byte_Limit);
      Decode ((Defaults with delta Max_Opcodes => 4), Retained, False, Pictlib.Opcode_Count_Limit);
      Decode ((Defaults with delta Max_Opcode_Bytes => 20), Retained, False, Pictlib.Opcode_Byte_Limit);
      Decode ((Defaults with delta Max_Region_Bytes => 9), Retained, False, Pictlib.Region_Byte_Limit);
      Decode ((Defaults with delta Max_Drawing_Work => 100), Retained, True, Pictlib.Drawing_Work_Limit);
      Decode ((Defaults with delta Max_Retained_Metadata_Bytes => 3), Retained, False,
              Pictlib.Retained_Metadata_Byte_Limit);
      Decode ((Defaults with delta Max_Metadata_Items => 0), Retained, False, Pictlib.Metadata_Item_Limit);
      Decode ((Defaults with delta Max_Allocation_Bytes => 100), Retained, True, Pictlib.Allocation_Byte_Limit);
      Decode ((Defaults with delta Max_Total_Allocation_Bytes => 0), Retained, False,
              Pictlib.Total_Allocation_Byte_Limit);
      Decode ((Defaults with delta Max_Output_Bytes => 100), Retained, True, Pictlib.Output_Byte_Limit);
      Decode ((Defaults with delta Max_Embedded_Image_Bytes => 100), Retained, True, Pictlib.Embedded_Image_Byte_Limit);
      Decode ((Defaults with delta Max_Embedded_Image_Pixels => 10), Retained, True,
              Pictlib.Embedded_Image_Pixel_Limit);
      Decode ((Defaults with delta Max_Warning_Records => 0), Retained, True, Pictlib.No_Limit);
      --  A reserved opcode warns: one warning by default, none, and no failure, under a zero cap.
      declare
         Warns : aliased constant Bytes := V2_Picture (0, 0, 4, 4, W (16#0024#) & W (0));
         Source : aliased Pictlib.Streams.Memory_Source;
         Decoder : Decoding.Decoder;
         Visitor : Null_Visitor;
         Outcome : Pictlib.Results.Result;
      begin
         for Cap in reverse 0 .. 1 loop
            Pictlib.Streams.Open (Source, Warns'Unchecked_Access);
            Decoding.Initialize
              (Decoder, Source'Access, Decode_Limits => (Defaults with delta Max_Warning_Records => Cap));
            Outcome := Decoding.Read_Header (Decoder);
            if Pictlib.Results.Succeeded (Outcome) then
               Outcome := Decoding.Enumerate (Decoder, Visitor);
            end if;
            Assert (Pictlib.Results.Succeeded (Outcome) and then Decoding.Warning_Count (Decoder) = Cap,
                    "a warning cap of" & Cap'Image & " kept" & Decoding.Warning_Count (Decoder)'Image
                    & " warnings, or failed with " & Outcome.First_Error.Code'Image);
         end loop;
      end;
      Encode ((Defaults with delta Max_Output_Bytes => 100));
      declare
         Polygon : aliased constant Bytes :=
           V2_Picture (0, 0, 4, 4, W (16#71#) & W (14) & Rect (0, 0, 4, 4) & W (1) & W (1));
         Source : aliased Pictlib.Streams.Memory_Source;
         Decoder : Decoding.Decoder;
         Visitor : Null_Visitor;
         Outcome : Pictlib.Results.Result;
      begin
         Pictlib.Streams.Open (Source, Polygon'Unchecked_Access);
         Decoding.Initialize (Decoder, Source'Access, Decode_Limits => (Defaults with delta Max_Polygon_Points => 0));
         Outcome := Decoding.Read_Header (Decoder);
         if Pictlib.Results.Succeeded (Outcome) then
            Outcome := Decoding.Enumerate (Decoder, Visitor);
         end if;
         Assert (Outcome.First_Error.Code = Pictlib.Errors.Limit_Exceeded
                 and then Outcome.First_Error.Context.Limit = Pictlib.Polygon_Point_Limit,
                 "a polygon budget reported " & Outcome.First_Error.Context.Limit'Image);
         Seen (Pictlib.Polygon_Point_Limit) := True;
      end;
      for Kind in Seen'Range loop
         Assert (Seen (Kind), "no input reports the limit " & Kind'Image);
      end loop;
   end Limit_Matrix;

   --  The largest frame the default limits allow is refused before any allocation when the view is wrong, and
   --  a picture of 100_000 opcodes enumerates.
   procedure Large_Inputs (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Many : aliased constant Bytes := V2_Picture (0, 0, 1, 1, [1 .. 200_000 => 0]);
      Huge_Frame : aliased constant Bytes := V2_Picture (0, 0, 16_384, 16_384, [1 .. 0 => 0]);
      Source : aliased Pictlib.Streams.Memory_Source;
      Decoder : Decoding.Decoder;
      Visitor : Null_Visitor;
      Small : aliased Bytes := [1 .. 3 => 0];
      Outcome : Pictlib.Results.Result;
   begin
      Pictlib.Streams.Open (Source, Many'Unchecked_Access);
      Decoding.Initialize (Decoder, Source'Access);
      Outcome := Decoding.Read_Header (Decoder);
      if Pictlib.Results.Succeeded (Outcome) then
         Outcome := Decoding.Enumerate (Decoder, Visitor);
      end if;
      Assert (Pictlib.Results.Succeeded (Outcome), "100_000 NOPs did not enumerate");

      Pictlib.Streams.Open (Source, Huge_Frame'Unchecked_Access);
      Decoding.Initialize (Decoder, Source'Access);
      Outcome := Decoding.Read_Header (Decoder);
      Assert (Pictlib.Results.Succeeded (Outcome), "the largest default frame was refused");
      Outcome := Decoding.Render (Decoder, Canvases.View (Small'Access, 1, 1));
      Assert (Outcome.First_Error.Code = Pictlib.Errors.Invalid_Argument, "a view of the wrong size was drawn into");
      Outcome := Decoding.Render
        (Decoder, (Descriptor => (Width => 16_384, Height => 16_384, Format => Pictlib.RGB_24, Stride => 3 * 16_384,
                                  Accessible_Bytes => 3 * 16_384 * 16_384),
                   Storage => Small'Unchecked_Access));
      Assert (Outcome.First_Error.Code = Pictlib.Errors.Invalid_Argument,
              "a view larger than its storage was drawn into");
   end Large_Inputs;
end Pictlib_Testing.Test_Stress;
