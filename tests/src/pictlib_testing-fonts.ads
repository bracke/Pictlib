with Pictlib.Fonts;

--  The committed DejaVu fixtures as a font table, for tools and tests that render text.
package Pictlib_Testing.Fonts is
   --  Test table.
   --  @return A table whose default is DejaVu Sans, relative to the tests directory.
   function Test_Table return Pictlib.Fonts.Font_Table;
end Pictlib_Testing.Fonts;
