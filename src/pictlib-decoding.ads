with Pictlib.Errors;
with Pictlib.Fonts;
with Pictlib.Images;
with Pictlib.Internal.Container;
with Pictlib.Internal.Sessions;
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
      Stopped,      --  the visitor stopped enumeration early
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
   --  @param Decode_Options Strictness, file header policy and metadata retention.
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
   --  @param Object Decoder in state Ready; Header_Read on success.
   --  @return Operation result.
   function Read_Header (Object : in out Decoder) return Results.Result;
   --  Header.
   --  @param Object Decoder.
   --  @return The header; meaningful once Read_Header succeeded.
   function Header (Object : Decoder) return Pictures.Header_Info;
   --  Enumerate.
   --  @param Object Decoder in state Header_Read; Finished or Stopped on success.
   --  @param Visitor Receives every opcode in order, the version opcode and HeaderOp included.
   --  @return Operation result.
   function Enumerate (Object : in out Decoder; Visitor : in out Opcode_Visitor'Class) return Results.Result;
   --  Render.
   --  @param Object Decoder in state Header_Read; Finished on success.
   --  @param Output A valid caller view exactly the size of the frame; canvas pixel (0, 0) is the frame's
   --  top-left corner. Its pixels are defined on success, and on a Partial_Picture warning.
   --  @return Success; Invalid_Argument for an invalid or wrongly sized view; Limit_Exceeded for a frame over
   --  the canvas or output limits; Unsupported_Feature (strictly) for drawing this release does not render.
   --  Recover_When_Safe returns success with a Partial_Picture warning when malformed data ends the picture.
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

   --  Total decoder-owned allocation bytes admitted during this session.
   --  @param Object Decoder.
   --  @return Monotonic allocation admission for the current session.
   function Total_Allocation_Bytes (Object : Decoder) return Byte_Count;

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
   --  @param Buffer Receives the item data from Buffer'First.
   --  @param Count Bytes copied; 0 on failure.
   --  @return Success, Invalid_Argument for an index out of range, or Limit_Exceeded when Buffer is short.
   function Copy_Metadata
     (Object : Decoder;
      Index : Positive;
      Buffer : out Streams.Byte_Array;
      Count : out Byte_Count) return Results.Result;

   --  Cancel.
   --  @param Object Decoder; later operations fail with Operation_Cancelled until Reset or Initialize.
   procedure Cancel (Object : in out Decoder);
   --  Finalize.
   --  @param Object Decoder; releases retained metadata and the source binding. Idempotent.
   procedure Finalize (Object : in out Decoder);

private
   type Decoder is limited record
      Current_State : Decoder_State := Created;
      Decode_Options : Options;
      Session : Internal.Sessions.Session;
      Info : Pictures.Header_Info;
      Header_Events : Internal.Container.Header_Events;
      Header_Event_Count : Natural := 0;
      First_Error : Errors.Error := Errors.Make (Errors.No_Error);
   end record;
end Pictlib.Decoding;
