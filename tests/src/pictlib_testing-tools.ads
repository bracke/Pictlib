--  Host lookups the tools of the tests crate share.
package Pictlib_Testing.Tools is
   --  Executable suffix.
   --  @return The host's executable suffix: ".exe" on Windows, "" elsewhere.
   function Executable_Suffix return String;

   --  ImageMagick.
   --  @return ImageMagick 7's `magick`, else ImageMagick 6's `convert` -- only when it reports itself as
   --  ImageMagick, so Windows' own convert.exe (a disk converter) is never taken; "" when neither is installed.
   function ImageMagick return String;

   --  Gnatprove.
   --  @return The gnatprove `alr install gnatprove` put under the Alire home, else one on PATH (as `alr exec`
   --  provides it); "" when there is none.
   function Gnatprove return String;
end Pictlib_Testing.Tools;
