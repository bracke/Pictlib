with Pictlib;
with Pictlib.Capabilities;
with Pictlib.Errors;
with Pictlib.Limits;
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
end Pictlib_API_Consumer;
