with Pictlib.Errors;
with Pictlib.Images;
with Pictlib.Limits;
with Pictlib.Pictures;
with Pictlib.Results;

--  The failures several units report, each built in one place: a crossed limit, a malformed opcode, a failure
--  within a row, and the frame size limits the decoder and the encoder share.
package Pictlib.Internal.Failures is
   pragma Preelaborate;

   --  Context of.
   --  @param Event An opcode.
   --  @return A diagnostic context naming it: its offset, opcode and ordinal.
   function Context_Of (Event : Pictures.Opcode_Event) return Errors.Diagnostic_Context is
     ((Source => Event.Offset, Op => Event.Op, Has_Opcode => True, Ordinal => Event.Ordinal, others => <>));

   --  Over limit.
   --  @param Limit The budget crossed.
   --  @param Expected The budget.
   --  @param Actual The amount asked for.
   --  @param Source Source offset, when the input has one.
   --  @param Destination Destination offset, when the output has one.
   --  @return A Limit_Exceeded failure.
   function Over_Limit
     (Limit : Limit_Kind;
      Expected, Actual : Byte_Count;
      Source : Source_Offset := 0;
      Destination : Destination_Offset := 0) return Results.Result is
     (Results.Failure
        (Errors.Make
           (Errors.Limit_Exceeded,
            (Source => Source, Destination => Destination, Expected => Expected, Actual => Actual, Limit => Limit,
             others => <>))));

   --  Over limit, in a context: a crossed limit the context names further, an opcode or an underlying code.
   --  @param Context The context the failure carries besides the limit.
   --  @param Limit The budget crossed.
   --  @param Expected The budget.
   --  @param Actual The amount asked for.
   --  @return A Limit_Exceeded failure.
   function Over_Limit
     (Context : Errors.Diagnostic_Context;
      Limit : Limit_Kind;
      Expected, Actual : Byte_Count) return Results.Result is
     (Results.Failure
        (Errors.Make
           (Errors.Limit_Exceeded, (Context with delta Limit => Limit, Expected => Expected, Actual => Actual))));

   --  Invalid view: a view of the right size that is not valid, reported as the least a valid view of its size and
   --  format holds against what it holds.
   --  @param Descriptor The view's descriptor.
   --  @return An Invalid_Argument failure.
   function Invalid_View (Descriptor : Images.Image_Descriptor) return Results.Result is
     (Results.Failure
        (Errors.Make
           (Errors.Invalid_Argument,
            (Expected =>
               Images.Minimum_Row_Bytes (Descriptor.Width, Descriptor.Format) * Byte_Count (Descriptor.Height),
             Actual => Descriptor.Accessible_Bytes,
             others => <>))));

   --  In opcode: a failure of an opcode's data.
   --  @param Event The opcode.
   --  @param Code Error code.
   --  @param Expected Expected count or value, for the diagnostic context.
   --  @param Actual Actual count or value, for the diagnostic context.
   --  @return The failure, naming the opcode's offset, opcode and ordinal.
   function In_Opcode
     (Event : Pictures.Opcode_Event;
      Code : Errors.Error_Code;
      Expected, Actual : Byte_Count := 0) return Results.Result is
     (Results.Failure (Errors.Make (Code, (Context_Of (Event) with delta Expected => Expected, Actual => Actual))));

   --  At row.
   --  @param Outcome A result.
   --  @param Row The pixel row being read, from 0.
   --  @return Outcome; a failure naming no row names Row.
   function At_Row (Outcome : Results.Result; Row : Natural) return Results.Result is
     (if Results.Succeeded (Outcome) or else Outcome.First_Error.Context.Has_Row then Outcome
      else Results.Failure
             ((Outcome.First_Error with delta
                 Context => (Outcome.First_Error.Context with delta Row => Row_Index (Row), Has_Row => True))));

   --  Check frame size.
   --  @param Width A picture's width.
   --  @param Height Its height.
   --  @param Budget Limits whose frame width and height apply.
   --  @param Source Source offset, when the input has one.
   --  @return Success, or Limit_Exceeded naming the frame width or height limit crossed.
   function Check_Frame_Size
     (Width, Height : Natural;
      Budget : Limits.Limit_Set;
      Source : Source_Offset := 0) return Results.Result is
     (if Width > Natural (Budget.Max_Frame_Width)
      then Over_Limit (Frame_Width_Limit, Byte_Count (Budget.Max_Frame_Width), Byte_Count (Width), Source)
      elsif Height > Natural (Budget.Max_Frame_Height)
      then Over_Limit (Frame_Height_Limit, Byte_Count (Budget.Max_Frame_Height), Byte_Count (Height), Source)
      else Results.Success);
end Pictlib.Internal.Failures;
