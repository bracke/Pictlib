--  Mutation fuzzing: seeds are the external and real-world fixtures, hand-assembled version 1 and version 2
--  pictures of shapes and text, and fresh encoder output; each iteration mutates one seed and has pictlib
--  enumerate it strictly and recoverably and render it in every strictness under tight limits. How each input is
--  read is drawn from its own bytes, so a replay repeats it: the header policy, metadata retention, whether input
--  must end at the end opcode, the view's format, short reads, a smaller total allocation budget, and a visitor
--  that stops, raises or rebinds its decoder at some opcode. An exception escaping pictlib is a defect and fails
--  the run. What an input may cost is bounded by the limits, not the clock, so time only reports: an input taking
--  longer than Slow_Seconds is slow, one taking longer than Stuck_Seconds stuck, and both are saved under
--  artifacts/fuzz for replay; a stuck input fails the run only with --fail-stuck, for a machine whose speed is
--  known. A failure must carry a fatal code and leave
--  the decoder Failed with it as its last error; a success must leave it in the state the call promises.
--  Arguments: [iterations] [seed], with --fail-stuck anywhere; seeds are taken in file-name order, so a pair is
--  deterministic everywhere. With --replay FILE..., each saved input is run through the same checks instead,
--  and its time printed.
--  Runs from anywhere below the pictlib tree.
with Pictlib_Testing.Builders;
with Pictlib_Testing.Canvases;
with Pictlib_Testing.Files;
with Pictlib_Testing.Fonts;
with Pictlib_Testing.Random;
with Pictlib_Testing.Recorders;
with Pictlib_Testing.Tools;
with Project_Tools.Processes;
with Ada.Calendar;
with Ada.Characters.Handling;
with Ada.Command_Line;
with Ada.Containers.Indefinite_Vectors;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Text_IO;
with Interfaces;
with Pictlib;
with Pictlib.Decoding;
with Pictlib.Encoding;
with Pictlib.Errors;
with Pictlib.Fonts;
with Pictlib.Images;
with Pictlib.Limits;
with Pictlib.Opcodes;
with Pictlib.Pictures;
with Pictlib.Results;
with Pictlib.Streams;
with Pictlib_Testing.Samples;

