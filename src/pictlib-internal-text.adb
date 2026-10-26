with Ada.Directories;
with Ada.Unchecked_Deallocation;
package body Pictlib.Internal.Text is
   use type Ada.Strings.Unbounded.Unbounded_String;
   use type Textrender.Status_Code;

   --  Mac Roman 16#80# .. 16#FF#, from the Unicode mapping of the Mac OS Roman encoding.
   High_Half : constant array (Byte range 16#80# .. 16#FF#) of Textrender.Codepoint :=
     [16#00C4#, 16#00C5#, 16#00C7#, 16#00C9#, 16#00D1#, 16#00D6#, 16#00DC#, 16#00E1#,
      16#00E0#, 16#00E2#, 16#00E4#, 16#00E3#, 16#00E5#, 16#00E7#, 16#00E9#, 16#00E8#,
      16#00EA#, 16#00EB#, 16#00ED#, 16#00EC#, 16#00EE#, 16#00EF#, 16#00F1#, 16#00F3#,
      16#00F2#, 16#00F4#, 16#00F6#, 16#00F5#, 16#00FA#, 16#00F9#, 16#00FB#, 16#00FC#,
      16#2020#, 16#00B0#, 16#00A2#, 16#00A3#, 16#00A7#, 16#2022#, 16#00B6#, 16#00DF#,
      16#00AE#, 16#00A9#, 16#2122#, 16#00B4#, 16#00A8#, 16#2260#, 16#00C6#, 16#00D8#,
      16#221E#, 16#00B1#, 16#2264#, 16#2265#, 16#00A5#, 16#00B5#, 16#2202#, 16#2211#,
      16#220F#, 16#03C0#, 16#222B#, 16#00AA#, 16#00BA#, 16#03A9#, 16#00E6#, 16#00F8#,
      16#00BF#, 16#00A1#, 16#00AC#, 16#221A#, 16#0192#, 16#2248#, 16#2206#, 16#00AB#,
      16#00BB#, 16#2026#, 16#00A0#, 16#00C0#, 16#00C3#, 16#00D5#, 16#0152#, 16#0153#,
      16#2013#, 16#2014#, 16#201C#, 16#201D#, 16#2018#, 16#2019#, 16#00F7#, 16#25CA#,
      16#00FF#, 16#0178#, 16#2044#, 16#20AC#, 16#2039#, 16#203A#, 16#FB01#, 16#FB02#,
      16#2021#, 16#00B7#, 16#201A#, 16#201E#, 16#2030#, 16#00C2#, 16#00CA#, 16#00C1#,
      16#00CB#, 16#00C8#, 16#00CD#, 16#00CE#, 16#00CF#, 16#00CC#, 16#00D3#, 16#00D4#,
      16#F8FF#, 16#00D2#, 16#00DA#, 16#00DB#, 16#00D9#, 16#0131#, 16#02C6#, 16#02DC#,
      16#00AF#, 16#02D8#, 16#02D9#, 16#02DA#, 16#00B8#, 16#02DD#, 16#02DB#, 16#02C7#];

   function To_Unicode (Item : Byte) return Textrender.Codepoint is
     (if Item < 16#80# then Textrender.Codepoint (Item) else High_Half (Item));

   protected Textrender_Lock is
      entry Seize;
      procedure Release;
   private
      Busy : Boolean := False;
   end Textrender_Lock;

   protected body Textrender_Lock is
      entry Seize when not Busy is
      begin
         Busy := True;
      end Seize;

      procedure Release is
      begin
         Busy := False;
      end Release;
   end Textrender_Lock;

   overriding procedure Initialize (Guard : in out Textrender_Guard) is
   begin
      Textrender_Lock.Seize;
      Guard.Held := True;
   end Initialize;

   overriding procedure Finalize (Guard : in out Textrender_Guard) is
   begin
      if Guard.Held then
         Guard.Held := False;
         Textrender_Lock.Release;
      end if;
   end Finalize;

   function Cell (Size : Positive) return Positive is (2 * Size + 2);

   function Atlas_Side (Size : Positive) return Positive is (Positive'Max (256, 4 * Cell (Size)));

   function Atlas_Bytes (Size : Positive) return Byte_Count is (Byte_Count (Atlas_Side (Size)) ** 2);

   function File_Bytes (Path : String) return Byte_Count is
   begin
      return Byte_Count (Ada.Directories.Size (Path));
   exception
      --  A path that names no readable file: the load fails, and costs nothing for its file.
      when Ada.Directories.Name_Error | Ada.Directories.Use_Error =>
         return 0;
   end File_Bytes;

   function Load_Work (Size : Positive; File : Byte_Count) return Pixel_Count is
     (Pixel_Count (Atlas_Bytes (Size)) + Pixel_Count (File) + 65_536);

   function Glyph_Work (Size : Positive) return Pixel_Count is (16 * Pixel_Count (Cell (Size)) ** 2);

   procedure Free is new Ada.Unchecked_Deallocation (Textrender.Renderer, Renderer_Access);

   function Cached (Cache : Font_Cache; Path : String; Size : Positive) return Boolean is
     (for some Item of Cache.Items =>
        Item.Used and then Ada.Strings.Unbounded.To_String (Item.Path) = Path and then Item.Size = Size);

   function Acquire
     (Cache : in out Font_Cache;
      Path : String;
      Size : Positive;
      Slot : out Positive;
      Held : Textrender_Guard) return Textrender.Status_Code
   is
      Key : constant Ada.Strings.Unbounded.Unbounded_String := Ada.Strings.Unbounded.To_Unbounded_String (Path);
      Spare : Natural := 0;
      Loaded : Natural := 0;
      Status : Textrender.Status_Code;
   begin
      Cache.Clock := (if Cache.Clock = Natural'Last then 0 else Cache.Clock + 1);
      for Index in Cache.Items'Range loop
         if Cache.Items (Index).Used and then Cache.Items (Index).Path = Key and then Cache.Items (Index).Size = Size
         then
            Cache.Items (Index).Stamp := Cache.Clock;
            Slot := Index;
            return Textrender.Success;
         elsif Cache.Items (Index).Used then
            Loaded := Loaded + 1;
         elsif Spare = 0 then
            Spare := Index;
         end if;
      end loop;
      --  At most Slots of the Slots + 1 renderers are in use, so one is free.
      Slot := Spare;
      declare
         Item : Slot_Type renames Cache.Items (Spare);
      begin
         if Item.Renderer = null then
            Item.Renderer := new Textrender.Renderer;
         end if;
         Status := Item.Renderer.Load_Font
           (Path => Path, Pixel_Size => Size, Cell_Width => Cell (Size), Cell_Height => Cell (Size),
            Atlas_Width => Atlas_Side (Size), Atlas_Height => Atlas_Side (Size));
         if Status /= Textrender.Success then
            return Status;
         end if;
         --  A full atlas evicts glyphs rather than refusing new ones.
         Item.Renderer.Set_Atlas_Eviction (True);
         Item.Path := Key;
         Item.Size := Size;
         Item.Used := True;
         Item.Stamp := Cache.Clock;
      end;
      --  The new font is in: only now does the least recently used one make room.
      if Loaded = Slots then
         declare
            Oldest : Natural := 0;
         begin
            for Index in Cache.Items'Range loop
               if Index /= Spare and then Cache.Items (Index).Used
                 and then (Oldest = 0 or else Cache.Items (Index).Stamp < Cache.Items (Oldest).Stamp)
               then
                  Oldest := Index;
               end if;
            end loop;
            Cache.Items (Oldest).Renderer.Reset;
            Cache.Items (Oldest).Used := False;
            Cache.Items (Oldest).Path := Ada.Strings.Unbounded.Null_Unbounded_String;
         end;
      end if;
      return Textrender.Success;
   end Acquire;

   function Renderer (Cache : Font_Cache; Slot : Positive; Held : Textrender_Guard)
     return not null access Textrender.Renderer
   is
   begin
      return Cache.Items (Slot).Renderer;
   end Renderer;

   procedure Clear (Cache : in out Font_Cache) is
      Guard : Textrender_Guard;
      pragma Unreferenced (Guard);
   begin
      for Item of Cache.Items loop
         Free (Item.Renderer);
         Item.Used := False;
         Item.Path := Ada.Strings.Unbounded.Null_Unbounded_String;
      end loop;
   end Clear;

   overriding procedure Finalize (Item : in out Slot_Type) is
   begin
      if Item.Renderer /= null then
         declare
            Guard : Textrender_Guard;
            pragma Unreferenced (Guard);
         begin
            Free (Item.Renderer);
         end;
      end if;
   end Finalize;
end Pictlib.Internal.Text;
