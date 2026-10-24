package body Pictlib.Internal.Transfer_Modes is
   use type Interfaces.Unsigned_16;
   use type Images.RGB_Color;

   Dither_Flag : constant := 16#40#;

   function Classify (Mode : Interfaces.Unsigned_16; Kind : out Mode_Kind) return Boolean is
      Value : constant Natural := Natural (Mode and not Dither_Flag);
   begin
      Kind := Copy;
      case Value is
         when 0 .. 15 =>
            Kind := Mode_Kind'Val (Value mod 8);
         when 32 .. 39 =>
            Kind := Mode_Kind'Val (Mode_Kind'Pos (Blend) + Value - 32);
         when 49 =>
            Kind := Or_Mode;
         when 50 =>
            Kind := Hilite;
         when others =>
            return False;
      end case;
      return True;
   end Classify;

   type Component is range 0 .. 255;

   function Mix (Dark, Light, Share : Component) return Byte is
     --  Share of Light, the rest Dark: Share = 255 is all Light.
     (Byte ((Natural (Dark) * Natural (255 - Share) + Natural (Light) * Natural (Share) + 127) / 255));

   function Compose
     (Kind : Mode_Kind;
      Source : Images.RGB_Color;
      Destination : Images.RGB_Color;
      Colors : Port_Colors;
      Colorize : Boolean := True;
      Bit_Source : Boolean := False) return Images.RGB_Color
   is
      Fore : constant Images.RGB_Color := (if Colorize then Colors.Foreground else Images.Black);
      Back : constant Images.RGB_Color := (if Colorize then Colors.Background else Images.White);
      --  What the arithmetic modes and transparent work on: a bit pattern's 1 bits are the foreground and its 0
      --  bits the background, as for every mode; a copied pixel is itself. Worked out only for those modes.
      function Painted return Images.RGB_Color is
        (if Colorize and then Bit_Source
         then (Mix (Component (Fore.Red), Component (Back.Red), Component (Source.Red)),
               Mix (Component (Fore.Green), Component (Back.Green), Component (Source.Green)),
               Mix (Component (Fore.Blue), Component (Back.Blue), Component (Source.Blue)))
         else Source);

      function Each (S, D, F, B, Op : Byte) return Byte is
         Inverse : constant Component := Component (255 - S);
         Plain : constant Component := Component (S);
         Shade : constant Component := (if Kind in Not_Copy .. Not_Bic then Inverse else Plain);
      begin
         case Kind is
            when Copy | Not_Copy => return Mix (Component (F), Component (B), Shade);
            when Or_Mode | Not_Or => return Mix (Component (F), Component (D), Shade);
            when Bic | Not_Bic => return Mix (Component (B), Component (D), Shade);
            when Xor_Mode | Not_Xor => return D xor Byte (255 - Shade);
            when Blend => return Mix (Component (D), Component (S), Component (Op));
            when Add_Pin => return Byte'Min (Byte (Natural'Min (Natural (S) + Natural (D), 255)), Op);
            when Add_Over => return Byte ((Natural (S) + Natural (D)) mod 256);
            when Sub_Pin => return Byte'Max (Byte (Integer'Max (Integer (D) - Integer (S), 0)), Op);
            when Sub_Over => return Byte ((Integer (D) - Integer (S)) mod 256);
            when Add_Max => return Byte'Max (S, D);
            when Ad_Min => return Byte'Min (S, D);
            when Transparent | Hilite => return D;
         end case;
      end Each;
   begin
      case Kind is
         when Transparent =>
            declare
               Color : constant Images.RGB_Color := Painted;
            begin
               return (if Color = Colors.Background then Destination else Color);
            end;
         when Hilite =>
            --  Where the source is dark, the background and the highlight color trade places.
            if Natural (Source.Red) + Natural (Source.Green) + Natural (Source.Blue) >= 3 * 128 then
               return Destination;
            elsif Destination = Colors.Background then
               return Colors.Highlight;
            elsif Destination = Colors.Highlight then
               return Colors.Background;
            end if;
            return Destination;
         when Blend | Add_Pin | Add_Over | Sub_Pin | Add_Max | Sub_Over | Ad_Min =>
            declare
               Color : constant Images.RGB_Color := Painted;
            begin
               return
                 (Each (Color.Red, Destination.Red, Fore.Red, Back.Red, Colors.Operation.Red),
                  Each (Color.Green, Destination.Green, Fore.Green, Back.Green, Colors.Operation.Green),
                  Each (Color.Blue, Destination.Blue, Fore.Blue, Back.Blue, Colors.Operation.Blue));
            end;
         when others =>
            return
              (Each (Source.Red, Destination.Red, Fore.Red, Back.Red, Colors.Operation.Red),
               Each (Source.Green, Destination.Green, Fore.Green, Back.Green, Colors.Operation.Green),
               Each (Source.Blue, Destination.Blue, Fore.Blue, Back.Blue, Colors.Operation.Blue));
      end case;
   end Compose;
   function Effect
     (Kind : Mode_Kind;
      Source : Images.RGB_Color;
      Colors : Port_Colors;
      Colorize : Boolean;
      Color : out Images.RGB_Color) return Effect_Kind
   is
      --  The share of the destination the or and bic modes keep is the source component (its inverse for the
      --  not modes): none of it when every component is dark, all of it when every one is light.
      Shade : constant Images.RGB_Color :=
        (if Kind in Not_Copy .. Not_Bic then (not Source.Red, not Source.Green, not Source.Blue) else Source);
   begin
      Color := Compose (Kind, Source, Images.White, Colors, Colorize, Bit_Source => Colorize);
      case Kind is
         when Copy | Not_Copy =>
            return Constant_Color;
         when Or_Mode | Bic | Not_Or | Not_Bic =>
            if Shade = Images.Black then
               return Constant_Color;
            elsif Shade = Images.White then
               return Unchanged;
            end if;
            return Depends_On_Destination;
         when others =>
            return Depends_On_Destination;
      end case;
   end Effect;
end Pictlib.Internal.Transfer_Modes;
