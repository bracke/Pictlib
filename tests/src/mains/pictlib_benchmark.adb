--  Throughput, for information only: each layout encoded from and rendered back into a 1024 x 768 view, and the
--  real-world vector picture rendered. Prints megapixels per second. Runs from anywhere below the pictlib tree.
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
      Rate : constant Float := Float (Pixels) / Float (Elapsed) / 1.0E6;
   begin
      Ada.Text_IO.Put (Label & ": ");
      Duration_IO.Put (Elapsed, Fore => 3, Aft => 3);
      Ada.Text_IO.Put_Line (" s," & Integer'Image (Integer (Rate)) & " Mpx/s");
   end Report;

   function Render (Data : Pictlib.Streams.Byte_Array_Access; Out_Width, Out_Height : Positive) return Boolean is
      Source : aliased Pictlib.Streams.Memory_Source;
      Decoder : Pictlib.Decoding.Decoder;
      Storage : constant Pictlib.Streams.Byte_Array_Access :=
        new Pictlib.Streams.Byte_Array (1 .. 3 * Out_Width * Out_Height);
      Outcome : Pictlib.Results.Result;
   begin
      Pictlib.Streams.Open (Source, Pictlib.Streams.Const_Byte_Array_Access (Data));
      Pictlib.Decoding.Initialize (Decoder, Source'Access);
      Outcome := Pictlib.Decoding.Read_Header (Decoder);
      if Pictlib.Results.Succeeded (Outcome) then
         Outcome := Pictlib.Decoding.Render
           (Decoder,
            (Descriptor => (Width => Pictlib.Image_Width (Out_Width), Height => Pictlib.Image_Height (Out_Height),
                            Format => Pictlib.RGB_24, Stride => Pictlib.Row_Stride (3 * Out_Width),
                            Accessible_Bytes => Pictlib.Byte_Count (3 * Out_Width * Out_Height)),
             Storage => Storage));
      end if;
      return Pictlib.Results.Succeeded (Outcome);
   end Render;

   procedure Layout (Item : Pictlib_Testing.Samples.Kind; Kind : Pictlib.Encoding.Layout_Kind) is
      Source : constant Pictlib_Testing.Samples.Bytes_Access := Pictlib_Testing.Samples.Make (Item, Width, Height);
      Started : Ada.Calendar.Time;
      Picture : Pictlib_Testing.Samples.Encoded;
      Encoded : Pictlib.Streams.Byte_Array_Access;
   begin
      Started := Ada.Calendar.Clock;
      for Round in 1 .. Rounds loop
         Picture := Pictlib_Testing.Samples.Encode
           (Pictlib_Testing.Samples.View (Source, Width, Height), (Layout => Kind, others => <>),
            Room => 8 * Width * Height);
         if not Pictlib.Results.Succeeded (Picture.Outcome) then
            Pictlib_Testing.Tools.Fail (Kind'Image & ": encode failed");
            return;
         end if;
      end loop;
      Report (Kind'Image & " encode", Rounds * Width * Height, Ada.Calendar.Clock - Started);
      Encoded := Pictlib.Streams.Byte_Array_Access (Picture.Data);
      Started := Ada.Calendar.Clock;
      for Round in 1 .. Rounds loop
         if not Render (Encoded, Width, Height) then
            Pictlib_Testing.Tools.Fail (Kind'Image & ": render failed");
            return;
         end if;
      end loop;
      Report (Kind'Image & " render", Rounds * Width * Height, Ada.Calendar.Clock - Started);
   end Layout;

   procedure Vector_Picture (Path : String) is
      Data : constant Pictlib_Testing.Files.Bytes_Access := Pictlib_Testing.Files.Load_Path (Path);
      Started : Ada.Calendar.Time;
      Source : aliased Pictlib.Streams.Memory_Source;
      Decoder : Pictlib.Decoding.Decoder;
   begin
      Pictlib.Streams.Open (Source, Pictlib.Streams.Const_Byte_Array_Access (Data));
      Pictlib.Decoding.Initialize (Decoder, Source'Access);
      if not Pictlib.Results.Succeeded (Pictlib.Decoding.Read_Header (Decoder)) then
         Pictlib_Testing.Tools.Fail (Ada.Directories.Simple_Name (Path) & ": header failed");
         return;
      end if;
      declare
         Frame : constant Pictlib.Geometry.Rect := Pictlib.Decoding.Header (Decoder).Frame;
         Frame_Width : constant Positive := Pictlib.Geometry.Width (Frame);
         Frame_Height : constant Positive := Pictlib.Geometry.Height (Frame);
      begin
         Started := Ada.Calendar.Clock;
         if Render (Pictlib.Streams.Byte_Array_Access (Data), Frame_Width, Frame_Height) then
            Report (Ada.Directories.Simple_Name (Path) & " render", Frame_Width * Frame_Height,
                    Ada.Calendar.Clock - Started);
         else
            Pictlib_Testing.Tools.Fail (Ada.Directories.Simple_Name (Path) & ": render failed");
         end if;
      end;
   end Vector_Picture;
begin
   if not Pictlib_Testing.Tools.Enter_Tests_Directory then
      return;
   end if;
   Pictlib_Testing.Tools.Start_Report ("pictlib_benchmark");
   Layout (Pictlib_Testing.Samples.Gradient, Pictlib.Encoding.Direct_32);
   Layout (Pictlib_Testing.Samples.Three_Colors, Pictlib.Encoding.Indexed_8);
   Layout (Pictlib_Testing.Samples.Black_And_White, Pictlib.Encoding.Mono_1);
   Vector_Picture ("fixtures/real_world/libreoffice/pass/ooo25876-2.pct");
   Pictlib_Testing.Tools.Finish_Report;
end Pictlib_Benchmark;
