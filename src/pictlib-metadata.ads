with Interfaces;

--  Non-pixel content a decoder may retain, under Limits.Max_Retained_Metadata_Bytes and Max_Metadata_Items.
package Pictlib.Metadata is
   pragma Preelaborate;

   type Item_Kind is
     (File_Header,        --  the 512-byte application header of a PICT file
      Short_Comment,      --  ShortComment (16#00A0#): a kind, no data
      Long_Comment,       --  LongComment (16#00A1#): a kind and its data
      Font_Name,          --  fontName (16#002C#): a font ID and its Mac Roman name
      QuickTime_Payload,  --  the data of CompressedQuickTime / UncompressedQuickTime
      Reserved_Payload);  --  the data of a reserved length-prefixed opcode

   type Retention_Policy is record
      File_Headers : Boolean := False;
      Comments : Boolean := True;
      Font_Names : Boolean := True;
      QuickTime_Payloads : Boolean := False;
      Reserved_Payloads : Boolean := False;
   end record;

   type Item_Info is record
      Kind : Item_Kind := File_Header;
      Ordinal : Opcode_Ordinal := 0;
      Offset : Source_Offset := 0;
      Op : Opcode := 0;
      Comment_Kind : Interfaces.Unsigned_16 := 0;
      Font_ID : Interfaces.Unsigned_16 := 0;
      Data_Length : Byte_Count := 0;
   end record;
end Pictlib.Metadata;
