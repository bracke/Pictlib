with Ada.Containers.Hashed_Maps;
with Ada.Containers.Vectors;
with Ada.Finalization;
with Interfaces;
with Pictlib.Internal.Bytes;
with Pictlib.Internal.Failures;
with Pictlib.Internal.PackBits;
with Pictlib.Internal.Pixels;
with Pictlib.Internal.Writers;
with Pictlib.Opcodes;

package body Pictlib.Encoding is
   use type Images.RGB_Color;
   use type Geometry.Fixed;

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

   type Pixel is record
      Color : Images.RGB_Color;
      Alpha : Byte := 16#FF#;
   end record;

   function Pixel_At (Image : Images.Image_View; X, Y : Natural) return Pixel is
      Format : constant Pixel_Format := Image.Descriptor.Format;
      At_Pixel : constant Positive := Image.Storage'First + Internal.Pixels.Pixel_Offset (Image.Descriptor, X, Y);
   begin
      return (Internal.Pixels.Color_At (Format, Image.Storage.all, At_Pixel),
              Internal.Pixels.Alpha_At (Format, Image.Storage.all, At_Pixel));
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
   procedure Step (Outcome : in out Results.Result; Item : Results.Result) is
   begin
      if Results.Succeeded (Outcome) then
         Outcome := Item;
      end if;
   end Step;

   --  picSize, picFrame, the version opcode, an extended version 2 HeaderOp, DefHilite and a clip of the frame.
   procedure Put_Header
     (Out_Bytes : in out Writers.Writer;
      Settings : Options;
      Item : Plan;
      Picture_Size : Byte_Count;
      Outcome : in out Results.Result) is
   begin
      Writers.Start_Picture (Out_Bytes);
      Step (Outcome, Writers.Put_Word (Out_Bytes, Natural (Picture_Size mod 16#1_0000#)));
      Step (Outcome, Writers.Put_Rect (Out_Bytes, Item.Frame));
      Step (Outcome, Writers.Put_Word (Out_Bytes, Natural (Opcodes.Version_Op)));
      Step (Outcome, Writers.Put_Word (Out_Bytes, Internal.Version_2_Word));
      --  HeaderOp: its version, reserved, the resolution, the frame, reserved.
      Step (Outcome, Writers.Put_Word (Out_Bytes, Natural (Opcodes.Header_Op)));
      Step (Outcome, Writers.Put_Word (Out_Bytes, Internal.Extended_Header_Version));
      Step (Outcome, Writers.Put_Word (Out_Bytes, 0));
      Step (Outcome, Writers.Put_Long (Out_Bytes, Interfaces.Unsigned_32 (Settings.Horizontal_Resolution)));
      Step (Outcome, Writers.Put_Long (Out_Bytes, Interfaces.Unsigned_32 (Settings.Vertical_Resolution)));
      Step (Outcome, Writers.Put_Rect (Out_Bytes, Item.Frame));
      Step (Outcome, Writers.Put_Long (Out_Bytes, 0));
      Step (Outcome, Writers.Put_Word (Out_Bytes, Natural (Opcodes.Default_Hilite)));
      --  A rectangular region: its size word and box.
      Step (Outcome, Writers.Put_Word (Out_Bytes, Natural (Opcodes.Clip)));
      Step (Outcome, Writers.Put_Word (Out_Bytes, Internal.Smallest_Region));
      Step (Outcome, Writers.Put_Rect (Out_Bytes, Item.Frame));
   end Put_Header;

   --  An Indexed_8 picture's color table: ctSeed, ctFlags, ctSize, then each entry's value, which is its index, and
   --  its components widened to 16 bits, in the order the colors first appear.
   procedure Put_Color_Table (Out_Bytes : in out Writers.Writer; Colors : Palette; Outcome : in out Results.Result) is
   begin
      Step (Outcome, Writers.Put_Long (Out_Bytes, 0));
      Step (Outcome, Writers.Put_Word (Out_Bytes, 0));
      Step (Outcome, Writers.Put_Word (Out_Bytes, Natural (Colors.Colors.Length) - 1));
      for Index in 0 .. Natural (Colors.Colors.Length) - 1 loop
         declare
            Color : constant Images.RGB_Color := Colors.Colors (Index);
         begin
            Step (Outcome, Writers.Put_Word (Out_Bytes, Index));
            Step (Outcome, Writers.Put_Word (Out_Bytes, Widen_Component * Natural (Color.Red)));
            Step (Outcome, Writers.Put_Word (Out_Bytes, Widen_Component * Natural (Color.Green)));
            Step (Outcome, Writers.Put_Word (Out_Bytes, Widen_Component * Natural (Color.Blue)));
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
         Step (Outcome, Writers.Put_Word (Out_Bytes, 0));
         Step (Outcome, Writers.Put_Word (Out_Bytes, Pack));
         Step (Outcome, Writers.Put_Long (Out_Bytes, 0));
         Step (Outcome, Writers.Put_Long (Out_Bytes, Interfaces.Unsigned_32 (Settings.Horizontal_Resolution)));
         Step (Outcome, Writers.Put_Long (Out_Bytes, Interfaces.Unsigned_32 (Settings.Vertical_Resolution)));
         Step (Outcome, Writers.Put_Word (Out_Bytes, Pixel_Type));
         Step (Outcome, Writers.Put_Word (Out_Bytes, Pixel_Size));
         Step (Outcome, Writers.Put_Word (Out_Bytes, Component_Count));
         Step (Outcome, Writers.Put_Word (Out_Bytes, Component_Size));
         for Index in 1 .. 3 loop  --  planeBytes, pmTable, pmReserved
            Step (Outcome, Writers.Put_Long (Out_Bytes, 0));
         end loop;
      end Put_Pixmap_Tail;
   begin
      case Item.Layout is
         when Direct_32 =>
            Step (Outcome, Writers.Put_Word (Out_Bytes, Natural (Opcodes.Direct_Bits_Rect)));
            Step (Outcome, Writers.Put_Long (Out_Bytes, Direct_Base_Address));
            Step (Outcome, Writers.Put_Word (Out_Bytes, Internal.Pixmap_Flag + Item.Stored));
            Step (Outcome, Writers.Put_Rect (Out_Bytes, Item.Frame));
            Put_Pixmap_Tail (Pack => Pack_Component_Planes, Pixel_Type => Direct_Pixels, Pixel_Size => 32,
                             Component_Count => Item.Components, Component_Size => 8);
         when Indexed_8 =>
            Step (Outcome, Writers.Put_Word (Out_Bytes, Natural (Opcodes.Pack_Bits_Rect)));
            Step (Outcome, Writers.Put_Word (Out_Bytes, Internal.Pixmap_Flag + Item.Stored));
            Step (Outcome, Writers.Put_Rect (Out_Bytes, Item.Frame));
            Put_Pixmap_Tail (Pack => Pack_Default, Pixel_Type => Indexed_Pixels, Pixel_Size => 8, Component_Count => 1,
                             Component_Size => 8);
            Put_Color_Table (Out_Bytes, Colors, Outcome);
         when others =>
            Step (Outcome, Writers.Put_Word (Out_Bytes, Natural (Opcodes.Pack_Bits_Rect)));
            Step (Outcome, Writers.Put_Word (Out_Bytes, Item.Stored));
            Step (Outcome, Writers.Put_Rect (Out_Bytes, Item.Frame));
      end case;
      Step (Outcome, Writers.Put_Rect (Out_Bytes, Item.Frame));  --  srcRect
      Step (Outcome, Writers.Put_Rect (Out_Bytes, Item.Frame));  --  dstRect
      Step (Outcome, Writers.Put_Word (Out_Bytes, 0));           --  srcCopy
   end Put_Bits_Header;

   --  One row as it is stored before packing.
   procedure Fill_Row
     (Image : Images.Image_View;
      Settings : Options;
      Item : Plan;
      Colors : Palette;
      Y : Natural;
      Row : out Streams.Byte_Array)
   is
      Width : constant Natural := Item.Width;
      Red : constant Natural := Internal.Plane_Offset (Internal.Red_Plane, Item.Components, Width);
      Green : constant Natural := Internal.Plane_Offset (Internal.Green_Plane, Item.Components, Width);
      Blue : constant Natural := Internal.Plane_Offset (Internal.Blue_Plane, Item.Components, Width);
   begin
      Row := [others => 0];
      for X in 0 .. Width - 1 loop
         declare
            Source : constant Pixel := Pixel_At (Image, X, Y);
         begin
            case Item.Layout is
               when Direct_32 =>
                  if not Item.Packed then
                     --  Unpacked chunky pixels: pad (or alpha), red, green, blue.
                     Row (Row'First + 4 * X .. Row'First + 4 * X + 3) :=
                       [(if Item.Components = 4 then Source.Alpha else 0), Source.Color.Red, Source.Color.Green,
                        Source.Color.Blue];
                  else
                     if Item.Components = 4 then
                        Row (Row'First + X) := Source.Alpha;
                     end if;
                     Row (Row'First + Red + X) := Source.Color.Red;
                     Row (Row'First + Green + X) := Source.Color.Green;
                     Row (Row'First + Blue + X) := Source.Color.Blue;
                  end if;
               when Indexed_8 =>
                  Row (Row'First + X) := Byte (Colors.Indexes.Element (Key (Source.Color)));
               when others =>
                  if Luminance (Source.Color) < Natural (Settings.Mono_Threshold) then
                     Row (Row'First + X / 8) := Row (Row'First + X / 8) or Byte (2 ** (7 - X mod 8));
                  end if;
            end case;
         end;
      end loop;
   end Fill_Row;

   --  Rows: unpacked below 8 rowBytes, otherwise PackBits behind a byte count, or a word count above 250.
   procedure Put_Rows
     (Out_Bytes : in out Writers.Writer;
      Image : Images.Image_View;
      Settings : Options;
      Item : Plan;
      Colors : Palette;
      Outcome : in out Results.Result)
   is
      --  Allocated in the body, so the handler below releases whichever was made.
      Row, Packed : Streams.Byte_Array_Access := null;
      Packed_Length : Natural;
   begin
      Row := new Streams.Byte_Array (1 .. Item.Unpacked_Length);
      Packed := new Streams.Byte_Array (1 .. Internal.PackBits.Worst_Case (Item.Unpacked_Length));
      for Y in 0 .. Item.Height - 1 loop
         exit when not Results.Succeeded (Outcome);
         Fill_Row (Image, Settings, Item, Colors, Y, Row.all);
         if not Item.Packed then
            Step (Outcome, Writers.Put (Out_Bytes, Row.all));
         else
            Internal.PackBits.Pack (Row.all, Packed.all, Packed_Length);
            if Item.Stored > Internal.Byte_Count_Row_Bytes then
               Step (Outcome, Writers.Put_Word (Out_Bytes, Packed_Length));
            else
               Step (Outcome, Writers.Put_Byte (Out_Bytes, Packed_Length));
            end if;
            Step (Outcome, Writers.Put (Out_Bytes, Packed (1 .. Packed_Length)));
         end if;
      end loop;
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
      Picture_Size : Byte_Count) return Results.Result
   is
      Outcome : Results.Result := Results.Success;
   begin
      Put_Header (Out_Bytes, Settings, Item, Picture_Size, Outcome);
      Put_Bits_Header (Out_Bytes, Settings, Item, Colors, Outcome);
      Put_Rows (Out_Bytes, Image, Settings, Item, Colors, Outcome);
      Step (Outcome, Writers.Align (Out_Bytes));
      Step (Outcome, Writers.Put_Word (Out_Bytes, Natural (Opcodes.End_Picture)));
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
   end Reset;

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

   --  Choose layout: Auto takes Mono_1 only for pure black and white, which it must keep exactly, whatever the
   --  threshold: one between the two does.
   procedure Choose_Layout
     (Image : Images.Image_View;
      Colors : Palette;
      Settings : in out Options;
      Layout : out Layout_Kind) is
   begin
      Layout := Settings.Layout;
      if Layout = Auto then
         Layout :=
           (if Alpha_Kept (Image, Settings) then Direct_32
            elsif Colors.Black_And_White then Mono_1
            elsif Natural (Colors.Colors.Length) <= Largest_Colors then Indexed_8
            else Direct_32);
         if Layout = Mono_1 then
            Settings.Mono_Threshold := Default_Mono_Threshold;
         end if;
      end if;
   end Choose_Layout;

   --  Check plan: what the layout needs, against what a PICT and the budget allow.
   function Check_Plan (Item : Plan; Colors : Palette; Budget : Limits.Limit_Set) return Results.Result is
      Buffers : constant Byte_Count := Row_Buffer_Bytes (Item);
   begin
      if Item.Layout = Indexed_8 and then Natural (Colors.Colors.Length) > Largest_Colors then
         return Results.Failure
           (Errors.Make
              (Errors.Too_Many_Colors,
               (Expected => Largest_Colors, Actual => Byte_Count (Colors.Colors.Length), others => <>)));
      elsif Item.Stored > Largest_Row_Bytes then
         --  rowBytes must stay below 16#4000#.
         return Invalid (Largest_Row_Bytes, Byte_Count (Item.Stored));
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
      Started : not null access Boolean) return Results.Result
   is
      Budget : Limits.Limit_Set renames Object.Encode_Limits;
      Measure : Writers.Writer;
      Output : Writers.Writer;
      Outcome : Results.Result;

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
            Result := Write_Picture (Into, Image, Settings, Item, Colors, Picture_Size);
         end if;
         return Result;
      end Emit;
   begin
      Started.all := False;
      --  The dry run counts what the output will hold, the file header included, against the limit as it was
      --  set, so a picture that does not fit is reported in the caller's terms.
      Writers.Start (Measure, null, Budget.Max_Output_Bytes);
      Outcome := Emit (Measure, 0);
      if not Results.Succeeded (Outcome) then
         return Outcome;
      end if;
      Started.all := True;
      Writers.Start (Output, Object.Output, Budget.Max_Output_Bytes);
      Outcome := Emit (Output, Writers.Picture_Count (Measure));
      Object.Written := Writers.Count (Output);
      return Outcome;
   end Write;

   --  Guards a call that runs the destination, caller code which may raise, or the task be aborted. Busy is held
   --  for the call. A call that used the destination and left the encoder in From, the state it began in, did not
   --  return, since every return moves it on, and leaves it Failed with Destination_Write_Failed, so no second
   --  picture follows a part of the first.
   type Write_Guard
     (From : Encoder_State;
      State : not null access Encoder_State;
      Error : not null access Errors.Error;
      Started : not null access constant Boolean;
      Busy : not null access Boolean;
      Binds : not null access constant Bind_Count) is new Ada.Finalization.Limited_Controlled with record
      Binds_At_Start : Bind_Count := 0;
   end record;

   overriding procedure Initialize (Guard : in out Write_Guard);
   overriding procedure Finalize (Guard : in out Write_Guard);

   overriding procedure Initialize (Guard : in out Write_Guard) is
   begin
      Guard.Busy.all := True;
      Guard.Binds_At_Start := Guard.Binds.all;
   end Initialize;

   overriding procedure Finalize (Guard : in out Write_Guard) is
   begin
      Guard.Busy.all := False;
      --  A destination that rebound the encoder left it as it chose.
      if Guard.Started.all and then Guard.State.all = Guard.From and then Guard.Binds.all = Guard.Binds_At_Start then
         Guard.State.all := Failed;
         Guard.Error.all := Errors.Make (Errors.Destination_Write_Failed);
      end if;
   end Finalize;

   function Encode_Picture (Object : in out Encoder; Image : Images.Image_View) return Results.Result is
      --  The settings the picture is written with.
      Settings : Options := Object.Encode_Options;
      Colors : Palette;
      Layout : Layout_Kind;
      Outcome : Results.Result;
      --  Whether the destination was written to: a failure before leaves the encoder Ready.
      Started : aliased Boolean := False;
      Guard : Write_Guard
        (Ready, Object.Current_State'Access, Object.First_Error'Access, Started'Access, Object.Busy'Access,
         Object.Binds'Access);
      Binds : constant Bind_Count := Object.Binds;
      pragma Unreferenced (Guard);
   begin
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
      if Results.Succeeded (Outcome) then
         --  Only Auto's choice and an indexed palette need the colors; the other layouts write pixels as they are.
         if Settings.Layout in Auto | Indexed_8 then
            Survey (Image, Colors);
         end if;
         Choose_Layout (Image, Colors, Settings, Layout);
         declare
            Item : constant Plan := Plan_For (Image, Settings, Layout);
         begin
            Outcome := Check_Plan (Item, Colors, Object.Encode_Limits);
            if Results.Succeeded (Outcome) then
               Outcome := Write (Object, Image, Settings, Item, Colors, Started'Access);
            end if;
         end;
      end if;
      --  The destination cancelled, reset or finalized the encoder under it: that stands.
      if Object.Current_State /= Ready or else Object.Binds /= Binds then
         return Wrong_State (Object);
      elsif Results.Succeeded (Outcome) then
         Object.Layout := Layout;
         Object.Current_State := Encoded;
      elsif not Started then
         return Outcome;
      end if;
      return Fail (Object, Outcome);
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
         pragma Unreferenced (Guard);
         Binds : constant Bind_Count := Object.Binds;
         Flushed : constant Errors.Error := Object.Output.Flush;
      begin
         if Object.Current_State /= Encoded or else Object.Binds /= Binds then
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
   end Finalize;
end Pictlib.Encoding;
