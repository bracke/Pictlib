--  What the tools of the tests crate share: host lookups, where they run, and how they report.
package Pictlib_Testing.Tools is
   --  Root.
   --  @return The pictlib tree the current directory is below, "" when it is below none.
   function Root return String;
   --  Alr.
   --  @return The alr on PATH, "" when there is none.
   function Alr return String;

   --  Enter tests directory: tools read fixtures and write artifacts relative to the tests crate, so each
   --  starts by moving there from wherever below the pictlib tree it was run.
   --  @return False, having said so and set a failing exit status, when the current directory is not below a
   --  pictlib tree.
   function Enter_Tests_Directory return Boolean;

   --  Start report: Fail messages are prefixed with Tool.
   procedure Start_Report (Tool : String);
   --  Fail: print "tool: Message" on standard error and count it.
   procedure Fail (Message : String);
   --  Failures.
   --  @return Fail calls so far.
   function Failures return Natural;
   --  Finish report: a nonzero exit status when anything failed.
   procedure Finish_Report;

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
