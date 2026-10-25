with Pictlib.Errors;
with Pictlib.Streams;

--  The one judgement of a source's reply, shared by the exact transfers and the picture stream.
package Pictlib.Internal.Replies is
   pragma Preelaborate;

   --  Judged.
   --  @param Step The source's reply to a request.
   --  @param Requested The bytes asked for.
   --  @param Where The source offset the request was made at.
   --  @return The source's own failure; Internal_Invariant_Failed when it claims more than it was asked for, since
   --  offsets could no longer be trusted; Source_Zero_Progress when it delivers nothing short of the end;
   --  No_Error otherwise, a reply of nothing at the end included.
   function Judged (Step : Streams.Source_Result; Requested : Byte_Count; Where : Source_Offset)
     return Errors.Error;

   --  Judged write.
   --  @param Step The destination's reply to a write.
   --  @param Requested The bytes given it.
   --  @param Where The destination offset the write was made at.
   --  @return The destination's own failure; Internal_Invariant_Failed when it claims more than it was given;
   --  Destination_Zero_Progress when it takes nothing of a write; No_Error otherwise.
   function Judged_Write (Step : Streams.Destination_Result; Requested : Byte_Count; Where : Destination_Offset)
     return Errors.Error;
end Pictlib.Internal.Replies;
