private with Ada.Containers.Indefinite_Hashed_Maps;
private with Ada.Containers.Indefinite_Ordered_Maps;
private with Ada.Strings.Hash_Case_Insensitive;
private with Ada.Strings.Equal_Case_Insensitive;
private with Ada.Strings.Unbounded;

--  The TrueType fonts text renders with. pictlib ships no fonts: the caller maps the Macintosh font families a
--  picture names to TrueType files, by name or by font ID, and may name a default for everything else.
package Pictlib.Fonts is
   type Font_ID is range 0 .. 16#FFFF#;

   type Font_Table is private;

   Empty : constant Font_Table;

   --  Add.
   --  @param Table Table to extend; a later entry for the same name replaces the earlier one.
   --  @param Family A Macintosh font family name, compared without regard to case.
   --  @param Path A TrueType font file.
   procedure Add (Table : in out Font_Table; Family : String; Path : String);
   --  Add.
   --  @param Table Table to extend; a later entry for the same ID replaces the earlier one.
   --  @param ID A font ID, as TxFont names it.
   --  @param Path A TrueType font file.
   procedure Add (Table : in out Font_Table; ID : Font_ID; Path : String);
   --  Set default.
   --  @param Table Table to change.
   --  @param Path The font file for any family the table does not name; empty for none.
   procedure Set_Default (Table : in out Font_Table; Path : String);

   --  Classic name.
   --  @param ID A font ID.
   --  @return The family the classic Macintosh system gave that ID (0 Chicago, 1 and 3 Geneva, 2 New York,
   --  4 Monaco, 20 Times, 21 Helvetica, 22 Courier, 23 Symbol, ...), or "" when it gave none.
   function Classic_Name (ID : Font_ID) return String;

   --  Resolve.
   --  @param Table Table to search.
   --  @param ID The font ID text is drawn in.
   --  @param Family The family name the picture gave that ID (fontName), or "".
   --  @return The file for Family, else for ID, else for Classic_Name (ID), else the default; "" when none.
   function Resolve (Table : Font_Table; ID : Font_ID; Family : String := "") return String;

private
   package Name_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type => String, Element_Type => String, Hash => Ada.Strings.Hash_Case_Insensitive,
      Equivalent_Keys => Ada.Strings.Equal_Case_Insensitive);

   package ID_Maps is new Ada.Containers.Indefinite_Ordered_Maps (Key_Type => Font_ID, Element_Type => String);

   type Font_Table is record
      Names : Name_Maps.Map;
      IDs : ID_Maps.Map;
      Default : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   Empty : constant Font_Table := (others => <>);
end Pictlib.Fonts;
