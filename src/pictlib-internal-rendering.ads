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

   --  The drawing machinery: the caller's view and the span buffers rows are painted through. Only the row
   --  helpers below use it.
   type Engine is limited private;

   --  A QuickDraw port being drawn: its state, which the opcodes change, and the engine that paints.
   type Painter is limited record
      Machine : Engine;
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
   end record;

   type Paint_Kind is (Pattern_Paint, Invert_Paint);

   --  How covered pixels change: one of the port's patterns, named rather than copied, through a transfer mode,
   --  or inversion.
   type Paint is record
      Kind : Paint_Kind := Pattern_Paint;
      Source : Pattern_Slot := Pen_Slot;
      Mode : Transfer_Modes.Mode_Kind := Transfer_Modes.Copy;
   end record;

   --  Start: a painter for one render, its canvas the caller's view, its port state QuickDraw's default.
   --  @param P Painter to prepare.
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

   --  Unsupported: a construct a release cannot render, reported by the strictness rule.
   --  @param S Session whose strictness decides.
   --  @param Event The opcode that cannot be rendered yet.
   --  @param Expected What a release supports, when a count says why, as the diagnostic's Expected.
   --  @param Actual What the picture asks for, as the diagnostic's Actual.
   --  @return Unsupported_Feature strictly; success with an Approximated_Rendering warning otherwise.
   function Unsupported
     (S : in out Sessions.Session;
      Event : Pictures.Opcode_Event;
      Expected, Actual : Byte_Count := 0) return Results.Result;

   --  Take hilite: HiliteMode applies to the one drawing after it, drawn or not.
   --  @param P Painter; its HiliteMode flag is cleared.
   --  @return True when HiliteMode preceded this drawing, which then draws in the hilite mode.
   function Take_Hilite (P : in out Painter) return Boolean;

   --  Mode: a transfer mode word, classified.
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


   --  Every drawing paints a row at a time through these: Begin_Row (Begin_Masked_Row when a mask applies),
   --  then Paint_Row, so clipping, masking and charging happen once, in one order. Fill does the same for a shape's
   --  rows. Nothing else writes a pixel.

   --  Begin row.
   --  @param P Painter whose Row_Spans become columns Left .. Right - 1 of row Y inside the window, cut by the
   --  clip region; none when that is empty.
   --  @param S Session whose drawing budget the clip walk is charged to.
   --  @param Y Picture row.
   --  @param Left First picture column.
   --  @param Right Column after the last.
   --  @return Success, or Limit_Exceeded when the drawing budget is crossed.
   function Begin_Row (P : in out Painter; S : in out Sessions.Session; Y, Left, Right : Integer)
     return Results.Result;
   --  Begin masked row: Begin_Row, then, when Masked and the row holds a span, its cut by Mask's row Y, the
   --  mask walk charged before the spans are cut.
   --  @param P Painter whose Row_Spans become the row's.
   --  @param S Session whose drawing budget applies.
   --  @param Y Picture row.
   --  @param Left First picture column.
   --  @param Right Column after the last.
   --  @param Mask Mask region, in picture coordinates.
   --  @param Masked True when Mask applies.
   --  @return Success, or Limit_Exceeded when the drawing budget is crossed.
   function Begin_Masked_Row
     (P : in out Painter;
      S : in out Sessions.Session;
      Y, Left, Right : Integer;
      Mask : in out Regions.Region;
      Masked : Boolean) return Results.Result;
   --  Paint row: each span of Row_Spans is charged, then each of its pixels becomes Color_At of what is under it;
   --  nothing is painted past the budget.
   --  @param P Painter whose begun row is painted.
   --  @param S Session whose drawing budget applies.
   --  @param Y Picture row.
   --  @return Success, or Limit_Exceeded when the drawing budget is crossed.
   generic
      with function Color_At (X, Y : Integer; Under : Images.RGB_Color) return Images.RGB_Color;
   function Paint_Row (P : in out Painter; S : in out Sessions.Session; Y : Integer) return Results.Result;

   --  Fill: a shape painted row by row, clipped, through How.
   --  @param P Painter.
   --  @param S Session whose drawing budget applies.
   --  @param Shape Pixels to change, in picture coordinates; clipped by the clip region and the canvas.
   --  @param How How they change.
   --  @return Success, or Limit_Exceeded when the drawing budget is crossed.
   function Fill
     (P : in out Painter;
      S : in out Sessions.Session;
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
private
   type Engine is limited record
      Target : Canvas.Canvas;
      Clip_Spans : Regions.Span_Vectors.Vector;
      Mask_Spans : Regions.Span_Vectors.Vector;
      Row_Spans : Regions.Span_Vectors.Vector;
      Scratch : Regions.Span_Vectors.Vector;
   end record;
end Pictlib.Internal.Rendering;
