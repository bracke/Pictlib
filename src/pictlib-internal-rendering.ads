with Interfaces;
with Pictlib.Geometry;
with Pictlib.Images;
with Pictlib.Internal.Canvas;
with Pictlib.Internal.Coverage;
with Pictlib.Internal.Patterns;
with Pictlib.Internal.Pixmaps;
with Pictlib.Internal.Regions;
with Pictlib.Internal.Sessions;
with Pictlib.Internal.Transfer_Modes;
with Pictlib.Pictures;
with Pictlib.Results;

--  Drawing state while a picture renders onto the caller's view. Coordinates read from the picture are local;
--  the Origin opcode moves the local system, and a local point P is picture point P - Origin. Canvas pixel (0, 0)
--  is the frame's top-left corner.
package Pictlib.Internal.Rendering is
   subtype Area is Regions.Area;

   type Painter is limited record
      Target : Canvas.Canvas;
      --  The canvas in picture coordinates.
      Window : Area;
      Origin_H : Integer := 0;
      Origin_V : Integer := 0;
      Has_Clip : Boolean := False;
      Clip : Regions.Region;
      Colors : Transfer_Modes.Port_Colors;
      Pen_Width : Integer := 1;
      Pen_Height : Integer := 1;
      Pen_Mode : Transfer_Modes.Mode_Kind := Transfer_Modes.Copy;
      Pen_Pattern : Patterns.Pattern := Patterns.From_Bits (Patterns.Black);
      Fill_Pattern : Patterns.Pattern := Patterns.From_Bits (Patterns.Black);
      Back_Pattern : Patterns.Pattern := Patterns.From_Bits (Patterns.White);
      --  Pen location in picture coordinates.
      Pen_H : Integer := 0;
      Pen_V : Integer := 0;
      Oval_Width : Integer := 0;
      Oval_Height : Integer := 0;
      --  HiliteMode makes the next drawing operation highlight.
      Hilite_Next : Boolean := False;
      --  The last shapes, as read (local coordinates), for the "same" opcodes.
      Last_Rect : Geometry.Rect;
      Last_Polygon : Coverage.Point_Vectors.Vector;
      Last_Region : Regions.Region;
      --  Pixels painted and work done, against Limits.Max_Drawing_Work.
      Work : Pixel_Count := 0;
      Clip_Spans : Regions.Span_Vectors.Vector;
      Mask_Spans : Regions.Span_Vectors.Vector;
      Row_Spans : Regions.Span_Vectors.Vector;
      Scratch : Regions.Span_Vectors.Vector;
   end record;

   type Paint_Kind is (Pattern_Paint, Invert_Paint);

   --  How covered pixels change: a pattern through a transfer mode, or inversion.
   type Paint is record
      Kind : Paint_Kind := Pattern_Paint;
      Source : Patterns.Pattern;
      Mode : Transfer_Modes.Mode_Kind := Transfer_Modes.Copy;
   end record;

   --  Start.
   --  @param P Painter to prepare; the port state is QuickDraw's default.
   --  @param View A valid caller view the size of Frame.
   --  @param Frame The picture frame.
   --  @param Background Color the view is filled with first.
   procedure Start
     (P : in out Painter;
      View : Images.Mutable_Image_View;
      Frame : Geometry.Rect;
      Background : Images.RGB_Color)
     with Pre => Images.Is_Valid (View);

   --  To picture.
   --  @param P Painter.
   --  @param Item A local rectangle.
   --  @return Item in picture coordinates.
   function To_Picture (P : Painter; Item : Geometry.Rect) return Area is
     (Regions.To_Area (Item, -P.Origin_H, -P.Origin_V));

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

   --  Mode.
   --  @param S Session whose strictness decides.
   --  @param Event The opcode, for diagnostics.
   --  @param Value A transfer mode word.
   --  @param Kind The mode; Copy when a lenient session replaces an unknown one.
   --  @return Success, or Transfer_Mode_Invalid strictly for an unknown mode.
   function Mode
     (S : in out Sessions.Session;
      Event : Pictures.Opcode_Event;
      Value : Interfaces.Unsigned_16;
      Kind : out Transfer_Modes.Mode_Kind) return Results.Result;

   --  Fill.
   --  @param P Painter.
   --  @param S Session whose drawing budget applies.
   --  @param Shape Pixels to change, in picture coordinates; clipped by the clip region and the canvas.
   --  @param How How they change.
   --  @return Success, or Limit_Exceeded when the drawing budget is crossed.
   function Fill
     (P : in out Painter;
      S : Sessions.Session;
      Shape : Coverage.Shape;
      How : Paint) return Results.Result;

   --  Copy bits.
   --  @param P Painter.
   --  @param S Session positioned at the pixel data of Header.
   --  @param Header The bits opcode's header.
   --  @param Mask Its mask region, in local coordinates, when Header.Masked.
   --  @param Event The opcode, for diagnostics.
   --  @return Success, or the failure.
   function Copy_Bits
     (P : in out Painter;
      S : in out Sessions.Session;
      Header : Pixmaps.Bits_Header;
      Mask : in out Regions.Region;
      Event : Pictures.Opcode_Event) return Results.Result;
end Pictlib.Internal.Rendering;
