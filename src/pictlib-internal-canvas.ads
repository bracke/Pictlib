with Pictlib.Images;

--  The caller's view as a drawing surface: canvas pixel (0, 0) is the view's first pixel. Every drawn pixel is
--  opaque. The view must be valid before it is bound.
package Pictlib.Internal.Canvas is
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
