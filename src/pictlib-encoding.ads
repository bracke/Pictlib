with Pictlib.Errors;
with Pictlib.Geometry;
with Pictlib.Images;
with Pictlib.Limits;
with Pictlib.Results;
with Pictlib.Streams;

--  Forward-only raster PICT encoder. One image becomes one extended version 2 picture: the optional 512-byte
--  file header, picSize, picFrame, VersionOp, HeaderOp, DefHilite, a clip of the frame, one bits opcode and
--  OpEndPic. Calls in the wrong state fail with Invalid_State (Operation_Cancelled after Cancel).
package Pictlib.Encoding is
   type Layout_Kind is
     (Auto,       --  Direct_32 when alpha is kept, else Mono_1 for black and white only, Indexed_8 for at most 256
                  --  colors, Direct_32 otherwise
      Direct_32,  --  DirectBitsRect, 32 bits, PackBits over component planes (pack type 4)
      Indexed_8,  --  PackBitsRect, an 8-bit PixMap with an exact color table
      Mono_1);    --  PackBitsRect, a 1-bit BitMap: black below Mono_Threshold luminance, white otherwise

   --  The luminance below which Mono_1 writes black, and the one Auto uses for black-and-white images.
   Default_Mono_Threshold : constant Byte := 128;

   type Options is record
      Layout : Layout_Kind := Auto;
      File_Header : Boolean := True;
      Horizontal_Resolution : Geometry.Fixed := Geometry.Fixed_72;
      Vertical_Resolution : Geometry.Fixed := Geometry.Fixed_72;
      Mono_Threshold : Byte := Default_Mono_Threshold;
      --  Direct_32 from a 32-bit view: write its alpha as a fourth component plane.
      Keep_Alpha : Boolean := False;
   end record;

   type Encoder_State is (Created, Ready, Encoded, Finished, Failed, Cancelled);

   type Encoder is limited private;

   --  Initialize.
   --  @param Object Encoder; any earlier picture is discarded.
   --  @param Output Borrowed destination; the caller keeps it alive until Finalize or another Initialize.
   --  @param Encode_Options Layout, file header, resolution, threshold and alpha.
   --  @param Encode_Limits Max_Output_Bytes, Max_Allocation_Bytes and the frame limits apply.
   procedure Initialize
     (Object : in out Encoder;
      Output : not null access Streams.Destination'Class;
      Encode_Options : Options := (others => <>);
      Encode_Limits : Limits.Limit_Set := Limits.Default_Limits);
   --  State.
   --  @param Object Encoder.
   --  @return Current state.
   function State (Object : Encoder) return Encoder_State;
   --  Encode.
   --  @param Object Encoder in state Ready; Encoded on success, Failed on a failure while writing or an exception
   --  from the destination once writing began (which propagates), and still Ready, Last_Error unchanged, on a
   --  failure found before the destination was written to.
   --  @param Image A valid caller view.
   --  @return Success; Invalid_Argument for an invalid view, a non-positive resolution or an image too wide for
   --  the layout's rowBytes; Too_Many_Colors for Indexed_8 above 256 colors (counted up to 257);
   --  Limit_Exceeded above the frame, output or allocation limits; the destination's failure.
   function Encode (Object : in out Encoder; Image : Images.Image_View) return Results.Result;
   --  Finish.
   --  @param Object Encoder in state Encoded; Finished on success.
   --  @return Success, or the destination's flush failure.
   function Finish (Object : in out Encoder) return Results.Result;
   --  Layout used.
   --  @param Object Encoder.
   --  @return The layout Encode chose; meaningful once it succeeded.
   function Layout_Used (Object : Encoder) return Layout_Kind;
   --  Bytes written.
   --  @param Object Encoder.
   --  @return Bytes written to the destination.
   function Bytes_Written (Object : Encoder) return Byte_Count;
   --  Last error.
   --  @param Object Encoder.
   --  @return The failure that put the encoder in state Failed, or No_Error.
   function Last_Error (Object : Encoder) return Errors.Error;
   --  Cancel.
   --  @param Object Encoder; in Ready or Encoded it becomes Cancelled, and later operations fail with
   --  Operation_Cancelled until Initialize; in any other state nothing changes.
   procedure Cancel (Object : in out Encoder);
   --  Finalize.
   --  @param Object Encoder; releases the destination binding. Idempotent.
   procedure Finalize (Object : in out Encoder);

private
   type Destination_Access is access all Streams.Destination'Class;

   type Encoder is limited record
      Current_State : aliased Encoder_State := Created;
      Output : Destination_Access := null;
      Encode_Options : Options;
      Encode_Limits : Limits.Limit_Set := Limits.Default_Limits;
      Layout : Layout_Kind := Auto;
      Written : Byte_Count := 0;
      First_Error : aliased Errors.Error := Errors.Make (Errors.No_Error);
   end record;
end Pictlib.Encoding;
