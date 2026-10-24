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

   function Pixmap_Tail (Pack_Type, Pixel_Size, Component_Count, Component_Size : Natural) return Bytes is
     (W (0) & W (Pack_Type) & L (0) & L (72 * 16#1_0000#) & L (72 * 16#1_0000#)
      & W ((if Pixel_Size >= 16 then 16 else 0)) & W (Pixel_Size) & W (Component_Count) & W (Component_Size)
      & L (0) & L (0) & L (0));
end Pictlib_Testing.Builders;
