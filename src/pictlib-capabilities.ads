--  Each constant is True only when its feature is implemented and exercised by the test suite.
package Pictlib.Capabilities is
   pragma Pure;

   Foundation_API : constant Boolean := True;
   Memory_Streams : constant Boolean := True;
   Container_Decoding : constant Boolean := True;
   Opcode_Enumeration : constant Boolean := True;
   Raster_Decoding : constant Boolean := True;
   Vector_Rendering : constant Boolean := True;
   Text_Rendering : constant Boolean := True;
   QuickTime_JPEG_Decoding : constant Boolean := True;
   Metadata_Retention : constant Boolean := True;
   Raster_Encoding : constant Boolean := False;
end Pictlib.Capabilities;
