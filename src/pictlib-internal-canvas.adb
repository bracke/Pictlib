with Pictlib.Streams;

package body Pictlib.Internal.Canvas is
   procedure Bind (Target : out Canvas; View : Images.Mutable_Image_View) is
   begin
      Target :=
        (View => View, Width => Natural (View.Descriptor.Width), Height => Natural (View.Descriptor.Height),
         Step => Positive (Images.Bytes_Per_Pixel (View.Descriptor.Format)));
   end Bind;

   function Index (Target : Canvas; X, Y : Natural) return Positive is
     (Target.View.Storage'First + Pixels.Pixel_Offset (Target.View.Descriptor, X, Y));

   procedure Put (Target : in out Canvas; X, Y : Natural; Color : Images.RGB_Color) is
   begin
      Put_At (Target, Index (Target, X, Y), Color);
   end Put;

   --  Each byte stored on its own, not through an aggregate the compiler may build first.
   procedure Put_At (Target : in out Canvas; At_Pixel : Positive; Color : Images.RGB_Color) is
      Storage : Streams.Byte_Array renames Target.View.Storage.all;
   begin
      case Target.View.Descriptor.Format is
         when RGB_24 =>
            Storage (At_Pixel) := Color.Red;
            Storage (At_Pixel + 1) := Color.Green;
            Storage (At_Pixel + 2) := Color.Blue;
         when BGR_24 =>
            Storage (At_Pixel) := Color.Blue;
            Storage (At_Pixel + 1) := Color.Green;
            Storage (At_Pixel + 2) := Color.Red;
         when RGBA_32 =>
            Storage (At_Pixel) := Color.Red;
            Storage (At_Pixel + 1) := Color.Green;
            Storage (At_Pixel + 2) := Color.Blue;
            Storage (At_Pixel + 3) := 16#FF#;
         when BGRA_32 =>
            Storage (At_Pixel) := Color.Blue;
            Storage (At_Pixel + 1) := Color.Green;
            Storage (At_Pixel + 2) := Color.Red;
            Storage (At_Pixel + 3) := 16#FF#;
         when ARGB_32 =>
            Storage (At_Pixel) := 16#FF#;
            Storage (At_Pixel + 1) := Color.Red;
            Storage (At_Pixel + 2) := Color.Green;
            Storage (At_Pixel + 3) := Color.Blue;
      end case;
   end Put_At;

   procedure Put_Run (Target : in out Canvas; At_Pixel : Positive; Colors : Pixels.Color_Row) is
      Storage : Streams.Byte_Array renames Target.View.Storage.all;
      At_Byte : Positive := At_Pixel;
   begin
      case Target.View.Descriptor.Format is
         when RGB_24 =>
            for Color of Colors loop
               Storage (At_Byte) := Color.Red;
               Storage (At_Byte + 1) := Color.Green;
               Storage (At_Byte + 2) := Color.Blue;
               At_Byte := At_Byte + 3;
            end loop;
         when BGR_24 =>
            for Color of Colors loop
               Storage (At_Byte) := Color.Blue;
               Storage (At_Byte + 1) := Color.Green;
               Storage (At_Byte + 2) := Color.Red;
               At_Byte := At_Byte + 3;
            end loop;
         when RGBA_32 =>
            for Color of Colors loop
               Storage (At_Byte) := Color.Red;
               Storage (At_Byte + 1) := Color.Green;
               Storage (At_Byte + 2) := Color.Blue;
               Storage (At_Byte + 3) := 16#FF#;
               At_Byte := At_Byte + 4;
            end loop;
         when BGRA_32 =>
            for Color of Colors loop
               Storage (At_Byte) := Color.Blue;
               Storage (At_Byte + 1) := Color.Green;
               Storage (At_Byte + 2) := Color.Red;
               Storage (At_Byte + 3) := 16#FF#;
               At_Byte := At_Byte + 4;
            end loop;
         when ARGB_32 =>
            for Color of Colors loop
               Storage (At_Byte) := 16#FF#;
               Storage (At_Byte + 1) := Color.Red;
               Storage (At_Byte + 2) := Color.Green;
               Storage (At_Byte + 3) := Color.Blue;
               At_Byte := At_Byte + 4;
            end loop;
      end case;
   end Put_Run;

   procedure Put_Strided
     (Target : in out Canvas;
      At_Pixel : Positive;
      Count : Natural;
      Stride : Positive;
      Color : Images.RGB_Color)
   is
      Storage : Streams.Byte_Array renames Target.View.Storage.all;
      Step : constant Positive := Stride * Target.Step;
      At_Byte : Positive := At_Pixel;
      --  The pixel's bytes in storage order, the format decided here once.
      Size : constant Positive := Target.Step;
      Bytes : constant Streams.Byte_Array (1 .. 4) :=
        (case Target.View.Descriptor.Format is
            when RGB_24 | RGBA_32 => [Color.Red, Color.Green, Color.Blue, 16#FF#],
            when BGR_24 | BGRA_32 => [Color.Blue, Color.Green, Color.Red, 16#FF#],
            when ARGB_32 => [16#FF#, Color.Red, Color.Green, Color.Blue]);
      B1 : constant Byte := Bytes (1);
      B2 : constant Byte := Bytes (2);
      B3 : constant Byte := Bytes (3);
      B4 : constant Byte := Bytes (4);
   begin
      if Count = 0 then
         return;
      end if;
      --  One loop for each pixel size, the last pixel written apart, so the loop tests neither.
      if Size = 4 then
         for Written in 1 .. Count - 1 loop
            Storage (At_Byte .. At_Byte + 3) := [B1, B2, B3, B4];
            At_Byte := At_Byte + Step;
         end loop;
         Storage (At_Byte .. At_Byte + 3) := [B1, B2, B3, B4];
      else
         for Written in 1 .. Count - 1 loop
            Storage (At_Byte .. At_Byte + 2) := [B1, B2, B3];
            At_Byte := At_Byte + Step;
         end loop;
         Storage (At_Byte .. At_Byte + 2) := [B1, B2, B3];
      end if;
   end Put_Strided;

   function Get_At (Target : Canvas; At_Pixel : Positive) return Images.RGB_Color is
     (Pixels.Color_At (Target.View.Descriptor.Format, Target.View.Storage.all, At_Pixel));

   procedure Repeat (Target : in out Canvas; Left, Right, Y : Natural; Period : Positive) is
      Storage : Streams.Byte_Array renames Target.View.Storage.all;
      First : constant Positive := Index (Target, Left, Y);
      Filled : Natural := Natural'Min (Period, Right - Left) * Target.Step;
      Total : constant Natural := (Right - Left) * Target.Step;
   begin
      --  Double what is written until the span is full: whole periods, so the pattern stays in phase.
      while Filled < Total loop
         declare
            Step : constant Natural := Natural'Min (Filled, Total - Filled);
         begin
            Storage (First + Filled .. First + Filled + Step - 1) := Storage (First .. First + Step - 1);
            Filled := Filled + Step;
         end;
      end loop;
   end Repeat;

   procedure Put_Span (Target : in out Canvas; Left, Right, Y : Natural; Color : Images.RGB_Color) is
   begin
      if Left = Right then
         return;
      elsif Right - Left <= 16 then
         --  A short span costs less written a pixel at a time than doubled.
         Put_Strided (Target, Index (Target, Left, Y), Right - Left, 1, Color);
         return;
      end if;
      Put (Target, Left, Y, Color);
      Repeat (Target, Left, Right, Y, 1);
   end Put_Span;

   function Get (Target : Canvas; X, Y : Natural) return Images.RGB_Color is (Get_At (Target, Index (Target, X, Y)));

   --  The first row pixel by pixel, then every other row as a copy of it.
   procedure Fill (Target : in out Canvas; Color : Images.RGB_Color) is
      Row_Bytes : constant Natural :=
        Target.Width * Natural (Images.Bytes_Per_Pixel (Target.View.Descriptor.Format));
   begin
      --  A canvas not bound to a view has no pixels, and no storage to name.
      if Target.Width = 0 or else Target.Height = 0 then
         return;
      end if;
      for X in 0 .. Target.Width - 1 loop
         Put (Target, X, 0, Color);
      end loop;
      declare
         Storage : Streams.Byte_Array renames Target.View.Storage.all;
         First : constant Positive := Index (Target, 0, 0);
      begin
         for Y in 1 .. Target.Height - 1 loop
            declare
               Start : constant Positive := Index (Target, 0, Y);
            begin
               Storage (Start .. Start + Row_Bytes - 1) := Storage (First .. First + Row_Bytes - 1);
            end;
         end loop;
      end;
   end Fill;
end Pictlib.Internal.Canvas;
