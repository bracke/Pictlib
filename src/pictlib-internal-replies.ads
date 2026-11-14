with Pictlib.Errors;
with Pictlib.Results;
with Pictlib.Streams;

--  The one judgement of a source's reply, shared by the exact transfers and the picture stream.
package Pictlib.Internal.Replies is
   pragma Preelaborate;

   --  Judged.
   --  @param Step The source's reply to a request.
   --  @param Requested The bytes asked for.
   --  @param Where The source offset a failure names: where the request was made, or where the source says it
   --  stands after replying.
   --  @return The source's own failure; Internal_Invariant_Failed when it claims more than it was asked for, since
   --  offsets could no longer be trusted; Source_Zero_Progress when it delivers nothing short of the end;
   --  No_Error otherwise, a reply of nothing at the end included.
   function Judged (Step : Streams.Source_Result; Requested : Byte_Count; Where : Source_Offset)
     return Errors.Error;

   --  Judged write.
   --  @param Step The destination's reply to a write.
   --  @param Requested The bytes given it.
   --  @param Where The destination offset a failure names: where the write was made, or where the destination
   --  says it stands after replying.
   --  @return The destination's own failure; Internal_Invariant_Failed when it claims more than it was given;
   --  Destination_Zero_Progress when it takes nothing of a write; No_Error otherwise.
   function Judged_Write (Step : Streams.Destination_Result; Requested : Byte_Count; Where : Destination_Offset)
     return Errors.Error;

   --  Sound step: whether a step of an exact transfer needs no judgement, as almost every one does.
   --  @param Step The source's reply to a request.
   --  @param Remaining The bytes the transfer still needs.
   --  @return True for no failure and some bytes, no more than asked.
   function Sound_Step (Step : Streams.Source_Result; Remaining : Byte_Count) return Boolean is
     (not Errors.Is_Fatal (Step.Error) and then Step.Count in 1 .. Remaining)
     with Inline;
   --  Step failure: what an exact transfer fails with for a step that is not sound.
   --  @param Object The source, asked its Offset for the diagnostic, as only a failure does.
   --  @param Step The source's reply.
   --  @param Total Bytes the transfer is for.
   --  @param Completed Bytes done before the step.
   --  @return The source's failure, Internal_Invariant_Failed or Source_Zero_Progress as Judged gives them, or
   --  Source_Unexpected_End for an end of input short of Total.
   function Step_Failure
     (Object : Streams.Source'Class;
      Step : Streams.Source_Result;
      Total, Completed : Byte_Count) return Results.Result
     with Pre => not Sound_Step (Step, Total - Completed);
end Pictlib.Internal.Replies;
