--  Throughput, for information only: each layout encoded from and rendered back into a 1024 x 768 view, patterned
--  fills, text and shapes under a clip of many lines drawn on one, and the real-world vector picture rendered.
--  Prints megapixels per second of frame, timed in the process's CPU time, which a busy machine skews less than
--  the wall clock. Runs from anywhere below the pictlib tree.
with Pictlib_Testing.Builders;
with Pictlib_Testing.Canvases;
with Pictlib_Testing.Fonts;
with Pictlib_Testing.Tools;
with Ada.Directories;
with Ada.Execution_Time;
with Ada.Real_Time;
with Ada.Text_IO;
with Pictlib;
with Pictlib.Decoding;
with Pictlib.Encoding;
with Pictlib.Geometry;
with Pictlib.Results;
with Pictlib.Streams;
with Pictlib_Testing.Files;
with Pictlib_Testing.Samples;

procedure Pictlib_Benchmark is
   use type Ada.Execution_Time.CPU_Time;
   use type Pictlib.Streams.Byte_Array;
   use Pictlib_Testing.Builders;

   --  The time spent so far, as a point to measure from.
   function Clock return Ada.Execution_Time.CPU_Time is (Ada.Execution_Time.Clock);
   function Since (Start : Ada.Execution_Time.CPU_Time) return Duration is
     (Ada.Real_Time.To_Duration (Ada.Execution_Time.Clock - Start));

   Width : constant := 1024;
   Height : constant := 768;
   Rounds : constant := 5;

   package Duration_IO is new Ada.Text_IO.Fixed_IO (Duration);

   procedure Report (Label : String; Pixels : Natural; Elapsed : Duration) is
   begin
      Ada.Text_IO.Put (Label & ": ");
      Duration_IO.Put (Elapsed, Fore => 3, Aft => 3);
      --  A clock too coarse to time the work has no rate to report.
      if Elapsed <= 0.0 then
         Ada.Text_IO.Put_Line (" s, too fast to time");
      else
         Ada.Text_IO.Put_Line
           (" s," & Natural'Image (Natural (Float'Min (Float (Pixels) / Float (Elapsed) / 1.0E6, 1.0E9)))
            & " Mpx/s");
      end if;
   end Report;

   procedure Free (Item : in out Pictlib.Streams.Byte_Array_Access) renames Pictlib_Testing.Files.Free;

   --  Render Data into a view of its frame, allocated once and kept in Storage across calls; Pixels is the frame's
   --  count.
   function Render
     (Data : Pictlib.Streams.Byte_Array_Access;
      Storage : in out Pictlib.Streams.Byte_Array_Access;
      Pixels : out Natural;
      Options : Pictlib.Decoding.Options := (others => <>)) return Boolean
   is
      Source : aliased Pictlib.Streams.Memory_Source;
      Decoder : Pictlib.Decoding.Decoder;
      Outcome : Pictlib.Results.Result;
   begin
      Pixels := 0;
      Pictlib.Streams.Open (Source, Pictlib.Streams.Const_Byte_Array_Access (Data));
      Pictlib.Decoding.Initialize (Decoder, Source'Access, Options);
      Outcome := Pictlib.Decoding.Read_Header (Decoder);
      if Pictlib.Results.Succeeded (Outcome) then
         declare
            Frame : constant Pictlib.Geometry.Rect := Pictlib.Decoding.Header (Decoder).Frame;
         begin
            Pixels := Pictlib.Geometry.Width (Frame) * Pictlib.Geometry.Height (Frame);
         end;
         Outcome := Pictlib_Testing.Canvases.Render_Frame (Decoder, Storage);
      end if;
      return Pictlib.Results.Succeeded (Outcome);
   end Render;

   --  Encode Item in layout Kind Rounds times through one encoder and one destination, so only the encoding is
   --  timed, then render the picture back Rounds times.
   procedure Layout (Item : Pictlib_Testing.Samples.Kind; Kind : Pictlib.Encoding.Layout_Kind) is
      Source : Pictlib_Testing.Samples.Bytes_Access := Pictlib_Testing.Samples.Make (Item, Width, Height);
      Room : Pictlib.Streams.Byte_Array_Access := new Pictlib.Streams.Byte_Array (1 .. 8 * Width * Height);
      Output : aliased Pictlib.Streams.Fixed_Buffer_Destination;
      Encoder : Pictlib.Encoding.Encoder;
      Outcome : Pictlib.Results.Result;
      Started : Ada.Execution_Time.CPU_Time;
      Encoded : Pictlib.Streams.Byte_Array_Access;
      Storage : Pictlib.Streams.Byte_Array_Access;
      Pixels : Natural;

      procedure Release is
      begin
         Pictlib.Encoding.Finalize (Encoder);
         Free (Source);
         Free (Room);
         Free (Encoded);
         Free (Storage);
      end Release;
   begin
      Pictlib.Streams.Open (Output, Room);
      Pictlib.Encoding.Initialize (Encoder, Output'Access, (Layout => Kind, others => <>));
      Started := Clock;
      for Round in 1 .. Rounds loop
         if Round > 1 then
            Pictlib.Streams.Open (Output, Room);
            Pictlib.Encoding.Reset (Encoder, Output'Access);
         end if;
         Outcome := Pictlib.Encoding.Encode (Encoder, Pictlib_Testing.Samples.View (Source, Width, Height));
         if Pictlib.Results.Succeeded (Outcome) then
            Outcome := Pictlib.Encoding.Finish (Encoder);
         end if;
         if not Pictlib.Results.Succeeded (Outcome) then
            Pictlib_Testing.Tools.Fail (Kind'Image & ": encode failed");
            Release;
            return;
         end if;
      end loop;
      Report (Kind'Image & " encode", Rounds * Width * Height, Since (Started));
      Encoded := new Pictlib.Streams.Byte_Array'(Room (1 .. Natural (Output.Offset)));
      Started := Clock;
      for Round in 1 .. Rounds loop
         if not Render (Encoded, Storage, Pixels) then
            Pictlib_Testing.Tools.Fail (Kind'Image & ": render failed");
            Release;
            return;
         end if;
      end loop;
      Report (Kind'Image & " render", Rounds * Width * Height, Since (Started));
      Release;
   end Layout;

   procedure Vector_Picture (Path : String) is
      Data : Pictlib_Testing.Files.Bytes_Access := Pictlib_Testing.Files.Load_Path (Path);
      Started : constant Ada.Execution_Time.CPU_Time := Clock;
      Storage : Pictlib.Streams.Byte_Array_Access;
      Pixels : Natural;
   begin
      if Render (Data, Storage, Pixels) then
         Report (Ada.Directories.Simple_Name (Path) & " render", Pixels, Since (Started));
      else
         Pictlib_Testing.Tools.Fail (Ada.Directories.Simple_Name (Path) & ": render failed");
      end if;
      Free (Storage);
      Free (Data);
   end Vector_Picture;
   --  Render Picture, built here, Rounds times with Options.
   procedure Drawn (Label : String; Picture : Pictlib.Streams.Byte_Array; Options : Pictlib.Decoding.Options) is
      Data : Pictlib.Streams.Byte_Array_Access := new Pictlib.Streams.Byte_Array'(Picture);
      Storage : Pictlib.Streams.Byte_Array_Access;
      Pixels : Natural := 0;
      Started : constant Ada.Execution_Time.CPU_Time := Clock;
   begin
      for Round in 1 .. Rounds loop
         if not Render (Data, Storage, Pixels, Options) then
            Pictlib_Testing.Tools.Fail (Label & ": render failed");
            exit;
         end if;
      end loop;
      Report (Label & " render", Rounds * Pixels, Since (Started));
      Free (Storage);
      Free (Data);
   end Drawn;

   --  A two-by-two dither, as gray fills use.
   Gray : constant Pictlib.Streams.Byte_Array := Repeat (B (16#AA#) & B (16#55#), 4);
   --  Ten fills of the frame with a pattern, copied, then ten painted with the pen's pattern or-ed in.
   Patterned : constant Pictlib.Streams.Byte_Array :=
     Pic (Width, Height,
          W (16#0A#) & Gray & Repeat (Op_Rect (16#34#, 0, 0, Height, Width), 10)
          & W (16#09#) & Gray & Pen_Mode (9) & Repeat (Op_Rect (16#31#, 0, 0, Height, Width), 10));
   --  Fifty lines of eighty characters of 12-point Helvetica, or-ed in.
   function Text_Lines return Pictlib.Streams.Byte_Array is
      Line : constant String := "The quick brown fox jumps over the lazy dog, 0123456789 times, as PICT text draws.";
      One : constant Pictlib.Streams.Byte_Array := W (16#28#) & W (0) & W (0) & B (80) & Text (Line (1 .. 80)) & B (0);
      Result : Pictlib.Streams.Byte_Array (1 .. 50 * One'Length);
   begin
      for Index in 0 .. 49 loop
         Result (Index * One'Length + 1 .. (Index + 1) * One'Length) :=
           W (16#28#) & W (14 * (Index + 1)) & W (0) & One (One'First + 6 .. One'Last);
      end loop;
      return Pic (Width, Height, W (16#03#) & W (21) & W (16#0D#) & W (12) & W (16#05#) & W (1) & Result);
   end Text_Lines;

   --  Two thousand 20 x 20 ovals under a clip of every other row.
   function Clipped return Pictlib.Streams.Byte_Array is
      One : constant Natural := Op_Rect (16#51#, 0, 0, 20, 20)'Length;
      Shapes : Pictlib.Streams.Byte_Array (1 .. 2_000 * One);
   begin
      for Index in 0 .. 1_999 loop
         declare
            Top : constant Natural := (Index / 50) * 19;
            Left : constant Natural := (Index mod 50) * 20;
         begin
            Shapes (Index * One + 1 .. (Index + 1) * One) := Op_Rect (16#51#, Top, Left, Top + 20, Left + 20);
         end;
      end loop;
      return Pic (Width, Height, W (16#01#) & Striped_Region (0, Height, Width) & Shapes);
   end Clipped;
begin
   if not Pictlib_Testing.Tools.Enter_Tests_Directory then
      return;
   end if;
   Pictlib_Testing.Tools.Start_Report ("pictlib_benchmark");
   if not Pictlib_Testing.Tools.Arguments_Known ([1 .. 0 => null]) then
      Pictlib_Testing.Tools.Finish_Report;
      return;
   end if;
   Layout (Pictlib_Testing.Samples.Gradient, Pictlib.Encoding.Direct_32);
   Layout (Pictlib_Testing.Samples.Three_Colors, Pictlib.Encoding.Indexed_8);
   Layout (Pictlib_Testing.Samples.Black_And_White, Pictlib.Encoding.Mono_1);
   Drawn ("patterned fills", Patterned, (others => <>));
   Drawn ("text", Text_Lines, (Fonts => Pictlib_Testing.Fonts.Test_Table, others => <>));
   Drawn ("clipped ovals", Clipped, (others => <>));
   Vector_Picture ("fixtures/real_world/libreoffice/pass/ooo25876-2.pct");
   Pictlib_Testing.Tools.Finish_Report;
end Pictlib_Benchmark;
