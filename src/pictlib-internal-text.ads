with Ada.Containers.Indefinite_Ordered_Maps;
with Ada.Finalization;
with Ada.Strings.Unbounded;
with Interfaces;
with Pictlib.Fonts;
with Pictlib.Geometry;
with Textrender;

--  Text state of the port, the Mac Roman character set, and the TrueType renderers text is drawn with.
package Pictlib.Internal.Text is
   package Name_Maps is new Ada.Containers.Indefinite_Ordered_Maps (Fonts.Font_ID, String, Fonts."<");

   --  TxFace bits.
   Bold : constant := 1;
   Italic : constant := 2;
   Underline : constant := 4;
   Outline : constant := 8;
   Shadow : constant := 16;
   Condense : constant := 32;
   Extend : constant := 64;

   type Text_State is record
      Font : Fonts.Font_ID := 0;
      Face : Byte := 0;
      --  srcOr, QuickDraw's default text mode.
      Mode : Interfaces.Unsigned_16 := 1;
      --  0 is the default size, 12.
      Size : Natural := 0;
      Space_Extra : Geometry.Fixed := 0;
      Char_Extra : Integer := 0;
      Unit_Ratio : Boolean := True;
      --  Where the last text was drawn from, in picture coordinates; DHText and DVText move it.
      Origin_H : Integer := 0;
      Origin_V : Integer := 0;
      --  fontName: the family names this picture gave its font IDs.
      Names : Name_Maps.Map;
   end record;

   --  To unicode.
   --  @param Item A Mac Roman character.
   --  @return Its Unicode code point.
   function To_Unicode (Item : Byte) return Textrender.Codepoint;

   --  Textrender keeps scratch buffers shared by every renderer, so no two textrender calls may run at once,
   --  even on different renderers. A Textrender_Guard holds the process-wide lock for its lifetime.
   type Textrender_Guard is new Ada.Finalization.Limited_Controlled with private;

   type Font_Cache is limited private;

   --  Acquire.
   --  @param Cache Cache of loaded fonts; the least recently used one is replaced when it is full, unless Path
   --  cannot be read at all. A file that is read but does not load still frees the slot it was loaded into.
   --  @param Path TrueType file.
   --  @param Size Pixel size.
   --  @param Slot The renderer's slot.
   --  @return Textrender's status of loading the font, Success when it was loaded already.
   function Acquire (Cache : in out Font_Cache; Path : String; Size : Positive; Slot : out Positive)
     return Textrender.Status_Code;
   --  Cached.
   --  @param Cache Cache of loaded fonts.
   --  @param Path TrueType file.
   --  @param Size Pixel size.
   --  @return True when Acquire would find the font loaded and load nothing.
   function Cached (Cache : Font_Cache; Path : String; Size : Positive) return Boolean;
   --  Renderer.
   --  @param Cache Cache.
   --  @param Slot A slot Acquire returned.
   --  @return Its renderer.
   function Renderer (Cache : aliased in out Font_Cache; Slot : Positive)
     return not null access Textrender.Renderer;
   --  Clear.
   --  @param Cache Cache whose fonts are released.
   procedure Clear (Cache : in out Font_Cache);

   --  Atlas bytes.
   --  @param Size Pixel size.
   --  @return Bytes of the square alpha atlas a font of that size is loaded with.
   function Atlas_Bytes (Size : Positive) return Byte_Count;

   --  File bytes.
   --  @param Path TrueType file.
   --  @return Its size, which textrender copies whole on every load; 0 when it cannot be read, as the load
   --  then fails.
   function File_Bytes (Path : String) return Byte_Count;

   --  Drawing work of loading a font: clearing its atlas and reading and parsing its file.
   --  @param Size Pixel size.
   --  @param File The font file's bytes.
   --  @return The units to charge before a font is loaded.
   function Load_Work (Size : Positive; File : Byte_Count) return Pixel_Count;

   --  Drawing work of one glyph request: rasterizing at most a cell, sampled 16 times a pixel, as measured.
   --  @param Size Pixel size.
   --  @return The units to charge before each character is looked up, drawn or not.
   function Glyph_Work (Size : Positive) return Pixel_Count;

private
   type Textrender_Guard is new Ada.Finalization.Limited_Controlled with record
      Held : Boolean := False;
   end record;

   overriding procedure Initialize (Guard : in out Textrender_Guard);
   overriding procedure Finalize (Guard : in out Textrender_Guard);

   Slots : constant := 8;

   type Slot_Type is limited record
      Renderer : aliased Textrender.Renderer;
      Path : Ada.Strings.Unbounded.Unbounded_String;
      Size : Natural := 0;
      Used : Boolean := False;
      Stamp : Natural := 0;
   end record;

   type Slot_Array is array (1 .. Slots) of Slot_Type;

   type Font_Cache is limited record
      Items : Slot_Array;
      Clock : Natural := 0;
   end record;
end Pictlib.Internal.Text;
