with Pictlib.Images;
with Pictlib.Streams;

--  The caller's view as a drawing surface: canvas pixel (0, 0) is the view's first pixel. Every drawn pixel is
--  opaque. The view must be valid before it is bound.
package Pictlib.Internal.Canvas is
   --  Pixel offset: where a view's pixel starts, shared by the canvas and the encoder that reads views.
   --  @param Descriptor A valid view's descriptor.
   --  @param X Column.
   --  @param Y Row.
   --  @return The offset of pixel X, Y from the view's first storage byte.
   function Pixel_Offset (Descriptor : Images.Image_Descriptor; X, Y : Natural) return Natural is
     (Natural (Byte_Count (Y) * Byte_Count (Descriptor.Stride)
               + Byte_Count (X) * Images.Bytes_Per_Pixel (Descriptor.Format)));
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

   type Canvas is record
      View : Images.Mutable_Image_View;
      Width : Natural := 0;
      Height : Natural := 0;
   end record;

   --  Bind.
   --  @param Target Canvas to bind.
   --  @param View A valid caller view.
   procedure Bind (Target : out Canvas; View : Images.Mutable_Image_View)
     with Pre => Images.Is_Valid (View);
   --  Fill.
   --  @param Target Canvas to fill.
   --  @param Color Opaque color for every pixel.
   procedure Fill (Target : in out Canvas; Color : Images.RGB_Color);
   --  Put.
   --  @param Target Canvas to draw on.
   --  @param X Column.
   --  @param Y Row.
   --  @param Color Opaque color.
   procedure Put (Target : in out Canvas; X, Y : Natural; Color : Images.RGB_Color)
     with Pre => X < Target.Width and then Y < Target.Height, Inline;
   --  Put span.
   --  @param Target Canvas to draw on.
   --  @param Left First column.
   --  @param Right One past the last column.
   --  @param Y Row.
   --  @param Color Opaque color for columns Left .. Right - 1.
   procedure Put_Span (Target : in out Canvas; Left, Right, Y : Natural; Color : Images.RGB_Color)
     with Pre => Left <= Right and then Right <= Target.Width and then Y < Target.Height;
   --  Get.
   --  @param Target Canvas to read.
   --  @param X Column.
   --  @param Y Row.
   --  @return The pixel's color.
   function Get (Target : Canvas; X, Y : Natural) return Images.RGB_Color
     with Pre => X < Target.Width and then Y < Target.Height;
end Pictlib.Internal.Canvas;
