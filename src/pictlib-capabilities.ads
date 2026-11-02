--  Each constant is True only when its feature is implemented and exercised by the test suite.
package Pictlib.Capabilities is
   pragma Pure;

   --  The core types, errors, results and limits.
   Foundation_API : constant Boolean := True;
   --  Memory_Source and Fixed_Buffer_Destination.
   Memory_Streams : constant Boolean := True;
   --  PICT versions 1 and 2 and extended version 2, with or without the file header.
   Container_Decoding : constant Boolean := True;
   --  Decoding.Enumerate: every opcode, with its ordinal, offset and data length.
   Opcode_Enumeration : constant Boolean := True;
   --  BitMaps and PixMaps rendered into a caller's view.
   Raster_Decoding : constant Boolean := True;
   --  QuickDraw's lines, shapes, regions, patterns and transfer modes.
   Vector_Rendering : constant Boolean := True;
   --  Text drawn with the caller's TrueType fonts.
   Text_Rendering : constant Boolean := True;
   --  JPEG images embedded through the QuickTime opcodes.
   QuickTime_JPEG_Decoding : constant Boolean := True;
   --  Comments, font names, file headers and payloads kept on request.
   Metadata_Retention : constant Boolean := True;
   --  Encoding.Encode: raster PICT version 2.
   Raster_Encoding : constant Boolean := True;
end Pictlib.Capabilities;