procedure Pictlib_Fuzz is
   procedure Fail (Message : String) renames Pictlib_Testing.Tools.Fail;
   use type Ada.Calendar.Time;
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

   Fail_Stuck : constant Boolean := Project_Tools.Processes.Has_Argument ("--fail-stuck");
   Replay : constant Boolean := Project_Tools.Processes.Has_Argument ("--replay");

   package Name_Vectors renames Pictlib_Testing.Tools.Name_Vectors;

   --  The arguments that are not flags: the replayed files, or the iterations and seed.
   function Positional return Name_Vectors.Vector is
      Result : Name_Vectors.Vector;
   begin
      for Index in 1 .. Ada.Command_Line.Argument_Count loop
         if Ada.Command_Line.Argument (Index) not in "--fail-stuck" | "--replay" then
            --  A replayed file is named from where the tool was run, before it moves to the tests directory.
            Result.Append
              (if Replay then Ada.Directories.Full_Name (Ada.Command_Line.Argument (Index))
               else Ada.Command_Line.Argument (Index));
         end if;
      end loop;
      return Result;
   end Positional;
   Arguments : constant Name_Vectors.Vector := Positional;

   --  The iterations and seed, when the arguments give valid ones.
   Usable : Boolean := True;
   Iterations : Natural := 2_000;
   --  The generator's seed, printed so a run can be repeated: the generator's default unless one is given.
   Seed_Used : Interfaces.Unsigned_64 := 16#9E37_79B9_7F4A_7C15#;
   Generator : Pictlib_Testing.Random.Generator := Pictlib_Testing.Random.Seeded (Seed_Used);

   function Random (Bound : Positive) return Natural is (Pictlib_Testing.Random.Next (Generator, Bound));

   Budget : constant Pictlib.Limits.Limit_Set :=
     (Pictlib.Limits.Default_Limits with delta
        Max_Frame_Width => 1024, Max_Frame_Height => 1024, Max_Canvas_Pixels => 2 ** 20,
        Max_Drawing_Work => 2 ** 26, Max_Allocation_Bytes => 64 * 1024 * 1024,
        Max_Embedded_Image_Pixels => 2 ** 20, Max_Embedded_Image_Bytes => 4 * 1024 * 1024,
        Max_Opcodes => 100_000);
   Canvas : constant Pictlib.Streams.Byte_Array_Access := new Bytes (1 .. 4 * 1024 * 1024);

   subtype Null_Visitor is Pictlib_Testing.Recorders.Null_Visitor;

   Seeds : Byte_Vectors.Vector;
   --  How far inputs got: past the header, rendered completely, rendered as a partial picture.
   Headers_Read, Rendered, Partial : Natural := 0;

   --  A decoder that broke its contract on an input that did not make it raise.
   Contract_Broken : exception;

   --  Check what a call left: a failure carries a fatal code and leaves the decoder Failed with it as its last
   --  error; a success leaves it Promised.
   procedure Check
     (Decoder : Pictlib.Decoding.Decoder;
      Outcome : Pictlib.Results.Result;
      Promised : Pictlib.Decoding.Decoder_State;
      Call : String)
   is
      use type Pictlib.Decoding.Decoder_State;
      use type Pictlib.Errors.Error_Code;
   begin
      if Pictlib.Results.Succeeded (Outcome) then
         if Pictlib.Decoding.State (Decoder) /= Promised then
            raise Contract_Broken with
              Call & " succeeded and left " & Pictlib.Decoding.State (Decoder)'Image & ", not " & Promised'Image;
         end if;
      elsif not Pictlib.Errors.Is_Fatal (Outcome.First_Error) then
         raise Contract_Broken with Call & " failed with the non-fatal " & Outcome.First_Error.Code'Image;
      elsif Pictlib.Decoding.State (Decoder) /= Pictlib.Decoding.Failed
        or else Pictlib.Decoding.Last_Error (Decoder).Code /= Outcome.First_Error.Code
      then
         raise Contract_Broken with
           Call & " failed with " & Outcome.First_Error.Code'Image & " and left "
           & Pictlib.Decoding.State (Decoder)'Image & ", last error "
           & Pictlib.Decoding.Last_Error (Decoder).Code'Image;
      end if;
   end Check;

   procedure Add_Files (Directory : String) is
   begin
      if not Ada.Directories.Exists (Directory) then
         Fail ("missing seed directory " & Directory);
         return;
      end if;
      --  Sorted, so the seeds' order does not depend on the file system.
      for Name of Pictlib_Testing.Tools.Files_Below (Directory, Recursive => False) loop
         if Ada.Characters.Handling.To_Lower (Ada.Directories.Extension (Name)) in "pict" | "pct"
           and then Ada.Directories."<=" (Ada.Directories.Size (Name), 262_144)
         then
            Seeds.Append (Pictlib_Testing.Files.Load_Path (Name).all);
         end if;
      end loop;
   end Add_Files;

   procedure Add_Encoded (Item : Pictlib_Testing.Samples.Kind; Layout : Pictlib.Encoding.Layout_Kind) is
      Picture : constant Pictlib_Testing.Samples.Encoded :=
        Pictlib_Testing.Samples.Encode (Item, 23, 9, (Layout => Layout, others => <>));
   begin
      if Pictlib.Results.Succeeded (Picture.Outcome) then
         Seeds.Append (Picture.Data.all);
      end if;
   end Add_Encoded;

   procedure Save (Name : String; Input : Bytes) is
   begin
      Ada.Directories.Create_Path (Artifacts);
      Pictlib_Testing.Files.Save_Path (Artifacts & "/" & Name, Input);
   end Save;

   --  Pictures of the shapes, pen, pattern and text opcodes, assembled by hand from Inside Macintosh's layouts:
   --  one in version 1, one in version 2. Each must render compatibly, or it seeds nothing it claims to;
   --  LineJustify, which pictlib does not draw, is skipped with a warning.
   procedure Add_Hand_Seeds is
      use Pictlib_Testing.Builders;
      Triangle : constant Bytes := W (22) & Rect (0, 0, 20, 20) & W (0) & W (0) & W (20) & W (10) & W (0) & W (20);
      Version_1 : constant Bytes :=
        V1_Prefix (0, 0, 30, 40)
        & B (16#07#) & W (2) & W (2) & B (16#09#) & Checker & B (16#30#) & Rect (2, 2, 20, 30)
        & B (16#0B#) & W (4) & W (4) & B (16#40#) & Rect (3, 3, 25, 35) & B (16#51#) & Rect (5, 5, 15, 25)
        & B (16#60#) & Rect (0, 0, 30, 40) & W (0) & W (90) & B (16#71#) & Triangle
        & B (16#22#) & W (1) & W (1) & B (5) & B (5) & B (16#03#) & W (3) & B (16#0D#) & W (12)
        & B (16#28#) & W (20) & W (5) & B (2) & Text ("Hi") & B (16#FF#);
      Version_2 : constant Bytes :=
        Pic (40, 30,
             Pen_Size (2, 3) & W (16#0B#) & W (6) & W (6) & W (16#09#) & Checker & RGB (16#1A#, 16#FFFF#, 0, 0)
             & Op_Rect (16#30#, 2, 2, 20, 30) & Op_Rect (16#41#, 4, 4, 18, 28) & Op_Rect (16#51#, 5, 5, 15, 25)
             & Op_Rect (16#60#, 0, 0, 30, 40) & W (0) & W (135) & W (16#70#) & Triangle
             & W (16#81#) & L_Region & W (16#20#) & W (1) & W (1) & W (25) & W (35)
             & W (16#22#) & W (3) & W (3) & B (5) & B (7)
             & W (16#2C#) & W (8) & W (3) & B (5) & Text ("Hello") & W (16#03#) & W (3) & W (16#0D#) & W (12)
             & W (16#2D#) & W (8) & L (16#0001_0000#) & L (0)
             & W (16#28#) & W (20) & W (5) & B (2) & Text ("Hi") & B (0));
      Table : constant Pictlib.Fonts.Font_Table := Pictlib_Testing.Fonts.Test_Table;
   begin
      for Picture of Byte_Vectors.Vector'[Version_1, Version_2] loop
         declare
            Input : aliased constant Bytes := Picture;
            Source : aliased Pictlib.Streams.Memory_Source;
            Decoder : Pictlib.Decoding.Decoder;
            Outcome : Pictlib.Results.Result;
         begin
            Pictlib.Streams.Open (Source, Input'Unchecked_Access);
            Pictlib.Decoding.Initialize
              (Decoder, Source'Access, (Strictness => Pictlib.Compatible, Fonts => Table, others => <>), Budget);
            Outcome := Pictlib.Decoding.Read_Header (Decoder);
            if Pictlib.Results.Succeeded (Outcome) then
               Outcome := Pictlib.Decoding.Render
                 (Decoder, Pictlib_Testing.Canvases.Frame_View (Decoder, Canvas, Pictlib.RGBA_32));
            end if;
            if Pictlib.Results.Succeeded (Outcome) then
               Seeds.Append (Picture);
            else
               Fail ("a hand-assembled seed does not render: "
                     & Pictlib.Errors.Identifiers.To_String (Outcome.First_Error.Identifier) & " at opcode"
                     & Outcome.First_Error.Context.Op'Image & " " & Outcome.First_Error.Context.Limit'Image
                     & ", expected"
                     & Outcome.First_Error.Context.Expected'Image & ", actual"
                     & Outcome.First_Error.Context.Actual'Image & "; saved as hand-seed.pict");
               Save ("hand-seed.pict", Picture);
            end if;
         end;
      end loop;
   end Add_Hand_Seeds;

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
                  when others =>  --  plant an opcode, half the time where a version 2 opcode may begin
                     declare
                        Ops : constant array (1 .. 28) of Natural :=
                          [16#0001#, 16#0007#, 16#000B#, 16#000C#, 16#0012#, 16#0020#, 16#0022#, 16#0023#,
                           16#0028#, 16#0029#, 16#002C#, 16#002D#, 16#0030#, 16#0041#, 16#0051#, 16#0060#,
                           16#0070#, 16#0081#, 16#0090#, 16#0098#, 16#009A#, 16#00A1#, 16#00FF#, 16#0C00#,
                           16#8200#, 16#0031#, 16#0044#, 16#0084#];
                        Value : constant Natural := Ops (1 + Random (Ops'Length));
                        --  The picture begins at 0 or 512, so an even offset is a word boundary in both.
                        Aligned : constant Boolean := Random (2) = 0;
                        Place : constant Positive :=
                          (if Aligned and then (At_Byte - Current'First) mod 2 = 1 then At_Byte - 1 else At_Byte);
                     begin
                        if Place >= Current'First and then Place < Current'Last then
                           declare
                              Changed : Bytes := Current;
                           begin
                              Changed (Place) := Pictlib.Byte (Value / 256);
                              Changed (Place + 1) := Pictlib.Byte (Value mod 256);
                              Data.Append (Changed);
                           end;
                        end if;
                     end;
               end case;
            end;
         end;
      end loop;
      return Data.Last_Element;
   end Mutate;

   --  What a visitor does at its At-th opcode: nothing, return Stop, raise, or rebind its decoder to Again.
   type Visitor_Move is (Continues, Stops, Raises, Rebinds);

   Visitor_Raised : exception;

   type Fuzz_Visitor is new Pictlib.Decoding.Opcode_Visitor with record
      Move : Visitor_Move := Continues;
      At_Visit : Positive := 1;
      Visits : Natural := 0;
      Target : access Pictlib.Decoding.Decoder;
      Again : access Pictlib.Streams.Source'Class;
      --  Whether it made its move, and at which opcode.
      Moved : Boolean := False;
      Moved_At : Pictlib.Opcode := 0;
   end record;

   overriding function Visit (Object : in out Fuzz_Visitor; Event : Pictlib.Pictures.Opcode_Event)
     return Pictlib.Decoding.Visit_Action;
   overriding function Visit (Object : in out Fuzz_Visitor; Event : Pictlib.Pictures.Opcode_Event)
     return Pictlib.Decoding.Visit_Action is
   begin
      Object.Visits := Object.Visits + 1;
      if Object.Move = Continues or else Object.Visits /= Object.At_Visit then
         return Pictlib.Decoding.Continue;
      end if;
      Object.Moved := True;
      Object.Moved_At := Event.Op;
      case Object.Move is
         when Continues | Stops => return Pictlib.Decoding.Stop;
         when Raises => raise Visitor_Raised;
         when Rebinds =>
            Pictlib.Decoding.Reset (Object.Target.all, Object.Again);
            return Pictlib.Decoding.Continue;
      end case;
   end Visit;

   --  FNV-1a over Input: what the variant of an input is drawn from, never 0.
   function Hash (Input : Bytes) return Interfaces.Unsigned_64 is
      use type Interfaces.Unsigned_64;
      Value : Interfaces.Unsigned_64 := 16#CBF2_9CE4_8422_2325#;
   begin
      for Item of Input loop
         Value := (Value xor Interfaces.Unsigned_64 (Item)) * 16#0000_0100_0000_01B3#;
      end loop;
      return (if Value = 0 then 1 else Value);
   end Hash;

   procedure Exercise (Input : aliased Bytes) is
      use type Pictlib.Decoding.Decoder_State;
      use type Pictlib.Errors.Error_Code;
      Variant : Pictlib_Testing.Random.Generator := Pictlib_Testing.Random.Seeded (Hash (Input));
      function Pick (Bound : Positive) return Natural is (Pictlib_Testing.Random.Next (Variant, Bound));

      --  How this input is read: mostly as most callers would, otherwise in one of the ways it may be.
      Transfer : constant Pictlib.Byte_Count :=
        (if Pick (4) = 0 then Pictlib.Byte_Count (1 + Pick (7)) else Pictlib.Byte_Count'Last);
      Format : constant Pictlib.Pixel_Format := Pictlib.Pixel_Format'Val (Pick (5));
      Policy : constant Pictlib.Header_Policy :=
        (if Pick (4) = 0 then Pictlib.Header_Policy'Val (1 + Pick (2)) else Pictlib.Auto);
      Keep_All : constant Boolean := Pick (2) = 0;
      Require_End : constant Boolean := Pick (3) = 0;
      --  One draw a declaration: the order an aggregate's components are evaluated in is not defined.
      Red : constant Pictlib.Byte := Pictlib.Byte (Pick (256));
      Green : constant Pictlib.Byte := Pictlib.Byte (Pick (256));
      Blue : constant Pictlib.Byte := Pictlib.Byte (Pick (256));
      Background : constant Pictlib.Images.RGB_Color := (Red, Green, Blue);
      Limits : constant Pictlib.Limits.Limit_Set :=
        (if Pick (4) = 0
         then (Budget with delta Max_Total_Allocation_Bytes => Pictlib.Byte_Count (1 + Pick (2 ** 20)))
         else Budget);
      Move : constant Visitor_Move := Visitor_Move'Val (Pick (4));
      At_Visit : constant Positive := 1 + Pick (40);
      Table : constant Pictlib.Fonts.Font_Table := Pictlib_Testing.Fonts.Test_Table;

      function Settings (Strictness : Pictlib.Strictness_Mode) return Pictlib.Decoding.Options is
        (Strictness => Strictness, File_Header => Policy,
         Retention => (if Keep_All then (others => True) else (others => <>)),
         Require_End_Of_Input => Require_End, Background => Background, Fonts => Table);

      Visitor : Null_Visitor;
      Outcome : Pictlib.Results.Result;

      --  Enumerate with a visitor that makes Move at its At_Visit-th opcode, and check what that left.
      procedure Enumerate (Strictness : Pictlib.Strictness_Mode) is
         Source, Again : aliased Pictlib.Streams.Memory_Source;
         Decoder : aliased Pictlib.Decoding.Decoder;
         Mover : Fuzz_Visitor :=
           (Move => Move, At_Visit => At_Visit, Target => Decoder'Unchecked_Access,
            Again => Again'Unchecked_Access, others => <>);
         Raised : Boolean := False;
      begin
         Pictlib.Streams.Open (Source, Input'Unchecked_Access, Transfer);
         Pictlib.Streams.Open (Again, Input'Unchecked_Access, Transfer);
         Pictlib.Decoding.Initialize (Decoder, Source'Access, Settings (Strictness), Limits);
         Outcome := Pictlib.Decoding.Read_Header (Decoder);
         Check (Decoder, Outcome, Pictlib.Decoding.Header_Read, "Read_Header");
         if not Pictlib.Results.Succeeded (Outcome) then
            return;
         end if;
         begin
            Outcome := Pictlib.Decoding.Enumerate (Decoder, Mover);
         exception
            when Visitor_Raised => Raised := True;
         end;
         if Raised then
            if Pictlib.Decoding.State (Decoder) /= Pictlib.Decoding.Stopped then
               raise Contract_Broken with
                 "a visitor's exception left " & Pictlib.Decoding.State (Decoder)'Image & ", not STOPPED";
            end if;
         elsif Mover.Moved and then Move = Rebinds then
            --  The rebinding stands: the call ends refused, and the decoder reads its new source from the start.
            if Outcome.First_Error.Code /= Pictlib.Errors.Invalid_State
              or else Pictlib.Decoding.State (Decoder) /= Pictlib.Decoding.Ready
            then
               raise Contract_Broken with
                 "a visitor's Reset ended Enumerate with " & Outcome.First_Error.Code'Image & " and left "
                 & Pictlib.Decoding.State (Decoder)'Image;
            end if;
            Outcome := Pictlib.Decoding.Read_Header (Decoder);
            Check (Decoder, Outcome, Pictlib.Decoding.Header_Read, "Read_Header after a visitor's Reset");
            if Pictlib.Results.Succeeded (Outcome) then
               Outcome := Pictlib.Decoding.Enumerate (Decoder, Visitor);
               Check (Decoder, Outcome, Pictlib.Decoding.Finished, "Enumerate after a visitor's Reset");
            end if;
         elsif Mover.Moved and then Move = Stops and then Pictlib.Results.Succeeded (Outcome) then
            --  Stop at the end opcode is a finished picture.
            Check (Decoder, Outcome,
                   (if Pictlib."=" (Mover.Moved_At, Pictlib.Opcodes.End_Picture) then Pictlib.Decoding.Finished
                    else Pictlib.Decoding.Stopped),
                   "Enumerate stopped");
         else
            Check (Decoder, Outcome, Pictlib.Decoding.Finished, "Enumerate");
         end if;
      end Enumerate;

      Source : aliased Pictlib.Streams.Memory_Source;
      Decoder : Pictlib.Decoding.Decoder;
   begin
      Enumerate (Pictlib.Strict);
      Enumerate (Pictlib.Recover_When_Safe);
      for Strictness in Pictlib.Strictness_Mode loop
         Pictlib.Streams.Open (Source, Input'Unchecked_Access, Transfer);
         Pictlib.Decoding.Initialize (Decoder, Source'Access, Settings (Strictness), Limits);
         Outcome := Pictlib.Decoding.Read_Header (Decoder);
         Check (Decoder, Outcome, Pictlib.Decoding.Header_Read, "Read_Header");
         if Pictlib.Results.Succeeded (Outcome) then
            if Strictness = Pictlib.Recover_When_Safe then
               Headers_Read := Headers_Read + 1;
            end if;
            --  The budget's frame limits keep every frame within Canvas, in any format.
            Outcome := Pictlib.Decoding.Render
              (Decoder, Pictlib_Testing.Canvases.Frame_View (Decoder, Canvas, Format));
            Check (Decoder, Outcome, Pictlib.Decoding.Finished, "Render");
            if Pictlib.Results.Succeeded (Outcome) and then Strictness = Pictlib.Recover_When_Safe then
               --  Any warning may be the partial picture's: an overflowing log ends with its own marker.
               if (for some Index in 1 .. Pictlib.Decoding.Warning_Count (Decoder) =>
                     Pictlib.Errors."=" (Pictlib.Decoding.Warning_At (Decoder, Index).Code,
                                         Pictlib.Errors.Partial_Picture))
               then
                  Partial := Partial + 1;
               else
                  Rendered := Rendered + 1;
               end if;
            end if;
         end if;
      end loop;
   end Exercise;

   Defects, Slow, Stuck : Natural := 0;

   --  Run each saved input named after --replay through the same checks, printing how long it took.
   procedure Replay_Inputs is
   begin
      for Name of Arguments loop
         declare
            Data : Pictlib_Testing.Files.Bytes_Access;
            Started : Ada.Calendar.Time;
         begin
            --  Loaded apart, so a file that cannot be read is reported as such, not as a defect.
            begin
               Data := Pictlib_Testing.Files.Load_Path (Name);
            exception
               when Error : others =>
                  Fail ("cannot read " & Name & ": " & Ada.Exceptions.Exception_Message (Error));
            end;
            if Pictlib.Streams."/=" (Data, null) then
               Started := Ada.Calendar.Clock;
               Exercise (Data.all);
               Ada.Text_IO.Put_Line (Name & Duration'Image (Ada.Calendar.Clock - Started) & " s");
            end if;
         exception
            when Error : others =>
               Defects := Defects + 1;
               Fail ("DEFECT " & Name & ": " & Ada.Exceptions.Exception_Information (Error));
         end;
      end loop;
   end Replay_Inputs;
begin
   if not Pictlib_Testing.Tools.Enter_Tests_Directory then
      return;
   end if;
   Pictlib_Testing.Tools.Start_Report ("pictlib_fuzz");
   if not Replay then
      begin
         if Natural (Arguments.Length) > 2 then
            Usable := False;
         elsif Natural (Arguments.Length) >= 1 then
            Iterations := Natural'Value (Arguments (1));
            --  No iterations would pass having fuzzed nothing.
            Usable := Iterations > 0;
         end if;
         if Natural (Arguments.Length) = 2 then
            declare
               Seed : constant Interfaces.Unsigned_64 := Interfaces.Unsigned_64'Value (Arguments (2));
            begin
               --  The generator never leaves 0: every choice would be the first.
               Usable := Usable and then Interfaces."/=" (Seed, 0);
               if Usable then
                  Seed_Used := Seed;
                  Generator := Pictlib_Testing.Random.Seeded (Seed);
               end if;
            end;
         end if;
      exception
         when Constraint_Error => Usable := False;
      end;
      if not Usable then
         Fail ("usage: pictlib_fuzz [iterations] [seed] [--fail-stuck] | --replay FILE...");
         Pictlib_Testing.Tools.Finish_Report;
         return;
      end if;
   end if;
   if Replay and then Arguments.Is_Empty then
      Fail ("usage: pictlib_fuzz --replay FILE...: no file to replay");
      Pictlib_Testing.Tools.Finish_Report;
      return;
   elsif Replay then
      Replay_Inputs;
      Pictlib_Testing.Tools.Finish_Report;
      return;
   end if;
   Add_Files ("fixtures/external");
   Add_Files ("fixtures/real_world/libreoffice/pass");
   --  The fixtures are most of what is fuzzed: without them the run would mutate three tiny encoder outputs and
   --  pass, having tested little.
   if Seeds.Is_Empty then
      Fail ("no fixture seeds: fixtures/external and fixtures/real_world/libreoffice/pass hold no picture");
      Pictlib_Testing.Tools.Finish_Report;
      return;
   end if;
   Add_Hand_Seeds;
   Add_Encoded (Pictlib_Testing.Samples.Gradient, Pictlib.Encoding.Direct_32);
   Add_Encoded (Pictlib_Testing.Samples.Three_Colors, Pictlib.Encoding.Indexed_8);
   Add_Encoded (Pictlib_Testing.Samples.Black_And_White, Pictlib.Encoding.Mono_1);
   Ada.Text_IO.Put_Line (Natural'Image (Natural (Seeds.Length)) & " seeds," & Iterations'Image & " iterations, seed"
                         & Seed_Used'Image);
   for Iteration in 1 .. Iterations loop
      begin
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
               Fail ("DEFECT at iteration" & Iteration'Image & ": " & Ada.Exceptions.Exception_Information (Error));
               --  Reported first, so a failure to save the input cannot hide the defect.
               begin
                  Save ("defect-" & Iteration'Image (2 .. Iteration'Image'Last) & ".pict", Input);
               exception
                  when Save_Error : others =>
                     Fail ("could not save the input of iteration" & Iteration'Image & ": "
                           & Ada.Exceptions.Exception_Message (Save_Error));
               end;
         end;
      exception
         --  Mutation itself failed: a fault of this tool, with no input to save.
         when Error : others =>
            Fail ("mutation failed at iteration" & Iteration'Image & ": "
                  & Ada.Exceptions.Exception_Information (Error));
      end;
   end loop;
   Ada.Text_IO.Put_Line (Iterations'Image & " inputs:" & Headers_Read'Image & " past the header," & Rendered'Image
                         & " rendered," & Partial'Image & " partial;" & Defects'Image & " defects," & Stuck'Image
                         & " stuck," & Slow'Image & " slow");
   if Stuck > 0 and then Fail_Stuck then
      Fail ("--fail-stuck:" & Stuck'Image & " stuck inputs");
   end if;
   Pictlib_Testing.Tools.Finish_Report;
end Pictlib_Fuzz;
