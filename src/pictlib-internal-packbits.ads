with Pictlib.Streams;

--  Apple PackBits. A flag byte N introduces N + 1 literal units (0 .. 127), one unit repeated 257 - N times
--  (129 .. 255), or nothing (128). A unit is a byte, or a big-endian word for 16-bit pixel rows.
package Pictlib.Internal.PackBits is
   pragma Preelaborate;

   type Unit_Size is range 1 .. 2;

   type Unpack_Status is
     (Exact,     --  the packed bytes unpacked to exactly the output length
      Overrun,   --  the packed bytes describe more than the output holds; the output is filled
      Underrun,  --  the packed bytes ran out before the output was filled; the rest is zero
      Truncated);  --  a run or literal was cut off by the end of the packed bytes

   --  Unpack.
   --  @param Packed One packed row.
   --  @param Unit Bytes per unit.
   --  @param Output Receives the unpacked row; its length is a whole number of units.
   --  @param Written Bytes of Output that were unpacked.
   --  @return Whether the packed row matched Output exactly.
   function Unpack
     (Packed : Streams.Byte_Array;
      Unit : Unit_Size;
      Output : out Streams.Byte_Array;
      Written : out Natural) return Unpack_Status
     with Pre => Output'Length mod Natural (Unit) = 0;

   --  Pack.
   --  @param Row One row of whole units.
   --  @param Unit Bytes per unit.
   --  @param Output Receives the packed row; it must hold Worst_Case (Row'Length, Unit) bytes.
   --  @param Written Bytes of Output used.
   procedure Pack
     (Row : Streams.Byte_Array;
      Unit : Unit_Size;
      Output : out Streams.Byte_Array;
      Written : out Natural)
     with Pre => Row'Length mod Natural (Unit) = 0;

   --  Worst case.
   --  @param Length Bytes of an unpacked row.
   --  @param Unit Bytes per unit.
   --  @return The most bytes Pack can produce for it.
   function Worst_Case (Length : Natural; Unit : Unit_Size) return Natural is
     (Length + (Length / Natural (Unit) + 127) / 128);
end Pictlib.Internal.PackBits;
