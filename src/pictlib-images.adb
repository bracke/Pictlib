package body Pictlib.Images is
   function Bytes_Per_Pixel (Format : Pixel_Format) return Byte_Count is
     (case Format is
         when RGB_24 | BGR_24 => 3,
         when RGBA_32 | BGRA_32 | ARGB_32 => 4);

   function Minimum_Row_Bytes (Width : Image_Width; Format : Pixel_Format) return Byte_Count is
     (Byte_Count (Width) * Bytes_Per_Pixel (Format));

   function Descriptor_Is_Valid (Descriptor : Image_Descriptor; Storage_Length : Natural) return Boolean is
      Row_Bytes : constant Byte_Count := Minimum_Row_Bytes (Descriptor.Width, Descriptor.Format);
      Stride_Bytes : constant Byte_Count := Byte_Count (Descriptor.Stride);
      Rows_Before_Last : constant Byte_Count := Byte_Count (Descriptor.Height) - 1;
   begin
      if Stride_Bytes < Row_Bytes then
         return False;
      elsif Rows_Before_Last /= 0 and then Stride_Bytes > (Byte_Count'Last - Row_Bytes) / Rows_Before_Last then
         return False;
      end if;
      return Descriptor.Accessible_Bytes >= Stride_Bytes * Rows_Before_Last + Row_Bytes
        and then Byte_Count (Storage_Length) >= Descriptor.Accessible_Bytes;
   end Descriptor_Is_Valid;

   function Is_Valid (View : Image_View) return Boolean is
     (View.Storage /= null and then Descriptor_Is_Valid (View.Descriptor, View.Storage'Length));

   function Is_Valid (View : Mutable_Image_View) return Boolean is
     (View.Storage /= null and then Descriptor_Is_Valid (View.Descriptor, View.Storage'Length));
end Pictlib.Images;
