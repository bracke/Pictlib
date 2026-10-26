with Interfaces;
with Jpeglib.Streams;
with Pictlib.Internal.Sessions;
with Pictlib.Pictures;
with Pictlib.Results;

--  The one bridge to jpeglib: an embedded JPEG read straight from the picture through its public API, under
--  pictlib's budgets, its failures told in pictlib's terms.
package Pictlib.Internal.JPEG_Bridge is
   --  Decoded pixels are RGB.
   Bytes_Per_Pixel : constant := 3;

   type Pixel_Buffer_Access is access Jpeglib.Streams.Byte_Array;

   --  Free.
   --  @param Pixels Pixels to release; null after.
   procedure Free (Pixels : in out Pixel_Buffer_Access);

   --  The image a picture describes: its size, and the bytes of compressed data that follow.
   type Image is record
      Width, Height : Natural := 0;
      Data_Size : Interfaces.Unsigned_32 := 0;
   end record;

   --  Pixel bytes.
   --  @param Item An image.
   --  @return The bytes its decoded pixels take.
   function Pixel_Bytes (Item : Image) return Byte_Count is
     (Bytes_Per_Pixel * Byte_Count (Item.Width) * Byte_Count (Item.Height));

   --  Admit and decode.
   --  @param S Session positioned at the compressed data.
   --  @param Event The opcode, for diagnostics.
   --  @param Item The image the description states.
   --  @param Pixels Receives the decoded RGB pixels, row by row; null on failure.
   --  @return Success, or the failure: a budget, an unsupported or malformed JPEG, the picture's own reading.
   function Admit_And_Decode
     (S : in out Sessions.Session;
      Event : Pictures.Opcode_Event;
      Item : Image;
      Pixels : out Pixel_Buffer_Access) return Results.Result
     --  The pixels are one array, indexed by Natural: the caller refuses an image larger.
     with Pre => Pixel_Bytes (Item) <= Byte_Count (Natural'Last);
end Pictlib.Internal.JPEG_Bridge;
