with Pictlib.Internal.Sessions.Accounting;
with Ada.Unchecked_Deallocation;
with Jpeglib;
with Jpeglib.Decoding;
with Jpeglib.Errors;
with Jpeglib.Images;
with Jpeglib.Limits;
with Jpeglib.Results;
with Pictlib.Errors;
with Pictlib.Internal.Checked_Arithmetic;
with Pictlib.Internal.Failures;
with Pictlib.Streams;

package body Pictlib.Internal.JPEG_Bridge is
   package Accounting renames Pictlib.Internal.Sessions.Accounting;
   use type Jpeglib.Source_Offset;

   --  jpeglib's own buffers may take at most this many times the image's RGB bytes, counted over its MCU-padded
   --  extent, plus Jpeglib_Fixed_Bytes: what a progressive decode of that size needs, however narrow the image
   --  and however its chroma is subsampled, so one image does not take a session's whole allocation quota.
   Jpeglib_Pixel_Factor : constant := 8;
   Jpeglib_Fixed_Bytes : constant := 1_048_576;
   --  The largest MCU side: 8 pixels times jpeglib's largest sampling factor, 4.
   MCU_Side : constant := 32;
   --  The most jpeglib is handed at once.
   Read_Chunk : constant := 4096;
   --  jpeglib's coefficients: 64 per block, 4 bytes each.
   Coefficient_Block_Bytes : constant := 64 * 4;
   --  jpeglib decodes a progressive scan with a map of 64 bytes a block on the stack, sized by the image; a
   --  decoder may run in a task with a small stack, so pictlib draws no progressive image whose map would be
   --  larger than this.
   Progressive_Stack_Bytes : constant := 512 * 1024;

   procedure Free_Buffer is new Ada.Unchecked_Deallocation (Jpeglib.Streams.Byte_Array, Pixel_Buffer_Access);

   procedure Free (Pixels : in out Pixel_Buffer_Access) is
   begin
      Free_Buffer (Pixels);
   end Free;

   --  What jpeglib's failure means for the picture. Its pixel and buffer limits are pictlib's limits, a JPEG
   --  feature it lacks is an unsupported feature and its own invariants are an internal failure, none of them
   --  recovered; malformed JPEG data, its metadata included, is Embedded_Image_Failed. jpeglib's code is kept
   --  as the underlying one. A failure of the picture's own reading, which jpeglib saw as its source failing, is
   --  Source_Failure, and stands.
   function Rejected
     (S : Sessions.Session;
      Event : Pictures.Opcode_Event;
      Item : Image;
      Share : Byte_Count;
      Decoded : Jpeglib.Results.Result;
      Source_Failure : Results.Result) return Results.Result
   is
      use type Jpeglib.Errors.Error_Code;
      use type Jpeglib.Marker_Code;
      Code : constant Jpeglib.Errors.Error_Code := Decoded.First_Error.Code;
      --  jpeglib reports a frame of more components than it decodes at the frame's marker, and its buffers
      --  outgrowing their share nowhere in particular.
      At_Frame : constant Boolean := Decoded.First_Error.Context.Marker /= 0;
      Pixels_Of : constant Byte_Count := Byte_Count (Item.Width) * Byte_Count (Item.Height);
      --  The pixels and jpeglib's share are what the image was allowed: the configured limit itself when
      --  nothing capped the share.
      Allowed : constant Byte_Count := Checked_Arithmetic.Saturating_Add (Bytes_Per_Pixel * Pixels_Of, Share);
      Context : constant Errors.Diagnostic_Context :=
        (Failures.Context_Of (Event) with delta
           Underlying_Code => Long_Long_Integer (Jpeglib.Errors.Error_Code'Pos (Code)),
           Has_Underlying_Code => True);
   begin
      if not Results.Succeeded (Source_Failure) then
         return Source_Failure;
      elsif Code = Jpeglib.Errors.Pixel_Count_Exceeded then
         return Failures.Over_Limit
           (Context, Embedded_Image_Pixel_Limit, Byte_Count (S.Budget.Max_Embedded_Image_Pixels), Pixels_Of);
      elsif Code = Jpeglib.Errors.Output_Limit_Exceeded and then not At_Frame then
         return Failures.Over_Limit
           (Context, Allocation_Byte_Limit, Allowed, Checked_Arithmetic.Saturating_Add (Allowed, 1));
      end if;
      return Results.Failure
        (Errors.Make
           ((case Code is
                when Jpeglib.Errors.Unsupported_Feature | Jpeglib.Errors.Output_Limit_Exceeded =>
                  Errors.Unsupported_Feature,
                --  pictlib drives jpeglib's states in order, so Invalid_State comes only from malformed data.
                when Jpeglib.Errors.Operation_Cancelled | Jpeglib.Errors.Internal_Invariant_Failed =>
                  Errors.Internal_Invariant_Failed,
                when others => Errors.Embedded_Image_Failed),
            Context));
   end Rejected;

   --  What pictlib requires of a JPEG's header before decoding it: the description's size, a height known now,
   --  no lossless frame or large progressive one, whose stack buffers no budget bounds, and a hierarchical one's
   --  coefficients twice over within jpeglib's share.
   function Check_Header
     (Event : Pictures.Opcode_Event;
      Item : Image;
      Share : Byte_Count;
      Info : Jpeglib.Decoding.Image_Info) return Results.Result
   is
      Bytes : constant Natural := Bytes_Per_Pixel * Item.Width * Item.Height;
      Blocks : constant Byte_Count := Byte_Count (Info.Coefficient_Blocks);
      --  A hierarchical image's continuation frames may be progressive whatever its first frame is.
      Progressive : constant Boolean :=
        Info.Mode in Jpeglib.Progressive_DCT | Jpeglib.Differential_Progressive_DCT or else Info.Hierarchical;
   begin
      if not Info.Height_Defined then
         --  A height a later DNL marker gives: jpeglib reports neither the height nor the coefficients it will
         --  need, so nothing here could bound them.
         return Failures.In_Opcode (Event, Errors.Unsupported_Feature);
      elsif Natural (Info.Width) /= Item.Width or else Natural (Info.Height) /= Item.Height then
         --  The JPEG must be the image the description states.
         return Failures.In_Opcode (Event, Errors.Embedded_Image_Failed);
      elsif Info.Mode in Jpeglib.Lossless | Jpeglib.Differential_Lossless
        or else (Progressive and then Blocks > Progressive_Stack_Bytes / 64)
      then
         --  jpeglib would decode it through stack buffers sized by the image, which no budget bounds: a lossless
         --  image's planes, a large progressive image's coefficient map. This renderer does not draw it.
         return Failures.In_Opcode (Event, Errors.Unsupported_Feature);
      elsif Info.Hierarchical
        and then Checked_Arithmetic.Saturating_Multiply (2 * Coefficient_Block_Bytes, Blocks) > Share
      then
         --  A continuation frame's coefficients are held beside the first frame's: twice what jpeglib checks
         --  against its share.
         return Failures.Over_Limit
           (Failures.Context_Of (Event), Allocation_Byte_Limit,
            Checked_Arithmetic.Saturating_Add (Byte_Count (Bytes), Share),
            Checked_Arithmetic.Saturating_Add
              (Byte_Count (Bytes), Checked_Arithmetic.Saturating_Multiply (2 * Coefficient_Block_Bytes, Blocks)));
      end if;
      return Results.Success;
   end Check_Header;

   --  Decode the JPEG, read straight from the picture, at most Item.Data_Size bytes, into Pixels, which is set
   --  aside only once the JPEG's header agrees with the description; jpeglib is given Share for its buffers.
   function Decode_JPEG
     (S : in out Sessions.Session;
      Event : Pictures.Opcode_Event;
      Item : Image;
      Share : Byte_Count;
      Pixels : out Pixel_Buffer_Access) return Results.Result
   is
      type Embedded_Source is limited new Jpeglib.Streams.Source with record
         Remaining : Byte_Count := Byte_Count (Item.Data_Size);
         Taken : Jpeglib.Source_Offset := 0;
         Failure : Results.Result := Results.Success;
      end record;

      overriding function Read
        (Object : in out Embedded_Source; Buffer : out Jpeglib.Streams.Byte_Array)
         return Jpeglib.Streams.Source_Result;
      overriding function Offset (Object : Embedded_Source) return Jpeglib.Source_Offset is (Object.Taken);
      overriding function Skip (Object : in out Embedded_Source; Count : Jpeglib.Byte_Count)
        return Jpeglib.Streams.Source_Result;

      function Failed (Object : in out Embedded_Source; Step : Results.Result)
        return Jpeglib.Streams.Source_Result is
      begin
         Object.Failure := Step;
         return (Result => Jpeglib.Errors.Make (Jpeglib.Errors.Source_Read_Failed), Count => 0,
                 End_Of_Input => False);
      end Failed;

      overriding function Read
        (Object : in out Embedded_Source; Buffer : out Jpeglib.Streams.Byte_Array)
         return Jpeglib.Streams.Source_Result
      is
         Count : constant Natural :=
           Natural (Byte_Count'Min (Byte_Count (Natural'Min (Buffer'Length, Read_Chunk)), Object.Remaining));
         Chunk : Streams.Byte_Array (1 .. Count);
         Step : Results.Result;
      begin
         --  Only the bytes delivered are defined, as for any source: clearing the rest on every call would clear
         --  jpeglib's buffer over and over.
         if Count = 0 then
            return (Result => Jpeglib.Errors.Make (Jpeglib.Errors.No_Error), Count => 0, End_Of_Input => True);
         end if;
         Step := Sessions.Read_Into (S, Chunk);
         if not Results.Succeeded (Step) then
            return Failed (Object, Step);
         end if;
         for Index in Chunk'Range loop
            Buffer (Buffer'First + Index - 1) := Jpeglib.Byte (Chunk (Index));
         end loop;
         Object.Remaining := Object.Remaining - Byte_Count (Count);
         Object.Taken := Object.Taken + Jpeglib.Source_Offset (Count);
         return (Result => Jpeglib.Errors.Make (Jpeglib.Errors.No_Error), Count => Jpeglib.Byte_Count (Count),
                 End_Of_Input => Object.Remaining = 0);
      end Read;

      overriding function Skip (Object : in out Embedded_Source; Count : Jpeglib.Byte_Count)
        return Jpeglib.Streams.Source_Result
      is
         Wanted : constant Byte_Count := Byte_Count'Min (Byte_Count (Count), Object.Remaining);
         Step : constant Results.Result := Sessions.Skip_Data (S, Wanted);
      begin
         if not Results.Succeeded (Step) then
            return Failed (Object, Step);
         end if;
         Object.Remaining := Object.Remaining - Wanted;
         Object.Taken := Object.Taken + Jpeglib.Source_Offset (Wanted);
         return (Result => Jpeglib.Errors.Make (Jpeglib.Errors.No_Error), Count => Jpeglib.Byte_Count (Wanted),
                 End_Of_Input => Object.Remaining = 0);
      end Skip;

      Input : aliased Embedded_Source;
      Decoder : Jpeglib.Decoding.Decoder;
      Decoded : Jpeglib.Results.Result;
      Bytes : constant Natural := Bytes_Per_Pixel * Item.Width * Item.Height;

   begin
      Pixels := null;
      Jpeglib.Decoding.Initialize
        (Decoder, Input'Access,
         (Output_Format => Jpeglib.Images.RGB_24, others => <>),
         (Jpeglib.Limits.Default_Limits with delta
            Max_Pixels => Jpeglib.Pixel_Count (S.Budget.Max_Embedded_Image_Pixels),
            --  Its own caps are pictlib's: the coefficients come out of its share, and its output is the pixels.
            Max_Allocation_Bytes => Jpeglib.Byte_Count (Share),
            Max_Coefficient_Bytes => Jpeglib.Byte_Count (Share),
            Max_Output_Bytes => Jpeglib.Byte_Count (Bytes),
            --  pictlib keeps no JPEG metadata, and what jpeglib counts of it lies within the data, which
            --  Max_Embedded_Image_Bytes bounds: a valid JPEG's metadata is never over a limit.
            Max_Metadata_Segments => Natural'Last,
            Max_Metadata_Bytes => Jpeglib.Byte_Count (Item.Data_Size),
            Max_ICC_Profile_Bytes => Jpeglib.Byte_Count (Item.Data_Size)));
      Decoded := Jpeglib.Decoding.Read_Header (Decoder);
      if Jpeglib.Results.Succeeded (Decoded) then
         declare
            Checked : constant Results.Result :=
              Check_Header (Event, Item, Share, Jpeglib.Decoding.Header (Decoder));
         begin
            if not Results.Succeeded (Checked) then
               Jpeglib.Decoding.Finalize (Decoder);
               return Checked;
            end if;
         end;
      end if;
      if Jpeglib.Results.Succeeded (Decoded) then
         Pixels := new Jpeglib.Streams.Byte_Array (1 .. Bytes);
         declare
            View : Jpeglib.Images.Mutable_Image_View :=
              (Descriptor =>
                 (Width => Jpeglib.Image_Width (Item.Width), Height => Jpeglib.Image_Height (Item.Height),
                  Format => Jpeglib.Images.RGB_24, Stride => Jpeglib.Row_Stride (Bytes_Per_Pixel * Item.Width),
                  Accessible_Bytes => Jpeglib.Byte_Count (Bytes)),
               Storage => Pixels);
         begin
            Decoded := Jpeglib.Decoding.Decode_Image (Decoder, View);
         end;
      end if;
      Jpeglib.Decoding.Finalize (Decoder);
      if not Jpeglib.Results.Succeeded (Decoded) then
         Free (Pixels);
         return Rejected (S, Event, Item, Share, Decoded, Input.Failure);
      end if;
      --  What jpeglib left of the image data; the pixels are no one's if it cannot be skipped.
      if Input.Remaining > 0 then
         declare
            Skipped : constant Results.Result := Sessions.Skip_Data (S, Input.Remaining);
         begin
            if not Results.Succeeded (Skipped) then
               Free (Pixels);
            end if;
            return Skipped;
         end;
      end if;
      return Results.Success;
   exception
      --  The source's exception, met through jpeglib or skipping, passes through, the pixels and jpeglib's buffers
      --  released.
      when others =>
         Jpeglib.Decoding.Finalize (Decoder);
         Free (Pixels);
         raise;
   end Decode_JPEG;

   --  Admit the image's pixels and jpeglib's share of the allocation budgets, charge its decoding, and decode it.
   --  The pixels are one allocation. Decoding is drawing work, a unit per pixel and per row, drawn or not, as for
   --  a copied pixmap, and a unit per byte of compressed data, which jpeglib reads bit by bit. jpeglib's own
   --  buffers get what is left of the per-allocation budget once the pixels are admitted, but no more than a
   --  decode of this size needs, counted against the session's total.
   function Admit_And_Decode
     (S : in out Sessions.Session;
      Event : Pictures.Opcode_Event;
      Item : Image;
      Pixels : out Pixel_Buffer_Access) return Results.Result
   is
      Pixel_Bytes : constant Byte_Count := Bytes_Per_Pixel * Byte_Count (Item.Width) * Byte_Count (Item.Height);
      Padded_Bytes : constant Byte_Count :=
        Bytes_Per_Pixel * Byte_Count ((Item.Width + MCU_Side - 1) / MCU_Side * MCU_Side)
        * Byte_Count ((Item.Height + MCU_Side - 1) / MCU_Side * MCU_Side);
      Outcome : Results.Result := Accounting.Admit_Allocation (S, Pixel_Bytes);
   begin
      Pixels := null;
      if Results.Succeeded (Outcome) then
         Outcome :=
           Accounting.Charge_Work
             (S, Pixel_Count (Item.Width) * Pixel_Count (Item.Height) + Pixel_Count (Item.Height)
                 + Pixel_Count (Item.Data_Size));
      end if;
      if not Results.Succeeded (Outcome) then
         return Outcome;
      end if;
      declare
         Share : constant Byte_Count :=
           Byte_Count'Min (S.Budget.Max_Allocation_Bytes - Pixel_Bytes,
                           Jpeglib_Pixel_Factor * Padded_Bytes + Jpeglib_Fixed_Bytes);
      begin
         Outcome := Accounting.Admit_Aggregate (S, Share);
         if Results.Succeeded (Outcome) then
            Outcome := Decode_JPEG (S, Event, Item, Share, Pixels);
         end if;
         return Outcome;
      end;
   end Admit_And_Decode;
end Pictlib.Internal.JPEG_Bridge;
