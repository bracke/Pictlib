package body Pictlib.Opcodes
  with SPARK_Mode => On
is
   function Fixed (Length : Natural) return Length_Rule is ((Rule => Fixed_Data, Fixed_Length => Length));

   function Rule_For (Op : Opcode) return Length_Rule is
   begin
      case Op is
         when 16#0000# => return Fixed (0);
         when 16#0001# => return (Rule => Region_Data, Fixed_Length => 0);
         when 16#0002# => return Fixed (8);
         when 16#0003# => return Fixed (2);
         when 16#0004# => return Fixed (1);
         when 16#0005# => return Fixed (2);
         when 16#0006# => return Fixed (4);
         when 16#0007# => return Fixed (4);
         when 16#0008# => return Fixed (2);
         when 16#0009# .. 16#000A# => return Fixed (8);
         when 16#000B# .. 16#000C# => return Fixed (4);
         when 16#000D# => return Fixed (2);
         when 16#000E# .. 16#000F# => return Fixed (4);
         when 16#0010# => return Fixed (8);
         when 16#0011# => return (Rule => Version_Data, Fixed_Length => 0);
         when 16#0012# .. 16#0014# => return (Rule => Pixel_Pattern_Data, Fixed_Length => 0);
         when 16#0015# .. 16#0016# => return Fixed (2);
         when 16#0017# .. 16#0019# => return Fixed (0);
         when 16#001A# .. 16#001B# => return Fixed (6);
         when 16#001C# => return Fixed (0);
         when 16#001D# => return Fixed (6);
         when 16#001E# => return Fixed (0);
         when 16#001F# => return Fixed (6);
         when 16#0020# => return Fixed (8);
         when 16#0021# => return Fixed (4);
         when 16#0022# => return Fixed (6);
         when 16#0023# => return Fixed (2);
         when 16#0024# .. 16#0027# => return (Rule => Word_Length_Data, Fixed_Length => 0);
         when 16#0028# => return (Rule => Text_Data, Fixed_Length => 4);
         when 16#0029# .. 16#002A# => return (Rule => Text_Data, Fixed_Length => 1);
         when 16#002B# => return (Rule => Text_Data, Fixed_Length => 2);
         when 16#002C# .. 16#002F# => return (Rule => Word_Length_Data, Fixed_Length => 0);
         when 16#0030# .. 16#0037# => return Fixed (8);
         when 16#0038# .. 16#003F# => return Fixed (0);
         when 16#0040# .. 16#0047# => return Fixed (8);
         when 16#0048# .. 16#004F# => return Fixed (0);
         when 16#0050# .. 16#0057# => return Fixed (8);
         when 16#0058# .. 16#005F# => return Fixed (0);
         when 16#0060# .. 16#0067# => return Fixed (12);
         when 16#0068# .. 16#006F# => return Fixed (4);
         when 16#0070# .. 16#0077# => return (Rule => Polygon_Data, Fixed_Length => 0);
         when 16#0078# .. 16#007F# => return Fixed (0);
         when 16#0080# .. 16#0087# => return (Rule => Region_Data, Fixed_Length => 0);
         when 16#0088# .. 16#008F# => return Fixed (0);
         when 16#0090# .. 16#0091# => return (Rule => Bits_Data, Fixed_Length => 0);
         when 16#0092# .. 16#0097# => return (Rule => Word_Length_Data, Fixed_Length => 0);
         when 16#0098# .. 16#009B# => return (Rule => Bits_Data, Fixed_Length => 0);
         when 16#009C# .. 16#009F# => return (Rule => Word_Length_Data, Fixed_Length => 0);
         when 16#00A0# => return Fixed (2);
         when 16#00A1# => return (Rule => Long_Comment_Data, Fixed_Length => 0);
         when 16#00A2# .. 16#00AF# => return (Rule => Word_Length_Data, Fixed_Length => 0);
         when 16#00B0# .. 16#00CF# => return Fixed (0);
         when 16#00D0# .. 16#00FE# => return (Rule => Long_Length_Data, Fixed_Length => 0);
         when 16#00FF# => return (Rule => End_Of_Picture, Fixed_Length => 0);
         when 16#0100# .. 16#7FFF# => return Fixed (2 * Natural (Op / 16#100#));
         when 16#8000# .. 16#80FF# => return Fixed (0);
         when 16#8100# .. 16#FFFF# => return (Rule => Long_Length_Data, Fixed_Length => 0);
      end case;
   end Rule_For;

   function Is_Reserved (Op : Opcode) return Boolean is
   begin
      case Op is
         when 16#0017# .. 16#0019# | 16#0024# .. 16#0027# | 16#002F#
            | 16#0035# .. 16#0037# | 16#003D# .. 16#003F#
            | 16#0045# .. 16#0047# | 16#004D# .. 16#004F#
            | 16#0055# .. 16#0057# | 16#005D# .. 16#005F#
            | 16#0065# .. 16#0067# | 16#006D# .. 16#006F#
            | 16#0075# .. 16#0077# | 16#007D# .. 16#007F#
            | 16#0085# .. 16#0087# | 16#008D# .. 16#008F#
            | 16#0092# .. 16#0097# | 16#009C# .. 16#009F#
            | 16#00A2# .. 16#00FE# =>
            return True;
         when 16#0100# .. 16#FFFF# =>
            return Op not in Header_Op | Compressed_QuickTime | Uncompressed_QuickTime;
         when others =>
            return False;
      end case;
   end Is_Reserved;

   function Verb_Name (Verb : Natural) return String is
     (case Verb is
         when 0 => "frame",
         when 1 => "paint",
         when 2 => "erase",
         when 3 => "invert",
         when others => "fill");

   function Shape_Opcode_Name (Op : Opcode; Shape : String) return String
     with Pre => Shape'Length <= 8
   is
      Verb : constant Natural := Natural (Op mod 8);
      Same : constant Boolean := Op mod 16 >= 8;
   begin
      if Verb > 4 then
         return "Reserved";
      elsif Same then
         return Verb_Name (Verb) & "Same" & Shape;
      else
         return Verb_Name (Verb) & Shape;
      end if;
   end Shape_Opcode_Name;

   function Name (Op : Opcode) return String is
   begin
      if Is_Reserved (Op) then
         return "Reserved";
      end if;
      case Op is
         when 16#0000# => return "NOP";
         when 16#0001# => return "Clip";
         when 16#0002# => return "BkPat";
         when 16#0003# => return "TxFont";
         when 16#0004# => return "TxFace";
         when 16#0005# => return "TxMode";
         when 16#0006# => return "SpExtra";
         when 16#0007# => return "PnSize";
         when 16#0008# => return "PnMode";
         when 16#0009# => return "PnPat";
         when 16#000A# => return "FillPat";
         when 16#000B# => return "OvSize";
         when 16#000C# => return "Origin";
         when 16#000D# => return "TxSize";
         when 16#000E# => return "FgColor";
         when 16#000F# => return "BkColor";
         when 16#0010# => return "TxRatio";
         when 16#0011# => return "VersionOp";
         when 16#0012# => return "BkPixPat";
         when 16#0013# => return "PnPixPat";
         when 16#0014# => return "FillPixPat";
         when 16#0015# => return "PnLocHFrac";
         when 16#0016# => return "ChExtra";
         when 16#001A# => return "RGBFgCol";
         when 16#001B# => return "RGBBkCol";
         when 16#001C# => return "HiliteMode";
         when 16#001D# => return "HiliteColor";
         when 16#001E# => return "DefHilite";
         when 16#001F# => return "OpColor";
         when 16#0020# => return "Line";
         when 16#0021# => return "LineFrom";
         when 16#0022# => return "ShortLine";
         when 16#0023# => return "ShortLineFrom";
         when 16#0028# => return "LongText";
         when 16#0029# => return "DHText";
         when 16#002A# => return "DVText";
         when 16#002B# => return "DHDVText";
         when 16#002C# => return "fontName";
         when 16#002D# => return "lineJustify";
         when 16#002E# => return "glyphState";
         when 16#0030# .. 16#003F# => return Shape_Opcode_Name (Op, "Rect");
         when 16#0040# .. 16#004F# => return Shape_Opcode_Name (Op, "RRect");
         when 16#0050# .. 16#005F# => return Shape_Opcode_Name (Op, "Oval");
         when 16#0060# .. 16#006F# => return Shape_Opcode_Name (Op, "Arc");
         when 16#0070# .. 16#007F# => return Shape_Opcode_Name (Op, "Poly");
         when 16#0080# .. 16#008F# => return Shape_Opcode_Name (Op, "Rgn");
         when 16#0090# => return "BitsRect";
         when 16#0091# => return "BitsRgn";
         when 16#0098# => return "PackBitsRect";
         when 16#0099# => return "PackBitsRgn";
         when 16#009A# => return "DirectBitsRect";
         when 16#009B# => return "DirectBitsRgn";
         when 16#00A0# => return "ShortComment";
         when 16#00A1# => return "LongComment";
         when 16#00FF# => return "OpEndPic";
         when 16#0C00# => return "HeaderOp";
         when 16#8200# => return "CompressedQuickTime";
         when 16#8201# => return "UncompressedQuickTime";
         when others => return "Reserved";
      end case;
   end Name;
end Pictlib.Opcodes;
