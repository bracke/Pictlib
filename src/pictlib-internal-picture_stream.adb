with Pictlib.Errors;
with Pictlib.Internal.Failures;

package body Pictlib.Internal.Picture_Stream is
   procedure Bind (Object : in out Reader; Input : not null access Streams.Source'Class; Max_Bytes : Byte_Count) is
   begin
      Object.Input := Input.all'Unchecked_Access;
      Object.First := 1;
      Object.Last := 0;
      Object.Input_Ended := False;
      Object.Base := Input.Offset;
      Object.Consumed := 0;
      Object.Picture_Origin := 0;
      Object.Max_Bytes := Max_Bytes;
   end Bind;

   procedure Unbind (Object : in out Reader) is
   begin
      Object.Input := null;
      Object.First := 1;
      Object.Last := 0;
      Object.Input_Ended := False;
      Object.Consumed := 0;
      Object.Picture_Origin := 0;
   end Unbind;

   function Buffered (Object : Reader) return Natural is (Object.Last - Object.First + 1);

   function Lookahead_Length (Object : Reader) return Natural is (Buffered (Object));

   function Input_Ended (Object : Reader) return Boolean is (Object.Input_Ended);

   function Lookahead_At (Object : Reader; Index : Positive) return Byte is
     (Object.Buffer (Object.First + Index - 1));

   --  The budget is spent: the next byte would be one past it.
   function Over_Budget (Object : Reader) return Errors.Error is
     (Failures.Over_Limit
        (Picture_Byte_Limit, Object.Max_Bytes, Object.Consumed + 1, Object.Base + Source_Offset (Object.Consumed))
        .First_Error);

   --  Bytes the reader may still deliver.
   function Remaining_Budget (Object : Reader) return Byte_Count is
     (if Object.Consumed >= Object.Max_Bytes then 0 else Object.Max_Bytes - Object.Consumed);

   --  The one judgement of a source's reply to a request of Requested bytes made at At_Offset: its own failure;
   --  Internal_Invariant_Failed when it claims more than it was asked for, since the reader's offsets could no
   --  longer be trusted; Source_Zero_Progress when it delivers nothing short of the end.
   function Judged (Step : Streams.Source_Result; Requested : Byte_Count; At_Offset : Source_Offset)
     return Errors.Error is
   begin
      if Errors.Is_Fatal (Step.Error) then
         return Step.Error;
      elsif Step.Count > Requested then
         return Errors.Make
           (Errors.Internal_Invariant_Failed,
            (Source => At_Offset, Expected => Requested, Actual => Step.Count, others => <>));
      elsif Step.Count = 0 and then Requested > 0 and then not Step.End_Of_Input then
         return Errors.Make (Errors.Source_Zero_Progress, (Source => At_Offset, others => <>));
      end if;
      return Errors.Make (Errors.No_Error);
   end Judged;

   --  Count what the source delivered for a request of Requested bytes, once it is judged sound.
   function Advance
     (Object : in out Reader;
      Step : Streams.Source_Result;
      Requested : Byte_Count) return Streams.Source_Result
   is
      Failure : constant Errors.Error :=
        Judged (Step, Requested, Object.Base + Source_Offset (Object.Consumed));
   begin
      if Errors.Is_Fatal (Failure) then
         return (Error => Failure, Count => 0, End_Of_Input => False);
      end if;
      Object.Consumed := Object.Consumed + Step.Count;
      Object.Input_Ended := Step.End_Of_Input;
      return Step;
   end Advance;

   function Fill_Lookahead (Object : in out Reader; Count : Positive) return Results.Result is
      --  Never buffer beyond the budget: those bytes could not be delivered.
      Wanted : constant Natural :=
        (if Remaining_Budget (Object) < Byte_Count (Count) then Natural (Remaining_Budget (Object)) else Count);
   begin
      if Object.Input = null then
         return Results.Failure (Errors.Source_Read_Failed);
      end if;
      --  Move what is buffered to the front so Count bytes fit.
      if Object.First > 1 then
         declare
            Held : constant Natural := Buffered (Object);
         begin
            Object.Buffer (1 .. Held) := Object.Buffer (Object.First .. Object.Last);
            Object.First := 1;
            Object.Last := Held;
         end;
      end if;
      while Object.Last < Wanted and then not Object.Input_Ended loop
         declare
            Step : constant Streams.Source_Result := Object.Input.Read (Object.Buffer (Object.Last + 1 .. Wanted));
            --  Buffered bytes are not consumed yet, so the reply is judged where the buffer ends.
            Failure : constant Errors.Error :=
              Judged (Step, Byte_Count (Wanted - Object.Last),
                      Object.Base + Source_Offset (Object.Consumed) + Source_Offset (Buffered (Object)));
         begin
            if Errors.Is_Fatal (Failure) then
               return Results.Failure (Failure);
            end if;
            Object.Last := Object.Last + Natural (Step.Count);
            Object.Input_Ended := Step.End_Of_Input;
         end;
      end loop;
      return Results.Success;
   end Fill_Lookahead;

   procedure Start_Picture (Object : in out Reader) is
   begin
      Object.Picture_Origin := Object.Consumed;
   end Start_Picture;

   function Picture_Offset (Object : Reader) return Byte_Count is (Object.Consumed - Object.Picture_Origin);

   overriding function Read (Object : in out Reader; Buffer : out Streams.Byte_Array) return Streams.Source_Result is
   begin
      Buffer := [others => 0];
      if Object.Input = null then
         return (Error => Errors.Make (Errors.Source_Read_Failed), Count => 0, End_Of_Input => False);
      elsif Buffer'Length = 0 then
         return (Error => Errors.Make (Errors.No_Error), Count => 0, End_Of_Input => False);
      end if;

      if Buffered (Object) = 0 and then Object.Input_Ended then
         return (Error => Errors.Make (Errors.No_Error), Count => 0, End_Of_Input => True);
      elsif Remaining_Budget (Object) = 0 then
         return (Error => Over_Budget (Object), Count => 0, End_Of_Input => False);
      elsif Buffered (Object) > 0 then
         declare
            Count : constant Natural := Natural'Min (Buffer'Length, Buffered (Object));
         begin
            Buffer (Buffer'First .. Buffer'First + Count - 1) :=
              Object.Buffer (Object.First .. Object.First + Count - 1);
            Object.First := Object.First + Count;
            Object.Consumed := Object.Consumed + Byte_Count (Count);
            return
              (Error => Errors.Make (Errors.No_Error),
               Count => Byte_Count (Count),
               End_Of_Input => Buffered (Object) = 0 and then Object.Input_Ended);
         end;
      end if;

      declare
         Allowed : constant Natural :=
           (if Remaining_Budget (Object) < Byte_Count (Buffer'Length) then Natural (Remaining_Budget (Object))
            else Buffer'Length);
         Step : constant Streams.Source_Result :=
           Object.Input.Read (Buffer (Buffer'First .. Buffer'First + Allowed - 1));
      begin
         return Advance (Object, Step, Byte_Count (Allowed));
      end;
   end Read;

   function Probe_Past_End (Object : in out Reader) return Streams.Source_Result is
      Probe : Streams.Byte_Array (1 .. 1);
   begin
      if Object.Input = null then
         return (Error => Errors.Make (Errors.Source_Read_Failed), Count => 0, End_Of_Input => False);
      elsif Buffered (Object) > 0 then
         Object.First := Object.First + 1;
         Object.Consumed := Object.Consumed + 1;
         return (Error => Errors.Make (Errors.No_Error), Count => 1, End_Of_Input => False);
      elsif Object.Input_Ended then
         return (Error => Errors.Make (Errors.No_Error), Count => 0, End_Of_Input => True);
      end if;
      declare
         Step : constant Streams.Source_Result := Object.Input.Read (Probe);
      begin
         return Advance (Object, Step, 1);
      end;
   end Probe_Past_End;

   overriding function Offset (Object : Reader) return Source_Offset is
     (Object.Base + Source_Offset (Object.Consumed));

   overriding function Skip (Object : in out Reader; Count : Byte_Count) return Streams.Source_Result is
   begin
      if Object.Input = null then
         return (Error => Errors.Make (Errors.Source_Read_Failed), Count => 0, End_Of_Input => False);
      elsif Count = 0 then
         return (Error => Errors.Make (Errors.No_Error), Count => 0, End_Of_Input => False);
      end if;

      if Buffered (Object) = 0 and then Object.Input_Ended then
         return (Error => Errors.Make (Errors.No_Error), Count => 0, End_Of_Input => True);
      elsif Remaining_Budget (Object) = 0 then
         return (Error => Over_Budget (Object), Count => 0, End_Of_Input => False);
      elsif Buffered (Object) > 0 then
         declare
            Taken : constant Natural :=
              (if Count < Byte_Count (Buffered (Object)) then Natural (Count) else Buffered (Object));
         begin
            Object.First := Object.First + Taken;
            Object.Consumed := Object.Consumed + Byte_Count (Taken);
            return
              (Error => Errors.Make (Errors.No_Error),
               Count => Byte_Count (Taken),
               End_Of_Input => Buffered (Object) = 0 and then Object.Input_Ended);
         end;
      end if;

      declare
         Allowed : constant Byte_Count := Byte_Count'Min (Count, Remaining_Budget (Object));
         Step : constant Streams.Source_Result := Object.Input.Skip (Allowed);
      begin
         return Advance (Object, Step, Allowed);
      end;
   end Skip;
end Pictlib.Internal.Picture_Stream;
