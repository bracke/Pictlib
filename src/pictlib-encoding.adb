with Ada.Unchecked_Deallocation;
with Ada.Containers.Vectors;
with Interfaces;
with Pictlib.Internal.Bytes;
with Pictlib.Internal.Call_Guards;
with Pictlib.Internal.Failures;
with Pictlib.Internal.PackBits;
with Pictlib.Internal.Pixels;
with Pictlib.Opcodes;

package body Pictlib.Encoding is
   use type Images.RGB_Color;
   use type Geometry.Fixed;
   use type Internal.Generation;
   use type Streams.Byte_Array_Access;
   use all type Internal.Call_Guards.Guard;

   package Writers renames Internal.Writers;

   --  The longest even rowBytes a PixMap can state.
   Largest_Row_Bytes : constant := Internal.Pixmap_Row_Bytes_Mask - 1;
   --  The PixMap fields this encoder writes: packType 0 (the default: PackBits from rowBytes 8, as the indexed
   --  layout's rows are written) or 4 (each component plane packed), pixelType
   --  0 (indexed) or 16 (RGBDirect), and the baseAddr QuickDraw writes for a DirectBitsRect.
   Pack_Default : constant := 0;
   Pack_Component_Planes : constant := 4;
   Indexed_Pixels : constant := 0;
   Direct_Pixels : constant := 16;
   Direct_Base_Address : constant := 16#0000_00FF#;
   --  Every color table entry's components, 8 bits widened to 16.
   Widen_Component : constant := 257;
   Largest_Colors : constant := 256;

   --  Where row Y of Image starts in its storage; the next pixel starts Bytes_Per_Pixel on.
   function Row_Start (Image : Images.Image_View; Y : Natural) return Positive is
     (Image.Storage'First + Internal.Pixels.Pixel_Offset (Image.Descriptor, 0, Y));

   function Key (Color : Images.RGB_Color) return Natural is
     (Natural (Color.Red) * 65_536 + Natural (Color.Green) * 256 + Natural (Color.Blue));

   package Color_Vectors is new Ada.Containers.Vectors (Natural, Images.RGB_Color);

   --  A color's index is found in an open-addressed table of twice the most colors kept, so a slot is always
   --  free and every probe sequence ends; it holds no controlled state, unlike a hashed map, so a lookup per
   --  pixel costs no tamper check.
   Slots : constant := 512;
   subtype Slot is Natural range 0 .. Slots - 1;
   No_Key : constant := -1;
   type Slot_Keys is array (Slot) of Integer range No_Key .. 16#FF_FFFF#;
   type Slot_Indexes is array (Slot) of Natural;

   --  The image's colors in the order they first appear, up to one more than a color table holds.
   type Palette is record
      Keys : Slot_Keys := [others => No_Key];
      Indexes : Slot_Indexes := [others => 0];
      Colors : Color_Vectors.Vector;
      Black_And_White : Boolean := True;
   end record;

   --  The slot holding Color's key, or the free slot it would take.
   function Slot_Of (Item : Palette; Color : Images.RGB_Color) return Slot is
      use type Interfaces.Unsigned_32;
      Wanted : constant Natural := Key (Color);
      --  Fibonacci hashing: the key times 2^32 / phi, its top bits.
      At_Slot : Slot := Slot (Interfaces.Shift_Right (Interfaces.Unsigned_32 (Wanted) * 2_654_435_769, 23) mod Slots);
   begin
      while Item.Keys (At_Slot) /= No_Key and then Item.Keys (At_Slot) /= Wanted loop
         At_Slot := (At_Slot + 1) mod Slots;
      end loop;
      return At_Slot;
   end Slot_Of;

   --  The index of a color the survey found.
   function Index_Of (Item : Palette; Color : Images.RGB_Color) return Natural is
     (Item.Indexes (Slot_Of (Item, Color)));

   procedure Survey (Image : Images.Image_View; Item : out Palette) is
      Format : constant Pixel_Format := Image.Descriptor.Format;
      Step : constant Positive := Positive (Images.Bytes_Per_Pixel (Format));
   begin
      for Y in 0 .. Natural (Image.Descriptor.Height) - 1 loop
         declare
            At_Pixel : Positive := Row_Start (Image, Y);
         begin
            for X in 0 .. Natural (Image.Descriptor.Width) - 1 loop
               declare
                  Color : constant Images.RGB_Color := Internal.Pixels.Color_At (Format, Image.Storage.all, At_Pixel);
                  At_Slot : constant Slot := Slot_Of (Item, Color);
               begin
                  if Color /= Images.Black and then Color /= Images.White then
                     Item.Black_And_White := False;
                  end if;
                  if Item.Keys (At_Slot) = No_Key then
                     Item.Keys (At_Slot) := Key (Color);
                     Item.Indexes (At_Slot) := Natural (Item.Colors.Length);
                     Item.Colors.Append (Color);
                  end if;
               end;
               exit when Natural (Item.Colors.Length) > Largest_Colors;
               At_Pixel := At_Pixel + Step;
            end loop;
         end;
         --  More colors than an indexed picture holds are not all black or white.
         exit when Natural (Item.Colors.Length) > Largest_Colors;
      end loop;
   end Survey;

   function Invalid (Expected, Actual : Byte_Count) return Results.Result is
     (Results.Failure (Errors.Make (Errors.Invalid_Argument, (Expected => Expected, Actual => Actual, others => <>))));

   --  Bytes per stored row: pixels padded to an even count of bytes.
   function Row_Bytes (Layout : Layout_Kind; Width : Natural) return Natural is
     (case Layout is
         when Direct_32 => 4 * Width,
         when Indexed_8 => Width + Width mod 2,
         when others => ((Width + 7) / 8 + 1) / 2 * 2);

   --  Alpha is kept only from a view that has it.
   function Alpha_Kept (Image : Images.Image_View; Settings : Options) return Boolean is
     (Settings.Keep_Alpha and then Image.Descriptor.Format in RGBA_32 | BGRA_32 | ARGB_32);

   --  What one image is written as.
   type Plan is record
      Width : Natural := 0;
      Height : Natural := 0;
      Frame : Geometry.Rect;
      Layout : Layout_Kind := Direct_32;
      Components : Natural := 3;
      --  rowBytes, whether rows are packed, and the bytes of a row before packing.
      Stored : Natural := 0;
      Packed : Boolean := False;
      Unpacked_Length : Natural := 0;
   end record;

   function Plan_For (Image : Images.Image_View; Settings : Options; Layout : Layout_Kind) return Plan is
      Width : constant Natural := Natural (Image.Descriptor.Width);
      Height : constant Natural := Natural (Image.Descriptor.Height);
      Components : constant Natural := (if Alpha_Kept (Image, Settings) then 4 else 3);
      Stored : constant Natural := Row_Bytes (Layout, Width);
      Packed : constant Boolean := Stored >= Internal.Smallest_Packed_Row_Bytes;
   begin
      return
        (Width => Width, Height => Height, Frame => (0, 0, Coordinate (Height), Coordinate (Width)),
         Layout => Layout, Components => Components, Stored => Stored, Packed => Packed,
         --  Packed direct rows are component planes; anything stored unpacked is the stored row.
         Unpacked_Length =>
           (if Layout = Direct_32 and then Packed then Internal.Planar_Row_Length (Components, Width) else Stored));
   end Plan_For;

   --  The row buffers writing a picture allocates: a row before packing, and its worst case packed.
   function Row_Buffer_Bytes (Item : Plan) return Byte_Count is
     (Byte_Count (Item.Unpacked_Length) + Byte_Count (Internal.PackBits.Worst_Case (Item.Unpacked_Length)));

   --  Every write after a failure is refused by the writer, which writes nothing more; the first failure is kept.
   procedure Accumulate (Outcome : in out Results.Result; Item : Results.Result) is
   begin
      if Results.Succeeded (Outcome) then
         Outcome := Item;
      end if;
   end Accumulate;

   --  picSize, picFrame, the version opcode, an extended version 2 HeaderOp, DefHilite and a clip of the frame.
   procedure Put_Header
     (Out_Bytes : in out Writers.Writer;
      Settings : Options;
      Item : Plan;
      Picture_Size : Byte_Count;
      Outcome : in out Results.Result) is
   begin
      Writers.Start_Picture (Out_Bytes);
      Accumulate (Outcome, Writers.Put_Word (Out_Bytes, Natural (Picture_Size mod 16#1_0000#)));
      Accumulate (Outcome, Writers.Put_Rect (Out_Bytes, Item.Frame));
      Accumulate (Outcome, Writers.Put_Word (Out_Bytes, Natural (Opcodes.Version_Op)));
      Accumulate (Outcome, Writers.Put_Word (Out_Bytes, Internal.Version_2_Word));
      --  HeaderOp: its version, reserved, the resolution, the frame, reserved.
      Accumulate (Outcome, Writers.Put_Word (Out_Bytes, Natural (Opcodes.Header_Op)));
      Accumulate (Outcome, Writers.Put_Word (Out_Bytes, Internal.Extended_Header_Version));
      Accumulate (Outcome, Writers.Put_Word (Out_Bytes, 0));
      Accumulate (Outcome, Writers.Put_Long (Out_Bytes, Interfaces.Unsigned_32 (Settings.Horizontal_Resolution)));
      Accumulate (Outcome, Writers.Put_Long (Out_Bytes, Interfaces.Unsigned_32 (Settings.Vertical_Resolution)));
      Accumulate (Outcome, Writers.Put_Rect (Out_Bytes, Item.Frame));
      Accumulate (Outcome, Writers.Put_Long (Out_Bytes, 0));
      Accumulate (Outcome, Writers.Put_Word (Out_Bytes, Natural (Opcodes.Default_Hilite)));
      --  A rectangular region: its size word and box.
      Accumulate (Outcome, Writers.Put_Word (Out_Bytes, Natural (Opcodes.Clip)));
      Accumulate (Outcome, Writers.Put_Word (Out_Bytes, Internal.Smallest_Region));
      Accumulate (Outcome, Writers.Put_Rect (Out_Bytes, Item.Frame));
   end Put_Header;

   --  An Indexed_8 picture's color table: ctSeed, ctFlags, ctSize, then each entry's value, which is its index, and
   --  its components widened to 16 bits, in the order the colors first appear.
   procedure Put_Color_Table (Out_Bytes : in out Writers.Writer; Colors : Palette; Outcome : in out Results.Result) is
   begin
      Accumulate (Outcome, Writers.Put_Long (Out_Bytes, 0));
      Accumulate (Outcome, Writers.Put_Word (Out_Bytes, 0));
      Accumulate (Outcome, Writers.Put_Word (Out_Bytes, Natural (Colors.Colors.Length) - 1));
      for Index in 0 .. Natural (Colors.Colors.Length) - 1 loop
         declare
            Color : constant Images.RGB_Color := Colors.Colors (Index);
         begin
            Accumulate (Outcome, Writers.Put_Word (Out_Bytes, Index));
            Accumulate (Outcome, Writers.Put_Word (Out_Bytes, Widen_Component * Natural (Color.Red)));
            Accumulate (Outcome, Writers.Put_Word (Out_Bytes, Widen_Component * Natural (Color.Green)));
            Accumulate (Outcome, Writers.Put_Word (Out_Bytes, Widen_Component * Natural (Color.Blue)));
         end;
      end loop;
   end Put_Color_Table;

   --  The bits opcode up to its pixel data: rowBytes, bounds, a PixMap's fields and color table, srcRect,
   --  dstRect and srcCopy.
   procedure Put_Bits_Header
     (Out_Bytes : in out Writers.Writer;
      Settings : Options;
      Item : Plan;
      Colors : Palette;
      Outcome : in out Results.Result)
   is
      procedure Put_Pixmap_Tail (Pack, Pixel_Type, Pixel_Size, Component_Count, Component_Size : Natural) is
      begin
         Accumulate (Outcome, Writers.Put_Word (Out_Bytes, 0));
         Accumulate (Outcome, Writers.Put_Word (Out_Bytes, Pack));
         Accumulate (Outcome, Writers.Put_Long (Out_Bytes, 0));
         Accumulate (Outcome, Writers.Put_Long (Out_Bytes, Interfaces.Unsigned_32 (Settings.Horizontal_Resolution)));
         Accumulate (Outcome, Writers.Put_Long (Out_Bytes, Interfaces.Unsigned_32 (Settings.Vertical_Resolution)));
         Accumulate (Outcome, Writers.Put_Word (Out_Bytes, Pixel_Type));
         Accumulate (Outcome, Writers.Put_Word (Out_Bytes, Pixel_Size));
         Accumulate (Outcome, Writers.Put_Word (Out_Bytes, Component_Count));
         Accumulate (Outcome, Writers.Put_Word (Out_Bytes, Component_Size));
         for Index in 1 .. 3 loop  --  planeBytes, pmTable, pmReserved
            Accumulate (Outcome, Writers.Put_Long (Out_Bytes, 0));
         end loop;
      end Put_Pixmap_Tail;
   begin
      case Item.Layout is
         when Direct_32 =>
            Accumulate (Outcome, Writers.Put_Word (Out_Bytes, Natural (Opcodes.Direct_Bits_Rect)));
            Accumulate (Outcome, Writers.Put_Long (Out_Bytes, Direct_Base_Address));
            Accumulate (Outcome, Writers.Put_Word (Out_Bytes, Internal.Pixmap_Flag + Item.Stored));
            Accumulate (Outcome, Writers.Put_Rect (Out_Bytes, Item.Frame));
            Put_Pixmap_Tail (Pack => Pack_Component_Planes, Pixel_Type => Direct_Pixels, Pixel_Size => 32,
                             Component_Count => Item.Components, Component_Size => 8);
         when Indexed_8 =>
            Accumulate (Outcome, Writers.Put_Word (Out_Bytes, Natural (Opcodes.Pack_Bits_Rect)));
            Accumulate (Outcome, Writers.Put_Word (Out_Bytes, Internal.Pixmap_Flag + Item.Stored));
            Accumulate (Outcome, Writers.Put_Rect (Out_Bytes, Item.Frame));
            Put_Pixmap_Tail (Pack => Pack_Default, Pixel_Type => Indexed_Pixels, Pixel_Size => 8, Component_Count => 1,
                             Component_Size => 8);
            Put_Color_Table (Out_Bytes, Colors, Outcome);
         when others =>
            Accumulate (Outcome, Writers.Put_Word (Out_Bytes, Natural (Opcodes.Pack_Bits_Rect)));
            Accumulate (Outcome, Writers.Put_Word (Out_Bytes, Item.Stored));
            Accumulate (Outcome, Writers.Put_Rect (Out_Bytes, Item.Frame));
      end case;
      Accumulate (Outcome, Writers.Put_Rect (Out_Bytes, Item.Frame));  --  srcRect
      Accumulate (Outcome, Writers.Put_Rect (Out_Bytes, Item.Frame));  --  dstRect
      Accumulate (Outcome, Writers.Put_Word (Out_Bytes, 0));           --  srcCopy
   end Put_Bits_Header;

   --  One row as it is stored before packing. The layout is decided once a row, and the image's pixels are
   --  stepped through, each read once.
   procedure Fill_Row
     (Image : Images.Image_View;
      Settings : Options;
      Item : Plan;
      Colors : Palette;
      Y : Natural;
      Row : out Streams.Byte_Array)
   is
      Width : constant Natural := Item.Width;
      Format : constant Pixel_Format := Image.Descriptor.Format;
      Step : constant Positive := Positive (Images.Bytes_Per_Pixel (Format));
      Data : Streams.Byte_Array renames Image.Storage.all;
      At_Pixel : Positive := Row_Start (Image, Y);
      First : constant Positive := Row'First;
      Alpha : constant Boolean := Item.Components = 4;

      function Color return Images.RGB_Color is (Internal.Pixels.Color_At (Format, Data, At_Pixel));
   begin
      case Item.Layout is
         when Direct_32 =>
            if not Item.Packed then
               --  Unpacked chunky pixels: pad (or alpha), red, green, blue.
               for X in 0 .. Width - 1 loop
                  declare
                     Pixel : constant Images.RGB_Color := Color;
                  begin
                     Row (First + 4 * X) := (if Alpha then Internal.Pixels.Alpha_At (Format, Data, At_Pixel) else 0);
                     Row (First + 4 * X + 1) := Pixel.Red;
                     Row (First + 4 * X + 2) := Pixel.Green;
                     Row (First + 4 * X + 3) := Pixel.Blue;
                  end;
                  At_Pixel := At_Pixel + Step;
               end loop;
            else
               declare
                  Red : constant Natural := Internal.Plane_Offset (Internal.Red_Plane, Item.Components, Width);
                  Green : constant Natural := Internal.Plane_Offset (Internal.Green_Plane, Item.Components, Width);
                  Blue : constant Natural := Internal.Plane_Offset (Internal.Blue_Plane, Item.Components, Width);
               begin
                  for X in 0 .. Width - 1 loop
                     declare
                        Pixel : constant Images.RGB_Color := Color;
                     begin
                        if Alpha then
                           Row (First + X) := Internal.Pixels.Alpha_At (Format, Data, At_Pixel);
                        end if;
                        Row (First + Red + X) := Pixel.Red;
                        Row (First + Green + X) := Pixel.Green;
                        Row (First + Blue + X) := Pixel.Blue;
                     end;
                     At_Pixel := At_Pixel + Step;
                  end loop;
               end;
            end if;
         when Indexed_8 =>
            --  An odd width leaves a pad byte.
            Row (Row'Last) := 0;
            for X in 0 .. Width - 1 loop
               Row (First + X) := Byte (Index_Of (Colors, Color));
               At_Pixel := At_Pixel + Step;
            end loop;
         when others =>
            --  Black where the luminance, (299 R + 587 G + 114 B) / 1000 truncated, is below the threshold: the sum
            --  against 1000 times the threshold, the same test without a division. Eight pixels make a byte, most
            --  significant first.
            Row := [others => 0];
            declare
               Dark_Below : constant Natural := 1000 * Natural (Settings.Mono_Threshold);
               Bits : Byte := 0;
            begin
               for X in 0 .. Width - 1 loop
                  declare
                     Pixel : constant Images.RGB_Color := Color;
                  begin
                     Bits := Bits * 2
                       + (if 299 * Natural (Pixel.Red) + 587 * Natural (Pixel.Green) + 114 * Natural (Pixel.Blue)
                             < Dark_Below
                          then 1 else 0);
                  end;
                  if X mod 8 = 7 then
                     Row (First + X / 8) := Bits;
                     Bits := 0;
                  end if;
                  At_Pixel := At_Pixel + Step;
               end loop;
               if Width mod 8 /= 0 then
                  Row (First + Width / 8) := Bits * 2 ** (8 - Width mod 8);
               end if;
            end;
      end case;
   end Fill_Row;

   --  The rows a dry run stores, back to back, kept for the write so it does not convert and pack them again: row
   --  Y is Data (Ends (Y) + 1 .. Ends (Y + 1)). Kept once the dry run has stored every row.
   type Row_Ends is array (Natural range <>) of Natural;
   type Row_Ends_Access is access Row_Ends;
   procedure Free is new Ada.Unchecked_Deallocation (Row_Ends, Row_Ends_Access);
   type Row_Store is record
      Data : Streams.Byte_Array_Access;
      Ends : Row_Ends_Access;
      Kept : Boolean := False;
   end record;
   --  The most kept: past it, a picture's rows are stored twice rather than held whole.
   Row_Store_Limit : constant := 64 * 1024 * 1024;

   --  Rows: unpacked below 8 rowBytes, otherwise PackBits behind a byte count, or a word count above 250.
   procedure Put_Rows
     (Out_Bytes : in out Writers.Writer;
      Image : Images.Image_View;
      Settings : Options;
      Item : Plan;
      Colors : Palette;
      Store : in out Row_Store;
      Outcome : in out Results.Result)
   is
      --  Allocated in the body, so the handler below releases whichever was made.
      Row, Packed : Streams.Byte_Array_Access := null;
      Packed_Length : Natural;

      --  A row as stored: a packed one behind its count.
      procedure Put_Row (Stored : Streams.Byte_Array) is
      begin
         if Item.Packed then
            if Item.Stored > Internal.Byte_Count_Row_Bytes then
               Accumulate (Outcome, Writers.Put_Word (Out_Bytes, Stored'Length));
            else
               Accumulate (Outcome, Writers.Put_Byte (Out_Bytes, Stored'Length));
            end if;
         end if;
         Accumulate (Outcome, Writers.Put (Out_Bytes, Stored));
      end Put_Row;

      --  Row Y put, and kept when the store has room for every row.
      procedure Put_And_Keep (Y : Natural; Stored : Streams.Byte_Array) is
      begin
         Put_Row (Stored);
         if Store.Data /= null then
            Store.Data (Store.Ends (Y) + 1 .. Store.Ends (Y) + Stored'Length) := Stored;
            Store.Ends (Y + 1) := Store.Ends (Y) + Stored'Length;
         end if;
      end Put_And_Keep;
   begin
      if Store.Kept then
         for Y in 0 .. Item.Height - 1 loop
            exit when not Results.Succeeded (Outcome);
            Put_Row (Store.Data (Store.Ends (Y) + 1 .. Store.Ends (Y + 1)));
         end loop;
         return;
      end if;
      Row := new Streams.Byte_Array (1 .. Item.Unpacked_Length);
      Packed := new Streams.Byte_Array (1 .. Internal.PackBits.Worst_Case (Item.Unpacked_Length));
      for Y in 0 .. Item.Height - 1 loop
         exit when not Results.Succeeded (Outcome);
         Fill_Row (Image, Settings, Item, Colors, Y, Row.all);
         if Item.Packed then
            Internal.PackBits.Pack (Row.all, Packed.all, Packed_Length);
            Put_And_Keep (Y, Packed (1 .. Packed_Length));
         else
            Put_And_Keep (Y, Row.all);
         end if;
      end loop;
      Store.Kept := Store.Data /= null and then Results.Succeeded (Outcome);
      Internal.Bytes.Free (Row);
      Internal.Bytes.Free (Packed);
   exception
      --  A destination's exception passes through, the row buffers released.
      when others =>
         Internal.Bytes.Free (Row);
         Internal.Bytes.Free (Packed);
         raise;
   end Put_Rows;

   --  One picture, measured or written.
   function Write_Picture
     (Out_Bytes : in out Writers.Writer;
      Image : Images.Image_View;
      Settings : Options;
      Item : Plan;
      Colors : Palette;
      Store : in out Row_Store;
      Picture_Size : Byte_Count) return Results.Result
   is
      Outcome : Results.Result := Results.Success;
   begin
      Put_Header (Out_Bytes, Settings, Item, Picture_Size, Outcome);
      Put_Bits_Header (Out_Bytes, Settings, Item, Colors, Outcome);
      Put_Rows (Out_Bytes, Image, Settings, Item, Colors, Store, Outcome);
      Accumulate (Outcome, Writers.Align (Out_Bytes));
      Accumulate (Outcome, Writers.Put_Word (Out_Bytes, Natural (Opcodes.End_Picture)));
      return Outcome;
   end Write_Picture;

   procedure Initialize
     (Object : in out Encoder;
      Output : not null access Streams.Destination'Class;
      Encode_Options : Options := (others => <>);
      Encode_Limits : Limits.Limit_Set := Limits.Default_Limits) is
   begin
      Object.Encode_Options := Encode_Options;
      Object.Encode_Limits := Encode_Limits;
      Reset (Object, Output);
   end Initialize;

   procedure Reset (Object : in out Encoder; Output : not null access Streams.Destination'Class) is
   begin
      Object.Output := Output.all'Unchecked_Access;
      Object.Layout := Auto;
      Object.Written := 0;
      Object.First_Error := Errors.Make (Errors.No_Error);
      Object.Current_State := Ready;
      Object.Binds := Object.Binds + 1;
      Object.Stops := Object.Stops + 1;
   end Reset;

   function State (Object : Encoder) return Encoder_State is (Object.Current_State);

   function Wrong_State (Object : Encoder) return Results.Result is
     (Internal.Failures.Wrong_State (Object.Current_State = Cancelled));

   function Fail (Object : in out Encoder; Outcome : Results.Result) return Results.Result is
   begin
      if not Results.Succeeded (Outcome) then
         Object.First_Error := Outcome.First_Error;
         Object.Current_State := Failed;
      end if;
      return Outcome;
   end Fail;

   --  Choose layout: Auto takes Mono_1 only for pure black and white, which it must keep exactly. Any threshold
   --  strictly between black and white does, and the caller's need not be one, so Auto uses
   --  Default_Mono_Threshold rather than the caller's.
   procedure Choose_Layout
     (Image : Images.Image_View;
      Colors : Palette;
      Settings : in out Options;
      Layout : out Layout_Kind) is
   begin
      Layout :=
        (if Alpha_Kept (Image, Settings) then Direct_32
         elsif Colors.Black_And_White then Mono_1
         elsif Natural (Colors.Colors.Length) <= Largest_Colors then Indexed_8
         else Direct_32);
      if Layout = Mono_1 then
         Settings.Mono_Threshold := Default_Mono_Threshold;
      end if;
   end Choose_Layout;

   --  The rowBytes a PixMap or BitMap can state: below 16#4000#.
   function Check_Row_Bytes (Item : Plan) return Results.Result is
     (if Item.Stored > Largest_Row_Bytes then Invalid (Largest_Row_Bytes, Byte_Count (Item.Stored))
      else Results.Success);

   --  Check plan: what the layout needs of the colors and the budget, its rowBytes already checked.
   function Check_Plan (Item : Plan; Colors : Palette; Budget : Limits.Limit_Set) return Results.Result is
      Buffers : constant Byte_Count := Row_Buffer_Bytes (Item);
   begin
      if Item.Layout = Indexed_8 and then Natural (Colors.Colors.Length) > Largest_Colors then
         return Results.Failure
           (Errors.Make
              (Errors.Too_Many_Colors,
               (Expected => Largest_Colors, Actual => Byte_Count (Colors.Colors.Length), others => <>)));
      elsif Buffers > Budget.Max_Allocation_Bytes then
         return Internal.Failures.Over_Limit (Allocation_Byte_Limit, Budget.Max_Allocation_Bytes, Buffers);
      end if;
      return Results.Success;
   end Check_Plan;

   --  Write: picSize needs the picture's length before the picture is written, so a dry run measures it first.
   function Write
     (Object : in out Encoder;
      Image : Images.Image_View;
      Settings : Options;
      Item : Plan;
      Colors : Palette;
      --  Set as the first byte is written; by reference, so an exception from the destination leaves it set.
      Started : not null access Boolean;
      --  What the destination took.
      Written : out Byte_Count) return Results.Result
   is
      Budget : Limits.Limit_Set renames Object.Encode_Limits;
      Measure : Writers.Writer;
      Output : Writers.Writer;
      Outcome : Results.Result;
      --  Every row at its worst case, which the dry run's rows are kept in when one allocation holds it.
      Worst : constant Byte_Count :=
        Byte_Count (Item.Height)
        * Byte_Count (if Item.Packed then Internal.PackBits.Worst_Case (Item.Unpacked_Length) else Item.Stored);
      Store : Row_Store;

      --  What both runs write: the optional file header, then the picture. The dry run and the real one are this
      --  one sequence, so the real run writes exactly the bytes the dry run measured.
      function Emit (Into : in out Writers.Writer; Picture_Size : Byte_Count) return Results.Result is
         File_Header : constant Streams.Byte_Array (1 .. Internal.File_Header_Bytes) := [others => 0];
         Result : Results.Result := Results.Success;
      begin
         if Settings.File_Header then
            Result := Writers.Put (Into, File_Header);
         end if;
         if Results.Succeeded (Result) then
            Result := Write_Picture (Into, Image, Settings, Item, Colors, Store, Picture_Size);
         end if;
         return Result;
      end Emit;
      procedure Release is
      begin
         Internal.Bytes.Free (Store.Data);
         Free (Store.Ends);
      end Release;
   begin
      Started.all := False;
      Written := 0;
      if Worst <= Byte_Count'Min (Budget.Max_Allocation_Bytes, Row_Store_Limit) then
         Store.Data := new Streams.Byte_Array (1 .. Natural (Worst));
         Store.Ends := new Row_Ends'(0 .. Item.Height => 0);
      end if;
      --  The dry run counts what the output will hold, the file header included, against the limit as it was
      --  set, so a picture that does not fit is reported in the caller's terms.
      Writers.Start (Measure, null, Budget.Max_Output_Bytes);
      Outcome := Emit (Measure, 0);
      if not Results.Succeeded (Outcome) then
         Release;
         return Outcome;
      end if;
      Started.all := True;
      Writers.Start (Output, Object.Output, Budget.Max_Output_Bytes, Object.Stops'Access);
      Outcome := Emit (Output, Writers.Picture_Count (Measure));
      Written := Writers.Count (Output);
      Release;
      return Outcome;
   exception
      --  The destination's exception, or the store not allocated, passes through with the store released.
      when others =>
         Release;
         raise;
   end Write;

   --  Guards a call that runs the destination, as Call_Guards describes: one that used the destination and did
   --  not return leaves the encoder Failed with Destination_Write_Failed, so no second picture follows a part of
   --  the first. The error means a write in progress did not return, whoever raised: the destination, or the
   --  encoder itself, out of storage for its row buffers once the header was written.
   type Write_Guard
     (From : Encoder_State;
      State : not null access Encoder_State;
      Error : not null access Errors.Error;
      Started : not null access constant Boolean;
      Busy : not null access Boolean;
      Binds : not null access constant Internal.Generation) is new Internal.Call_Guards.Guard (Busy, Binds)
   with null record;

   overriding procedure Left_Unfinished (Guard : in out Write_Guard);

   overriding procedure Left_Unfinished (Guard : in out Write_Guard) is
   begin
      if Guard.Started.all and then Guard.State.all = Guard.From then
         Guard.State.all := Failed;
         Guard.Error.all := Errors.Make (Errors.Destination_Write_Failed);
      end if;
   end Left_Unfinished;

   function Encode_Picture (Object : in out Encoder; Image : Images.Image_View) return Results.Result is
      --  The settings the picture is written with.
      Settings : Options := Object.Encode_Options;
      Colors : Palette;
      Layout : Layout_Kind := Settings.Layout;
      Item : Plan;
      Outcome : Results.Result;
   begin
      --  Nothing before the write runs caller code: a failure here leaves the encoder Ready.
      if Object.Current_State /= Ready then
         return Wrong_State (Object);
      elsif not Images.Is_Valid (Image) then
         --  The least a valid view of its size and format holds, against what it holds.
         return Internal.Failures.Invalid_View (Image.Descriptor);
      elsif Settings.Horizontal_Resolution <= 0 or else Settings.Vertical_Resolution <= 0 then
         return Invalid (1, 0);
      end if;
      Outcome :=
        Internal.Failures.Check_Frame_Size
          (Natural (Image.Descriptor.Width), Natural (Image.Descriptor.Height), Object.Encode_Limits);
      if not Results.Succeeded (Outcome) then
         return Outcome;
      end if;
      --  A layout given is planned, and checked against the rowBytes a PixMap can state, before any pixel is
      --  surveyed; Auto's once the colors choose it.
      if Layout /= Auto then
         Item := Plan_For (Image, Settings, Layout);
         Outcome := Check_Row_Bytes (Item);
         if not Results.Succeeded (Outcome) then
            return Outcome;
         end if;
      end if;
      --  Only an indexed palette and Auto's choice, unless alpha decides it, need the colors; the other layouts
      --  write pixels as they are.
      if Layout = Indexed_8 or else (Layout = Auto and then not Alpha_Kept (Image, Settings)) then
         Survey (Image, Colors);
      end if;
      if Layout = Auto then
         Choose_Layout (Image, Colors, Settings, Layout);
         Item := Plan_For (Image, Settings, Layout);
         Outcome := Check_Row_Bytes (Item);
      end if;
      if Results.Succeeded (Outcome) then
         Outcome := Check_Plan (Item, Colors, Object.Encode_Limits);
      end if;
      if not Results.Succeeded (Outcome) then
         return Outcome;
      end if;
      declare
         --  Whether the destination was written to: a failure before leaves the encoder Ready.
         Started : aliased Boolean := False;
         Guard : Write_Guard
           (Ready, Object.Current_State'Access, Object.First_Error'Access, Started'Access, Object.Busy'Access,
            Object.Binds'Access);
         Written : Byte_Count := 0;
      begin
         Outcome := Write (Object, Image, Settings, Item, Colors, Started'Access, Written);
         --  The destination cancelled, reset or finalized the encoder under it: that stands. A rebinding set
         --  the count; an encoder cancelled and not rebound keeps what its destination took.
         if Object.Current_State = Cancelled and then not Rebound (Guard) then
            Object.Written := Written;
         end if;
         if Object.Current_State /= Ready or else Rebound (Guard) then
            return Wrong_State (Object);
         end if;
         Object.Written := Written;
         if Results.Succeeded (Outcome) then
            Object.Layout := Layout;
            Object.Current_State := Encoded;
         elsif not Started then
            return Outcome;
         end if;
         return Fail (Object, Outcome);
      end;
   end Encode_Picture;

   function Encode (Object : in out Encoder; Image : Images.Image_View) return Results.Result is
     (if Object.Busy then Results.Failure (Errors.Invalid_State) else Encode_Picture (Object, Image));

   function Finish (Object : in out Encoder) return Results.Result is
      Flushing : aliased constant Boolean := True;
   begin
      if Object.Busy then
         return Results.Failure (Errors.Invalid_State);
      elsif Object.Current_State /= Encoded then
         return Wrong_State (Object);
      end if;
      declare
         Guard : Write_Guard
           (Encoded, Object.Current_State'Access, Object.First_Error'Access, Flushing'Access, Object.Busy'Access,
            Object.Binds'Access);
         Flushed : constant Errors.Error := Object.Output.Flush;
      begin
         if Object.Current_State /= Encoded or else Rebound (Guard) then
            return Wrong_State (Object);
         elsif Errors.Is_Fatal (Flushed) then
            return Fail (Object, Results.Failure (Flushed));
         end if;
         --  Inside the guard's scope, so a flush that returned is not taken for one that raised.
         Object.Current_State := Finished;
         return Results.Success;
      end;
   end Finish;

   function Layout_Used (Object : Encoder) return Layout_Kind is (Object.Layout);

   function Bytes_Written (Object : Encoder) return Byte_Count is (Object.Written);

   function Last_Error (Object : Encoder) return Errors.Error is (Object.First_Error);

   procedure Cancel (Object : in out Encoder) is
   begin
      if Object.Current_State in Ready | Encoded then
         Object.Current_State := Cancelled;
         Object.Stops := Object.Stops + 1;
      end if;
   end Cancel;

   procedure Finalize (Object : in out Encoder) is
   begin
      Object.Output := null;
      Object.Written := 0;
      Object.Layout := Auto;
      Object.First_Error := Errors.Make (Errors.No_Error);
      Object.Current_State := Created;
      Object.Binds := Object.Binds + 1;
      Object.Stops := Object.Stops + 1;
   end Finalize;
end Pictlib.Encoding;
