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

   procedure Fill (Target : in out Canvas; Color : Images.RGB_Color) is
   begin
      for Y in 0 .. Target.Height - 1 loop
         for X in 0 .. Target.Width - 1 loop
            Put (Target, X, Y, Color);
         end loop;
      end loop;
   end Fill;
end Pictlib.Internal.Canvas;
