with Pictlib.Streams;

package body Pictlib.Internal.Canvas is
   procedure Bind (Target : out Canvas; View : Images.Mutable_Image_View) is
   begin
      Target := (View => View, Width => Natural (View.Descriptor.Width), Height => Natural (View.Descriptor.Height));
   end Bind;

   function Position (Target : Canvas; X, Y : Natural) return Positive is
     (Target.View.Storage'First
      + Natural (Byte_Count (Y) * Byte_Count (Target.View.Descriptor.Stride)
                 + Byte_Count (X) * Images.Bytes_Per_Pixel (Target.View.Descriptor.Format)));

   procedure Put (Target : in out Canvas; X, Y : Natural; Color : Images.RGB_Color) is
      At_Pixel : constant Positive := Position (Target, X, Y);
      Storage : Streams.Byte_Array renames Target.View.Storage.all;
   begin
      case Target.View.Descriptor.Format is
         when RGB_24 =>
            Storage (At_Pixel .. At_Pixel + 2) := [Color.Red, Color.Green, Color.Blue];
         when BGR_24 =>
            Storage (At_Pixel .. At_Pixel + 2) := [Color.Blue, Color.Green, Color.Red];
         when RGBA_32 =>
            Storage (At_Pixel .. At_Pixel + 3) := [Color.Red, Color.Green, Color.Blue, 16#FF#];
         when BGRA_32 =>
            Storage (At_Pixel .. At_Pixel + 3) := [Color.Blue, Color.Green, Color.Red, 16#FF#];
         when ARGB_32 =>
            Storage (At_Pixel .. At_Pixel + 3) := [16#FF#, Color.Red, Color.Green, Color.Blue];
      end case;
   end Put;

   procedure Put_Span (Target : in out Canvas; Left, Right, Y : Natural; Color : Images.RGB_Color) is
      Size : constant Natural := Natural (Images.Bytes_Per_Pixel (Target.View.Descriptor.Format));
      Storage : Streams.Byte_Array renames Target.View.Storage.all;
   begin
      if Left = Right then
         return;
      end if;
      Put (Target, Left, Y, Color);
      declare
         First : constant Positive := Position (Target, Left, Y);
         Filled : Natural := Size;
         Total : constant Natural := (Right - Left) * Size;
      begin
         --  Double what is written until the span is full.
         while Filled < Total loop
            declare
               Step : constant Natural := Natural'Min (Filled, Total - Filled);
            begin
               Storage (First + Filled .. First + Filled + Step - 1) := Storage (First .. First + Step - 1);
               Filled := Filled + Step;
            end;
         end loop;
      end;
   end Put_Span;

   function Get (Target : Canvas; X, Y : Natural) return Images.RGB_Color is
      At_Pixel : constant Positive := Position (Target, X, Y);
      Storage : Streams.Byte_Array renames Target.View.Storage.all;
   begin
      case Target.View.Descriptor.Format is
         when RGB_24 | RGBA_32 =>
            return (Storage (At_Pixel), Storage (At_Pixel + 1), Storage (At_Pixel + 2));
         when BGR_24 | BGRA_32 =>
            return (Storage (At_Pixel + 2), Storage (At_Pixel + 1), Storage (At_Pixel));
         when ARGB_32 =>
            return (Storage (At_Pixel + 1), Storage (At_Pixel + 2), Storage (At_Pixel + 3));
      end case;
   end Get;

   --  The first row pixel by pixel, then every other row as a copy of it.
   procedure Fill (Target : in out Canvas; Color : Images.RGB_Color) is
      Row_Bytes : constant Natural :=
        Target.Width * Natural (Images.Bytes_Per_Pixel (Target.View.Descriptor.Format));
      Storage : Streams.Byte_Array renames Target.View.Storage.all;
      First : constant Positive := Position (Target, 0, 0);
   begin
      if Target.Width = 0 or else Target.Height = 0 then
         return;
      end if;
      for X in 0 .. Target.Width - 1 loop
         Put (Target, X, 0, Color);
      end loop;
      for Y in 1 .. Target.Height - 1 loop
         declare
            Start : constant Positive := Position (Target, 0, Y);
         begin
            Storage (Start .. Start + Row_Bytes - 1) := Storage (First .. First + Row_Bytes - 1);
         end;
      end loop;
   end Fill;
end Pictlib.Internal.Canvas;
