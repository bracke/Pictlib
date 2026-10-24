--  Each constant is True only when its feature is implemented and exercised by the test suite.
package Pictlib.Capabilities is
   pragma Pure;

   Foundation_API : constant Boolean := True;
   Memory_Streams : constant Boolean := True;
   Container_Decoding : constant Boolean := False;
   Opcode_Enumeration : constant Boolean := False;
   Raster_Decoding : constant Boolean := False;
   Vector_Rendering : constant Boolean := False;
   Text_Rendering : constant Boolean := False;
   QuickTime_JPEG_Decoding : constant Boolean := False;
   Metadata_Retention : constant Boolean := False;
   Raster_Encoding : constant Boolean := False;
end Pictlib.Capabilities;
