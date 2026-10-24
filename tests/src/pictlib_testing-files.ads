with Pictlib.Images;
with Pictlib.Streams;

--  Fixture files, read from the tests crate's directory.
package Pictlib_Testing.Files is
   type Bytes_Access is access Pictlib.Streams.Byte_Array;

   --  Load: the whole of fixtures/<Name>.
   function Load (Name : String) return Bytes_Access;
   --  Load path: the whole of the file at Path.
   function Load_Path (Path : String) return Bytes_Access;

   --  A binary Netpbm raster: P6 (8-bit RGB) or P4 (1-bit, 1 is black).
   type Raster is record
      Data : Bytes_Access;
      Kind : Character := '6';
      Width : Natural := 0;
      Height : Natural := 0;
      First_Pixel : Positive := 1;
   end record;

   --  Read raster: the file at Path as a Netpbm raster whose pixels all lie within it.
   --  @param Path A file, which may be missing or written by another program.
   --  @param Item The raster; meaningful only when the result is True.
   --  @return True when the file is a complete P6 or P4 raster with 8-bit samples.
   function Read_Raster (Path : String; Item : out Raster) return Boolean;
   --  Load raster: fixtures/<Name> as a Netpbm raster, which must be one.
   function Load_Raster (Name : String) return Raster;
   --  Pixel of a raster.
   function Pixel (Item : Raster; X, Y : Natural) return Pictlib.Images.RGB_Color;
end Pictlib_Testing.Files;
