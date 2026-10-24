with Pictlib;
with Pictlib.Capabilities;
with Pictlib.Decoding;
with Pictlib.Errors;
with Pictlib.Geometry;
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
end Pictlib_API_Consumer;
