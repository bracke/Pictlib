package body Pictlib.Internal.Replies is
   function Judged (Step : Streams.Source_Result; Requested : Byte_Count; Where : Source_Offset)
     return Errors.Error is
   begin
      if Errors.Is_Fatal (Step.Error) then
         return Step.Error;
      elsif Step.Count > Requested then
         return Errors.Make
           (Errors.Internal_Invariant_Failed,
            (Source => Where, Expected => Requested, Actual => Step.Count, others => <>));
      elsif Step.Count = 0 and then Requested > 0 and then not Step.End_Of_Input then
         return Errors.Make (Errors.Source_Zero_Progress, (Source => Where, others => <>));
      end if;
      return Errors.Make (Errors.No_Error);
   end Judged;

   function Judged_Write (Step : Streams.Destination_Result; Requested : Byte_Count; Where : Destination_Offset)
     return Errors.Error is
   begin
      if Errors.Is_Fatal (Step.Error) then
         return Step.Error;
      elsif Step.Count > Requested then
         return Errors.Make
           (Errors.Internal_Invariant_Failed,
            (Destination => Where, Expected => Requested, Actual => Step.Count, others => <>));
      elsif Step.Count = 0 and then Requested > 0 then
         return Errors.Make (Errors.Destination_Zero_Progress, (Destination => Where, others => <>));
      end if;
      return Errors.Make (Errors.No_Error);
   end Judged_Write;

   function Step_Failure
     (Object : Streams.Source'Class;
      Step : Streams.Source_Result;
      Total, Completed : Byte_Count) return Results.Result
   is
      Where : constant Source_Offset := Object.Offset;
      Failure : constant Errors.Error := Judged (Step, Total - Completed, Where);
   begin
      if Errors.Is_Fatal (Failure) then
         return Results.Failure (Failure);
      end if;
      --  Nothing, at the end of the input.
      return Results.Failure
        (Errors.Make
           (Errors.Source_Unexpected_End, (Source => Where, Expected => Total, Actual => Completed, others => <>)));
   end Step_Failure;
end Pictlib.Internal.Replies;
