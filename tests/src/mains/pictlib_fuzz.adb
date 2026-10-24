--  Mutation fuzzing: seeds are the external and real-world fixtures and fresh encoder output; each iteration
--  mutates one seed and has pictlib enumerate it strictly and render it compatibly and recoverably under tight
--  limits. An exception escaping pictlib is a defect and fails the run. What an input may cost is bounded by the
--  limits, not the clock, so time only reports: an input taking longer than Slow_Seconds is slow, one taking
--  longer than Stuck_Seconds stuck, and both are saved under artifacts/fuzz for replay; a stuck input fails the
--  run only with --fail-stuck, for a machine whose speed is known. Arguments: [iterations] [seed]
--  [--fail-stuck]; seeds are taken in file-name order, so a pair is deterministic everywhere. With --replay
--  FILE..., each saved input is run through the same checks instead, and its time printed.
--  Runs from anywhere below the pictlib tree.
with Pictlib_Testing.Fonts;
with Pictlib_Testing.Tools;
with Ada.Calendar;
with Ada.Command_Line;
with Ada.Containers.Indefinite_Vectors;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Streams.Stream_IO;
with Ada.Text_IO;
with Interfaces;
with Pictlib;
with Pictlib.Decoding;
with Pictlib.Encoding;
with Pictlib.Errors;
with Pictlib.Fonts;
with Pictlib.Geometry;
with Pictlib.Limits;
with Pictlib.Pictures;
with Pictlib.Results;
with Pictlib.Streams;
with Pictlib_Testing.Samples;

