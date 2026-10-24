with Pictlib.Geometry;
with Pictlib.Images;
with Pictlib.Internal.Canvas;
with Pictlib.Internal.Pixmaps;
with Pictlib.Internal.Regions;
with Pictlib.Internal.Sessions;
with Pictlib.Pictures;
with Pictlib.Results;

--  Drawing state while a picture renders onto the caller's view. Canvas pixel (0, 0) is the frame's top-left
--  corner; QuickDraw coordinates are mapped by subtracting the frame origin.
package Pictlib.Internal.Rendering is
   type Painter is limited record
      Target : Canvas.Canvas;
      Frame : Geometry.Rect;
      Has_Clip : Boolean := False;
      Clip : Regions.Region;
      --  Pixels painted and region work done, against Limits.Max_Drawing_Work.
      Work : Pixel_Count := 0;
      --  QuickDraw colorizes copies when the foreground is not black or the background not white.
      Default_Foreground : Boolean := True;
      Default_Background : Boolean := True;
      Clip_Spans : Regions.Span_Vectors.Vector;
      Mask_Spans : Regions.Span_Vectors.Vector;
      Row_Spans : Regions.Span_Vectors.Vector;
      Scratch : Regions.Span_Vectors.Vector;
   end record;

   --  Start.
   --  @param P Painter to prepare.
   --  @param View A valid caller view the size of Frame.
   --  @param Frame The picture frame.
   --  @param Background Color the view is filled with first.
   procedure Start
     (P : in out Painter;
      View : Images.Mutable_Image_View;
      Frame : Geometry.Rect;
      Background : Images.RGB_Color)
     with Pre => Images.Is_Valid (View);

   --  Charge.
   --  @param P Painter whose work grows.
   --  @param S Session whose drawing budget applies.
   --  @param Units Units of work about to be done.
   --  @return Success, or Limit_Exceeded when the drawing budget would be crossed.
   function Charge (P : in out Painter; S : Sessions.Session; Units : Natural) return Results.Result;

   --  Unsupported.
   --  @param S Session whose strictness decides.
   --  @param Event The opcode that cannot be rendered yet.
   --  @return Unsupported_Feature strictly; success with an Approximated_Rendering warning otherwise.
   function Unsupported (S : in out Sessions.Session; Event : Pictures.Opcode_Event) return Results.Result;

   --  Copy bits.
   --  @param P Painter.
   --  @param S Session positioned at the pixel data of Header.
   --  @param Header The bits opcode's header.
   --  @param Mask Its mask region, when Header.Masked.
   --  @param Event The opcode, for diagnostics.
   --  @return Success, or the failure; the pixel data is consumed in either case of success.
   function Copy_Bits
     (P : in out Painter;
      S : in out Sessions.Session;
      Header : Pixmaps.Bits_Header;
      Mask : in out Regions.Region;
      Event : Pictures.Opcode_Event) return Results.Result;
end Pictlib.Internal.Rendering;
