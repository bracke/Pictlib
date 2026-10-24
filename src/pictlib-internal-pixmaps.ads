with Interfaces;
with Pictlib.Geometry;
with Pictlib.Images;
with Pictlib.Internal.Regions;
with Pictlib.Internal.Sessions;
with Pictlib.Results;
with Pictlib.Streams;

--  BitMaps, PixMaps, color tables and pixel rows of the bits opcodes (BitsRect .. DirectBitsRgn).
package Pictlib.Internal.Pixmaps is
   type Color_Array is array (Natural range 0 .. 255) of Images.RGB_Color;
   type Defined_Array is array (Natural range 0 .. 255) of Boolean;

   type Color_Table is record
      Colors : Color_Array := [others => Images.Black];
      Defined : Defined_Array := [others => False];
   end record;

   type Pixmap_Fields is record
      Pack : Natural := 0;
      Pixel_Size : Natural := 1;
      Component_Count : Natural := 1;
   end record;

   --  How each row of pixel data is stored.
   type Row_Layout is
     (Unpacked,        --  Raw_Length bytes
      Packed_Bytes,    --  a byte or word count, then PackBits bytes unpacking to Unpacked_Length
      Packed_Words);   --  a byte or word count, then PackBits words unpacking to Unpacked_Length

   --  How a decoded row's bytes become colors.
   type Pixel_Encoding is
     (Bitmap_Bits,     --  1 bit per pixel, 1 black and 0 white
      Indexed_Bits,    --  1, 2, 4 or 8 bits per pixel into the color table
      RGB_555,         --  16-bit words, x RRRRR GGGGG BBBBB
      XRGB_Chunky,     --  4 bytes per pixel, pad or alpha first
      RGB_Triplets,    --  3 bytes per pixel (pack type 2)
      Planar);         --  a row of each component, alpha first when there are four

   type Bits_Header is record
      Op : Opcode := 0;
      Is_Pixmap : Boolean := False;
      Row_Bytes : Natural := 0;
      Bounds : Geometry.Rect;
      Width : Natural := 0;
      Height : Natural := 0;
      Fields : Pixmap_Fields;
      Table : Color_Table;
      Source : Geometry.Rect;
      Destination : Geometry.Rect;
      Mode : Interfaces.Unsigned_16 := 0;
      Masked : Boolean := False;
      Layout : Row_Layout := Unpacked;
      Encoding : Pixel_Encoding := Bitmap_Bits;
      --  Bytes one stored row occupies when unpacked, and bytes it holds once unpacked.
      Raw_Length : Natural := 0;
      Unpacked_Length : Natural := 0;
   end record;

   --  Read pixmap tail.
   --  @param S Session positioned after a PixMap's rowBytes and bounds.
   --  @param Fields Pack type, pixel size and component count.
   --  @return Success, or Pixmap_Invalid for an unknown pixel size or pack type.
   function Read_Pixmap_Tail (S : in out Sessions.Session; Fields : out Pixmap_Fields) return Results.Result;
   --  Read color table.
   --  @param S Session positioned at a color table.
   --  @param Table The colors it defines, reduced to 8 bits.
   --  @return Success, or Color_Table_Invalid for more than 256 entries or (strictly) an index above 255.
   function Read_Color_Table (S : in out Sessions.Session; Table : out Color_Table) return Results.Result;
   --  Skip color table.
   --  @param S Session positioned at a color table.
   --  @return Success, or Color_Table_Invalid for more than 256 entries.
   function Skip_Color_Table (S : in out Sessions.Session) return Results.Result;

   --  Decide layout.
   --  @param S Session, for diagnostics.
   --  @param Header A header whose Op, Is_Pixmap, Row_Bytes, Width and Fields are set; its row layout and pixel
   --  encoding are filled in.
   --  @param For_Decoding True to also check that rows cover the width, as decoding needs.
   --  @return Success, or Pixmap_Invalid when depth, pack type, components and row length disagree.
   function Decide_Layout (S : Sessions.Session; Header : in out Bits_Header; For_Decoding : Boolean)
     return Results.Result;

   --  Read bits header.
   --  @param S Session positioned after a bits opcode.
   --  @param Op The opcode.
   --  @param Header Everything before the pixel data.
   --  @param Mask The mask region of a Rgn opcode, when Read_Mask; otherwise skipped.
   --  @param Read_Mask True to parse the mask region rather than skip it.
   --  @param For_Decoding True to also check that rows cover the bounds width, as decoding needs.
   --  @return Operation result.
   function Read_Bits_Header
     (S : in out Sessions.Session;
      Op : Opcode;
      Header : out Bits_Header;
      Mask : out Regions.Region;
      Read_Mask : Boolean;
      For_Decoding : Boolean) return Results.Result;

   --  Skip pixels.
   --  @param S Session positioned at the pixel data.
   --  @param Header Its header.
   --  @return Operation result.
   function Skip_Pixels (S : in out Sessions.Session; Header : Bits_Header) return Results.Result;

   type Color_Row is array (Natural range <>) of Images.RGB_Color;

   --  Row decoder: holds the heap buffers one opcode's rows are decoded through.
   type Row_Decoder is limited private;

   --  Admit.
   --  @param S Session whose allocation budget applies.
   --  @param Header The opcode's header, its layout decided.
   --  @param Extra Bytes the opcode allocates besides the row buffers, counted with them.
   --  @return Success when Start may allocate the row buffers and Extra, or Limit_Exceeded; allocates nothing.
   function Admit (S : Sessions.Session; Header : Bits_Header; Extra : Byte_Count := 0) return Results.Result;

   --  Start.
   --  @param S Session whose allocation budget applies.
   --  @param Decoder Decoder to prepare.
   --  @param Header The opcode's header.
   --  @param Extra Bytes the opcode allocates besides the row buffers, counted with them.
   --  @return Success, or Limit_Exceeded when the row buffers and Extra exceed the allocation budget.
   function Start
     (S : Sessions.Session;
      Decoder : in out Row_Decoder;
      Header : Bits_Header;
      Extra : Byte_Count := 0) return Results.Result;
   --  Read row.
   --  @param S Session positioned at the next row.
   --  @param Decoder Started decoder.
   --  @param Row Row index from 0, for diagnostics.
   --  @return Success, or the failure; a lenient session repairs bad PackBits and color indexes with warnings.
   function Read_Row (S : in out Sessions.Session; Decoder : in out Row_Decoder; Row : Natural) return Results.Result;
   --  Pixel.
   --  @param Decoder Decoder holding the last row read.
   --  @param Column Pixel column from 0, within the bounds width.
   --  @return The pixel's color.
   function Pixel (Decoder : Row_Decoder; Column : Natural) return Images.RGB_Color;
   --  Finish.
   --  @param Decoder Decoder whose buffers are released.
   procedure Finish (Decoder : in out Row_Decoder);

private
   type Color_Row_Access is access Color_Row;

   type Row_Decoder is limited record
      Header : Bits_Header;
      Stored : Streams.Byte_Array_Access := null;
      Unpacked : Streams.Byte_Array_Access := null;
      Colors : Color_Row_Access := null;
      Bad_Index_Reported : Boolean := False;
   end record;
end Pictlib.Internal.Pixmaps;
