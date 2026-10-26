with Pictlib.Errors;
with Pictlib.Fonts;
with Pictlib.Images;
with Pictlib.Internal.Decoder_State;
with Pictlib.Limits;
with Pictlib.Metadata;
with Pictlib.Pictures;
with Pictlib.Results;
with Pictlib.Streams;

--  Forward-only PICT decoder. Initialize binds a borrowed source; Read_Header reads the container;
--  Enumerate walks the opcode stream once. Calls in the wrong state fail with Invalid_State (Operation_Cancelled
--  after Cancel) and leave the state unchanged. Reset rebinds a source for another picture.
package Pictlib.Decoding is
   type Decoder_State is
     (Created,      --  not initialized, or finalized
      Ready,        --  bound to a source
      Header_Read,  --  the container was read; the opcode stream is next
      Finished,     --  the end opcode was reached
      Stopped,      --  the visitor stopped enumeration early, or caller code raised mid-picture
      Failed,       --  a failure ended decoding; Last_Error reports it
      Cancelled);

   type Options is record
      Strictness : Strictness_Mode := Strict;
      File_Header : Header_Policy := Auto;
      Retention : Metadata.Retention_Policy;
      --  Fail (Strict) or warn when bytes follow the end opcode; otherwise they are not read.
      Require_End_Of_Input : Boolean := False;
      --  The color Render fills the view with before drawing.
      Background : Images.RGB_Color := Images.White;
      --  The TrueType fonts text renders with.
      Fonts : Pictlib.Fonts.Font_Table := Pictlib.Fonts.Empty;
   end record;

   type Visit_Action is (Continue, Stop);

   type Opcode_Visitor is limited interface;
   --  Visit.
   --  @param Object Visitor.
   --  @param Event One opcode, after its data was consumed.
   --  @return Continue, or Stop to end enumeration early.
   function Visit (Object : in out Opcode_Visitor; Event : Pictures.Opcode_Event) return Visit_Action is abstract;

   type Decoder is limited private;

   --  Initialize.
   --  @param Object Decoder; any earlier picture is discarded.
   --  @param Input Borrowed source; the caller keeps it alive until Reset, Finalize or another Initialize.
   --  @param Decode_Options Strictness, file header policy, metadata retention, whether input must end at the
   --  end opcode, the background a render starts from, and the fonts text is drawn with.
   --  @param Decode_Limits Resource budgets.
   procedure Initialize
     (Object : in out Decoder;
      Input : not null access Streams.Source'Class;
      Decode_Options : Options := (others => <>);
      Decode_Limits : Limits.Limit_Set := Limits.Default_Limits);
   --  Reset.
   --  @param Object Decoder; options and limits are kept, the earlier picture is discarded.
   --  @param Input Borrowed source for the next picture.
   procedure Reset (Object : in out Decoder; Input : not null access Streams.Source'Class);
   --  State.
   --  @param Object Decoder.
   --  @return Current state.
   function State (Object : Decoder) return Decoder_State;
   --  Read header.
   --  @param Object Decoder in state Ready; Header_Read on success; Stopped, until Reset or Initialize, when an
   --  exception from the source propagates.
   --  @return Operation result.
   function Read_Header (Object : in out Decoder) return Results.Result;
   --  Header.
   --  @param Object Decoder.
   --  @return The header; meaningful once Read_Header succeeded.
   function Header (Object : Decoder) return Pictures.Header_Info;
   --  Enumerate.
   --  @param Object Decoder in state Header_Read; Finished or Stopped on success.
   --  @param Visitor Receives every opcode in order, the version opcode and HeaderOp included. While it is called,
   --  Read_Header, Enumerate and Render on Object fail with Invalid_State; it may Cancel, Reset or Finalize
   --  Object, which ends the enumeration with what a call in the state it leaves gets. Its exceptions propagate
   --  and leave Object Stopped, if the visit left it Header_Read, until Reset or Initialize, as the source's do.
   --  @return Operation result.
   function Enumerate (Object : in out Decoder; Visitor : in out Opcode_Visitor'Class) return Results.Result;
   --  Render.
   --  @param Object Decoder in state Header_Read; Finished on success.
   --  @param Output A valid caller view exactly the size of the frame; canvas pixel (0, 0) is the frame's
   --  top-left corner. Its pixels are defined on success, and on a Partial_Picture warning.
   --  @return Success; Invalid_Argument for an invalid or wrongly sized view, or Limit_Exceeded for a view over
   --  Max_Output_Bytes, both leaving the decoder in Header_Read so another view can be given; Limit_Exceeded
   --  for a frame over Max_Canvas_Pixels, which no view can render, leaving it Failed; Unsupported_Feature
   --  (strictly) for drawing this release does not render; otherwise the first failure while drawing, a
   --  budget crossed among them.
   --  Recover_When_Safe returns success with a Partial_Picture warning when malformed data ends the picture. An
   --  exception from the source propagates and leaves Object Stopped until Reset or Initialize.
   function Render (Object : in out Decoder; Output : Images.Mutable_Image_View) return Results.Result;
   --  Last error.
   --  @param Object Decoder.
   --  @return The failure that put the decoder in state Failed, or No_Error.
   function Last_Error (Object : Decoder) return Errors.Error;

   --  Warning count.
   --  @param Object Decoder.
   --  @return Warnings recorded, at most Limits.Max_Warning_Records.
   function Warning_Count (Object : Decoder) return Natural;
   --  Warning at.
   --  @param Object Decoder.
   --  @param Index 1-based warning position.
   --  @return The warning.
   function Warning_At (Object : Decoder; Index : Positive) return Errors.Warning
     with Pre => Index <= Warning_Count (Object);

   --  Metadata count.
   --  @param Object Decoder.
   --  @return Items retained so far.
   function Metadata_Count (Object : Decoder) return Natural;
   --  Metadata item.
   --  @param Object Decoder.
   --  @param Index 1-based item position.
   --  @return Item description.
   function Metadata_Item (Object : Decoder; Index : Positive) return Metadata.Item_Info
     with Pre => Index <= Metadata_Count (Object);
   --  Copy metadata.
   --  @param Object Decoder.
   --  @param Index 1-based item position.
   --  @param Buffer Cleared whole, then receives the item data from Buffer'First.
   --  @param Count Bytes copied; 0 on failure.
   --  @return Success, or Invalid_Argument for an index out of range or a Buffer shorter than the item (expecting
   --  Buffer's length, with the item's as actual).
   function Copy_Metadata
     (Object : Decoder;
      Index : Positive;
      Buffer : out Streams.Byte_Array;
      Count : out Byte_Count) return Results.Result;

   --  Cancel.
   --  @param Object Decoder; in Ready or Header_Read it becomes Cancelled, and later operations fail with
   --  Operation_Cancelled until Reset or Initialize; in any other state nothing changes.
   procedure Cancel (Object : in out Decoder);
   --  Finalize.
   --  @param Object Decoder; releases retained metadata and the source binding. Idempotent.
   procedure Finalize (Object : in out Decoder);

private
   --  Steps on every Initialize, Reset and Finalize, so a call can tell caller code rebound the decoder under it.
   type Bind_Count is mod 2 ** 32;

   type Decoder is limited record
      Current_State : aliased Decoder_State := Created;
      --  True while Read_Header, Enumerate or Render runs caller code, a visitor or the source, which may not read
      --  the picture again under it.
      Busy : aliased Boolean := False;
      Decode_Options : Options;
      Inner : Internal.Decoder_State.State;
      First_Error : Errors.Error := Errors.Make (Errors.No_Error);
      Binds : aliased Bind_Count := 0;
   end record;
end Pictlib.Decoding;
