with Interfaces;
with Pictlib.Fonts;
with Pictlib.Geometry;
with Pictlib.Images;
with Pictlib.Internal.Canvas;
with Pictlib.Internal.Coverage;
with Pictlib.Internal.Patterns;
with Pictlib.Internal.Pixmaps;
with Pictlib.Internal.Regions;
with Pictlib.Internal.Sessions;
with Pictlib.Internal.Text;
with Pictlib.Internal.Transfer_Modes;
with Pictlib.Pictures;
with Pictlib.Results;

--  Drawing state while a picture renders onto the caller's view. Coordinates read from the picture are local;
--  the Origin opcode moves the local system, and a local point P is picture point P - Origin. Canvas pixel (0, 0)
--  is the frame's top-left corner.
package Pictlib.Internal.Rendering is
   subtype Area is Regions.Area;

   --  The origin, the pen location and the text origin stay within this many units of picture coordinate 0, so
   --  every coordinate derived from them fits the arithmetic the renderer uses.
   Reach : constant := 2 ** 24;

   --  Within reach.
   --  @param Value A picture coordinate.
   --  @return True when Value is within Reach.
   function Within_Reach (Value : Integer) return Boolean is (Value in -Reach .. Reach);

   --  The origin stays a 16-bit coordinate inside Reach, so every point read after it is within reach.
   Origin_Reach : constant := Reach - 2 ** 15;

   --  Origin within reach.
   --  @param Value An origin coordinate.
   --  @return True when Value is within Origin_Reach.
   function Origin_Within_Reach (Value : Integer) return Boolean is (Value in -Origin_Reach .. Origin_Reach);

   --  The port's three patterns.
   type Pattern_Slot is (Back_Slot, Pen_Slot, Fill_Slot);
   type Port_Patterns is array (Pattern_Slot) of Patterns.Pattern;

   --  Default pattern.
   --  @param Slot A port pattern.
   --  @return QuickDraw's default for it: white for the background, black for the pen and fill.
   function Default_Pattern (Slot : Pattern_Slot) return Patterns.Pattern is
     (Patterns.From_Bits (if Slot = Back_Slot then Patterns.White else Patterns.Black));

   type Painter is limited record
      Target : Canvas.Canvas;
      --  The canvas in picture coordinates.
      Window : Area;
      Origin_H : Integer := 0;
      Origin_V : Integer := 0;
      Has_Clip : Boolean := False;
      --  In local coordinates, as read: the clip keeps them when the origin moves, so moving costs nothing.
      Clip : Regions.Region;
      Colors : Transfer_Modes.Port_Colors;
      Pen_Width : Integer := 1;
      Pen_Height : Integer := 1;
      Pen_Mode : Transfer_Modes.Mode_Kind := Transfer_Modes.Copy;
      Pattern_Set : Port_Patterns := [for Slot in Pattern_Slot => Default_Pattern (Slot)];
      --  Pen location in picture coordinates.
      Pen_H : Integer := 0;
      Pen_V : Integer := 0;
      Oval_Width : Integer := 0;
      Oval_Height : Integer := 0;
      --  HiliteMode makes the next drawing operation highlight.
      Hilite_Next : Boolean := False;
      --  A drawn QuickTime image makes the bits opcode right after it -- its placeholder for systems without
      --  the codec -- skipped.
      Skip_Next_Bits : Boolean := False;
      --  The last shapes, as read (local coordinates), for the "same" opcodes.
      Last_Rect : Geometry.Rect;
      Last_Polygon : Coverage.Point_Vectors.Vector;
      Last_Region : Regions.Region;
      Text_State : Text.Text_State;
      Fonts : Pictlib.Fonts.Font_Table;
      Font_Cache : aliased Text.Font_Cache;
      --  Pixels painted and work done, against Limits.Max_Drawing_Work.
      Work : Pixel_Count := 0;
      Clip_Spans : Regions.Span_Vectors.Vector;
      Mask_Spans : Regions.Span_Vectors.Vector;
      Row_Spans : Regions.Span_Vectors.Vector;
      Scratch : Regions.Span_Vectors.Vector;
   end record;

   type Paint_Kind is (Pattern_Paint, Invert_Paint);

   --  How covered pixels change: one of the port's patterns, named rather than copied, through a transfer mode,
   --  or inversion.
   type Paint is record
      Kind : Paint_Kind := Pattern_Paint;
      Source : Pattern_Slot := Pen_Slot;
      Mode : Transfer_Modes.Mode_Kind := Transfer_Modes.Copy;
   end record;

   --  Start.
   --  @param P Painter to prepare; the port state is QuickDraw's default.
   --  @param View A valid caller view the size of Frame.
   --  @param Frame The picture frame.
   --  @param Background Color the view is filled with first.
   --  @param Font_Files The TrueType fonts text renders with.
   procedure Start
     (P : in out Painter;
      View : Images.Mutable_Image_View;
      Frame : Geometry.Rect;
      Background : Images.RGB_Color;
      Font_Files : Pictlib.Fonts.Font_Table)
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
   function Charge (P : in out Painter; S : Sessions.Session; Units : Pixel_Count) return Results.Result;
   --  Drawing work still allowed: what a shape may spend being built.
   function Allowance (P : Painter; S : Sessions.Session) return Pixel_Count is
     (S.Budget.Max_Drawing_Work - Pixel_Count'Min (P.Work, S.Budget.Max_Drawing_Work));

   --  Unsupported.
   --  @param S Session whose strictness decides.
   --  @param Event The opcode that cannot be rendered yet.
   --  @param Expected What a release supports, when a count says why, as the diagnostic's Expected.
   --  @param Actual What the picture asks for, as the diagnostic's Actual.
   --  @return Unsupported_Feature strictly; success with an Approximated_Rendering warning otherwise.
   function Unsupported
     (S : in out Sessions.Session;
      Event : Pictures.Opcode_Event;
      Expected, Actual : Byte_Count := 0) return Results.Result;

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

   --  Clip row.
   --  @param P Painter whose Row_Spans are narrowed to the clip region's row Y, moved by the origin.
   --  @param S Session whose drawing budget applies.
   --  @param Y Picture row.
   --  @return Success, or Limit_Exceeded when the drawing budget is crossed.
   function Clip_Row (P : in out Painter; S : Sessions.Session; Y : Integer) return Results.Result;
   --  Get.
   --  @param P Painter.
   --  @param X Picture column inside the canvas.
   --  @param Y Picture row inside the canvas.
   --  @return The pixel there.
   function Get (P : Painter; X, Y : Integer) return Images.RGB_Color;
   --  Put.
   --  @param P Painter.
   --  @param X Picture column inside the canvas.
   --  @param Y Picture row inside the canvas.
   --  @param Color New pixel.
   procedure Put (P : in out Painter; X, Y : Integer; Color : Images.RGB_Color);

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
