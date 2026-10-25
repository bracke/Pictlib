with Pictlib.Streams;

--  Apple PackBits. A flag byte N introduces N + 1 literal units (0 .. 127), one unit repeated 257 - N times
--  (129 .. 255), or nothing (128). A unit is a byte, or a big-endian word for 16-bit pixel rows.
package Pictlib.Internal.PackBits
  with SPARK_Mode => On
is
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
   --  @param Status Whether the packed row matched Output exactly.
   procedure Unpack
     (Packed : Streams.Byte_Array;
      Unit : Unit_Size;
      Output : out Streams.Byte_Array;
      Written : out Natural;
      Status : out Unpack_Status)
     with Pre => Output'Length mod Natural (Unit) = 0 and then Packed'Last < Natural'Last
                 and then Output'Last < Natural'Last,
          Post => Written <= Output'Length;

   --  Worst case.
   --  @param Length Bytes of an unpacked row.
   --  @return The most bytes Pack can produce for it: a flag byte for every 128 literal bytes.
   function Worst_Case (Length : Natural) return Natural is (Length + (Length + 127) / 128)
     with Pre => Length <= Natural'Last / 2;

   --  Pack: a row of bytes, as the encoder writes rows. Word units are only ever unpacked.
   --  @param Row One row.
   --  @param Output Receives the packed row.
   --  @param Written Bytes of Output used, at most Worst_Case (Row'Length).
   procedure Pack
     (Row : Streams.Byte_Array;
      Output : out Streams.Byte_Array;
      Written : out Natural)
     with SPARK_Mode => Off,
          Pre => Row'Length <= Natural'Last / 2 and then Output'Length >= Worst_Case (Row'Length);
end Pictlib.Internal.PackBits;
