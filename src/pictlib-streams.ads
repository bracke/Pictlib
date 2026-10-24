with Pictlib.Errors;
with Pictlib.Results;

package Pictlib.Streams is
   pragma Preelaborate;

   type Byte_Array is array (Positive range <>) of Byte;
   type Byte_Array_Access is access all Byte_Array;
   type Const_Byte_Array_Access is access constant Byte_Array;

   type Source_Result is record
      Error : Errors.Error := Errors.Make (Errors.No_Error);
      Count : Byte_Count := 0;
      End_Of_Input : Boolean := False;
   end record;

   type Destination_Result is record
      Error : Errors.Error := Errors.Make (Errors.No_Error);
      Count : Byte_Count := 0;
   end record;

   type Source is limited interface;
   --  Read up to Buffer'Length bytes; a short count is legal.
   --  @param Object Source to read from.
   --  @param Buffer Receives the bytes read, from Buffer'First.
   --  @return Bytes transferred, end-of-input flag and any failure.
   function Read (Object : in out Source; Buffer : out Byte_Array) return Source_Result is abstract;
   --  Offset.
   --  @param Object Source to inspect.
   --  @return Bytes consumed so far.
   function Offset (Object : Source) return Source_Offset is abstract;
   --  Skip up to Count bytes; a short count is legal.
   --  @param Object Source to advance.
   --  @param Count Maximum bytes to skip.
   --  @return Bytes skipped, end-of-input flag and any failure.
   function Skip (Object : in out Source; Count : Byte_Count) return Source_Result is abstract;

   type Destination is limited interface;
   --  Write up to Buffer'Length bytes; a short count is legal.
   --  @param Object Destination to write to.
   --  @param Buffer Bytes to write, from Buffer'First.
   --  @return Bytes transferred and any failure.
   function Write (Object : in out Destination; Buffer : Byte_Array) return Destination_Result is abstract;
   --  Offset.
   --  @param Object Destination to inspect.
   --  @return Bytes written so far.
   function Offset (Object : Destination) return Destination_Offset is abstract;
   --  Flush.
   --  @param Object Destination to flush.
   --  @return No_Error or the flush failure.
   function Flush (Object : in out Destination) return Errors.Error is abstract;

   --  These helpers complete a requested transfer across short reads/writes.
   --  They reject a successful zero-byte transfer because retrying it could hang.

   --  Read exact.
   --  @param Object Source to read from.
   --  @param Buffer Filled completely on success.
   --  @return Success, or the stream failure, unexpected end or zero progress.
   function Read_Exact (Object : in out Source'Class; Buffer : out Byte_Array) return Results.Result;
   --  Skip exact.
   --  @param Object Source to advance.
   --  @param Count Bytes to skip.
   --  @return Success, or the stream failure, unexpected end or zero progress.
   function Skip_Exact (Object : in out Source'Class; Count : Byte_Count) return Results.Result;
   --  Write all.
   --  @param Object Destination to write to.
   --  @param Buffer Bytes written completely on success.
   --  @return Success, or the stream failure or zero progress.
   function Write_All (Object : in out Destination'Class; Buffer : Byte_Array) return Results.Result;

   type Memory_Source is limited new Source with private;
   --  Open.
   --  @param Object Source to bind.
   --  @param Storage Borrowed bytes; the caller keeps them alive while Object is used.
   --  @param Max_Transfer Largest count one Read or Skip returns, for short-transfer testing.
   procedure Open
     (Object : in out Memory_Source;
      Storage : not null Const_Byte_Array_Access;
      Max_Transfer : Byte_Count := Byte_Count'Last);
   overriding function Read (Object : in out Memory_Source; Buffer : out Byte_Array) return Source_Result;
   overriding function Offset (Object : Memory_Source) return Source_Offset;
   overriding function Skip (Object : in out Memory_Source; Count : Byte_Count) return Source_Result;

   type Fixed_Buffer_Destination is limited new Destination with private;
   --  Open.
   --  @param Object Destination to bind.
   --  @param Storage Borrowed bytes; the caller keeps them alive while Object is used.
   --  @param Max_Transfer Largest count one Write accepts, for short-transfer testing.
   procedure Open
     (Object : in out Fixed_Buffer_Destination;
      Storage : not null Byte_Array_Access;
      Max_Transfer : Byte_Count := Byte_Count'Last);
   overriding function Write
     (Object : in out Fixed_Buffer_Destination; Buffer : Byte_Array) return Destination_Result;
   overriding function Offset (Object : Fixed_Buffer_Destination) return Destination_Offset;
   overriding function Flush (Object : in out Fixed_Buffer_Destination) return Errors.Error;

private
   type Memory_Source is limited new Source with record
      Storage : Const_Byte_Array_Access := null;
      Position : Natural := 0;
      Max_Transfer : Byte_Count := Byte_Count'Last;
   end record;

   type Fixed_Buffer_Destination is limited new Destination with record
      Storage : Byte_Array_Access := null;
      Position : Natural := 0;
      Max_Transfer : Byte_Count := Byte_Count'Last;
   end record;
end Pictlib.Streams;
