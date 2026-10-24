with Pictlib.Errors;

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

   function Lookahead_At (Object : Reader; Index : Positive) return Byte is
     (Object.Buffer (Object.First + Index - 1));

   function Over_Budget (Object : Reader) return Errors.Error is
     (Errors.Make
        (Errors.Limit_Exceeded,
         (Source => Object.Base + Source_Offset (Object.Consumed),
          Expected => Object.Max_Bytes,
          Limit => Picture_Byte_Limit,
          others => <>)));

   --  Bytes the reader may still deliver.
   function Remaining_Budget (Object : Reader) return Byte_Count is
     (if Object.Consumed >= Object.Max_Bytes then 0 else Object.Max_Bytes - Object.Consumed);

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
         begin
            if Errors.Is_Fatal (Step.Error) then
               return Results.Failure (Step.Error);
            elsif Step.Count > Byte_Count (Wanted - Object.Last) then
               return Results.Failure (Errors.Internal_Invariant_Failed);
            elsif Step.Count = 0 and then not Step.End_Of_Input then
               return Results.Failure
                 (Errors.Make (Errors.Source_Zero_Progress, (Source => Object.Input.Offset, others => <>)));
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
         if not Errors.Is_Fatal (Step.Error) and then Step.Count <= Byte_Count (Allowed) then
            Object.Consumed := Object.Consumed + Step.Count;
            Object.Input_Ended := Step.End_Of_Input;
         end if;
         return Step;
      end;
   end Read;

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
         Step : constant Streams.Source_Result :=
           Object.Input.Skip (Byte_Count'Min (Count, Remaining_Budget (Object)));
      begin
         if not Errors.Is_Fatal (Step.Error) and then Step.Count <= Count then
            Object.Consumed := Object.Consumed + Step.Count;
            Object.Input_Ended := Step.End_Of_Input;
         end if;
         return Step;
      end;
   end Skip;
end Pictlib.Internal.Picture_Stream;
