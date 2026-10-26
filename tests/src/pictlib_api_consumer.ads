with Pictlib;
with Pictlib.Capabilities;
with Pictlib.Decoding;
with Pictlib.Encoding;
with Pictlib.Errors;
with Pictlib.Fonts;
with Pictlib.Geometry;
with Pictlib.Images;
with Pictlib.Limits;
with Pictlib.Metadata;
with Pictlib.Opcodes;
with Pictlib.Pictures;
with Pictlib.Results;
with Pictlib.Streams;
with Pictlib.Version;

--  Compile-only consumer of the public API, the way an outside crate would use it.
package Pictlib_API_Consumer is
   Version : constant String := Pictlib.Version.Current;
   Default_Mode : constant Pictlib.Strictness_Mode := Pictlib.Strict;
   Default_Header_Policy : constant Pictlib.Header_Policy := Pictlib.Auto;
   Default_Limits : constant Pictlib.Limits.Limit_Set := Pictlib.Limits.Default_Limits;
   No_Error : constant Pictlib.Errors.Error := Pictlib.Errors.Make (Pictlib.Errors.No_Error);
   Success : constant Pictlib.Results.Result := Pictlib.Results.Success;
   Streams_Available : constant Boolean := Pictlib.Capabilities.Memory_Streams;
   subtype Source is Pictlib.Streams.Source;
   subtype Destination is Pictlib.Streams.Destination;
   subtype Decoder is Pictlib.Decoding.Decoder;
   subtype Visitor is Pictlib.Decoding.Opcode_Visitor;
   Default_Decode_Options : constant Pictlib.Decoding.Options := (others => <>);
   Default_Retention : constant Pictlib.Metadata.Retention_Policy := (others => <>);
   Empty_Header : constant Pictlib.Pictures.Header_Info := (others => <>);
   Origin : constant Pictlib.Geometry.Point := (others => 0);
   End_Opcode : constant Pictlib.Opcode := Pictlib.Opcodes.End_Picture;
   Default_Background : constant Pictlib.Images.RGB_Color := Default_Decode_Options.Background;
   subtype Output_View is Pictlib.Images.Mutable_Image_View;
   No_Fonts : constant Pictlib.Fonts.Font_Table := Pictlib.Fonts.Empty;
   subtype Font_ID is Pictlib.Fonts.Font_ID;
   subtype Encoder is Pictlib.Encoding.Encoder;
   Default_Encode_Options : constant Pictlib.Encoding.Options := (others => <>);
   Mono_Threshold : constant Pictlib.Byte := Pictlib.Encoding.Default_Mono_Threshold;
   Keeps_Alpha : constant Boolean := Default_Encode_Options.Keep_Alpha;
   Automatic : constant Pictlib.Encoding.Layout_Kind := Pictlib.Encoding.Auto;
   Every_Capability : constant array (1 .. 10) of Boolean :=
     [Pictlib.Capabilities.Foundation_API, Pictlib.Capabilities.Memory_Streams,
      Pictlib.Capabilities.Container_Decoding, Pictlib.Capabilities.Opcode_Enumeration,
      Pictlib.Capabilities.Raster_Decoding, Pictlib.Capabilities.Vector_Rendering,
      Pictlib.Capabilities.Text_Rendering, Pictlib.Capabilities.QuickTime_JPEG_Decoding,
      Pictlib.Capabilities.Metadata_Retention, Pictlib.Capabilities.Raster_Encoding];

   --  Every public subprogram, renamed by its profile: a change to a parameter's or result's type, a parameter's
   --  mode, or the number of parameters breaks this unit. Ada does not compare a renaming's parameter subtypes,
   --  names or defaults with the subprogram's, so this unit does not catch changes to those.

   --  Decoding.
   procedure Initialize
     (Object : in out Decoder;
      Input : not null access Pictlib.Streams.Source'Class;
      Decode_Options : Pictlib.Decoding.Options := (others => <>);
      Decode_Limits : Pictlib.Limits.Limit_Set := Pictlib.Limits.Default_Limits)
     renames Pictlib.Decoding.Initialize;
   procedure Reset (Object : in out Decoder; Input : not null access Pictlib.Streams.Source'Class)
     renames Pictlib.Decoding.Reset;
   function State (Object : Decoder) return Pictlib.Decoding.Decoder_State renames Pictlib.Decoding.State;
   function Read_Header (Object : in out Decoder) return Pictlib.Results.Result renames Pictlib.Decoding.Read_Header;
   function Header (Object : Decoder) return Pictlib.Pictures.Header_Info renames Pictlib.Decoding.Header;
   function Enumerate (Object : in out Decoder; Visitor : in out Pictlib.Decoding.Opcode_Visitor'Class)
     return Pictlib.Results.Result renames Pictlib.Decoding.Enumerate;
   function Render (Object : in out Decoder; Output : Output_View) return Pictlib.Results.Result
     renames Pictlib.Decoding.Render;
   function Last_Error (Object : Decoder) return Pictlib.Errors.Error renames Pictlib.Decoding.Last_Error;
   function Warning_Count (Object : Decoder) return Natural renames Pictlib.Decoding.Warning_Count;
   function Warning_At (Object : Decoder; Index : Positive) return Pictlib.Errors.Warning
     renames Pictlib.Decoding.Warning_At;
   function Metadata_Count (Object : Decoder) return Natural renames Pictlib.Decoding.Metadata_Count;
   function Metadata_Item (Object : Decoder; Index : Positive) return Pictlib.Metadata.Item_Info
     renames Pictlib.Decoding.Metadata_Item;
   function Copy_Metadata
     (Object : Decoder;
      Index : Positive;
      Buffer : out Pictlib.Streams.Byte_Array;
      Count : out Pictlib.Byte_Count) return Pictlib.Results.Result renames Pictlib.Decoding.Copy_Metadata;
   procedure Cancel (Object : in out Decoder) renames Pictlib.Decoding.Cancel;
   procedure Finalize (Object : in out Decoder) renames Pictlib.Decoding.Finalize;

   --  Encoding.
   procedure Initialize
     (Object : in out Encoder;
      Output : not null access Pictlib.Streams.Destination'Class;
      Encode_Options : Pictlib.Encoding.Options := (others => <>);
      Encode_Limits : Pictlib.Limits.Limit_Set := Pictlib.Limits.Default_Limits)
     renames Pictlib.Encoding.Initialize;
   procedure Reset (Object : in out Encoder; Output : not null access Pictlib.Streams.Destination'Class)
     renames Pictlib.Encoding.Reset;
   function State (Object : Encoder) return Pictlib.Encoding.Encoder_State renames Pictlib.Encoding.State;
   function Encode (Object : in out Encoder; Image : Pictlib.Images.Image_View) return Pictlib.Results.Result
     renames Pictlib.Encoding.Encode;
   function Finish (Object : in out Encoder) return Pictlib.Results.Result renames Pictlib.Encoding.Finish;
   function Layout_Used (Object : Encoder) return Pictlib.Encoding.Layout_Kind renames Pictlib.Encoding.Layout_Used;
   function Bytes_Written (Object : Encoder) return Pictlib.Byte_Count renames Pictlib.Encoding.Bytes_Written;
   function Last_Error (Object : Encoder) return Pictlib.Errors.Error renames Pictlib.Encoding.Last_Error;
   procedure Cancel (Object : in out Encoder) renames Pictlib.Encoding.Cancel;
   procedure Finalize (Object : in out Encoder) renames Pictlib.Encoding.Finalize;

   --  Fonts.
   procedure Add (Table : in out Pictlib.Fonts.Font_Table; Family : String; Path : String)
     renames Pictlib.Fonts.Add;
   procedure Add (Table : in out Pictlib.Fonts.Font_Table; ID : Font_ID; Path : String) renames Pictlib.Fonts.Add;
   procedure Set_Default (Table : in out Pictlib.Fonts.Font_Table; Path : String) renames Pictlib.Fonts.Set_Default;
   function Classic_Name (ID : Font_ID) return String renames Pictlib.Fonts.Classic_Name;
   function Resolve (Table : Pictlib.Fonts.Font_Table; ID : Font_ID; Family : String := "") return String
     renames Pictlib.Fonts.Resolve;

   --  Images.
   function Bytes_Per_Pixel (Format : Pictlib.Pixel_Format) return Pictlib.Byte_Count
     renames Pictlib.Images.Bytes_Per_Pixel;
   function Minimum_Row_Bytes (Width : Pictlib.Image_Width; Format : Pictlib.Pixel_Format) return Pictlib.Byte_Count
     renames Pictlib.Images.Minimum_Row_Bytes;
   function Descriptor_Is_Valid (Descriptor : Pictlib.Images.Image_Descriptor; Storage_Length : Natural)
     return Boolean renames Pictlib.Images.Descriptor_Is_Valid;
   function Is_Valid (View : Pictlib.Images.Image_View) return Boolean renames Pictlib.Images.Is_Valid;
   function Is_Valid (View : Output_View) return Boolean renames Pictlib.Images.Is_Valid;

   --  Streams.
   procedure Open
     (Object : in out Pictlib.Streams.Memory_Source;
      Storage : not null Pictlib.Streams.Const_Byte_Array_Access;
      Max_Transfer : Pictlib.Byte_Count := Pictlib.Byte_Count'Last) renames Pictlib.Streams.Open;
   procedure Open
     (Object : in out Pictlib.Streams.Fixed_Buffer_Destination;
      Storage : not null Pictlib.Streams.Byte_Array_Access;
      Max_Transfer : Pictlib.Byte_Count := Pictlib.Byte_Count'Last) renames Pictlib.Streams.Open;
   function Read_Exact (Object : in out Source'Class; Buffer : out Pictlib.Streams.Byte_Array)
     return Pictlib.Results.Result renames Pictlib.Streams.Read_Exact;
   function Skip_Exact (Object : in out Source'Class; Count : Pictlib.Byte_Count) return Pictlib.Results.Result
     renames Pictlib.Streams.Skip_Exact;
   function Write_All (Object : in out Destination'Class; Buffer : Pictlib.Streams.Byte_Array)
     return Pictlib.Results.Result renames Pictlib.Streams.Write_All;

   --  Geometry and results.
   function Width (Item : Pictlib.Geometry.Rect) return Integer renames Pictlib.Geometry.Width;
   function Height (Item : Pictlib.Geometry.Rect) return Integer renames Pictlib.Geometry.Height;
   function Is_Empty (Item : Pictlib.Geometry.Rect) return Boolean renames Pictlib.Geometry.Is_Empty;
   function Succeeded_Result return Pictlib.Results.Result renames Pictlib.Results.Success;
   function Failure (Code : Pictlib.Errors.Error_Code) return Pictlib.Results.Result renames Pictlib.Results.Failure;
   function Failure (Item : Pictlib.Errors.Error) return Pictlib.Results.Result renames Pictlib.Results.Failure;
   function Succeeded (Item : Pictlib.Results.Result) return Boolean renames Pictlib.Results.Succeeded;

   --  The memory source's and the fixed destination's operations.
   function Read (Object : in out Pictlib.Streams.Memory_Source; Buffer : out Pictlib.Streams.Byte_Array)
     return Pictlib.Streams.Source_Result renames Pictlib.Streams.Read;
   function Offset (Object : Pictlib.Streams.Memory_Source) return Pictlib.Source_Offset renames Pictlib.Streams.Offset;
   function Skip (Object : in out Pictlib.Streams.Memory_Source; Count : Pictlib.Byte_Count)
     return Pictlib.Streams.Source_Result renames Pictlib.Streams.Skip;
   function Write (Object : in out Pictlib.Streams.Fixed_Buffer_Destination; Buffer : Pictlib.Streams.Byte_Array)
     return Pictlib.Streams.Destination_Result renames Pictlib.Streams.Write;
   function Offset (Object : Pictlib.Streams.Fixed_Buffer_Destination) return Pictlib.Destination_Offset
     renames Pictlib.Streams.Offset;
   function Flush (Object : in out Pictlib.Streams.Fixed_Buffer_Destination) return Pictlib.Errors.Error
     renames Pictlib.Streams.Flush;

   --  Opcodes and errors.
   function Rule_For (Op : Pictlib.Opcode) return Pictlib.Opcodes.Length_Rule renames Pictlib.Opcodes.Rule_For;
   function Is_Reserved (Op : Pictlib.Opcode) return Boolean renames Pictlib.Opcodes.Is_Reserved;
   function Name (Op : Pictlib.Opcode) return String renames Pictlib.Opcodes.Name;
   function Identifier_For (Code : Pictlib.Errors.Error_Code) return String renames Pictlib.Errors.Identifier_For;
   function Identifier_For (Code : Pictlib.Errors.Warning_Code) return String renames Pictlib.Errors.Identifier_For;
   function Make
     (Code : Pictlib.Errors.Error_Code;
      Context : Pictlib.Errors.Diagnostic_Context := (others => <>)) return Pictlib.Errors.Error
     renames Pictlib.Errors.Make;
   function Make_Warning
     (Code : Pictlib.Errors.Warning_Code;
      Severity : Pictlib.Errors.Warning_Severity;
      Context : Pictlib.Errors.Diagnostic_Context := (others => <>)) return Pictlib.Errors.Warning
     renames Pictlib.Errors.Make_Warning;
   function Is_Fatal (Item : Pictlib.Errors.Error) return Boolean renames Pictlib.Errors.Is_Fatal;
end Pictlib_API_Consumer;
