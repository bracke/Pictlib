with AUnit.Assertions;

with Pictlib;
with Pictlib.Images;
with Pictlib.Streams;

package body Pictlib_Testing.Test_Images is
   use AUnit.Assertions;
   use type Pictlib.Byte_Count;

   package Images renames Pictlib.Images;

   procedure Pixel_Sizes (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Descriptor_Validation (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure View_Validation (T : in out AUnit.Test_Cases.Test_Case'Class);

   overriding function Name (T : Test) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("images");
   end Name;

   overriding procedure Register_Tests (T : in out Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Pixel_Sizes'Access, "images.pixel_sizes");
      Register_Routine (T, Descriptor_Validation'Access, "images.descriptor_overflow");
      Register_Routine (T, View_Validation'Access, "images.view_validation");
   end Register_Tests;

   procedure Pixel_Sizes (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Images.Bytes_Per_Pixel (Pictlib.RGB_24) = 3 and then Images.Bytes_Per_Pixel (Pictlib.BGR_24) = 3,
              "24-bit formats");
      Assert (Images.Bytes_Per_Pixel (Pictlib.RGBA_32) = 4 and then Images.Bytes_Per_Pixel (Pictlib.BGRA_32) = 4
              and then Images.Bytes_Per_Pixel (Pictlib.ARGB_32) = 4, "32-bit formats");
      Assert (Images.Minimum_Row_Bytes (32_767, Pictlib.ARGB_32) = 131_068, "widest row");
   end Pixel_Sizes;

   procedure Descriptor_Validation (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Exact : constant Images.Image_Descriptor :=
        (Width => 4, Height => 3, Format => Pictlib.RGB_24, Stride => 12, Accessible_Bytes => 36);
      Padded : constant Images.Image_Descriptor :=
        (Width => 4, Height => 3, Format => Pictlib.RGBA_32, Stride => 20, Accessible_Bytes => 56);
   begin
      Assert (Images.Descriptor_Is_Valid (Exact, 36), "a tight descriptor was rejected");
      Assert (Images.Descriptor_Is_Valid (Padded, 56), "a padded descriptor whose last row is short was rejected");
      Assert (not Images.Descriptor_Is_Valid ((Exact with delta Stride => 11), 36), "a short stride was accepted");
      Assert (not Images.Descriptor_Is_Valid ((Exact with delta Accessible_Bytes => 35), 36),
              "accessible bytes short of the last row were accepted");
      Assert (not Images.Descriptor_Is_Valid (Exact, 35), "short storage was accepted");
      Assert (not Images.Descriptor_Is_Valid
                ((Width => 1, Height => 32_767, Format => Pictlib.RGB_24, Stride => Pictlib.Row_Stride'Last,
                  Accessible_Bytes => Pictlib.Byte_Count'Last), Natural'Last),
              "a row span overflowing 63 bits was accepted");
      Assert (Images.Descriptor_Is_Valid
                ((Width => 1, Height => 1, Format => Pictlib.RGB_24, Stride => Pictlib.Row_Stride'Last,
                  Accessible_Bytes => 3), 3),
              "one row with a huge stride needs only that row");
   end Descriptor_Validation;

   procedure View_Validation (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Storage : aliased Pictlib.Streams.Byte_Array := [1 .. 12 => 0];
      Good : constant Images.Mutable_Image_View :=
        (Descriptor => (Width => 2, Height => 2, Format => Pictlib.RGB_24, Stride => 6, Accessible_Bytes => 12),
         Storage => Storage'Unchecked_Access);
      Constant_View : constant Images.Image_View :=
        (Descriptor => Good.Descriptor, Storage => Storage'Unchecked_Access);
   begin
      Assert (Images.Is_Valid (Good) and then Images.Is_Valid (Constant_View), "a good view was rejected");
      Assert (not Images.Is_Valid (Images.Mutable_Image_View'(Descriptor => Good.Descriptor, Storage => null)),
              "a view without storage was accepted");
      Assert (not Images.Is_Valid ((Good with delta Descriptor => (Good.Descriptor with delta Height => 3))),
              "a view larger than its storage was accepted");
   end View_Validation;
end Pictlib_Testing.Test_Images;
