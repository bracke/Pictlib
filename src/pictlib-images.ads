with Pictlib.Streams;

--  Caller-owned pixel views. A descriptor states the visible extent and how the rows lie in storage; a view
--  borrows the storage. The decoder writes only into views whose descriptor and storage are valid.
package Pictlib.Images is
   pragma Preelaborate;

   type RGB_Color is record
      Red : Byte := 0;
      Green : Byte := 0;
      Blue : Byte := 0;
   end record;

   White : constant RGB_Color := (16#FF#, 16#FF#, 16#FF#);
   Black : constant RGB_Color := (0, 0, 0);

   --  Bytes per pixel.
   --  @param Format Pixel format.
   --  @return 3 or 4.
   function Bytes_Per_Pixel (Format : Pixel_Format) return Byte_Count
     with SPARK_Mode => On, Post => Bytes_Per_Pixel'Result in 3 .. 4;

   type Image_Descriptor is record
      Width : Image_Width := 1;
      Height : Image_Height := 1;
      Format : Pixel_Format := RGBA_32;
      --  Bytes from the start of one row to the start of the next.
      Stride : Row_Stride := 0;
      --  Bytes of storage the view may touch, from Storage'First.
      Accessible_Bytes : Byte_Count := 0;
   end record;

   type Image_View is record
      Descriptor : Image_Descriptor;
      Storage : access constant Streams.Byte_Array;
   end record;

   type Mutable_Image_View is record
      Descriptor : Image_Descriptor;
      Storage : access Streams.Byte_Array;
   end record;

   --  Minimum row bytes.
   --  @param Width Pixels per row.
   --  @param Format Pixel format.
   --  @return Bytes one row of pixels occupies.
   function Minimum_Row_Bytes (Width : Image_Width; Format : Pixel_Format) return Byte_Count
     with SPARK_Mode => On;
   --  Descriptor is valid.
   --  @param Descriptor Descriptor to check.
   --  @param Storage_Length Bytes of the storage it describes.
   --  @return True when the stride holds a row, the last row ends within Accessible_Bytes without overflow, and
   --  the storage holds Accessible_Bytes.
   function Descriptor_Is_Valid (Descriptor : Image_Descriptor; Storage_Length : Natural) return Boolean
     with SPARK_Mode => On;
   --  Is valid.
   --  @param View View to check.
   --  @return True when the storage is present and the descriptor is valid for it.
   function Is_Valid (View : Image_View) return Boolean with SPARK_Mode => Off;
   --  Is valid.
   --  @param View View to check.
   --  @return True when the storage is present and the descriptor is valid for it.
   function Is_Valid (View : Mutable_Image_View) return Boolean with SPARK_Mode => Off;
end Pictlib.Images;
