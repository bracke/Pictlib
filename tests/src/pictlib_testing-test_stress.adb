with AUnit.Assertions;

with Pictlib;
with Pictlib.Decoding;
with Pictlib.Encoding;
with Pictlib.Errors;
with Pictlib.Fonts;
with Pictlib.Images;
with Pictlib.Limits;
with Pictlib.Pictures;
with Pictlib.Results;
with Pictlib.Streams;
with Pictlib_Testing.Builders;
with Pictlib_Testing.Files;
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

   type Null_Visitor is new Decoding.Opcode_Visitor with null record;
   overriding function Visit (Object : in out Null_Visitor; Event : Pictlib.Pictures.Opcode_Event)
     return Decoding.Visit_Action is (Decoding.Continue);

   function Fonts return Pictlib.Fonts.Font_Table is
      Table : Pictlib.Fonts.Font_Table := Pictlib.Fonts.Empty;
   begin
      Pictlib.Fonts.Set_Default (Table, "fixtures/fonts/DejaVuSans.ttf");
      return Table;
   end Fonts;

   --  A picture that exercises every renderer path: a copy, shapes, a pattern, text and a QuickTime JPEG.
   function Everything return Bytes is
     (V2_Picture
        (0, 0, 24, 48,
         W (16#01#) & Region (0, 0, 24, 48)
         & W (16#1A#) & W (16#FFFF#) & W (0) & W (0) & W (16#51#) & Rect (2, 2, 20, 30)
         & W (16#1A#) & W (0) & W (0) & W (0)
         & W (16#0A#) & [16#AA#, 16#55#, 16#AA#, 16#55#, 16#AA#, 16#55#, 16#AA#, 16#55#]
         & W (16#34#) & Rect (4, 30, 20, 46)
         & W (16#98#) & W (2) & Rect (0, 0, 2, 8) & Rect (0, 0, 2, 8) & Rect (22, 0, 24, 8) & W (0)
         & B (16#A5#) & B (0) & B (16#0F#) & B (0)
         & W (16#28#) & W (18) & W (4) & B (2) & Text ("Hi") & B (0)
         & QuickTime ("jpeg", 8, 6, Files.Load ("external/small.jpg").all, Move_H => 36 * 16#1_0000#,
                      Move_V => 16#1_0000#)));

   --  Render Input with a fresh decoder of its own, returning the RGB pixels.
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
         Outcome := Decoding.Render
           (Decoder,
            (Descriptor => (Width => Pictlib.Image_Width (Width), Height => Pictlib.Image_Height (Height),
                            Format => Pictlib.RGB_24, Stride => Pictlib.Row_Stride (3 * Width),
                            Accessible_Bytes => Pictlib.Byte_Count (3 * Width * Height)),
             Storage => Storage'Unchecked_Access));
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
      View : constant Pictlib.Images.Mutable_Image_View :=
        (Descriptor => (Width => 48, Height => 24, Format => Pictlib.RGB_24, Stride => 144, Accessible_Bytes => 3456),
         Storage => Storage'Unchecked_Access);
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
      Seen : array (Pictlib.Limit_Kind) of Boolean := [Pictlib.No_Limit => True, others => False];

      procedure Decode (Budget : Pictlib.Limits.Limit_Set; Options : Decoding.Options; Render_It : Boolean) is
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
              (if Render_It then
                  Decoding.Render
                    (Decoder,
                     (Descriptor => (Width => 48, Height => 24, Format => Pictlib.RGB_24, Stride => 144,
                                     Accessible_Bytes => 3456),
                      Storage => Storage'Unchecked_Access))
               else Decoding.Enumerate (Decoder, Visitor));
         end if;
         if Outcome.First_Error.Code = Pictlib.Errors.Limit_Exceeded then
            Seen (Outcome.First_Error.Context.Limit) := True;
         end if;
         if Budget.Max_Warning_Records = 0 and then Decoding.Warning_Count (Decoder) = 0 then
            --  Warnings are capped, not failed: a zero cap keeps none.
            Seen (Pictlib.Warning_Record_Limit) := True;
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
         if Outcome.First_Error.Code = Pictlib.Errors.Limit_Exceeded then
            Seen (Outcome.First_Error.Context.Limit) := True;
         end if;
      end Encode;
   begin
      Decode ((Defaults with delta Max_Frame_Width => 47), Retained, False);
      Decode ((Defaults with delta Max_Frame_Height => 23), Retained, False);
      Decode ((Defaults with delta Max_Canvas_Pixels => 100), Retained, True);
      Decode ((Defaults with delta Max_Picture_Bytes => 100), Retained, False);
      Decode ((Defaults with delta Max_Opcodes => 4), Retained, False);
      Decode ((Defaults with delta Max_Opcode_Bytes => 20), Retained, False);
      Decode ((Defaults with delta Max_Region_Bytes => 9), Retained, False);
      Decode ((Defaults with delta Max_Drawing_Work => 100), Retained, True);
      Decode ((Defaults with delta Max_Retained_Metadata_Bytes => 3), Retained, False);
      Decode ((Defaults with delta Max_Metadata_Items => 0), Retained, False);
      Decode ((Defaults with delta Max_Allocation_Bytes => 100), Retained, True);
      Decode ((Defaults with delta Max_Output_Bytes => 100), Retained, True);
      Decode ((Defaults with delta Max_Embedded_Image_Bytes => 100), Retained, True);
      Decode ((Defaults with delta Max_Embedded_Image_Pixels => 10), Retained, True);
      Decode ((Defaults with delta Max_Warning_Records => 0), Retained, True);
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
         Seen (Outcome.First_Error.Context.Limit) := True;
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
      Outcome := Decoding.Render
        (Decoder,
         (Descriptor => (Width => 1, Height => 1, Format => Pictlib.RGB_24, Stride => 3, Accessible_Bytes => 3),
          Storage => Small'Unchecked_Access));
      Assert (Outcome.First_Error.Code = Pictlib.Errors.Invalid_Argument, "a view of the wrong size was drawn into");
      Outcome := Decoding.Render
        (Decoder, (Descriptor => (Width => 16_384, Height => 16_384, Format => Pictlib.RGB_24, Stride => 3 * 16_384,
                                  Accessible_Bytes => 3 * 16_384 * 16_384),
                   Storage => Small'Unchecked_Access));
      Assert (Outcome.First_Error.Code = Pictlib.Errors.Invalid_Argument,
              "a view larger than its storage was drawn into");
   end Large_Inputs;
end Pictlib_Testing.Test_Stress;
