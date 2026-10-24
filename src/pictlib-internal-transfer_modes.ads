with Interfaces;
with Pictlib.Images;

--  QuickDraw transfer modes on 8-bit RGB. A source is a copy's pixel or a pattern's sample. Boolean modes colorize:
--  each source component s says how near to black the source is, and that share of the foreground (or
--  background) color is used. With a black foreground and a white background this is QuickDraw's black-and-white
--  arithmetic; Copy reproduces the source exactly.
package Pictlib.Internal.Transfer_Modes is
   pragma Preelaborate;

   type Mode_Kind is
     (Copy, Or_Mode, Xor_Mode, Bic, Not_Copy, Not_Or, Not_Xor, Not_Bic,
      Blend, Add_Pin, Add_Over, Sub_Pin, Transparent, Add_Max, Sub_Over, Ad_Min,
      Hilite);

   type Port_Colors is record
      Foreground : Images.RGB_Color := Images.Black;
      Background : Images.RGB_Color := Images.White;
      --  Weight of blend, pin of addPin and subPin.
      Operation : Images.RGB_Color := Images.Black;
      Highlight : Images.RGB_Color := Images.Black;
   end record;

   --  Classify.
   --  @param Mode A transfer mode word: srcCopy .. notSrcBic (0 .. 7), patCopy .. notPatBic (8 .. 15), blend ..
   --  adMin (32 .. 39), grayishTextOr (49, as Or) or hilite (50); the ditherCopy flag 16#40# is ignored.
   --  @param Kind The mode.
   --  @return False for any other value.
   function Classify (Mode : Interfaces.Unsigned_16; Kind : out Mode_Kind) return Boolean;

   --  Compose.
   --  @param Kind Transfer mode.
   --  @param Source Source pixel or pattern sample.
   --  @param Destination Pixel already there.
   --  @param Colors Port colors.
   --  @param Colorize False for color patterns, which QuickDraw draws without the foreground and background.
   --  @return The resulting pixel.
   function Compose
     (Kind : Mode_Kind;
      Source : Images.RGB_Color;
      Destination : Images.RGB_Color;
      Colors : Port_Colors;
      Colorize : Boolean := True) return Images.RGB_Color;

   --  Invert.
   --  @param Item Pixel.
   --  @return Each component inverted, as InvertRect does.
   function Invert (Item : Images.RGB_Color) return Images.RGB_Color is
     ((not Item.Red, not Item.Green, not Item.Blue));
end Pictlib.Internal.Transfer_Modes;
