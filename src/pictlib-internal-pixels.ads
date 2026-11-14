with Pictlib.Images;
with Pictlib.Streams;

--  A view's pixels in each pixel format: where one starts, and its color and alpha. The canvas draws through
--  them and the encoder reads source images through them.
package Pictlib.Internal.Pixels is
   pragma Preelaborate;

   --  A run of colors, as a decoded row holds them and the canvas writes them.
   type Color_Row is array (Natural range <>) of Images.RGB_Color;

   --  Pixel offset: where a view's pixel starts.
   --  @param Descriptor A valid view's descriptor.
   --  @param X Column.
   --  @param Y Row.
   --  @return The offset of pixel X, Y from the view's first storage byte.
   function Pixel_Offset (Descriptor : Images.Image_Descriptor; X, Y : Natural) return Natural is
     (Natural (Byte_Count (Y) * Byte_Count (Descriptor.Stride)
               + Byte_Count (X) * Images.Bytes_Per_Pixel (Descriptor.Format)));
   --  Where each component of a pixel lies, counted from its first byte, so a loop over a row decides the format
   --  once; a format without alpha points Alpha at nothing, and its pixels are opaque.
   type Component_Offsets is record
      Red, Green, Blue, Alpha : Natural := 0;
      Has_Alpha : Boolean := False;
   end record;
   --  Offsets.
   --  @param Format A pixel format.
   --  @return Where its components lie.
   function Offsets (Format : Pixel_Format) return Component_Offsets is
     (case Format is
         when RGB_24 => (Red => 0, Green => 1, Blue => 2, Alpha => 0, Has_Alpha => False),
         when BGR_24 => (Red => 2, Green => 1, Blue => 0, Alpha => 0, Has_Alpha => False),
         when RGBA_32 => (Red => 0, Green => 1, Blue => 2, Alpha => 3, Has_Alpha => True),
         when BGRA_32 => (Red => 2, Green => 1, Blue => 0, Alpha => 3, Has_Alpha => True),
         when ARGB_32 => (Red => 1, Green => 2, Blue => 3, Alpha => 0, Has_Alpha => True));

   --  Color at.
   --  @param Format The view's pixel format.
   --  @param Data Its storage.
   --  @param At_Pixel Index of a pixel's first byte.
   --  @return The pixel's color.
   function Color_At (Format : Pixel_Format; Data : Streams.Byte_Array; At_Pixel : Positive)
     return Images.RGB_Color is
     (case Format is
         when RGB_24 | RGBA_32 => (Data (At_Pixel), Data (At_Pixel + 1), Data (At_Pixel + 2)),
         when BGR_24 | BGRA_32 => (Data (At_Pixel + 2), Data (At_Pixel + 1), Data (At_Pixel)),
         when ARGB_32 => (Data (At_Pixel + 1), Data (At_Pixel + 2), Data (At_Pixel + 3)));
   --  Alpha at.
   --  @param Format The view's pixel format.
   --  @param Data Its storage.
   --  @param At_Pixel Index of a pixel's first byte.
   --  @return The pixel's alpha; opaque for a format without one.
   function Alpha_At (Format : Pixel_Format; Data : Streams.Byte_Array; At_Pixel : Positive) return Byte is
     (case Format is
         when RGB_24 | BGR_24 => 16#FF#,
         when RGBA_32 | BGRA_32 => Data (At_Pixel + 3),
         when ARGB_32 => Data (At_Pixel));
end Pictlib.Internal.Pixels;
