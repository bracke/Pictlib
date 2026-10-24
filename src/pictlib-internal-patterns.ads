with Ada.Containers.Vectors;
with Pictlib.Images;
with Pictlib.Internal.Sessions;
with Pictlib.Results;

--  QuickDraw patterns: an 8x8 bit pattern whose 1 bits are the foreground and 0 bits the background, a color
--  pixel pattern (PixPat type 1) drawn with its own colors, or a dither pattern (type 2) drawn as its RGB color.
--  Patterns tile from picture coordinate (0, 0).
package Pictlib.Internal.Patterns is
   type Bit_Rows is array (Natural range 0 .. 7) of Byte;

   Black : constant Bit_Rows := [others => 16#FF#];
   White : constant Bit_Rows := [others => 0];

   type Pattern_Kind is (Bit_Pattern, Color_Pattern, Solid_Color);

   type Pattern is private;

   --  From bits.
   --  @param Rows 8 bytes, top row first, bit 7 leftmost.
   --  @return The bit pattern.
   function From_Bits (Rows : Bit_Rows) return Pattern;
   --  Kind.
   --  @param Item Pattern.
   --  @return Its kind.
   function Kind (Item : Pattern) return Pattern_Kind;
   --  Sample.
   --  @param Item Pattern.
   --  @param X Picture column.
   --  @param Y Picture row.
   --  @return Black or white for a bit pattern, otherwise the pattern's color.
   function Sample (Item : Pattern; X, Y : Integer) return Images.RGB_Color;

   --  Uniform.
   --  @param Item Pattern.
   --  @param Color Its one sample, when it has one.
   --  @return True when every sample of Item is the same.
   function Uniform (Item : Pattern; Color : out Images.RGB_Color) return Boolean;

   --  Read bit pattern.
   --  @param S Session positioned at 8 pattern bytes.
   --  @param Item The pattern.
   --  @return Operation result.
   function Read_Bit_Pattern (S : in out Sessions.Session; Item : out Pattern) return Results.Result;
   --  Read pixel pattern.
   --  @param S Session positioned at a PixPat.
   --  @param Item The pattern; its old tile is released before the new one is set aside. After a failure it is
   --  incomplete, and the caller puts its default back.
   --  @param Allowance Drawing work a tile's decoding may take, a unit per pixel and per row; a tile is decoded
   --  only when that fits.
   --  @param Work The drawing work it took, for the caller to charge: a unit for any pattern, plus a tile's
   --  decoding. The unit alone may exceed Allowance; the charge then fails.
   --  @return Success, Pattern_Invalid for an unknown type, Limit_Exceeded past Allowance, the allocation budget
   --  or the pixels a tile can index, or the pixmap's failure.
   function Read_Pixel_Pattern
     (S : in out Sessions.Session;
      Item : out Pattern;
      Allowance : Pixel_Count;
      Work : out Pixel_Count) return Results.Result;

private
   package Color_Vectors is new Ada.Containers.Vectors (Natural, Images.RGB_Color, Images."=");

   type Pattern is record
      Kind : Pattern_Kind := Bit_Pattern;
      Bits : Bit_Rows := Black;
      Color : Images.RGB_Color := Images.Black;
      Width : Positive := 8;
      Height : Positive := 8;
      Tile : Color_Vectors.Vector;
   end record;
end Pictlib.Internal.Patterns;
