package body Pictlib.Fonts is
   procedure Add (Table : in out Font_Table; Family : String; Path : String) is
   begin
      Table.Names.Include (Family, Path);
   end Add;

   procedure Add (Table : in out Font_Table; ID : Font_ID; Path : String) is
   begin
      Table.IDs.Include (ID, Path);
   end Add;

   procedure Set_Default (Table : in out Font_Table; Path : String) is
   begin
      Table.Default := Ada.Strings.Unbounded.To_Unbounded_String (Path);
   end Set_Default;

   function Classic_Name (ID : Font_ID) return String is
     (case ID is
         when 0 => "Chicago",
         when 1 | 3 => "Geneva",
         when 2 => "New York",
         when 4 => "Monaco",
         when 5 => "Venice",
         when 6 => "London",
         when 7 => "Athens",
         when 8 => "San Francisco",
         when 9 => "Toronto",
         when 11 => "Cairo",
         when 12 => "Los Angeles",
         when 20 => "Times",
         when 21 => "Helvetica",
         when 22 => "Courier",
         when 23 => "Symbol",
         when 24 => "Mobile",
         when others => "");

   function Resolve (Table : Font_Table; ID : Font_ID; Family : String := "") return String is
      Classic : constant String := Classic_Name (ID);
   begin
      if Family'Length > 0 and then Table.Names.Contains (Family) then
         return Table.Names.Element (Family);
      elsif Table.IDs.Contains (ID) then
         return Table.IDs.Element (ID);
      elsif Classic'Length > 0 and then Table.Names.Contains (Classic) then
         return Table.Names.Element (Classic);
      end if;
      return Ada.Strings.Unbounded.To_String (Table.Default);
   end Resolve;
end Pictlib.Fonts;