procedure Pictlib_Fuzz is
   use type Ada.Calendar.Time;
   use type Interfaces.Unsigned_64;
   use type Pictlib.Byte;
   use type Pictlib.Byte_Count;
   use type Pictlib.Pixel_Count;
   use type Pictlib.Strictness_Mode;
   use type Pictlib.Streams.Byte_Array;

   subtype Bytes is Pictlib.Streams.Byte_Array;
   package Byte_Vectors is new Ada.Containers.Indefinite_Vectors (Positive, Bytes, Pictlib.Streams."=");

   Slow_Seconds : constant Duration := 2.0;
   Stuck_Seconds : constant Duration := 60.0;
   Artifacts : constant String := "artifacts/fuzz";

   Fail_Stuck : constant Boolean :=
     (for some Index in 1 .. Ada.Command_Line.Argument_Count => Ada.Command_Line.Argument (Index) = "--fail-stuck");
   Replay : constant Boolean :=
     Ada.Command_Line.Argument_Count >= 1 and then Ada.Command_Line.Argument (1) = "--replay";
   Iterations : constant Natural :=
     (if Ada.Command_Line.Argument_Count >= 1 and then not Replay then Natural'Value (Ada.Command_Line.Argument (1))
      else 2_000);
   State : Interfaces.Unsigned_64 :=
     (if Ada.Command_Line.Argument_Count >= 2 and then not Replay
      then Interfaces.Unsigned_64'Value (Ada.Command_Line.Argument (2))
      else 16#9E37_79B9_7F4A_7C15#);

   --  xorshift64*.
   function Random (Bound : Positive) return Natural is
   begin
      State := State xor Interfaces.Shift_Right (State, 12);
      State := State xor Interfaces.Shift_Left (State, 25);
      State := State xor Interfaces.Shift_Right (State, 27);
      return Natural ((State * 16#2545_F491_4F6C_DD1D#) mod Interfaces.Unsigned_64 (Bound));
   end Random;

   Budget : constant Pictlib.Limits.Limit_Set :=
     (Pictlib.Limits.Default_Limits with delta
        Max_Frame_Width => 1024, Max_Frame_Height => 1024, Max_Canvas_Pixels => 2 ** 20,
        Max_Drawing_Work => 2 ** 26, Max_Allocation_Bytes => 64 * 1024 * 1024,
        Max_Embedded_Image_Pixels => 2 ** 20, Max_Embedded_Image_Bytes => 4 * 1024 * 1024,
        Max_Opcodes => 100_000);
   Canvas : constant Pictlib.Streams.Byte_Array_Access := new Bytes (1 .. 4 * 1024 * 1024);

   type Null_Visitor is new Pictlib.Decoding.Opcode_Visitor with null record;
   overriding function Visit (Object : in out Null_Visitor; Event : Pictlib.Pictures.Opcode_Event)
     return Pictlib.Decoding.Visit_Action is (Pictlib.Decoding.Continue);

   Seeds : Byte_Vectors.Vector;
   --  How far inputs got: past the header, rendered completely, rendered as a partial picture.
   Headers_Read, Rendered, Partial : Natural := 0;

   package Name_Vectors is new Ada.Containers.Indefinite_Vectors (Positive, String);
   package Name_Sorting is new Name_Vectors.Generic_Sorting;

   procedure Add_Files (Directory : String) is
      use Ada.Directories;
      Search : Search_Type;
      Item : Directory_Entry_Type;
      Names : Name_Vectors.Vector;
   begin
      if not Exists (Directory) then
         return;
      end if;
      Start_Search (Search, Directory, "*");
      while More_Entries (Search) loop
         Get_Next_Entry (Search, Item);
         if Kind (Item) = Ordinary_File and then Extension (Simple_Name (Item)) in "pict" | "pct" then
            Names.Append (Full_Name (Item));
         end if;
      end loop;
      End_Search (Search);
      --  The search order depends on the file system; the seeds' order must not.
      Name_Sorting.Sort (Names);
      for Name of Names loop
         declare
            use Ada.Streams.Stream_IO;
            File : File_Type;
            Data : Bytes (1 .. Natural (Ada.Directories.Size (Name)));
         begin
            Open (File, In_File, Name);
            Bytes'Read (Stream (File), Data);
            Close (File);
            if Data'Length <= 256 * 1024 then
               Seeds.Append (Data);
            end if;
         end;
      end loop;
   end Add_Files;

   procedure Add_Encoded (Item : Pictlib_Testing.Samples.Kind; Layout : Pictlib.Encoding.Layout_Kind) is
      Source : constant Pictlib_Testing.Samples.Bytes_Access := Pictlib_Testing.Samples.Make (Item, 23, 9);
      Storage : constant Pictlib.Streams.Byte_Array_Access := new Bytes (1 .. 100_000);
      Output : aliased Pictlib.Streams.Fixed_Buffer_Destination;
      Encoder : Pictlib.Encoding.Encoder;
   begin
      Pictlib.Streams.Open (Output, Storage);
      Pictlib.Encoding.Initialize (Encoder, Output'Access, (Layout => Layout, others => <>));
      if Pictlib.Results.Succeeded
        (Pictlib.Encoding.Encode (Encoder, Pictlib_Testing.Samples.View (Source, 23, 9)))
      then
         Seeds.Append (Storage (1 .. Natural (Output.Offset)));
      end if;
   end Add_Encoded;

   function Mutate (Seed : Bytes) return Bytes is
      Data : Byte_Vectors.Vector;
   begin
      Data.Append (Seed);
      for Round in 1 .. 1 + Random (4) loop
         declare
            Current : constant Bytes := Data.Last_Element;
            Length : constant Natural := Current'Length;
         begin
            exit when Length = 0;
            declare
               At_Byte : constant Positive := Current'First + Random (Length);
               Choice : constant Natural := Random (10);
            begin
               case Choice is
                  when 0 =>  --  flip a bit
                     declare
                        Changed : Bytes := Current;
                     begin
                        Changed (At_Byte) := Changed (At_Byte) xor Pictlib.Byte (2 ** Random (8));
                        Data.Append (Changed);
                     end;
                  when 1 =>  --  a boundary byte
                     declare
                        Changed : Bytes := Current;
                        Values : constant Bytes := [0, 1, 16#7F#, 16#80#, 16#FF#];
                     begin
                        Changed (At_Byte) := Values (Values'First + Random (Values'Length));
                        Data.Append (Changed);
                     end;
                  when 2 =>  --  a boundary word
                     if At_Byte < Current'Last then
                        declare
                           Changed : Bytes := Current;
                           Words : constant array (1 .. 6) of Natural := [0, 1, 16#7FFF#, 16#8000#, 16#FFFF#, 10];
                           Value : constant Natural := Words (1 + Random (6));
                        begin
                           Changed (At_Byte) := Pictlib.Byte (Value / 256);
                           Changed (At_Byte + 1) := Pictlib.Byte (Value mod 256);
                           Data.Append (Changed);
                        end;
                     end if;
                  when 3 =>  --  truncate
                     Data.Append (Bytes'(Current (Current'First .. At_Byte - 1)));
                  when 4 =>  --  delete a chunk
                     declare
                        Last : constant Natural := Natural'Min (Current'Last, At_Byte + Random (64));
                     begin
                        Data.Append
                          (Bytes'(Current (Current'First .. At_Byte - 1) & Current (Last + 1 .. Current'Last)));
                     end;
                  when 5 =>  --  duplicate a chunk
                     declare
                        Last : constant Natural := Natural'Min (Current'Last, At_Byte + Random (64));
                     begin
                        Data.Append
                          (Bytes'(Current (Current'First .. Last) & Current (At_Byte .. Last)
                                  & Current (Last + 1 .. Current'Last)));
                     end;
                  when 6 =>  --  insert random bytes
                     declare
                        Inserted : Bytes (1 .. 1 + Random (16));
                     begin
                        for Item of Inserted loop
                           Item := Pictlib.Byte (Random (256));
                        end loop;
                        Data.Append
                          (Bytes'(Current (Current'First .. At_Byte - 1) & Inserted
                                  & Current (At_Byte .. Current'Last)));
                     end;
                  when 7 =>  --  an extreme point: both words at the ends of their range
                     if At_Byte + 2 < Current'Last then
                        declare
                           Changed : Bytes := Current;
                           Ends : constant Bytes := [16#80#, 16#00#, 16#7F#, 16#FF#];
                        begin
                           for Offset in 0 .. 1 loop
                              declare
                                 Pick : constant Natural := 2 * Random (2);
                              begin
                                 Changed (At_Byte + 2 * Offset) := Ends (Ends'First + Pick);
                                 Changed (At_Byte + 2 * Offset + 1) := Ends (Ends'First + Pick + 1);
                              end;
                           end loop;
                           Data.Append (Changed);
                        end;
                     end if;
                  when 8 =>  --  repeat a short chunk, as runaway origins, pens and text do, up to 64 KiB
                     declare
                        Last : constant Natural := Natural'Min (Current'Last, At_Byte + 1 + Random (15));
                        Chunk : constant Bytes := Current (At_Byte .. Last);
                        Times : constant Positive := 1 + Random (65_536 / Chunk'Length);
                        Repeated : Bytes (1 .. Chunk'Length * Times);
                     begin
                        for Index in 0 .. Times - 1 loop
                           Repeated (1 + Index * Chunk'Length .. (Index + 1) * Chunk'Length) := Chunk;
                        end loop;
                        Data.Append
                          (Bytes'(Current (Current'First .. Last) & Repeated & Current (Last + 1 .. Current'Last)));
                     end;
                  when others =>  --  plant an opcode
                     if At_Byte < Current'Last then
                        declare
                           Changed : Bytes := Current;
                           Ops : constant array (1 .. 15) of Natural :=
                             [16#0001#, 16#000C#, 16#0012#, 16#0023#, 16#0028#, 16#0029#, 16#0070#, 16#0081#,
                              16#0090#, 16#0098#, 16#009A#, 16#00A1#, 16#00FF#, 16#0C00#, 16#8200#];
                           Value : constant Natural := Ops (1 + Random (15));
                        begin
                           Changed (At_Byte) := Pictlib.Byte (Value / 256);
                           Changed (At_Byte + 1) := Pictlib.Byte (Value mod 256);
                           Data.Append (Changed);
                        end;
                     end if;
               end case;
            end;
         end;
      end loop;
      return Data.Last_Element;
   end Mutate;

   procedure Exercise (Input : aliased Bytes) is
      Source : aliased Pictlib.Streams.Memory_Source;
      Decoder : Pictlib.Decoding.Decoder;
      Visitor : Null_Visitor;
      Outcome : Pictlib.Results.Result;
      Table : constant Pictlib.Fonts.Font_Table := Pictlib_Testing.Fonts.Test_Table;
   begin
      Pictlib.Streams.Open (Source, Input'Unchecked_Access);
      Pictlib.Decoding.Initialize (Decoder, Source'Access, Decode_Limits => Budget);
      Outcome := Pictlib.Decoding.Read_Header (Decoder);
      if Pictlib.Results.Succeeded (Outcome) then
         Outcome := Pictlib.Decoding.Enumerate (Decoder, Visitor);
      end if;
      for Strictness in Pictlib.Compatible .. Pictlib.Recover_When_Safe loop
         Pictlib.Streams.Open (Source, Input'Unchecked_Access);
         Pictlib.Decoding.Initialize
           (Decoder, Source'Access, (Strictness => Strictness, Fonts => Table, others => <>), Budget);
         Outcome := Pictlib.Decoding.Read_Header (Decoder);
         if Pictlib.Results.Succeeded (Outcome) then
            if Strictness = Pictlib.Recover_When_Safe then
               Headers_Read := Headers_Read + 1;
            end if;
            declare
               Frame : constant Pictlib.Geometry.Rect := Pictlib.Decoding.Header (Decoder).Frame;
               Width : constant Positive := Pictlib.Geometry.Width (Frame);
               Height : constant Positive := Pictlib.Geometry.Height (Frame);
            begin
               Outcome := Pictlib.Decoding.Render
                 (Decoder,
                  (Descriptor => (Width => Pictlib.Image_Width (Width), Height => Pictlib.Image_Height (Height),
                                  Format => Pictlib.RGBA_32, Stride => Pictlib.Row_Stride (4 * Width),
                                  Accessible_Bytes => Pictlib.Byte_Count (4 * Width * Height)),
                   Storage => Canvas));
               if Pictlib.Results.Succeeded (Outcome) and then Strictness = Pictlib.Recover_When_Safe then
                  if Pictlib.Decoding.Warning_Count (Decoder) > 0
                    and then Pictlib.Errors."="
                      (Pictlib.Decoding.Warning_At (Decoder, Pictlib.Decoding.Warning_Count (Decoder)).Code,
                       Pictlib.Errors.Partial_Picture)
                  then
                     Partial := Partial + 1;
                  else
                     Rendered := Rendered + 1;
                  end if;
               end if;
            end;
         end if;
      end loop;
   end Exercise;

   procedure Save (Name : String; Input : Bytes) is
      use Ada.Streams.Stream_IO;
      File : File_Type;
   begin
      Ada.Directories.Create_Path (Artifacts);
      Create (File, Out_File, Artifacts & "/" & Name);
      Bytes'Write (Stream (File), Input);
      Close (File);
   end Save;

   Defects, Slow, Stuck : Natural := 0;

   --  Run each saved input named after --replay through the same checks, printing how long it took.
   procedure Replay_Inputs is
   begin
      for Index in 2 .. Ada.Command_Line.Argument_Count loop
         declare
            use Ada.Streams.Stream_IO;
            Name : constant String := Ada.Command_Line.Argument (Index);
            File : File_Type;
            Data : constant Pictlib.Streams.Byte_Array_Access :=
              new Bytes (1 .. Natural (Ada.Directories.Size (Name)));
            Started : Ada.Calendar.Time;
         begin
            Open (File, In_File, Name);
            Bytes'Read (Stream (File), Data.all);
            Close (File);
            Started := Ada.Calendar.Clock;
            Exercise (Data.all);
            Ada.Text_IO.Put_Line (Name & Duration'Image (Ada.Calendar.Clock - Started) & " s");
         exception
            when Error : others =>
               Defects := Defects + 1;
               Ada.Text_IO.Put_Line ("DEFECT " & Name & ": " & Ada.Exceptions.Exception_Information (Error));
         end;
      end loop;
   end Replay_Inputs;
begin
   if not Pictlib_Testing.Tools.Enter_Tests_Directory then
      return;
   end if;
   if Replay then
      Replay_Inputs;
      if Defects > 0 then
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      end if;
      return;
   end if;
   Add_Files ("fixtures/external");
   Add_Files ("fixtures/real_world/libreoffice/pass");
   Add_Encoded (Pictlib_Testing.Samples.Gradient, Pictlib.Encoding.Direct_32);
   Add_Encoded (Pictlib_Testing.Samples.Three_Colors, Pictlib.Encoding.Indexed_8);
   Add_Encoded (Pictlib_Testing.Samples.Black_And_White, Pictlib.Encoding.Mono_1);
   Ada.Text_IO.Put_Line (Natural'Image (Natural (Seeds.Length)) & " seeds," & Iterations'Image & " iterations");
   for Iteration in 1 .. Iterations loop
      declare
         Input : aliased constant Bytes := Mutate (Seeds (1 + Random (Natural (Seeds.Length))));
         Started : constant Ada.Calendar.Time := Ada.Calendar.Clock;
      begin
         Exercise (Input);
         if Ada.Calendar.Clock - Started > Stuck_Seconds then
            Stuck := Stuck + 1;
            Save ("stuck-" & Iteration'Image (2 .. Iteration'Image'Last) & ".pict", Input);
         elsif Ada.Calendar.Clock - Started > Slow_Seconds then
            Slow := Slow + 1;
            Save ("slow-" & Iteration'Image (2 .. Iteration'Image'Last) & ".pict", Input);
         end if;
      exception
         when Error : others =>
            Defects := Defects + 1;
            Save ("defect-" & Iteration'Image (2 .. Iteration'Image'Last) & ".pict", Input);
            Ada.Text_IO.Put_Line ("DEFECT at iteration" & Iteration'Image & ": "
                                  & Ada.Exceptions.Exception_Information (Error));
      end;
   end loop;
   Ada.Text_IO.Put_Line (Iterations'Image & " inputs:" & Headers_Read'Image & " past the header," & Rendered'Image
                         & " rendered," & Partial'Image & " partial;" & Defects'Image & " defects," & Stuck'Image
                         & " stuck," & Slow'Image & " slow");
   if Defects > 0 or else (Stuck > 0 and then Fail_Stuck) then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Pictlib_Fuzz;
