with Ada.Containers.Hashed_Maps;
with Ada.Unchecked_Deallocation;
with Ada.Containers.Vectors;
with Interfaces;
with Pictlib.Internal.PackBits;
with Pictlib.Internal.Writers;
with Pictlib.Opcodes;

package body Pictlib.Encoding is
   use type Images.RGB_Color;
   use type Geometry.Fixed;

   package Writers renames Internal.Writers;

   procedure Streams_Free is new Ada.Unchecked_Deallocation (Streams.Byte_Array, Streams.Byte_Array_Access);

   --  rowBytes keeps flags in its two high bits.
   Largest_Row_Bytes : constant := 16#3FFE#;
   Largest_Colors : constant := 256;

   type Pixel is record
      Color : Images.RGB_Color;
      Alpha : Byte := 16#FF#;
   end record;

   function Pixel_At (Image : Images.Image_View; X, Y : Natural) return Pixel is
      Descriptor : constant Images.Image_Descriptor := Image.Descriptor;
      At_Pixel : constant Positive :=
        Image.Storage'First
        + Natural (Byte_Count (Y) * Byte_Count (Descriptor.Stride)
                   + Byte_Count (X) * Images.Bytes_Per_Pixel (Descriptor.Format));
      Data : Streams.Byte_Array renames Image.Storage.all;
   begin
      case Descriptor.Format is
         when RGB_24 => return ((Data (At_Pixel), Data (At_Pixel + 1), Data (At_Pixel + 2)), 16#FF#);
         when BGR_24 => return ((Data (At_Pixel + 2), Data (At_Pixel + 1), Data (At_Pixel)), 16#FF#);
         when RGBA_32 => return ((Data (At_Pixel), Data (At_Pixel + 1), Data (At_Pixel + 2)), Data (At_Pixel + 3));
         when BGRA_32 => return ((Data (At_Pixel + 2), Data (At_Pixel + 1), Data (At_Pixel)), Data (At_Pixel + 3));
         when ARGB_32 => return ((Data (At_Pixel + 1), Data (At_Pixel + 2), Data (At_Pixel + 3)), Data (At_Pixel));
      end case;
   end Pixel_At;

   function Key (Color : Images.RGB_Color) return Natural is
     (Natural (Color.Red) * 65_536 + Natural (Color.Green) * 256 + Natural (Color.Blue));

   function Hash (Item : Natural) return Ada.Containers.Hash_Type is (Ada.Containers.Hash_Type (Item));

   package Index_Maps is new Ada.Containers.Hashed_Maps (Natural, Natural, Hash, "=");
   package Color_Vectors is new Ada.Containers.Vectors (Natural, Images.RGB_Color);

   --  The image's colors in the order they first appear, up to one more than a color table holds.
   type Palette is record
      Indexes : Index_Maps.Map;
      Colors : Color_Vectors.Vector;
      Black_And_White : Boolean := True;
   end record;

   procedure Survey (Image : Images.Image_View; Item : out Palette) is
   begin
      for Y in 0 .. Natural (Image.Descriptor.Height) - 1 loop
         for X in 0 .. Natural (Image.Descriptor.Width) - 1 loop
            declare
               Color : constant Images.RGB_Color := Pixel_At (Image, X, Y).Color;
            begin
               if Color /= Images.Black and then Color /= Images.White then
                  Item.Black_And_White := False;
               end if;
               if Natural (Item.Colors.Length) <= Largest_Colors and then not Item.Indexes.Contains (Key (Color)) then
                  Item.Indexes.Insert (Key (Color), Natural (Item.Colors.Length));
                  Item.Colors.Append (Color);
               end if;
            end;
         end loop;
         exit when Natural (Item.Colors.Length) > Largest_Colors and then not Item.Black_And_White;
      end loop;
   end Survey;

   function Luminance (Color : Images.RGB_Color) return Natural is
     ((299 * Natural (Color.Red) + 587 * Natural (Color.Green) + 114 * Natural (Color.Blue)) / 1000);

   function Invalid (Expected, Actual : Byte_Count) return Results.Result is
     (Results.Failure (Errors.Make (Errors.Invalid_Argument, (Expected => Expected, Actual => Actual, others => <>))));

   --  Bytes per stored row: pixels padded to an even count of bytes.
   function Row_Bytes (Layout : Layout_Kind; Width : Natural) return Natural is
     (case Layout is
         when Direct_32 => 4 * Width,
         when Indexed_8 => Width + Width mod 2,
         when others => ((Width + 7) / 8 + 1) / 2 * 2);

   --  One picture, measured or written.
   function Write_Picture
     (Out_Bytes : in out Writers.Writer;
      Image : Images.Image_View;
      Settings : Options;
      Layout : Layout_Kind;
      Colors : Palette;
      Picture_Size : Byte_Count) return Results.Result
   is
      Width : constant Natural := Natural (Image.Descriptor.Width);
      Height : constant Natural := Natural (Image.Descriptor.Height);
      Frame : constant Geometry.Rect := (0, 0, Coordinate (Height), Coordinate (Width));
      Components : constant Natural :=
        (if Settings.Keep_Alpha and then Image.Descriptor.Format in RGBA_32 | BGRA_32 | ARGB_32 then 4 else 3);
      Stored : constant Natural := Row_Bytes (Layout, Width);
      --  Packed direct rows are component planes; anything stored unpacked is the stored row.
      Unpacked_Length : constant Natural :=
        (if Layout = Direct_32 and then Stored >= 8 then Components * Width else Stored);
      Outcome : Results.Result := Results.Success;

      procedure Step (Item : Results.Result) is
      begin
         if Results.Succeeded (Outcome) then
            Outcome := Item;
         end if;
      end Step;

      procedure Put_Pixmap_Tail (Pack, Pixel_Type, Pixel_Size, Component_Count, Component_Size : Natural) is
      begin
         Step (Writers.Put_Word (Out_Bytes, 0));
         Step (Writers.Put_Word (Out_Bytes, Pack));
         Step (Writers.Put_Long (Out_Bytes, 0));
         Step (Writers.Put_Long (Out_Bytes, Interfaces.Unsigned_32 (Settings.Horizontal_Resolution)));
         Step (Writers.Put_Long (Out_Bytes, Interfaces.Unsigned_32 (Settings.Vertical_Resolution)));
         Step (Writers.Put_Word (Out_Bytes, Pixel_Type));
         Step (Writers.Put_Word (Out_Bytes, Pixel_Size));
         Step (Writers.Put_Word (Out_Bytes, Component_Count));
         Step (Writers.Put_Word (Out_Bytes, Component_Size));
         for Index in 1 .. 3 loop  --  planeBytes, pmTable, pmReserved
            Step (Writers.Put_Long (Out_Bytes, 0));
         end loop;
      end Put_Pixmap_Tail;

      --  One row as it is stored before packing.
      procedure Fill_Row (Y : Natural; Row : out Streams.Byte_Array) is
      begin
         Row := [others => 0];
         for X in 0 .. Width - 1 loop
            declare
               Item : constant Pixel := Pixel_At (Image, X, Y);
            begin
               case Layout is
                  when Direct_32 =>
                     if Stored < 8 then
                        --  Unpacked chunky pixels: pad (or alpha), red, green, blue.
                        Row (Row'First + 4 * X .. Row'First + 4 * X + 3) :=
                          [(if Components = 4 then Item.Alpha else 0), Item.Color.Red, Item.Color.Green,
                           Item.Color.Blue];
                     else
                        declare
                           Red_Plane : constant Natural := (if Components = 4 then Width else 0);
                        begin
                           if Components = 4 then
                              Row (Row'First + X) := Item.Alpha;
                           end if;
                           Row (Row'First + Red_Plane + X) := Item.Color.Red;
                           Row (Row'First + Red_Plane + Width + X) := Item.Color.Green;
                           Row (Row'First + Red_Plane + 2 * Width + X) := Item.Color.Blue;
                        end;
                     end if;
                  when Indexed_8 =>
                     Row (Row'First + X) := Byte (Colors.Indexes.Element (Key (Item.Color)));
                  when others =>
                     if Luminance (Item.Color) < Natural (Settings.Mono_Threshold) then
                        Row (Row'First + X / 8) := Row (Row'First + X / 8) or Byte (2 ** (7 - X mod 8));
                     end if;
               end case;
            end;
         end loop;
      end Fill_Row;
   begin
      Writers.Start_Picture (Out_Bytes);
      Step (Writers.Put_Word (Out_Bytes, Natural (Picture_Size mod 16#1_0000#)));
      Step (Writers.Put_Rect (Out_Bytes, Frame));
      Step (Writers.Put_Word (Out_Bytes, Natural (Opcodes.Version_Op)));
      Step (Writers.Put_Word (Out_Bytes, 16#02FF#));
      --  HeaderOp, extended version 2: -2, reserved, the resolution, the frame, reserved.
      Step (Writers.Put_Word (Out_Bytes, Natural (Opcodes.Header_Op)));
      Step (Writers.Put_Word (Out_Bytes, -2));
      Step (Writers.Put_Word (Out_Bytes, 0));
      Step (Writers.Put_Long (Out_Bytes, Interfaces.Unsigned_32 (Settings.Horizontal_Resolution)));
      Step (Writers.Put_Long (Out_Bytes, Interfaces.Unsigned_32 (Settings.Vertical_Resolution)));
      Step (Writers.Put_Rect (Out_Bytes, Frame));
      Step (Writers.Put_Long (Out_Bytes, 0));
      Step (Writers.Put_Word (Out_Bytes, Natural (Opcodes.Default_Hilite)));
      Step (Writers.Put_Word (Out_Bytes, Natural (Opcodes.Clip)));
      Step (Writers.Put_Word (Out_Bytes, 10));
      Step (Writers.Put_Rect (Out_Bytes, Frame));

      case Layout is
         when Direct_32 =>
            Step (Writers.Put_Word (Out_Bytes, Natural (Opcodes.Direct_Bits_Rect)));
            Step (Writers.Put_Long (Out_Bytes, 16#0000_00FF#));  --  baseAddr
            Step (Writers.Put_Word (Out_Bytes, 16#8000# + Stored));
            Step (Writers.Put_Rect (Out_Bytes, Frame));
            Put_Pixmap_Tail (Pack => 4, Pixel_Type => 16, Pixel_Size => 32, Component_Count => Components,
                             Component_Size => 8);
         when Indexed_8 =>
            Step (Writers.Put_Word (Out_Bytes, Natural (Opcodes.Pack_Bits_Rect)));
            Step (Writers.Put_Word (Out_Bytes, 16#8000# + Stored));
            Step (Writers.Put_Rect (Out_Bytes, Frame));
            Put_Pixmap_Tail (Pack => 0, Pixel_Type => 0, Pixel_Size => 8, Component_Count => 1, Component_Size => 8);
            --  The color table: each entry's value is its index; 8-bit components widened to 16 bits.
            Step (Writers.Put_Long (Out_Bytes, 0));
            Step (Writers.Put_Word (Out_Bytes, 0));
            Step (Writers.Put_Word (Out_Bytes, Natural (Colors.Colors.Length) - 1));
            for Index in 0 .. Natural (Colors.Colors.Length) - 1 loop
               declare
                  Color : constant Images.RGB_Color := Colors.Colors (Index);
               begin
                  Step (Writers.Put_Word (Out_Bytes, Index));
                  Step (Writers.Put_Word (Out_Bytes, 257 * Natural (Color.Red)));
                  Step (Writers.Put_Word (Out_Bytes, 257 * Natural (Color.Green)));
                  Step (Writers.Put_Word (Out_Bytes, 257 * Natural (Color.Blue)));
               end;
            end loop;
         when others =>
            Step (Writers.Put_Word (Out_Bytes, Natural (Opcodes.Pack_Bits_Rect)));
            Step (Writers.Put_Word (Out_Bytes, Stored));
            Step (Writers.Put_Rect (Out_Bytes, Frame));
      end case;
      Step (Writers.Put_Rect (Out_Bytes, Frame));  --  srcRect
      Step (Writers.Put_Rect (Out_Bytes, Frame));  --  dstRect
      Step (Writers.Put_Word (Out_Bytes, 0));      --  srcCopy

      --  Rows: unpacked below 8 rowBytes, otherwise PackBits behind a byte count, or a word count above 250.
      declare
         Row : Streams.Byte_Array_Access := new Streams.Byte_Array (1 .. Unpacked_Length);
         Packed : Streams.Byte_Array_Access :=
           new Streams.Byte_Array (1 .. Internal.PackBits.Worst_Case (Unpacked_Length, 1));
         Packed_Length : Natural;
      begin
         for Y in 0 .. Height - 1 loop
            exit when not Results.Succeeded (Outcome);
            Fill_Row (Y, Row.all);
            if Stored < 8 then
               Step (Writers.Put (Out_Bytes, Row.all));
            else
               Internal.PackBits.Pack (Row.all, 1, Packed.all, Packed_Length);
               if Stored > 250 then
                  Step (Writers.Put_Word (Out_Bytes, Packed_Length));
               else
                  Step (Writers.Put_Byte (Out_Bytes, Packed_Length));
               end if;
               Step (Writers.Put (Out_Bytes, Packed (1 .. Packed_Length)));
            end if;
         end loop;
         Streams_Free (Row);
         Streams_Free (Packed);
      end;
      Step (Writers.Align (Out_Bytes));
      Step (Writers.Put_Word (Out_Bytes, Natural (Opcodes.End_Picture)));
      return Outcome;
   end Write_Picture;

   procedure Initialize
     (Object : in out Encoder;
      Output : not null access Streams.Destination'Class;
      Encode_Options : Options := (others => <>);
      Encode_Limits : Limits.Limit_Set := Limits.Default_Limits) is
   begin
      Object.Output := Output.all'Unchecked_Access;
      Object.Encode_Options := Encode_Options;
      Object.Encode_Limits := Encode_Limits;
      Object.Layout := Auto;
      Object.Written := 0;
      Object.First_Error := Errors.Make (Errors.No_Error);
      Object.Current_State := Ready;
   end Initialize;

   function State (Object : Encoder) return Encoder_State is (Object.Current_State);

   function Wrong_State (Object : Encoder) return Results.Result is
     (Results.Failure
        (if Object.Current_State = Cancelled then Errors.Operation_Cancelled else Errors.Invalid_State));

   function Fail (Object : in out Encoder; Outcome : Results.Result) return Results.Result is
   begin
      if not Results.Succeeded (Outcome) then
         Object.First_Error := Outcome.First_Error;
         Object.Current_State := Failed;
      end if;
      return Outcome;
   end Fail;

   function Encode (Object : in out Encoder; Image : Images.Image_View) return Results.Result is
      Settings : constant Options := Object.Encode_Options;
      Budget : constant Limits.Limit_Set := Object.Encode_Limits;
      Colors : Palette;
      Layout : Layout_Kind;
   begin
      if Object.Current_State /= Ready then
         return Wrong_State (Object);
      elsif not Images.Is_Valid (Image) then
         return Invalid (0, 0);
      elsif Settings.Horizontal_Resolution <= 0 or else Settings.Vertical_Resolution <= 0 then
         return Invalid (1, 0);
      elsif Image.Descriptor.Width > Budget.Max_Frame_Width or else Image.Descriptor.Height > Budget.Max_Frame_Height
      then
         return Fail
           (Object,
            Results.Failure
              (Errors.Make
                 (Errors.Limit_Exceeded,
                  (Expected => Byte_Count (Budget.Max_Frame_Width), Actual => Byte_Count (Image.Descriptor.Width),
                   Limit => (if Image.Descriptor.Width > Budget.Max_Frame_Width then Frame_Width_Limit
                             else Frame_Height_Limit),
                   others => <>))));
      end if;

      Survey (Image, Colors);
      Layout := Settings.Layout;
      if Layout = Auto then
         Layout :=
           (if Colors.Black_And_White and then not Settings.Keep_Alpha then Mono_1
            elsif Natural (Colors.Colors.Length) <= Largest_Colors and then not Settings.Keep_Alpha then Indexed_8
            else Direct_32);
      end if;
      if Layout = Indexed_8 and then Natural (Colors.Colors.Length) > Largest_Colors then
         return Fail
           (Object,
            Results.Failure
              (Errors.Make
                 (Errors.Too_Many_Colors,
                  (Expected => Largest_Colors, Actual => Byte_Count (Colors.Colors.Length), others => <>))));
      end if;
      declare
         Width : constant Natural := Natural (Image.Descriptor.Width);
         Stored : constant Natural := Row_Bytes (Layout, Width);
         Buffers : constant Byte_Count :=
           Byte_Count (4 * Width) + Byte_Count (Internal.PackBits.Worst_Case (4 * Width, 1));
      begin
         if Stored > Largest_Row_Bytes then
            --  rowBytes must stay below 16#4000#.
            return Fail (Object, Invalid (Largest_Row_Bytes, Byte_Count (Stored)));
         elsif Buffers > Budget.Max_Allocation_Bytes then
            return Fail
              (Object,
               Results.Failure
                 (Errors.Make
                    (Errors.Limit_Exceeded,
                     (Expected => Budget.Max_Allocation_Bytes, Actual => Buffers, Limit => Allocation_Byte_Limit,
                      others => <>))));
         end if;
      end;

      --  picSize needs the picture's length before the picture is written: measure it first.
      declare
         Header_Bytes : constant Byte_Count := (if Settings.File_Header then 512 else 0);
         Measure : Writers.Writer;
         Output : Writers.Writer;
         Outcome : Results.Result;
      begin
         Writers.Start
           (Measure, null, Budget.Max_Output_Bytes - Byte_Count'Min (Header_Bytes, Budget.Max_Output_Bytes));
         Outcome := Write_Picture (Measure, Image, Settings, Layout, Colors, 0);
         if Results.Succeeded (Outcome) then
            Writers.Start (Output, Object.Output, Budget.Max_Output_Bytes);
            if Settings.File_Header then
               Outcome := Writers.Put (Output, [1 .. 512 => 0]);
            end if;
            if Results.Succeeded (Outcome) then
               Outcome := Write_Picture (Output, Image, Settings, Layout, Colors, Writers.Picture_Count (Measure));
            end if;
            Object.Written := Writers.Count (Output);
         end if;
         if Results.Succeeded (Outcome) then
            Object.Layout := Layout;
            Object.Current_State := Encoded;
         end if;
         return Fail (Object, Outcome);
      end;
   end Encode;

   function Finish (Object : in out Encoder) return Results.Result is
   begin
      if Object.Current_State /= Encoded then
         return Wrong_State (Object);
      end if;
      declare
         Flushed : constant Errors.Error := Object.Output.Flush;
      begin
         if Errors.Is_Fatal (Flushed) then
            return Fail (Object, Results.Failure (Flushed));
         end if;
      end;
      Object.Current_State := Finished;
      return Results.Success;
   end Finish;

   function Layout_Used (Object : Encoder) return Layout_Kind is (Object.Layout);

   function Bytes_Written (Object : Encoder) return Byte_Count is (Object.Written);

   function Last_Error (Object : Encoder) return Errors.Error is (Object.First_Error);

   procedure Cancel (Object : in out Encoder) is
   begin
      if Object.Current_State in Ready | Encoded then
         Object.Current_State := Cancelled;
      end if;
   end Cancel;

   procedure Finalize (Object : in out Encoder) is
   begin
      Object.Output := null;
      Object.Written := 0;
      Object.First_Error := Errors.Make (Errors.No_Error);
      Object.Current_State := Created;
   end Finalize;
end Pictlib.Encoding;
