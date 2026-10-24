with Ada.Directories;
with Ada.Streams.Stream_IO;

package body Pictlib_Testing.Files is
   function Load (Name : String) return Bytes_Access is (Load_Path ("fixtures/" & Name));

   function Load_Path (Path : String) return Bytes_Access is
      use Ada.Streams.Stream_IO;
      Size : constant Natural := Natural (Ada.Directories.Size (Path));
      Result : constant Bytes_Access := new Pictlib.Streams.Byte_Array (1 .. Size);
      File : File_Type;
   begin
      Open (File, In_File, Path);
      Pictlib.Streams.Byte_Array'Read (Stream (File), Result.all);
      Close (File);
      return Result;
   end Load_Path;

   function Read_Raster (Path : String; Item : out Raster) return Boolean is
      Data : Bytes_Access;
      Position : Positive;
      Fields : array (1 .. 3) of Natural := [others => 0];
   begin
      Item := (others => <>);
      if not Ada.Directories.Exists (Path) then
         return False;
      end if;
      Data := Load_Path (Path);
      if Data'Length < 3 or else Character'Val (Data (Data'First)) /= 'P'
        or else Character'Val (Data (Data'First + 1)) not in '4' | '6'
      then
         return False;
      end if;
      Item.Kind := Character'Val (Data (Data'First + 1));
      Position := Data'First + 2;
      Fields (3) := 255;
      for Field in 1 .. (if Item.Kind = '6' then 3 else 2) loop
         Fields (Field) := 0;
         while Position <= Data'Last and then Character'Val (Data (Position)) not in '0' .. '9' loop
            Position := Position + 1;
         end loop;
         while Position <= Data'Last and then Character'Val (Data (Position)) in '0' .. '9'
           and then Fields (Field) < 1_000_000
         loop
            Fields (Field) := Fields (Field) * 10 + Character'Pos (Character'Val (Data (Position))) - 48;
            Position := Position + 1;
         end loop;
      end loop;
      --  One whitespace byte ends the header.
      Item := (Data => Data, Kind => Item.Kind, Width => Fields (1), Height => Fields (2),
               First_Pixel => Position + 1);
      return Fields (3) = 255 and then Fields (1) > 0 and then Fields (2) > 0
        and then Data'Last - Position
                 >= (if Item.Kind = '6' then 3 * Fields (1) else (Fields (1) + 7) / 8) * Fields (2);
   end Read_Raster;

   function Load_Raster (Name : String) return Raster is
      Item : Raster;
   begin
      if not Read_Raster ("fixtures/" & Name, Item) then
         raise Program_Error with "fixtures/" & Name & " is not a Netpbm raster";
      end if;
      return Item;
   end Load_Raster;

   function Pixel (Item : Raster; X, Y : Natural) return Pictlib.Images.RGB_Color is
   begin
      if Item.Kind = '6' then
         declare
            At_Pixel : constant Positive := Item.First_Pixel + 3 * (Y * Item.Width + X);
         begin
            return (Item.Data (At_Pixel), Item.Data (At_Pixel + 1), Item.Data (At_Pixel + 2));
         end;
      end if;
      declare
         Row_Bytes : constant Natural := (Item.Width + 7) / 8;
         Value : constant Natural := Natural (Item.Data (Item.First_Pixel + Y * Row_Bytes + X / 8));
      begin
         return (if (Value / 2 ** (7 - X mod 8)) mod 2 = 1 then Pictlib.Images.Black else Pictlib.Images.White);
      end;
   end Pixel;
end Pictlib_Testing.Files;
