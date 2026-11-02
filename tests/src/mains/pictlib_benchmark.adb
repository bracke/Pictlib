--  Throughput, for information only: each layout encoded from and rendered back into a 1024 x 768 view, and the
--  real-world vector picture rendered. Prints megapixels per second. Runs from anywhere below the pictlib tree.
with Pictlib_Testing.Canvases;
with Pictlib_Testing.Tools;
with Ada.Calendar;
with Ada.Directories;
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
   use type Ada.Calendar.Time;

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
      Pixels : out Natural) return Boolean
   is
      Source : aliased Pictlib.Streams.Memory_Source;
      Decoder : Pictlib.Decoding.Decoder;
      Outcome : Pictlib.Results.Result;
   begin
      Pixels := 0;
      Pictlib.Streams.Open (Source, Pictlib.Streams.Const_Byte_Array_Access (Data));
      Pictlib.Decoding.Initialize (Decoder, Source'Access);
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
      Started : Ada.Calendar.Time;
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
      Started := Ada.Calendar.Clock;
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
      Report (Kind'Image & " encode", Rounds * Width * Height, Ada.Calendar.Clock - Started);
      Encoded := new Pictlib.Streams.Byte_Array'(Room (1 .. Natural (Output.Offset)));
      Started := Ada.Calendar.Clock;
      for Round in 1 .. Rounds loop
         if not Render (Encoded, Storage, Pixels) then
            Pictlib_Testing.Tools.Fail (Kind'Image & ": render failed");
            Release;
            return;
         end if;
      end loop;
      Report (Kind'Image & " render", Rounds * Width * Height, Ada.Calendar.Clock - Started);
      Release;
   end Layout;

   procedure Vector_Picture (Path : String) is
      Data : Pictlib_Testing.Files.Bytes_Access := Pictlib_Testing.Files.Load_Path (Path);
      Started : constant Ada.Calendar.Time := Ada.Calendar.Clock;
      Storage : Pictlib.Streams.Byte_Array_Access;
      Pixels : Natural;
   begin
      if Render (Data, Storage, Pixels) then
         Report (Ada.Directories.Simple_Name (Path) & " render", Pixels, Ada.Calendar.Clock - Started);
      else
         Pictlib_Testing.Tools.Fail (Ada.Directories.Simple_Name (Path) & ": render failed");
      end if;
      Free (Storage);
      Free (Data);
   end Vector_Picture;
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
   Vector_Picture ("fixtures/real_world/libreoffice/pass/ooo25876-2.pct");
   Pictlib_Testing.Tools.Finish_Report;
end Pictlib_Benchmark;
