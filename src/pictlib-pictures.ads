with Interfaces;
with Pictlib.Geometry;

--  What a picture's header says, and what enumerating its opcode stream reports.
package Pictlib.Pictures is
   pragma Preelaborate;

   type Header_Info is record
      Version : PICT_Version := Version_1;
      --  True when the 512-byte application header of a PICT file preceded the picture.
      Has_File_Header : Boolean := False;
      --  The low 16 bits of the picture's length as the picture states it; unreliable for version 2.
      Picture_Size : Interfaces.Unsigned_16 := 0;
      Frame : Geometry.Rect;
      --  True when a version 2 picture carried its HeaderOp (16#0C00#).
      Has_Header_Opcode : Boolean := False;
      --  Version 2 (header version -1) only: the fixed-point picture bounds.
      Fixed_Bounds : Geometry.Fixed_Rect;
      --  Extended version 2 only; 72 dpi otherwise.
      Horizontal_Resolution : Geometry.Fixed := Geometry.Fixed_72;
      Vertical_Resolution : Geometry.Fixed := Geometry.Fixed_72;
      --  Extended version 2: the header's source rectangle; otherwise the frame.
      Source_Rect : Geometry.Rect;
   end record;

   --  One opcode of the stream, reported after its data has been consumed.
   type Opcode_Event is record
      Ordinal : Opcode_Ordinal := 0;
      --  Source offset of the opcode itself, after any alignment pad byte.
      Offset : Source_Offset := 0;
      Op : Opcode := 0;
      --  Bytes of data after the opcode, excluding the opcode and any pad byte.
      Data_Length : Byte_Count := 0;
      Reserved : Boolean := False;
   end record;
end Pictlib.Pictures;
