with Pictlib.Internal.Replies;

package body Pictlib.Streams is
   function Read_Exact (Object : in out Source'Class; Buffer : out Byte_Array) return Results.Result is
      Completed : Natural := 0;
   begin
      while Completed < Buffer'Length loop
         declare
            Step : constant Source_Result :=
              Object.Read (Buffer (Buffer'First + Completed .. Buffer'Last));
            Failure : constant Errors.Error :=
              Internal.Replies.Judged (Step, Byte_Count (Buffer'Length - Completed), Object.Offset);
         begin
            if Errors.Is_Fatal (Failure) then
               return Results.Failure (Failure);
            elsif Step.Count = 0 then
               --  Nothing, at the end of the input.
               return Results.Failure
                 (Errors.Make
                    (Errors.Source_Unexpected_End,
                     (Source => Object.Offset,
                      Expected => Byte_Count (Buffer'Length),
                      Actual => Byte_Count (Completed),
                      others => <>)));
            end if;
            Completed := Completed + Natural (Step.Count);
         end;
      end loop;
      return Results.Success;
   end Read_Exact;

   function Skip_Exact (Object : in out Source'Class; Count : Byte_Count) return Results.Result is
      Completed : Byte_Count := 0;
   begin
      while Completed < Count loop
         declare
            Step : constant Source_Result := Object.Skip (Count - Completed);
            Failure : constant Errors.Error := Internal.Replies.Judged (Step, Count - Completed, Object.Offset);
         begin
            if Errors.Is_Fatal (Failure) then
               return Results.Failure (Failure);
            elsif Step.Count = 0 then
               --  Nothing, at the end of the input.
               return Results.Failure
                 (Errors.Make
                    (Errors.Source_Unexpected_End,
                     (Source => Object.Offset, Expected => Count, Actual => Completed, others => <>)));
            end if;
            Completed := Completed + Step.Count;
         end;
      end loop;
      return Results.Success;
   end Skip_Exact;

   function Write_All (Object : in out Destination'Class; Buffer : Byte_Array) return Results.Result is
      Completed : Natural := 0;
   begin
      while Completed < Buffer'Length loop
         declare
            Step : constant Destination_Result :=
              Object.Write (Buffer (Buffer'First + Completed .. Buffer'Last));
            Failure : constant Errors.Error :=
              Internal.Replies.Judged_Write (Step, Byte_Count (Buffer'Length - Completed), Object.Offset);
         begin
            if Errors.Is_Fatal (Failure) then
               return Results.Failure (Failure);
            end if;
            Completed := Completed + Natural (Step.Count);
         end;
      end loop;
      return Results.Success;
   end Write_All;

   function Transfer_Cap (Value : Byte_Count) return Natural is
   begin
      if Value > Byte_Count (Natural'Last) then
         return Natural'Last;
      else
         return Natural (Value);
      end if;
   end Transfer_Cap;

   procedure Open
     (Object : in out Memory_Source;
      Storage : not null Const_Byte_Array_Access;
      Max_Transfer : Byte_Count := Byte_Count'Last)
   is
   begin
      Object.Storage := Storage;
      Object.Position := 0;
      Object.Max_Transfer := Max_Transfer;
   end Open;

   overriding function Read (Object : in out Memory_Source; Buffer : out Byte_Array) return Source_Result is
      Available : Natural;
      To_Copy : Natural;
   begin
      if Object.Storage = null then
         return (Error => Errors.Make (Errors.Source_Read_Failed), Count => 0, End_Of_Input => False);
      end if;

      Available := Object.Storage'Length - Object.Position;
      To_Copy := Natural'Min (Natural'Min (Buffer'Length, Available), Transfer_Cap (Object.Max_Transfer));

      if To_Copy > 0 then
         for I in 0 .. To_Copy - 1 loop
            Buffer (Buffer'First + I) := Object.Storage (Object.Storage'First + Object.Position + I);
         end loop;
      end if;

      Object.Position := Object.Position + To_Copy;
      return
        (Error => Errors.Make (Errors.No_Error),
         Count => Byte_Count (To_Copy),
         End_Of_Input => Object.Position = Object.Storage'Length);
   end Read;

   overriding function Offset (Object : Memory_Source) return Source_Offset is
   begin
      return Source_Offset (Object.Position);
   end Offset;

   overriding function Skip (Object : in out Memory_Source; Count : Byte_Count) return Source_Result is
      Available : Natural;
      To_Skip : Natural;
   begin
      if Object.Storage = null then
         return (Error => Errors.Make (Errors.Source_Read_Failed), Count => 0, End_Of_Input => False);
      end if;

      Available := Object.Storage'Length - Object.Position;
      To_Skip := Natural'Min (Natural'Min (Available, Transfer_Cap (Count)), Transfer_Cap (Object.Max_Transfer));
      Object.Position := Object.Position + To_Skip;
      return
        (Error => Errors.Make (Errors.No_Error),
         Count => Byte_Count (To_Skip),
         End_Of_Input => Object.Position = Object.Storage'Length);
   end Skip;

   procedure Open
     (Object : in out Fixed_Buffer_Destination;
      Storage : not null Byte_Array_Access;
      Max_Transfer : Byte_Count := Byte_Count'Last)
   is
   begin
      Object.Storage := Storage;
      Object.Position := 0;
      Object.Max_Transfer := Max_Transfer;
   end Open;

   overriding function Write
     (Object : in out Fixed_Buffer_Destination; Buffer : Byte_Array) return Destination_Result
   is
      Available : Natural;
      To_Copy : Natural;
      --  Where the write starts, for a full buffer's report.
      Start : constant Natural := Object.Position;
   begin
      if Object.Storage = null then
         return (Error => Errors.Make (Errors.Destination_Write_Failed), Count => 0);
      end if;

      Available := Object.Storage'Length - Object.Position;
      To_Copy := Natural'Min (Natural'Min (Buffer'Length, Available), Transfer_Cap (Object.Max_Transfer));

      if To_Copy > 0 then
         for I in 0 .. To_Copy - 1 loop
            Object.Storage (Object.Storage'First + Object.Position + I) := Buffer (Buffer'First + I);
         end loop;
      end if;
      Object.Position := Object.Position + To_Copy;

      if To_Copy < Buffer'Length and then To_Copy = Available then
         return
           --  The storage holds fewer bytes than the write needs: its length, against where the write would end.
           (Error => Errors.Make
              (Errors.Destination_Write_Failed,
               (Destination => Destination_Offset (Object.Position),
                Expected => Byte_Count (Object.Storage'Length),
                Actual => Byte_Count (Start) + Byte_Count (Buffer'Length),
                others => <>)),
            Count => Byte_Count (To_Copy));
      end if;

      return (Error => Errors.Make (Errors.No_Error), Count => Byte_Count (To_Copy));
   end Write;

   overriding function Offset (Object : Fixed_Buffer_Destination) return Destination_Offset is
   begin
      return Destination_Offset (Object.Position);
   end Offset;

   overriding function Flush (Object : in out Fixed_Buffer_Destination) return Errors.Error is
      pragma Unreferenced (Object);
   begin
      return Errors.Make (Errors.No_Error);
   end Flush;
end Pictlib.Streams;
