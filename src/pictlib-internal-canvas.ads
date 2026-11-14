with Pictlib.Images;

--  The caller's view as a drawing surface: canvas pixel (0, 0) is the view's first pixel. Every drawn pixel is
--  opaque. The view must be valid before it is bound.
package Pictlib.Internal.Canvas is
   type Canvas is record
      View : Images.Mutable_Image_View;
      Width : Natural := 0;
      Height : Natural := 0;
      --  Bytes from one pixel of a row to the next.
      Step : Positive := 3;
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
   --  Index: where pixel X, Y starts in the view's storage; the next pixel of the row starts Target.Step on.
   --  @param Target Canvas.
   --  @param X Column.
   --  @param Y Row.
   --  @return The storage index of the pixel's first byte, for Put_At and Get_At.
   function Index (Target : Canvas; X, Y : Natural) return Positive
     with Pre => X < Target.Width and then Y < Target.Height, Inline;
   --  Put at: Put by storage index, for a run of pixels stepped through by Target.Step.
   --  @param Target Canvas to draw on.
   --  @param At_Pixel Index of a pixel of the canvas.
   --  @param Color Opaque color.
   procedure Put_At (Target : in out Canvas; At_Pixel : Positive; Color : Images.RGB_Color) with Inline;
   --  Get at: Get by storage index.
   --  @param Target Canvas to read.
   --  @param At_Pixel Index of a pixel of the canvas.
   --  @return The pixel's color.
   function Get_At (Target : Canvas; At_Pixel : Positive) return Images.RGB_Color with Inline;
   --  Repeat: pixels Left .. Left + Period - 1 of row Y copied over the rest of Left .. Right - 1, period by
   --  period, as a pattern repeats.
   --  @param Target Canvas to draw on.
   --  @param Left First column, the first of the period already drawn.
   --  @param Right One past the last column.
   --  @param Y Row.
   --  @param Period Pixels that repeat.
   procedure Repeat (Target : in out Canvas; Left, Right, Y : Natural; Period : Positive)
     with Pre => Left < Right and then Right <= Target.Width and then Y < Target.Height;
   --  Get.
   --  @param Target Canvas to read.
   --  @param X Column.
   --  @param Y Row.
   --  @return The pixel's color.
   function Get (Target : Canvas; X, Y : Natural) return Images.RGB_Color
     with Pre => X < Target.Width and then Y < Target.Height;
end Pictlib.Internal.Canvas;
