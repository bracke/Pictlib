with AUnit.Assertions;

with Pictlib;
with Pictlib.Decoding;
with Pictlib.Encoding;
with Pictlib.Errors;
with Pictlib.Geometry;
with Pictlib.Images;
with Pictlib.Limits;
with Pictlib.Opcodes;
with Pictlib.Results;
with Pictlib.Streams;
with Pictlib_Testing.Canvases;
with Pictlib_Testing.Recorders;
with Pictlib_Testing.Samples;

package body Pictlib_Testing.Test_Encoding is
   use AUnit.Assertions;
   use type Pictlib.Byte;
   use type Pictlib.Byte_Count;
   use type Pictlib.Destination_Offset;
   use type Pictlib.Encoding.Encoder_State;
   use type Pictlib.Encoding.Layout_Kind;
   use type Pictlib.Errors.Error_Code;
   use type Pictlib.Geometry.Fixed;
   use type Pictlib.Geometry.Rect;
   use type Pictlib.Streams.Byte_Array;
   use type Pictlib.Images.RGB_Color;
   use type Pictlib.Limit_Kind;
   use type Pictlib.Opcode;
   use type Pictlib.PICT_Version;

   package Encoding renames Pictlib.Encoding;
   subtype Kind is Samples.Kind;

   Capacity : constant := 2_000_000;

   subtype Encoded is Samples.Encoded;

   --  A destination that refuses its Fail_At-th write, once, and takes every other.
   type Flaky is limited new Pictlib.Streams.Destination with record
      Inner : Pictlib.Streams.Fixed_Buffer_Destination;
      Calls : Natural := 0;
      Fail_At : Positive := 1;
      Writes_After : Natural := 0;
   end record;
   overriding function Write (Object : in out Flaky; Buffer : Pictlib.Streams.Byte_Array)
     return Pictlib.Streams.Destination_Result;
   overriding function Offset (Object : Flaky) return Pictlib.Destination_Offset is (Object.Inner.Offset);
   overriding function Flush (Object : in out Flaky) return Pictlib.Errors.Error is (Object.Inner.Flush);

   overriding function Write (Object : in out Flaky; Buffer : Pictlib.Streams.Byte_Array)
     return Pictlib.Streams.Destination_Result is
   begin
      Object.Calls := Object.Calls + 1;
      if Object.Calls = Object.Fail_At then
         return (Error => Pictlib.Errors.Make (Pictlib.Errors.Destination_Write_Failed), Count => 0);
      elsif Object.Calls > Object.Fail_At then
         Object.Writes_After := Object.Writes_After + 1;
      end if;
      return Object.Inner.Write (Buffer);
   end Write;

   --  Encode through Samples, requiring Bytes_Written to be what the destination holds, failure or not.
   function Encode
     (Item : Kind;
      Width, Height : Positive;
      Settings : Encoding.Options := (others => <>);
      Format : Pictlib.Pixel_Format := Pictlib.RGB_24;
      Budget : Pictlib.Limits.Limit_Set := Pictlib.Limits.Default_Limits;
      Max_Transfer : Pictlib.Byte_Count := Pictlib.Byte_Count'Last;
      Room : Natural := Capacity) return Encoded
   is
      Picture : constant Encoded := Samples.Encode (Item, Width, Height, Settings, Format, Budget, Max_Transfer, Room);
   begin
      Assert (Picture.Bytes_Written = Pictlib.Byte_Count (Picture.Data'Length),
              "Bytes_Written" & Picture.Bytes_Written'Image & " disagrees with the" & Picture.Data'Length'Image
              & " bytes output");
      return Picture;
   end Encode;

   --  Encode, decode with pictlib, and require every pixel, through Expected_Color.
   procedure Round_Trip
     (Item : Kind;
      Width, Height : Positive;
      Layout : Encoding.Layout_Kind;
      Label : String;
      Settings : Encoding.Options := (others => <>);
      Format : Pictlib.Pixel_Format := Pictlib.RGB_24)
   is
      Picture : constant Encoded := Encode (Item, Width, Height, (Settings with delta Layout => Layout), Format);
      Storage : aliased Pictlib.Streams.Byte_Array := [1 .. 3 * Width * Height => 16#EE#];
      Output : constant Pictlib.Images.Mutable_Image_View := Canvases.View (Storage'Access, Width, Height);
      Decoder : Pictlib.Decoding.Decoder;
      Outcome : Pictlib.Results.Result;
      Wrong : Natural := 0;
   begin
      Assert (Pictlib.Results.Succeeded (Picture.Outcome), Label & ": encode failed with "
              & Picture.Outcome.First_Error.Code'Image);
      Canvases.Render (Picture.Data.all, Decoder, Output, Outcome);
      Assert (Pictlib.Results.Succeeded (Outcome), Label & ": decode failed with " & Outcome.First_Error.Code'Image);
      for Y in 0 .. Height - 1 loop
         for X in 0 .. Width - 1 loop
            if Canvases.Pixel (Output, X, Y) /= Samples.Expected_Color (Item, X, Y, Layout, Settings.Mono_Threshold)
            then
               Wrong := Wrong + 1;
            end if;
         end loop;
      end loop;
      Assert (Wrong = 0, Label & ":" & Wrong'Image & " pixels changed");
   end Round_Trip;

   procedure Layouts (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Row_Lengths (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Automatic_Layout (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Picture_Structure (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Formats_And_Alpha (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Rejections (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Destinations (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure States (T : in out AUnit.Test_Cases.Test_Case'Class);

   overriding function Name (T : Test) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("encoding");
   end Name;

   overriding procedure Register_Tests (T : in out Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Layouts'Access, "encoding.layouts.round_trip");
      Register_Routine (T, Row_Lengths'Access, "encoding.row_lengths");
      Register_Routine (T, Automatic_Layout'Access, "encoding.auto_layout");
      Register_Routine (T, Picture_Structure'Access, "encoding.structure");
      Register_Routine (T, Formats_And_Alpha'Access, "encoding.formats_and_alpha");
      Register_Routine (T, Rejections'Access, "encoding.rejections");
      Register_Routine (T, Destinations'Access, "encoding.destinations");
      Register_Routine (T, States'Access, "encoding.states");
   end Register_Tests;

   procedure Layouts (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Round_Trip (Samples.Gradient, 37, 23, Encoding.Direct_32, "Direct_32");
      Round_Trip (Samples.Three_Colors, 37, 23, Encoding.Indexed_8, "Indexed_8");
      Round_Trip (Samples.Three_Colors, 37, 23, Encoding.Direct_32, "Direct_32 of few colors");
      Round_Trip (Samples.Black_And_White, 37, 23, Encoding.Mono_1, "Mono_1");
      Round_Trip (Samples.Gray_Ramp, 37, 3, Encoding.Mono_1, "Mono_1 threshold 128");
      Round_Trip (Samples.Gray_Ramp, 37, 3, Encoding.Mono_1, "Mono_1 threshold 200",
                  (Mono_Threshold => 200, others => <>));
   end Layouts;

   procedure Row_Lengths (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      --  rowBytes below 8 is stored unpacked; above 250 the packed counts are words.
      Round_Trip (Samples.Gradient, 1, 4, Encoding.Direct_32, "Direct_32, 1 pixel wide");
      Round_Trip (Samples.Gradient, 2, 4, Encoding.Direct_32, "Direct_32, 2 pixels wide");
      Round_Trip (Samples.Gradient, 100, 3, Encoding.Direct_32, "Direct_32, word counts");
      Round_Trip (Samples.Three_Colors, 1, 4, Encoding.Indexed_8, "Indexed_8, 1 pixel wide");
      Round_Trip (Samples.Three_Colors, 7, 4, Encoding.Indexed_8, "Indexed_8, 7 pixels wide");
      Round_Trip (Samples.Three_Colors, 300, 3, Encoding.Indexed_8, "Indexed_8, word counts");
      Round_Trip (Samples.Black_And_White, 3, 4, Encoding.Mono_1, "Mono_1, 3 pixels wide");
      Round_Trip (Samples.Black_And_White, 2100, 2, Encoding.Mono_1, "Mono_1, word counts");
      Round_Trip (Samples.Gradient, 4095, 1, Encoding.Direct_32, "Direct_32, widest");
   end Row_Lengths;

   procedure Automatic_Layout (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Encode (Samples.Black_And_White, 9, 4).Layout = Encoding.Mono_1, "black and white is Mono_1");
      Assert (Encode (Samples.Three_Colors, 9, 4).Layout = Encoding.Indexed_8, "three colors is Indexed_8");
      Assert (Encode (Samples.Gradient, 37, 23).Layout = Encoding.Direct_32, "a gradient is Direct_32");
      Assert (Encode (Samples.Black_And_White, 9, 4, (Keep_Alpha => True, others => <>), Pictlib.RGBA_32).Layout
              = Encoding.Direct_32, "kept alpha is Direct_32");
      Round_Trip (Samples.Gradient, 37, 23, Encoding.Auto, "Auto");
      --  Auto takes Mono_1 only for pure black and white, and keeps it exact whatever the threshold.
      Round_Trip (Samples.Black_And_White, 9, 4, Encoding.Auto, "Auto, black and white, threshold 0",
                  (Mono_Threshold => 0, others => <>));
      Round_Trip (Samples.Black_And_White, 9, 4, Encoding.Auto, "Auto, black and white, threshold 255",
                  (Mono_Threshold => 255, others => <>));
      --  Alpha is kept only from a view that has it: from RGB, Auto chooses as if it were not asked for.
      Assert (Encode (Samples.Black_And_White, 9, 4, (Keep_Alpha => True, others => <>)).Layout = Encoding.Mono_1,
              "Keep_Alpha on an RGB view chose Direct_32");
   end Automatic_Layout;

   procedure Picture_Structure (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      High : constant Pictlib.Geometry.Fixed := 300 * Pictlib.Geometry.Fixed_One;

      procedure Check (Item : Kind; Bits_Op : Pictlib.Opcode; Settings : Encoding.Options; Label : String) is
         Picture : constant Encoded := Encode (Item, 9, 4, Settings);
         Header_Bytes : constant Natural := (if Settings.File_Header then 512 else 0);
         Decoder : Pictlib.Decoding.Decoder;
         Events : Recorders.Recorder;
         Outcome : Pictlib.Results.Result;
         Picture_Size : constant Natural :=
           Natural (Picture.Data (Header_Bytes + 1)) * 256 + Natural (Picture.Data (Header_Bytes + 2));
         Expected_Ops : constant array (1 .. 6) of Pictlib.Opcode :=
           [Pictlib.Opcodes.Version_Op, Pictlib.Opcodes.Header_Op, Pictlib.Opcodes.Default_Hilite,
            Pictlib.Opcodes.Clip, Bits_Op, Pictlib.Opcodes.End_Picture];
      begin
         Assert (Pictlib.Results.Succeeded (Picture.Outcome), Label & ": encode failed");
         Assert (not Settings.File_Header or else (for all Index in 1 .. 512 => Picture.Data (Index) = 0),
                 Label & ": the file header is not zero");
         Assert (Picture_Size = (Picture.Data'Length - Header_Bytes) mod 65_536, Label & ": picSize is wrong");
         Recorders.Decode (Picture.Data.all, Decoder, Events, Outcome);
         Assert (Pictlib.Results.Succeeded (Outcome), Label & ": enumeration failed");
         Assert (Pictlib.Decoding.Header (Decoder).Version = Pictlib.Extended_Version_2
                 and then Pictlib.Decoding.Header (Decoder).Has_File_Header = Settings.File_Header,
                 Label & ": header is wrong");
         Assert (Pictlib.Decoding.Header (Decoder).Horizontal_Resolution = Settings.Horizontal_Resolution
                 and then Pictlib.Decoding.Header (Decoder).Vertical_Resolution = Settings.Vertical_Resolution,
                 Label & ": resolution is wrong");
         Assert (Pictlib.Decoding.Header (Decoder).Frame = (0, 0, 4, 9), Label & ": frame is wrong");
         Assert (Events.Count = 6, Label & ": wrong opcode count" & Events.Count'Image);
         for Index in Expected_Ops'Range loop
            Assert (Events.Events (Index).Op = Expected_Ops (Index), Label & ": wrong opcode" & Index'Image);
         end loop;
         Assert (Pictlib.Decoding.Warning_Count (Decoder) = 0, Label & ": the output draws warnings");
         Assert (Natural (Events.Events (6).Offset) + 2 = Picture.Data'Length, Label & ": bytes after OpEndPic");
      end Check;
   begin
      Check (Samples.Gradient, Pictlib.Opcodes.Direct_Bits_Rect, (Layout => Encoding.Direct_32, others => <>),
             "Direct_32");
      Check (Samples.Three_Colors, Pictlib.Opcodes.Pack_Bits_Rect, (Layout => Encoding.Indexed_8, others => <>),
             "Indexed_8");
      Check (Samples.Black_And_White, Pictlib.Opcodes.Pack_Bits_Rect,
             (Layout => Encoding.Mono_1, File_Header => False, Horizontal_Resolution => High,
              Vertical_Resolution => 2 * High, others => <>), "Mono_1, bare, 300 x 600 dpi");
      --  The BitMap has no PixMap flag; the PixMap has it.
      Assert ((Encode (Samples.Black_And_White, 9, 4, (Layout => Encoding.Mono_1, others => <>)).Data (512 + 57)
               and 16#80#) = 0, "the BitMap claims to be a PixMap");
      Assert ((Encode (Samples.Three_Colors, 9, 4, (Layout => Encoding.Indexed_8, others => <>)).Data (512 + 57)
               and 16#80#) /= 0, "the PixMap lacks its flag");
   end Picture_Structure;

   procedure Formats_And_Alpha (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      for Format in Pictlib.Pixel_Format loop
         Round_Trip (Samples.Gradient, 19, 7, Encoding.Direct_32, "Direct_32 from " & Format'Image, Format => Format);
         Round_Trip (Samples.Three_Colors, 19, 7, Encoding.Indexed_8, "Indexed_8 from " & Format'Image,
                     Format => Format);
      end loop;
      Round_Trip (Samples.Translucent, 19, 7, Encoding.Direct_32, "Direct_32 keeping alpha",
                  (Keep_Alpha => True, others => <>), Pictlib.RGBA_32);
      Round_Trip (Samples.Translucent, 1, 3, Encoding.Direct_32, "Direct_32 keeping alpha, unpacked",
                  (Keep_Alpha => True, others => <>), Pictlib.ARGB_32);
      declare
         With_Alpha : constant Encoded :=
           Encode (Samples.Translucent, 19, 7, (Layout => Encoding.Direct_32, Keep_Alpha => True, others => <>),
                   Pictlib.RGBA_32);
         Without : constant Encoded :=
           Encode (Samples.Translucent, 19, 7, (Layout => Encoding.Direct_32, others => <>), Pictlib.RGBA_32);
      begin
         --  cmpCount's low byte: picture offset 91, after DirectBitsRect at 54, baseAddr, rowBytes, bounds and
         --  the PixMap's first 20 bytes.
         Assert (With_Alpha.Data (512 + 92) = 4, "alpha was not written as a fourth plane");
         Assert (Without.Data (512 + 92) = 3, "alpha was written unasked");
         --  pictlib's decoder ignores alpha, so the planes are read here: the first row, at picture offset 124
         --  after srcRect, dstRect and the mode, is a count byte and PackBits of the alpha, red, green and blue
         --  planes, unpacked by the Inside Macintosh rule.
         declare
            Count : constant Natural := Natural (With_Alpha.Data (512 + 125));
            type Planar_Row is array (0 .. 4 * 19 - 1) of Pictlib.Byte;
            Row : Planar_Row := [others => 0];
            Next : Natural := 0;
            At_Byte : Positive := 512 + 126;
         begin
            while At_Byte < 512 + 126 + Count and then Next < Row'Length loop
               declare
                  Flag : constant Natural := Natural (With_Alpha.Data (At_Byte));
               begin
                  if Flag < 128 then
                     for Index in 0 .. Flag loop
                        exit when Next >= Row'Length;
                        Row (Next) := With_Alpha.Data (At_Byte + 1 + Index);
                        Next := Next + 1;
                     end loop;
                     At_Byte := At_Byte + Flag + 2;
                  else
                     for Index in 1 .. 257 - Flag loop
                        exit when Next >= Row'Length;
                        Row (Next) := With_Alpha.Data (At_Byte + 1);
                        Next := Next + 1;
                     end loop;
                     At_Byte := At_Byte + 2;
                  end if;
               end;
            end loop;
            Assert (Next = Row'Length, "the first row did not unpack to four planes");
            for X in 0 .. 18 loop
               Assert (Row (X) = Samples.Alpha (Samples.Translucent, X, 0)
                       and then Row (19 + X) = Samples.Color (Samples.Translucent, X, 0).Red
                       and then Row (38 + X) = Samples.Color (Samples.Translucent, X, 0).Green
                       and then Row (57 + X) = Samples.Color (Samples.Translucent, X, 0).Blue,
                       "planar pixel" & X'Image & " is not its alpha and color");
            end loop;
         end;
      end;
      --  Unpacked, below 8 rowBytes: each pixel is its alpha, then red, green and blue; three rows of one pixel
      --  end the picture before the end opcode.
      declare
         Narrow : constant Encoded :=
           Encode (Samples.Translucent, 1, 3, (Layout => Encoding.Direct_32, Keep_Alpha => True, others => <>),
                   Pictlib.ARGB_32);
         Rows : constant Positive := Narrow.Data'Length - 2 - 12 + 1;
      begin
         for Y in 0 .. 2 loop
            Assert (Narrow.Data (Rows + 4 * Y) = Samples.Alpha (Samples.Translucent, 0, Y)
                    and then Narrow.Data (Rows + 4 * Y + 1) = Samples.Color (Samples.Translucent, 0, Y).Red
                    and then Narrow.Data (Rows + 4 * Y + 3) = Samples.Color (Samples.Translucent, 0, Y).Blue,
                    "unpacked row" & Y'Image & " is not its alpha and color");
         end loop;
      end;
   end Formats_And_Alpha;

   procedure Rejections (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Defaults : constant Pictlib.Limits.Limit_Set := Pictlib.Limits.Default_Limits;
      Picture : Encoded;
      Output : aliased Pictlib.Streams.Fixed_Buffer_Destination;
      Storage : constant Pictlib.Streams.Byte_Array_Access := new Pictlib.Streams.Byte_Array (1 .. 1000);
      Encoder : Encoding.Encoder;
      Outcome : Pictlib.Results.Result;
   begin
      Picture := Encode (Samples.Gradient, 37, 23, (Layout => Encoding.Indexed_8, others => <>));
      Assert (Picture.Outcome.First_Error.Code = Pictlib.Errors.Too_Many_Colors
              and then Picture.Outcome.First_Error.Context.Actual = 257 and then Picture.Data'Length = 0,
              "more than 256 colors were indexed");
      Picture := Encode (Samples.Gradient, 4096, 1, (Layout => Encoding.Direct_32, others => <>));
      Assert (Picture.Outcome.First_Error.Code = Pictlib.Errors.Invalid_Argument,
              "rowBytes above 16#3FFE# was written");
      Picture := Encode (Samples.Gradient, 4, 4, (Horizontal_Resolution => 0, others => <>));
      Assert (Picture.Outcome.First_Error.Code = Pictlib.Errors.Invalid_Argument, "a zero resolution was written");
      Picture := Encode (Samples.Gradient, 40, 4, Budget => (Defaults with delta Max_Frame_Width => 39));
      Assert (Picture.Outcome.First_Error.Code = Pictlib.Errors.Limit_Exceeded
              and then Picture.Outcome.First_Error.Context.Limit = Pictlib.Frame_Width_Limit,
              "the frame limit was not enforced");
      Picture := Encode (Samples.Gradient, 40, 4, Budget => (Defaults with delta Max_Frame_Height => 3));
      Assert (Picture.Outcome.First_Error.Code = Pictlib.Errors.Limit_Exceeded
              and then Picture.Outcome.First_Error.Context.Limit = Pictlib.Frame_Height_Limit
              and then Picture.Outcome.First_Error.Context.Expected = 3
              and then Picture.Outcome.First_Error.Context.Actual = 4,
              "the frame height limit was not reported as itself");
      Picture := Encode (Samples.Gradient, 40, 4, Budget => (Defaults with delta Max_Output_Bytes => 600));
      Assert (Picture.Outcome.First_Error.Code = Pictlib.Errors.Limit_Exceeded
              and then Picture.Outcome.First_Error.Context.Limit = Pictlib.Output_Byte_Limit
              and then Picture.Data'Length = 0,
              "the output limit was not enforced before writing");
      --  It is reported as set, with the file header counted: the limit, and more than it.
      Assert (Picture.Outcome.First_Error.Context.Expected = 600
              and then Picture.Outcome.First_Error.Context.Actual > 600
              and then Picture.Outcome.First_Error.Context.Destination > 512,
              "the output limit was reported as" & Picture.Outcome.First_Error.Context.Expected'Image
              & ", not as set");
      --  The row buffers are a row before packing and its worst case packed: 120 + 121 bytes for 40 direct
      --  pixels, 40 + 41 for 40 indexed ones.
      Picture := Encode (Samples.Gradient, 40, 4, (Layout => Encoding.Direct_32, others => <>),
                         Budget => (Defaults with delta Max_Allocation_Bytes => 240));
      Assert (Picture.Outcome.First_Error.Code = Pictlib.Errors.Limit_Exceeded
              and then Picture.Outcome.First_Error.Context.Limit = Pictlib.Allocation_Byte_Limit
              and then Picture.Outcome.First_Error.Context.Actual = 241,
              "the allocation limit was not enforced");
      Picture := Encode (Samples.Gradient, 40, 4, (Layout => Encoding.Indexed_8, others => <>),
                         Budget => (Defaults with delta Max_Allocation_Bytes => 81));
      Assert (Pictlib.Results.Succeeded (Picture.Outcome), "indexed row buffers were sized as direct ones");

      Pictlib.Streams.Open (Output, Storage);
      Encoding.Initialize (Encoder, Output'Access);
      Outcome := Encoding.Encode (Encoder, (Descriptor => (Width => 4, Height => 4, Format => Pictlib.RGB_24,
                                                          Stride => 12, Accessible_Bytes => 48), Storage => null));
      Assert (Outcome.First_Error.Code = Pictlib.Errors.Invalid_Argument
              and then Encoding.State (Encoder) = Encoding.Ready,
              "a view without storage was encoded, or it failed the encoder");
   end Rejections;

   procedure Destinations (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Whole : constant Encoded := Encode (Samples.Gradient, 37, 23);
      Trickled : constant Encoded := Encode (Samples.Gradient, 37, 23, Max_Transfer => 1);
      Cramped : constant Encoded := Encode (Samples.Gradient, 37, 23, Room => 700);
   begin
      Assert (Pictlib.Results.Succeeded (Trickled.Outcome) and then Trickled.Data.all = Whole.Data.all,
              "one-byte writes changed the output");
      Assert (Cramped.Outcome.First_Error.Code = Pictlib.Errors.Limit_Exceeded
              and then Cramped.Outcome.First_Error.Context.Limit = Pictlib.Output_Byte_Limit,
              "a full destination was not reported");
      --  A destination that fails once and would take the rest is written nothing more: no gap, no end opcode
      --  after one.
      declare
         Image_Data : constant Samples.Bytes_Access := Samples.Make (Samples.Gradient, 37, 23);
         Storage : constant Pictlib.Streams.Byte_Array_Access := new Pictlib.Streams.Byte_Array (1 .. Capacity);
         Output : aliased Flaky;
         Encoder : Encoding.Encoder;
         Outcome : Pictlib.Results.Result;
      begin
         Pictlib.Streams.Open (Output.Inner, Storage);
         Output.Fail_At := 40;
         Encoding.Initialize (Encoder, Output'Access);
         Outcome := Encoding.Encode (Encoder, Samples.View (Image_Data, 37, 23));
         Assert (Outcome.First_Error.Code = Pictlib.Errors.Destination_Write_Failed,
                 "a failed write was not reported: " & Outcome.First_Error.Code'Image);
         Assert (Output.Writes_After = 0, "the encoder wrote" & Output.Writes_After'Image & " times after a failure");
         Assert (Encoding.Bytes_Written (Encoder) = Pictlib.Byte_Count (Output.Offset),
                 "Bytes_Written disagrees with the destination after a failure");
      end;
   end Destinations;

   procedure States (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Source : constant Samples.Bytes_Access := Samples.Make (Samples.Gradient, 4, 4);
      Image : constant Pictlib.Images.Image_View := Samples.View (Source, 4, 4);
      Storage : constant Pictlib.Streams.Byte_Array_Access := new Pictlib.Streams.Byte_Array (1 .. 10_000);
      Output : aliased Pictlib.Streams.Fixed_Buffer_Destination;
      Encoder : Encoding.Encoder;
      Outcome : Pictlib.Results.Result;
   begin
      Assert (Encoding.State (Encoder) = Encoding.Created, "a new encoder is not Created");
      Outcome := Encoding.Encode (Encoder, Image);
      Assert (Outcome.First_Error.Code = Pictlib.Errors.Invalid_State, "an uninitialized encoder encoded");
      Pictlib.Streams.Open (Output, Storage);
      Encoding.Initialize (Encoder, Output'Access);
      Outcome := Encoding.Finish (Encoder);
      Assert (Outcome.First_Error.Code = Pictlib.Errors.Invalid_State, "an encoder finished before encoding");
      Outcome := Encoding.Encode (Encoder, Image);
      Assert (Pictlib.Results.Succeeded (Outcome) and then Encoding.State (Encoder) = Encoding.Encoded, "encode");
      Outcome := Encoding.Encode (Encoder, Image);
      Assert (Outcome.First_Error.Code = Pictlib.Errors.Invalid_State, "an encoder encoded twice");
      Outcome := Encoding.Finish (Encoder);
      Assert (Pictlib.Results.Succeeded (Outcome) and then Encoding.State (Encoder) = Encoding.Finished, "finish");
      Encoding.Initialize (Encoder, Output'Access);
      Encoding.Cancel (Encoder);
      Outcome := Encoding.Encode (Encoder, Image);
      Assert (Outcome.First_Error.Code = Pictlib.Errors.Operation_Cancelled, "a cancelled encoder encoded");
      Encoding.Finalize (Encoder);
      Encoding.Finalize (Encoder);
      Assert (Encoding.State (Encoder) = Encoding.Created, "finalize is not idempotent");
   end States;
end Pictlib_Testing.Test_Encoding;
