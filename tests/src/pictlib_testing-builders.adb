package body Pictlib_Testing.Builders is
   use type Pictlib.Streams.Byte_Array;

   function B (Value : Natural) return Bytes is ([1 => Pictlib.Byte (Value)]);

   function W (Value : Integer) return Bytes is
      Raw : constant Natural := (if Value < 0 then Value + 16#1_0000# else Value);
   begin
      return [Pictlib.Byte (Raw / 256), Pictlib.Byte (Raw mod 256)];
   end W;

   function L (Value : Long_Long_Integer) return Bytes is
     (W (Integer (Value / 16#1_0000#)) & W (Integer (Value mod 16#1_0000#)));

   function Rect (Top, Left, Bottom, Right : Integer) return Bytes is (W (Top) & W (Left) & W (Bottom) & W (Right));

   function Zeros (Count : Natural) return Bytes is ([1 .. Count => 0]);

   function Text (Item : String) return Bytes is
      Result : Bytes (1 .. Item'Length);
   begin
      for Index in Item'Range loop
         Result (Index - Item'First + 1) := Pictlib.Byte (Character'Pos (Item (Index)));
      end loop;
      return Result;
   end Text;

   function Region (Top, Left, Bottom, Right : Integer) return Bytes is (W (10) & Rect (Top, Left, Bottom, Right));

   function L_Region return Bytes is
     (W (36) & Rect (0, 0, 4, 4) & W (0) & W (0) & W (2) & W (16#7FFF#) & W (2) & W (2) & W (4) & W (16#7FFF#)
      & W (4) & W (0) & W (4) & W (16#7FFF#) & W (16#7FFF#));

   function V1_Prefix (Top, Left, Bottom, Right : Integer; Size : Natural := 0) return Bytes is
     (W (Size) & Rect (Top, Left, Bottom, Right) & B (16#11#) & B (16#01#));

   function V2_Prefix (Top, Left, Bottom, Right : Integer; Size : Natural := 0) return Bytes is
     (W (Size) & Rect (Top, Left, Bottom, Right) & W (16#0011#) & W (16#02FF#)
      & W (16#0C00#) & W (-2) & W (0) & L (72 * 16#1_0000#) & L (72 * 16#1_0000#)
      & Rect (Top, Left, Bottom, Right) & L (0));

   function V2_Picture (Top, Left, Bottom, Right : Integer; Body_Bytes : Bytes) return Bytes is
     (V2_Prefix (Top, Left, Bottom, Right) & Body_Bytes & W (16#00FF#));

   function Table_Header (Flags, Entries : Natural) return Bytes is (L (0) & W (Flags) & W (Entries - 1));

   function Table_Entry (Value, Red, Green, Blue : Natural) return Bytes is
     (W (Value) & W (Red) & W (Green) & W (Blue));

   function QuickTime
     (Codec : String;
      Width, Height : Natural;
      Data : Bytes;
      Scale_H : Long_Long_Integer := 16#1_0000#;
      Scale_V : Long_Long_Integer := 16#1_0000#;
      Move_H : Long_Long_Integer := 0;
      Move_V : Long_Long_Integer := 0;
      Skew : Long_Long_Integer := 0;
      Mode : Natural := 16#40#;
      Source : Bytes := [1 .. 0 => 0];
      Matte : Bytes := [1 .. 0 => 0];
      Mask : Bytes := [1 .. 0 => 0];
      Description_Size : Natural := 86) return Bytes
   is
      function Fixed (Value : Long_Long_Integer) return Bytes is
        (L (if Value < 0 then Value + 16#1_0000_0000# else Value));
      Source_Rect : constant Bytes := (if Source'Length = 0 then Rect (0, 0, Height, Width) else Source);
      Description : constant Bytes :=
        L (Long_Long_Integer (Description_Size)) & Text (Codec) & L (0) & W (0) & W (0) & W (0) & W (0)
        & Text ("appl") & L (0) & L (16#300#) & W (Width) & W (Height) & L (72 * 16#1_0000#) & L (72 * 16#1_0000#)
        & L (Long_Long_Integer (Data'Length)) & W (1) & Zeros (32) & W (24) & W (-1)
        & Zeros (Natural'Max (0, Description_Size - 86));
      Payload : constant Bytes :=
        W (0) & Fixed (Scale_H) & Fixed (Skew) & L (0) & L (0) & Fixed (Scale_V) & L (0)
        & Fixed (Move_H) & Fixed (Move_V) & L (16#4000_0000#)
        & L (Long_Long_Integer (Matte'Length)) & Rect (0, 0, 0, 0) & W (Mode) & Source_Rect & L (16#300#)
        & L (Long_Long_Integer (Mask'Length)) & Matte & Mask & Description & Data;
      Whole : constant Bytes := W (16#8200#) & L (Long_Long_Integer (Payload'Length)) & Payload;
   begin
      return (if Whole'Length mod 2 = 0 then Whole else Whole & B (0));
   end QuickTime;

   function Pixmap_Tail (Pack_Type, Pixel_Size, Component_Count, Component_Size : Natural) return Bytes is
     (W (0) & W (Pack_Type) & L (0) & L (72 * 16#1_0000#) & L (72 * 16#1_0000#)
      & W ((if Pixel_Size >= 16 then 16 else 0)) & W (Pixel_Size) & W (Component_Count) & W (Component_Size)
      & L (0) & L (0) & L (0));

   function Pic (Width, Height : Natural; Body_Bytes : Bytes) return Bytes is
     (V2_Picture (0, 0, Height, Width, Body_Bytes));

   function Op_Rect (Op, Top, Left, Bottom, Right : Integer) return Bytes is (W (Op) & Rect (Top, Left, Bottom, Right));

   function Origin (Dh, Dv : Integer) return Bytes is (W (16#0C#) & W (Dh) & W (Dv));

   function Pen_Size (V, H : Integer) return Bytes is (W (16#07#) & W (V) & W (H));

   function Pen_Mode (Mode : Natural) return Bytes is (W (16#08#) & W (Mode));

   function RGB (Op, Red, Green, Blue : Natural) return Bytes is (W (Op) & W (Red) & W (Green) & W (Blue));

   function Bitmap_2x8
     (Mode : Natural := 0; Source, Destination : Bytes := Rect (0, 0, 2, 8)) return Bytes is
     (W (16#98#) & W (2) & Rect (0, 0, 2, 8) & Source & Destination & W (Mode)
      & B (16#A5#) & B (0) & B (16#0F#) & B (0));

   function Repeat (Item : Bytes; Count : Natural) return Bytes is
      Result : Bytes (1 .. Item'Length * Count);
   begin
      for Index in 0 .. Count - 1 loop
         Result (1 + Index * Item'Length .. (Index + 1) * Item'Length) := Item;
      end loop;
      return Result;
   end Repeat;
end Pictlib_Testing.Builders;
