package body Pictlib_Testing.Fonts is
   function Test_Table return Pictlib.Fonts.Font_Table is
      Table : Pictlib.Fonts.Font_Table := Pictlib.Fonts.Empty;
   begin
      Pictlib.Fonts.Set_Default (Table, "fixtures/fonts/DejaVuSans.ttf");
      return Table;
   end Test_Table;
end Pictlib_Testing.Fonts;
