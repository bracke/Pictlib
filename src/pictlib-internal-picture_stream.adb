with Pictlib.Errors;
with Pictlib.Internal.Checked_Arithmetic;
with Pictlib.Internal.Failures;
with Pictlib.Internal.Replies;

package body Pictlib.Internal.Picture_Stream is
   procedure Bind (Object : in out Reader; Input : not null access Streams.Source'Class; Max_Bytes : Byte_Count) is
      --  Caller code, which may raise: asked before anything changes.
      Base : constant Source_Offset := Input.Offset;
   begin
      Object.Input := Input.all'Unchecked_Access;
      Object.First := 1;
      Object.Last := 0;
      Object.Input_Ended := False;
      Object.Base := Base;
      Object.Consumed := 0;
      Object.Picture_Origin := 0;
      Object.Max_Bytes := Max_Bytes;
      Object.Bound := Object.Bound + 1;
   end Bind;

   procedure Unbind (Object : in out Reader) is
   begin
      Object.Input := null;
      Object.First := 1;
      Object.Last := 0;
      Object.Input_Ended := False;
      Object.Consumed := 0;
      Object.Picture_Origin := 0;
      Object.Bound := Object.Bound + 1;
   end Unbind;

   procedure Stop (Object : in out Reader) is
   begin
      Object.Input := null;
      Object.Bound := Object.Bound + 1;
   end Stop;

   function Buffered (Object : Reader) return Natural is (Object.Last - Object.First + 1);

   --  The reader was rebound, unbound or stopped while its source ran, by caller code the source called: what the
   --  source delivered belongs to no picture this reader reads, and is neither kept nor counted.
   Rebound_Reply : constant Streams.Source_Result :=
     (Error => Errors.Make (Errors.Invalid_State), Count => 0, End_Of_Input => False);

   --  The reader is bound to no source.
   Unbound_Reply : constant Streams.Source_Result :=
     (Error => Errors.Make (Errors.Source_Read_Failed), Count => 0, End_Of_Input => False);

   function Lookahead_Length (Object : Reader) return Natural is (Buffered (Object));

   function Input_Ended (Object : Reader) return Boolean is (Object.Input_Ended);

   function Lookahead_At (Object : Reader; Index : Positive) return Byte is
     (Object.Buffer (Object.First + Index - 1));

   --  The source offset Ahead bytes past what the reader consumed, saturating: a source may report any offset.
   function At_Offset (Object : Reader; Ahead : Natural := 0) return Source_Offset is
     (if Object.Base > Source_Offset'Last - Source_Offset (Object.Consumed) - Source_Offset (Ahead)
      then Source_Offset'Last
      else Object.Base + Source_Offset (Object.Consumed) + Source_Offset (Ahead));

   --  The budget is spent: the next byte would be one past it.
   function Over_Budget (Object : Reader) return Errors.Error is
     (Failures.Over_Limit
        (Picture_Byte_Limit, Object.Max_Bytes, Checked_Arithmetic.Saturating_Add (Object.Consumed, 1),
         At_Offset (Object))
        .First_Error);

   function Remaining_Budget (Object : Reader) return Byte_Count is
     (if Object.Consumed >= Object.Max_Bytes then 0 else Object.Max_Bytes - Object.Consumed);

   --  Count what the source delivered for a request of Requested bytes, once it is judged sound.
   function Advance
     (Object : in out Reader;
      Step : Streams.Source_Result;
      Requested : Byte_Count) return Streams.Source_Result
   is
      Failure : constant Errors.Error :=
        Replies.Judged (Step, Requested, At_Offset (Object));
   begin
      if Errors.Is_Fatal (Failure) then
         return (Error => Failure, Count => 0, End_Of_Input => False);
      end if;
      Object.Consumed := Object.Consumed + Step.Count;
      Object.Input_Ended := Step.End_Of_Input;
      return Step;
   end Advance;

   --  What the source replied to a request of Requested bytes made while the reader was in generation Before:
   --  refused when the source's caller code rebound the reader, otherwise counted once judged sound.
   function Delegated
     (Object : in out Reader;
      Before : Generation;
      Step : Streams.Source_Result;
      Requested : Byte_Count) return Streams.Source_Result
   is (if Object.Bound /= Before then Rebound_Reply else Advance (Object, Step, Requested));

   --  Wanted, cut to the picture budget left: what the source is asked for.
   function Within_Budget (Object : Reader; Wanted : Byte_Count) return Byte_Count is
     (Byte_Count'Min (Wanted, Remaining_Budget (Object)));

   function Fill_Lookahead (Object : in out Reader; Count : Positive) return Results.Result is
      --  Never buffer beyond the budget: those bytes could not be delivered.
      Wanted : constant Natural := Natural (Within_Budget (Object, Byte_Count (Count)));
   begin
      if Object.Input = null then
         return Results.Failure (Unbound_Reply.Error);
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
            Before : constant Generation := Object.Bound;
            Step : constant Streams.Source_Result := Object.Input.Read (Object.Buffer (Object.Last + 1 .. Wanted));
            --  Buffered bytes are not consumed yet, so the reply is judged where the buffer ends.
            Failure : constant Errors.Error :=
              Replies.Judged (Step, Byte_Count (Wanted - Object.Last),
                      At_Offset (Object, Buffered (Object)));
         begin
            if Object.Bound /= Before then
               return Results.Failure (Rebound_Reply.Error);
            elsif Errors.Is_Fatal (Failure) then
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

   --  What Read and Skip answer without asking the source, for Wanted bytes: nothing to read from, nothing wanted,
   --  the input ended or the budget spent. False when the look-ahead or the source must give them.
   function Answered (Object : Reader; Wanted : Byte_Count; Reply : out Streams.Source_Result) return Boolean is
   begin
      Reply := (Error => Errors.Make (Errors.No_Error), Count => 0, End_Of_Input => False);
      if Object.Input = null then
         Reply := Unbound_Reply;
      elsif Wanted = 0 then
         null;
      elsif Buffered (Object) = 0 and then Object.Input_Ended then
         Reply.End_Of_Input := True;
      elsif Remaining_Budget (Object) = 0 then
         Reply.Error := Over_Budget (Object);
      else
         return False;
      end if;
      return True;
   end Answered;

   --  Up to Wanted bytes of a look-ahead that holds some, consumed.
   function Take_Buffered (Object : in out Reader; Wanted : Byte_Count) return Streams.Source_Result is
      Count : constant Natural :=
        (if Wanted < Byte_Count (Buffered (Object)) then Natural (Wanted) else Buffered (Object));
   begin
      Object.First := Object.First + Count;
      Object.Consumed := Object.Consumed + Byte_Count (Count);
      return
        (Error => Errors.Make (Errors.No_Error),
         Count => Byte_Count (Count),
         End_Of_Input => Buffered (Object) = 0 and then Object.Input_Ended);
   end Take_Buffered;

   --  Only the bytes delivered are defined: clearing the rest on every call would make a caller that asks again
   --  for what is left, as Read_Exact does, clear the same bytes over and over.
   overriding function Read (Object : in out Reader; Buffer : out Streams.Byte_Array) return Streams.Source_Result is
      Reply : Streams.Source_Result;
   begin
      if Answered (Object, Byte_Count (Buffer'Length), Reply) then
         return Reply;
      elsif Buffered (Object) > 0 then
         declare
            Count : constant Natural := Natural'Min (Buffer'Length, Buffered (Object));
         begin
            Buffer (Buffer'First .. Buffer'First + Count - 1) :=
              Object.Buffer (Object.First .. Object.First + Count - 1);
            return Take_Buffered (Object, Byte_Count (Count));
         end;
      end if;

      declare
         Allowed : constant Natural := Natural (Within_Budget (Object, Byte_Count (Buffer'Length)));
         Before : constant Generation := Object.Bound;
         Step : constant Streams.Source_Result :=
           Object.Input.Read (Buffer (Buffer'First .. Buffer'First + Allowed - 1));
      begin
         return Delegated (Object, Before, Step, Byte_Count (Allowed));
      end;
   end Read;

   function Probe_Past_End (Object : in out Reader) return Streams.Source_Result is
      Probe : Streams.Byte_Array (1 .. 1);
   begin
      if Object.Input = null then
         return Unbound_Reply;
      elsif Buffered (Object) > 0 then
         return Take_Buffered (Object, 1);
      elsif Object.Input_Ended then
         return (Error => Errors.Make (Errors.No_Error), Count => 0, End_Of_Input => True);
      end if;
      declare
         Before : constant Generation := Object.Bound;
         Step : constant Streams.Source_Result := Object.Input.Read (Probe);
      begin
         return Delegated (Object, Before, Step, 1);
      end;
   end Probe_Past_End;

   overriding function Offset (Object : Reader) return Source_Offset is
     (At_Offset (Object));

   overriding function Skip (Object : in out Reader; Count : Byte_Count) return Streams.Source_Result is
      Reply : Streams.Source_Result;
   begin
      if Answered (Object, Count, Reply) then
         return Reply;
      elsif Buffered (Object) > 0 then
         return Take_Buffered (Object, Count);
      end if;

      declare
         Allowed : constant Byte_Count := Within_Budget (Object, Count);
         Before : constant Generation := Object.Bound;
         Step : constant Streams.Source_Result := Object.Input.Skip (Allowed);
      begin
         return Delegated (Object, Before, Step, Allowed);
      end;
   end Skip;
end Pictlib.Internal.Picture_Stream;
