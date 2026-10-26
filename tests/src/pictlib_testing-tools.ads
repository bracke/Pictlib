--  What the tools of the tests crate share: host lookups, where they run, and how they report.
with Ada.Containers.Indefinite_Vectors;

package Pictlib_Testing.Tools is
   package Name_Vectors is new Ada.Containers.Indefinite_Vectors (Positive, String);

   --  Files below.
   --  @param Directory A directory.
   --  @param Recursive Whether files in its subdirectories are included too.
   --  @return The absolute names of its ordinary files, hidden entries (a leading '.') left out, sorted, so a tool
   --  walks the same files in the same order on every file system; none when Directory does not exist.
   function Files_Below (Directory : String; Recursive : Boolean := True) return Name_Vectors.Vector;

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

   type Option is access constant String;
   type Option_List is array (Positive range <>) of Option;

   --  Arguments known: every command-line argument is one of Flags, or one of Valued followed by its value; an
   --  unknown one is reported as a usage failure, so a misspelt option is not silently ignored.
   --  @param Flags Options that stand alone.
   --  @param Valued Options that take the argument after them.
   --  @return True when every argument is known.
   function Arguments_Known (Flags : Option_List; Valued : Option_List := [1 .. 0 => null]) return Boolean;

   --  Version of.
   --  @param Program An external program's path.
   --  @param Flag The argument that makes it print its version: "-version" for ImageMagick, "--version" else.
   --  @return The first line it prints, so a report names the version an oracle ran at; "" when it fails.
   function Version_Of (Program : String; Flag : String := "--version") return String;
   --  Report version: Label and Program's version, printed.
   procedure Report_Version (Label, Program : String; Flag : String := "--version");

   --  Gnatprove.
   --  @return The gnatprove `alr install gnatprove` put under the Alire home, else one on PATH (as `alr exec`
   --  provides it); "" when there is none.
   function Gnatprove return String;
end Pictlib_Testing.Tools;
