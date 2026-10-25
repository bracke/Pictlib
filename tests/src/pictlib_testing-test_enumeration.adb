with AUnit.Assertions;
with Interfaces;

with Pictlib;
with Pictlib.Decoding;
with Pictlib.Errors;
with Pictlib.Limits;
with Pictlib.Metadata;
with Pictlib.Pictures;
with Pictlib.Results;
with Pictlib.Streams;
with Pictlib_Testing.Builders;
with Pictlib_Testing.Recorders;

package body Pictlib_Testing.Test_Enumeration is
   use AUnit.Assertions;
   use Pictlib_Testing.Builders;
   use type Interfaces.Unsigned_16;
   use type Pictlib.Byte_Count;
   use type Pictlib.Decoding.Decoder_State;
   use type Pictlib.Errors.Error_Code;
   use type Pictlib.Errors.Warning_Code;
   use type Pictlib.Limit_Kind;
   use type Pictlib.Metadata.Item_Kind;
   use type Pictlib.Opcode;
   use type Pictlib.Opcode_Ordinal;
   use type Pictlib.Row_Index;
   use type Pictlib.Source_Offset;
   use type Pictlib.Streams.Byte_Array;

   package Decoding renames Pictlib.Decoding;

   --  Version 1: one-byte opcodes, no alignment. Offsets: version 10, ShortComment 12, Clip 15, LongText 26,
   --  paintRect 35, end 44.
   V1_Picture : aliased constant Bytes :=
     V1_Prefix (0, 0, 10, 20, Size => 45)
     & B (16#A0#) & W (100)
     & B (16#01#) & Region (0, 0, 10, 20)
     & B (16#28#) & W (5) & W (6) & B (3) & Text ("abc")
     & B (16#31#) & Rect (1, 2, 3, 4)
     & B (16#FF#);

   --  Extended version 2 in a PICT file, covering every data rule; offsets are picture offsets plus 512.
   V2_Picture : aliased constant Bytes :=
     Zeros (512)
     & W (0) & Rect (0, 0, 4, 8) & W (16#0011#) & W (16#02FF#)                          --  p10 VersionOp
     & W (16#0C00#) & W (-2) & W (0) & L (16#0090_0000#) & L (16#0090_0000#)             --  p14 HeaderOp
     & Rect (0, 0, 8, 16) & L (0)
     & W (16#001E#)                                                                      --  p40 DefHilite
     & W (16#0001#) & Region (0, 0, 4, 8)                                                --  p42 Clip
     & W (16#00A1#) & W (100) & W (3) & Text ("abc") & B (0)                             --  p54 LongComment, pad
     & W (16#002C#) & W (8) & W (3) & B (5) & Text ("Hello")                             --  p64 fontName
     & W (16#0028#) & W (1) & W (2) & B (2) & Text ("Hi") & B (0)                        --  p76 LongText, pad
     & W (16#0024#) & W (2) & Text ("xy")                                                --  p86 reserved, word
     & W (16#00D0#) & L (3) & Text ("abc") & B (0)                                       --  p92 reserved, long
     & W (16#0100#) & W (0)                                                              --  p102 reserved, 2
     & W (16#8000#)                                                                      --  p106 reserved, 0
     & W (16#0098#) & W (2) & Rect (0, 0, 2, 16) & Rect (0, 0, 2, 16) & Rect (0, 0, 2, 16)  --  p108 PackBitsRect
     & W (0) & Zeros (4)
     & W (16#009A#) & L (16#FF#) & W (16#8000# + 8) & Rect (0, 0, 2, 2)                  --  p142 DirectBitsRect
     & Pixmap_Tail (Pack_Type => 4, Pixel_Size => 32, Component_Count => 3, Component_Size => 8)
     & Rect (0, 0, 2, 2) & Rect (0, 0, 2, 2) & W (0)
     & B (3) & Zeros (3) & B (3) & Zeros (3)
     & W (16#0071#) & W (14) & Rect (0, 0, 4, 4) & W (1) & W (1)                       --  p220 paintPoly
     & W (16#00A0#) & W (200)                                                            --  p236 ShortComment
     & W (16#8200#) & L (4) & Text ("jpeg")                                              --  p240 QuickTime
     & W (16#0012#) & W (2) & Zeros (8) & W (16#FFFF#) & W (0) & W (0)                   --  p250 BkPixPat
     & W (16#00FF#);                                                                     --  p268 end

   type Expected_Event is record
      Op : Pictlib.Opcode;
      Offset : Pictlib.Source_Offset;
      Length : Pictlib.Byte_Count;
   end record;

   type Expected_Events is array (Positive range <>) of Expected_Event;

   V1_Expected : constant Expected_Events :=
     [(16#11#, 10, 1), (16#A0#, 12, 2), (16#01#, 15, 10), (16#28#, 26, 8), (16#31#, 35, 8), (16#FF#, 44, 0)];

   V2_Expected : constant Expected_Events :=
     [(16#0011#, 522, 2), (16#0C00#, 526, 24), (16#001E#, 552, 0), (16#0001#, 554, 10), (16#00A1#, 566, 7),
      (16#002C#, 576, 10), (16#0028#, 588, 7), (16#0024#, 598, 4), (16#00D0#, 604, 7), (16#0100#, 614, 2),
      (16#8000#, 618, 0), (16#0098#, 620, 32), (16#009A#, 654, 76), (16#0071#, 732, 14), (16#00A0#, 748, 2),
      (16#8200#, 752, 8), (16#0012#, 762, 16), (16#00FF#, 780, 0)];

   procedure Check_Events (Events : Recorders.Recorder; Expected : Expected_Events; Label : String) is
   begin
      Assert (Events.Count = Expected'Length,
              Label & ": enumerated" & Events.Count'Image & " opcodes, expected" & Expected'Length'Image);
      for Index in Expected'Range loop
         declare
            Got : constant Pictlib.Pictures.Opcode_Event := Events.Events (Index);
         begin
            Assert (Got.Ordinal = Pictlib.Opcode_Ordinal (Index - 1), Label & ": ordinal of event" & Index'Image);
            Assert (Got.Op = Expected (Index).Op, Label & ": opcode of event" & Index'Image & " is" & Got.Op'Image);
            Assert (Got.Offset = Expected (Index).Offset,
                    Label & ": offset of event" & Index'Image & " is" & Got.Offset'Image);
            Assert (Got.Data_Length = Expected (Index).Length,
                    Label & ": data length of event" & Index'Image & " is" & Got.Data_Length'Image);
         end;
      end loop;
   end Check_Events;

   --  A bare extended version 2 picture whose opcodes after the HeaderOp are Body_Bytes; the body starts at
   --  picture offset 40.
   function V2_Body (Body_Bytes : Bytes) return Bytes is (V2_Prefix (0, 0, 4, 8) & Body_Bytes);

   procedure Version_1_Stream (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Version_2_Stream (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Short_Reads (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Default_Metadata (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Full_Metadata (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Metadata_Budgets (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Reserved_Warnings (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Pixel_Data_Layouts (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Malformed_Structures (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Truncation_And_End (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Trailing_Data (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Stream_Limits (T : in out AUnit.Test_Cases.Test_Case'Class);

   overriding function Name (T : Test) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("enumeration");
   end Name;

   overriding procedure Register_Tests (T : in out Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Version_1_Stream'Access, "enumeration.v1.stream");
      Register_Routine (T, Version_2_Stream'Access, "enumeration.v2.every_rule");
      Register_Routine (T, Short_Reads'Access, "enumeration.short_reads");
      Register_Routine (T, Default_Metadata'Access, "enumeration.metadata.default");
      Register_Routine (T, Full_Metadata'Access, "enumeration.metadata.full");
      Register_Routine (T, Metadata_Budgets'Access, "enumeration.metadata.budgets");
      Register_Routine (T, Reserved_Warnings'Access, "enumeration.warnings.reserved_and_cap");
      Register_Routine (T, Pixel_Data_Layouts'Access, "enumeration.pixel_data.layouts");
      Register_Routine (T, Malformed_Structures'Access, "enumeration.malformed.structures");
      Register_Routine (T, Truncation_And_End'Access, "enumeration.malformed.truncation_and_end");
      Register_Routine (T, Trailing_Data'Access, "enumeration.trailing_data");
      Register_Routine (T, Stream_Limits'Access, "enumeration.limits");
   end Register_Tests;

   procedure Version_1_Stream (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Decoder : Decoding.Decoder;
      Events : Recorders.Recorder;
      Outcome : Pictlib.Results.Result;
   begin
      Recorders.Decode (V1_Picture, Decoder, Events, Outcome);
      Assert (Pictlib.Results.Succeeded (Outcome), "v1 picture failed: " & Outcome.First_Error.Code'Image);
      Assert (Decoding.State (Decoder) = Decoding.Finished, "v1 picture did not finish");
      Check_Events (Events, V1_Expected, "v1");
      Assert (Decoding.Warning_Count (Decoder) = 0, "a clean v1 picture produced warnings");
   end Version_1_Stream;

   procedure Version_2_Stream (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Decoder : Decoding.Decoder;
      Events : Recorders.Recorder;
      Outcome : Pictlib.Results.Result;
   begin
      Recorders.Decode (V2_Picture, Decoder, Events, Outcome);
      Assert (Pictlib.Results.Succeeded (Outcome), "v2 picture failed: " & Outcome.First_Error.Code'Image &
              " at" & Outcome.First_Error.Context.Source'Image);
      Assert (Decoding.State (Decoder) = Decoding.Finished, "v2 picture did not finish");
      Check_Events (Events, V2_Expected, "v2");
      for Index in 1 .. Events.Count loop
         Assert (Events.Events (Index).Reserved
                 = (Events.Events (Index).Op in 16#0024# | 16#00D0# | 16#0100# | 16#8000#),
                 "reserved flag of event" & Index'Image);
      end loop;
   end Version_2_Stream;

   procedure Short_Reads (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Decoder : Decoding.Decoder;
      Events : Recorders.Recorder;
      Outcome : Pictlib.Results.Result;
   begin
      Recorders.Decode (V2_Picture, Decoder, Events, Outcome, Max_Transfer => 1);
      Assert (Pictlib.Results.Succeeded (Outcome), "one-byte reads failed");
      Check_Events (Events, V2_Expected, "v2, one-byte reads");
      Events := (others => <>);
      Recorders.Decode (V1_Picture, Decoder, Events, Outcome, Max_Transfer => 3);
      Assert (Pictlib.Results.Succeeded (Outcome), "three-byte reads failed");
      Check_Events (Events, V1_Expected, "v1, three-byte reads");
   end Short_Reads;

   procedure Expect_Item
     (Decoder : Decoding.Decoder;
      Index : Positive;
      Kind : Pictlib.Metadata.Item_Kind;
      Op : Pictlib.Opcode;
      Data : Bytes;
      Comment_Kind : Interfaces.Unsigned_16 := 0;
      Font_ID : Interfaces.Unsigned_16 := 0)
   is
      Item : constant Pictlib.Metadata.Item_Info := Decoding.Metadata_Item (Decoder, Index);
      Copy : Bytes (1 .. 600);
      Count : Pictlib.Byte_Count;
      Outcome : constant Pictlib.Results.Result := Decoding.Copy_Metadata (Decoder, Index, Copy, Count);
   begin
      Assert (Item.Kind = Kind, "item" & Index'Image & " is a " & Item.Kind'Image);
      Assert (Item.Op = Op, "item" & Index'Image & " has opcode" & Item.Op'Image);
      Assert (Item.Comment_Kind = Comment_Kind and then Item.Font_ID = Font_ID,
              "item" & Index'Image & " lost its kind or font ID");
      Assert (Item.Data_Length = Data'Length, "item" & Index'Image & " has" & Item.Data_Length'Image & " bytes");
      Assert (Pictlib.Results.Succeeded (Outcome) and then Count = Data'Length
              and then Copy (1 .. Natural (Count)) = Data,
              "item" & Index'Image & " has the wrong data");
   end Expect_Item;

   procedure Default_Metadata (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Decoder : Decoding.Decoder;
      Events : Recorders.Recorder;
      Outcome : Pictlib.Results.Result;
      Small : Bytes (1 .. 2);
      Count : Pictlib.Byte_Count;
   begin
      Recorders.Decode (V2_Picture, Decoder, Events, Outcome);
      Assert (Decoding.Metadata_Count (Decoder) = 3, "default retention kept" &
              Decoding.Metadata_Count (Decoder)'Image & " items");
      Expect_Item (Decoder, 1, Pictlib.Metadata.Long_Comment, 16#00A1#, Text ("abc"), Comment_Kind => 100);
      Expect_Item (Decoder, 2, Pictlib.Metadata.Font_Name, 16#002C#, Text ("Hello"), Font_ID => 3);
      Expect_Item (Decoder, 3, Pictlib.Metadata.Short_Comment, 16#00A0#, [1 .. 0 => 0], Comment_Kind => 200);
      Assert (Decoding.Metadata_Item (Decoder, 1).Ordinal = 4 and then Decoding.Metadata_Item (Decoder, 1).Offset = 566,
              "a comment lost its place in the stream");

      Outcome := Decoding.Copy_Metadata (Decoder, 1, Small, Count);
      Assert (Outcome.First_Error.Code = Pictlib.Errors.Invalid_Argument and then Count = 0
              and then Outcome.First_Error.Context.Expected = Small'Length
              and then Outcome.First_Error.Context.Actual = 3,
              "a short buffer was not rejected with its size and the item's");
      Outcome := Decoding.Copy_Metadata (Decoder, 4, Small, Count);
      Assert (Outcome.First_Error.Code = Pictlib.Errors.Invalid_Argument, "an index out of range was accepted");

      Recorders.Decode (V1_Picture, Decoder, Events, Outcome);
      Assert (Decoding.Metadata_Count (Decoder) = 1, "a v1 ShortComment was not retained");
      Expect_Item (Decoder, 1, Pictlib.Metadata.Short_Comment, 16#A0#, [1 .. 0 => 0], Comment_Kind => 100);
   end Default_Metadata;

   procedure Full_Metadata (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Decoder : Decoding.Decoder;
      Events : Recorders.Recorder;
      Outcome : Pictlib.Results.Result;
      Everything : constant Decoding.Options :=
        (Retention => (others => True), others => <>);
      Nothing : constant Decoding.Options :=
        (Retention => (others => False), others => <>);
   begin
      Recorders.Decode (V2_Picture, Decoder, Events, Outcome, Everything);
      Assert (Pictlib.Results.Succeeded (Outcome), "full retention failed");
      Assert (Decoding.Metadata_Count (Decoder) = 7, "full retention kept" &
              Decoding.Metadata_Count (Decoder)'Image & " items");
      Expect_Item (Decoder, 1, Pictlib.Metadata.File_Header, 0, Zeros (512));
      Expect_Item (Decoder, 2, Pictlib.Metadata.Long_Comment, 16#00A1#, Text ("abc"), Comment_Kind => 100);
      Expect_Item (Decoder, 3, Pictlib.Metadata.Font_Name, 16#002C#, Text ("Hello"), Font_ID => 3);
      Expect_Item (Decoder, 4, Pictlib.Metadata.Reserved_Payload, 16#0024#, Text ("xy"));
      Expect_Item (Decoder, 5, Pictlib.Metadata.Reserved_Payload, 16#00D0#, Text ("abc"));
      Expect_Item (Decoder, 6, Pictlib.Metadata.Short_Comment, 16#00A0#, [1 .. 0 => 0], Comment_Kind => 200);
      Expect_Item (Decoder, 7, Pictlib.Metadata.QuickTime_Payload, 16#8200#, Text ("jpeg"));
      Check_Events (Events, V2_Expected, "v2, full retention");

      Events := (others => <>);
      Recorders.Decode (V2_Picture, Decoder, Events, Outcome, Nothing);
      Assert (Pictlib.Results.Succeeded (Outcome) and then Decoding.Metadata_Count (Decoder) = 0,
              "nothing was to be retained");
      Check_Events (Events, V2_Expected, "v2, no retention");
   end Full_Metadata;

   procedure Metadata_Budgets (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Decoder : Decoding.Decoder;
      Events : Recorders.Recorder;
      Outcome : Pictlib.Results.Result;
      Two_Bytes : constant Pictlib.Limits.Limit_Set :=
        (Pictlib.Limits.Default_Limits with delta Max_Retained_Metadata_Bytes => 2);
      One_Item : constant Pictlib.Limits.Limit_Set :=
        (Pictlib.Limits.Default_Limits with delta Max_Metadata_Items => 1);
      Bad_Font_Name : aliased constant Bytes := V2_Body (W (16#002C#) & W (3) & W (1) & B (5) & B (0) & W (16#00FF#));
   begin
      Recorders.Expect_Failure (V2_Picture, Pictlib.Errors.Limit_Exceeded, "metadata bytes", 16#00A1#,
                      Budget => Two_Bytes, Limit => Pictlib.Retained_Metadata_Byte_Limit);
      Recorders.Expect_Failure (V2_Picture, Pictlib.Errors.Limit_Exceeded, "metadata items", 16#002C#,
                      Budget => One_Item, Limit => Pictlib.Metadata_Item_Limit);

      Recorders.Decode (V2_Picture, Decoder, Events, Outcome, (Strictness => Pictlib.Compatible, others => <>),
                        Two_Bytes);
      Assert (Pictlib.Results.Succeeded (Outcome), "a compatible decoder failed over the metadata budget");
      Assert (Decoding.Metadata_Count (Decoder) = 1, "only the empty ShortComment fits two bytes");
      Assert (Recorders.Has_Warning (Decoder, Pictlib.Errors.Data_Loss), "dropped metadata was not reported");
      Assert (Recorders.Warning_With (Decoder, Pictlib.Errors.Data_Loss).Context.Has_Opcode
              and then Recorders.Warning_With (Decoder, Pictlib.Errors.Data_Loss).Context.Ordinal > 0,
              "dropped metadata did not name its opcode");
      --  A 3 GB reserved payload, retained, with the byte budgets raised past it: the allocation budget as set
      --  stops it, before the most one buffer holds.
      declare
         Huge : aliased constant Bytes := V2_Body (W (16#8100#) & L (16#C000_0000#));
         Retain_Reserved : Decoding.Options;
         Big : constant Pictlib.Byte_Count := 2 ** 40;
         Huge_Events : Recorders.Recorder;
         Huge_Decoder : Decoding.Decoder;
      begin
         Retain_Reserved.Retention.Reserved_Payloads := True;
         Recorders.Decode
           (Huge, Huge_Decoder, Huge_Events, Outcome, Retain_Reserved,
            (Pictlib.Limits.Default_Limits with delta Max_Picture_Bytes => Big, Max_Opcode_Bytes => Big,
                                                      Max_Retained_Metadata_Bytes => Big,
                                                      Max_Allocation_Bytes => 1_000_000));
         Assert (Outcome.First_Error.Code = Pictlib.Errors.Limit_Exceeded
                 and then Outcome.First_Error.Context.Limit = Pictlib.Allocation_Byte_Limit
                 and then Outcome.First_Error.Context.Expected = 1_000_000
                 and then Outcome.First_Error.Context.Actual = 16#C000_0000#,
                 "a payload past one buffer named" & Outcome.First_Error.Context.Expected'Image
                 & ", not the allocation budget");
      end;
      --  A retained payload the picture byte limit cannot hold is refused as that, before anything is allocated
      --  for it: an allocation budget below it is never reached.
      declare
         Long : aliased constant Bytes := V2_Body (W (16#8100#) & L (5_000) & Zeros (5_000));
         Retain_Reserved : Decoding.Options;
         Long_Events : Recorders.Recorder;
         Long_Decoder : Decoding.Decoder;
      begin
         Retain_Reserved.Retention.Reserved_Payloads := True;
         Recorders.Decode
           (Long, Long_Decoder, Long_Events, Outcome, Retain_Reserved,
            (Pictlib.Limits.Default_Limits with delta Max_Picture_Bytes => 1_000, Max_Allocation_Bytes => 100));
         Assert (Outcome.First_Error.Code = Pictlib.Errors.Limit_Exceeded
                 and then Outcome.First_Error.Context.Limit = Pictlib.Picture_Byte_Limit
                 and then Outcome.First_Error.Context.Expected = 1_000
                 and then Outcome.First_Error.Context.Actual > 5_000,
                 "a payload past the picture byte limit reported " & Outcome.First_Error.Context.Limit'Image);
      end;
      Check_Events (Events, V2_Expected, "v2, dropped metadata");

      --  The session's allocation limit is never recovered, not even by dropping an item: at every total, a
      --  compatible decoder keeps everything or fails over that limit.
      for Total in Pictlib.Byte_Count range 0 .. 600 loop
         Recorders.Decode (V2_Picture, Decoder, Events, Outcome, (Strictness => Pictlib.Compatible, others => <>),
                           (Pictlib.Limits.Default_Limits with delta Max_Total_Allocation_Bytes => Total));
         Assert ((Pictlib.Results.Succeeded (Outcome) and then Decoding.Metadata_Count (Decoder) = 3)
                 or else (Outcome.First_Error.Code = Pictlib.Errors.Limit_Exceeded
                          and then Outcome.First_Error.Context.Limit = Pictlib.Total_Allocation_Byte_Limit),
                 "a total allocation of" & Total'Image & " bytes dropped metadata");
         Events := (others => <>);
      end loop;

      --  A comment over the per-opcode budget fails on that budget whether or not the store has room for it.
      declare
         Long_Comment : aliased constant Bytes := V2_Body (W (16#00A1#) & W (1) & W (100) & Zeros (100) & W (16#00FF#));
         Full_Store : constant Pictlib.Limits.Limit_Set :=
           (Pictlib.Limits.Default_Limits with delta Max_Opcode_Bytes => 50, Max_Metadata_Items => 0);
      begin
         Recorders.Expect_Failure (Long_Comment, Pictlib.Errors.Limit_Exceeded, "comment over the opcode budget",
                                   16#00A1#, Budget => Full_Store, Limit => Pictlib.Opcode_Byte_Limit);
         Recorders.Expect_Failure (Long_Comment, Pictlib.Errors.Limit_Exceeded, "comment over the opcode budget",
                                   16#00A1#, (Strictness => Pictlib.Compatible, others => <>), Full_Store,
                                   Pictlib.Opcode_Byte_Limit);
         Events := (others => <>);
         Recorders.Decode (Long_Comment, Decoder, Events, Outcome, (Strictness => Pictlib.Compatible, others => <>),
                           Full_Store);
         Assert (not Recorders.Has_Warning (Decoder, Pictlib.Errors.Data_Loss),
                 "a comment that fails its opcode budget was first reported as dropped");
      end;

      Recorders.Expect_Failure (Bad_Font_Name, Pictlib.Errors.Opcode_Length_Invalid, "bad font name", 16#002C#);
      --  The opcode's 3 bytes bound the 8 its name needs.
      Events := (others => <>);
      Recorders.Decode (Bad_Font_Name, Decoder, Events, Outcome);
      Assert (Outcome.First_Error.Context.Expected = 3 and then Outcome.First_Error.Context.Actual = 8,
              "a bad font name reported" & Outcome.First_Error.Context.Expected'Image & " against"
              & Outcome.First_Error.Context.Actual'Image);
      Events := (others => <>);
      Recorders.Decode (Bad_Font_Name, Decoder, Events, Outcome, (Strictness => Pictlib.Compatible, others => <>));
      Assert (Pictlib.Results.Succeeded (Outcome) and then Decoding.Metadata_Count (Decoder) = 0
              and then Recorders.Has_Warning (Decoder, Pictlib.Errors.Data_Loss),
              "a compatible decoder kept or silently dropped a malformed font name");
   end Metadata_Budgets;

   procedure Reserved_Warnings (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Decoder : Decoding.Decoder;
      Events : Recorders.Recorder;
      Outcome : Pictlib.Results.Result;
      Reserved : Natural := 0;
   begin
      Recorders.Decode (V2_Picture, Decoder, Events, Outcome);
      Reserved := Recorders.Count_Warnings (Decoder, Pictlib.Errors.Reserved_Opcode_Skipped);
      Assert (Reserved = 4 and then Decoding.Warning_Count (Decoder) = 4,
              "expected four reserved opcode warnings and nothing else, got" & Reserved'Image & " of"
              & Decoding.Warning_Count (Decoder)'Image);
      Assert ((for all Index in 1 .. 4 => Decoding.Warning_At (Decoder, Index).Context.Has_Opcode),
              "a reserved opcode warning lost its opcode");
      Assert (Decoding.Warning_At (Decoder, 1).Context.Op = 16#0024#
              and then Decoding.Warning_At (Decoder, 1).Context.Source = 598,
              "the first reserved opcode warning is misplaced");

      declare
         --  The second warning, which a cap of two displaces: the suppression record keeps its context.
         Second : constant Pictlib.Errors.Warning := Decoding.Warning_At (Decoder, 2);
      begin
         Recorders.Decode (V2_Picture, Decoder, Events, Outcome,
                           Budget => (Pictlib.Limits.Default_Limits with delta Max_Warning_Records => 2));
         Assert (Decoding.Warning_At (Decoder, 2).Context.Op = Second.Context.Op
                 and then Decoding.Warning_At (Decoder, 2).Context.Source = Second.Context.Source,
                 "the suppression record lost the context of the first warning suppressed");
      end;
      Assert (Pictlib.Results.Succeeded (Outcome), "the warning cap failed decoding");
      Assert (Decoding.Warning_Count (Decoder) = 2, "the warning cap was not honored");
      Assert (Decoding.Warning_At (Decoder, 1).Code = Pictlib.Errors.Reserved_Opcode_Skipped
              and then Decoding.Warning_At (Decoder, 2).Code = Pictlib.Errors.Warnings_Suppressed,
              "suppression was not reported in the last slot");
      --  Of the four warnings, the displaced second and the two after it were suppressed.
      Assert (Decoding.Warning_At (Decoder, 2).Context.Actual = 3,
              "the suppression record counts" & Decoding.Warning_At (Decoder, 2).Context.Actual'Image);
   end Reserved_Warnings;

   procedure Expect_Data_Length (Input : aliased Bytes; Op : Pictlib.Opcode; Length : Pictlib.Byte_Count;
                                 Label : String) is
      Decoder : Decoding.Decoder;
      Events : Recorders.Recorder;
      Outcome : Pictlib.Results.Result;
   begin
      Recorders.Decode (Input, Decoder, Events, Outcome);
      Assert (Pictlib.Results.Succeeded (Outcome), Label & ": failed with " & Outcome.First_Error.Code'Image);
      Assert (Events.Count = 4 and then Events.Events (3).Op = Op, Label & ": opcode not enumerated");
      Assert (Events.Events (3).Data_Length = Length,
              Label & ": data length" & Events.Events (3).Data_Length'Image & ", expected" & Length'Image);
   end Expect_Data_Length;

   procedure Pixel_Data_Layouts (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Header_Bytes : constant := 2 + 8 + 36;  --  rowBytes, bounds, PixMap tail
      Copy_Bytes : constant := 8 + 8 + 2;      --  srcRect, dstRect, mode
      --  BitsRect is never packed, even when rowBytes >= 8: 8 bytes x 2 rows.
      Bits : aliased constant Bytes :=
        V2_Body (W (16#0090#) & W (8) & Rect (0, 0, 2, 64) & Rect (0, 0, 2, 64) & Rect (0, 0, 2, 64) & W (0)
                 & Zeros (16) & W (16#00FF#));
      --  rowBytes 252 > 250: each packed row is prefixed by a word count.
      Wide_Rows : aliased constant Bytes :=
        V2_Body (W (16#0098#) & W (252) & Rect (0, 0, 2, 2016) & Rect (0, 0, 2, 2016) & Rect (0, 0, 2, 2016) & W (0)
                 & W (3) & Zeros (3) & W (1) & Zeros (1) & W (16#00FF#));
      --  An 8-bit pixmap with a two-entry color table and a mask region, rowBytes 4 < 8: unpacked.
      Indexed_Masked : aliased constant Bytes :=
        V2_Body (W (16#0099#) & W (16#8000# + 4) & Rect (0, 0, 3, 4)
                 & Pixmap_Tail (0, 8, 1, 8) & L (0) & W (0) & W (1) & Zeros (16)
                 & Rect (0, 0, 3, 4) & Rect (0, 0, 3, 4) & W (0) & Region (0, 0, 3, 4)
                 & Zeros (12) & W (16#00FF#));
      --  An empty color table (ctSize -1).
      Empty_Table : aliased constant Bytes :=
        V2_Body (W (16#0098#) & W (16#8000# + 4) & Rect (0, 0, 1, 4)
                 & Pixmap_Tail (0, 8, 1, 8) & L (0) & W (0) & W (16#FFFF#)
                 & Rect (0, 0, 1, 4) & Rect (0, 0, 1, 4) & W (0) & Zeros (4) & W (16#00FF#));
      --  32-bit pixels, pack type 2: the pad byte is dropped and the rest is unpacked, 3 bytes x 2 pixels x 2 rows.
      Pad_Dropped : aliased constant Bytes :=
        V2_Body (W (16#009A#) & L (16#FF#) & W (16#8000# + 8) & Rect (0, 0, 2, 2) & Pixmap_Tail (2, 32, 3, 8)
                 & Rect (0, 0, 2, 2) & Rect (0, 0, 2, 2) & W (0) & Zeros (12) & W (16#00FF#));
      --  Pack type 1: unpacked rows of rowBytes.
      Unpacked_Direct : aliased constant Bytes :=
        V2_Body (W (16#009B#) & L (16#FF#) & W (16#8000# + 8) & Rect (0, 0, 2, 2) & Pixmap_Tail (1, 32, 3, 8)
                 & Rect (0, 0, 2, 2) & Rect (0, 0, 2, 2) & W (0) & Region (0, 0, 2, 2) & Zeros (16) & W (16#00FF#));
      --  16-bit pixels, pack type 3, counted rows.
      Sixteen_Bit : aliased constant Bytes :=
        V2_Body (W (16#009A#) & L (16#FF#) & W (16#8000# + 8) & Rect (0, 0, 1, 4) & Pixmap_Tail (3, 16, 3, 5)
                 & Rect (0, 0, 1, 4) & Rect (0, 0, 1, 4) & W (0) & B (3) & Zeros (3) & W (16#00FF#));
      --  A color pixel pattern: 8x8 at 2 bits, rowBytes 2 < 8, unpacked.
      Color_Pattern : aliased constant Bytes :=
        V2_Body (W (16#0014#) & W (1) & Zeros (8) & W (16#8000# + 2) & Rect (0, 0, 8, 8) & Pixmap_Tail (0, 2, 1, 2)
                 & L (0) & W (0) & W (3) & Zeros (32) & Zeros (16) & W (16#00FF#));
      --  All four text opcodes.
      Texts : aliased constant Bytes :=
        V2_Body (W (16#0029#) & B (4) & B (1) & Text ("a") & B (0) & W (16#002A#) & B (4) & B (2) & Text ("bc")
                 & W (16#002B#) & B (1) & B (2) & B (0) & B (0) & W (16#00FF#));
      Decoder : Decoding.Decoder;
      Events : Recorders.Recorder;
      Outcome : Pictlib.Results.Result;
   begin
      Expect_Data_Length (Bits, 16#0090#, 2 + 8 + 8 + 8 + 2 + 16, "BitsRect");
      Expect_Data_Length (Wide_Rows, 16#0098#, 2 + 8 + 8 + 8 + 2 + 2 + 3 + 2 + 1, "word row counts");
      Expect_Data_Length (Indexed_Masked, 16#0099#, Header_Bytes + 8 + 16 + Copy_Bytes + 10 + 12, "PackBitsRgn");
      Expect_Data_Length (Empty_Table, 16#0098#, Header_Bytes + 8 + Copy_Bytes + 4, "empty color table");
      Expect_Data_Length (Pad_Dropped, 16#009A#, 4 + Header_Bytes + Copy_Bytes + 12, "pack type 2");
      Expect_Data_Length (Unpacked_Direct, 16#009B#, 4 + Header_Bytes + Copy_Bytes + 10 + 16, "pack type 1");
      Expect_Data_Length (Sixteen_Bit, 16#009A#, 4 + Header_Bytes + Copy_Bytes + 4, "pack type 3");
      Expect_Data_Length (Color_Pattern, 16#0014#, 2 + 8 + Header_Bytes + 8 + 32 + 16, "color pixel pattern");

      Recorders.Decode (Texts, Decoder, Events, Outcome);
      Assert (Pictlib.Results.Succeeded (Outcome) and then Events.Count = 6, "text opcodes failed");
      Assert (Events.Events (3).Data_Length = 3 and then Events.Events (4).Data_Length = 4
              and then Events.Events (5).Data_Length = 3,
              "text opcode lengths are wrong");
      Assert (Events.Events (4).Offset = 40 + 6 and then Events.Events (5).Offset = 40 + 12,
              "odd text lengths were not padded");
   end Pixel_Data_Layouts;

   procedure Malformed_Structures (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Short_Region : aliased constant Bytes := V2_Body (W (16#0001#) & W (4) & W (16#00FF#));
      Odd_Polygon : aliased constant Bytes :=
        V2_Body (W (16#0070#) & W (11) & Rect (0, 0, 1, 1) & B (0) & W (16#00FF#));
      Huge_Table : aliased constant Bytes :=
        V2_Body (W (16#0098#) & W (16#8000# + 4) & Rect (0, 0, 1, 4) & Pixmap_Tail (0, 8, 1, 8)
                 & L (0) & W (0) & W (300) & W (16#00FF#));
      Odd_Depth : aliased constant Bytes :=
        V2_Body (W (16#0098#) & W (16#8000# + 4) & Rect (0, 0, 1, 4) & Pixmap_Tail (0, 3, 1, 3) & W (16#00FF#));
      Bad_Pack : aliased constant Bytes :=
        V2_Body (W (16#009A#) & L (16#FF#) & W (16#8000# + 8) & Rect (0, 0, 1, 2) & Pixmap_Tail (5, 32, 3, 8)
                 & W (16#00FF#));
      Indexed_Direct : aliased constant Bytes :=
        V2_Body (W (16#009A#) & L (16#FF#) & W (16#8000# + 8) & Rect (0, 0, 1, 2) & Pixmap_Tail (0, 8, 1, 8)
                 & W (16#00FF#));
      Pad_Dropped_16 : aliased constant Bytes :=
        V2_Body (W (16#009A#) & L (16#FF#) & W (16#8000# + 8) & Rect (0, 0, 1, 4) & Pixmap_Tail (2, 16, 3, 5)
                 & Rect (0, 0, 1, 4) & Rect (0, 0, 1, 4) & W (0) & W (16#00FF#));
      --  An indexed pixmap is packed by default or not at all.
      function Indexed_Packed (Pack : Natural) return Bytes is
        (V2_Body (W (16#0098#) & W (16#8000# + 8) & Rect (0, 0, 1, 8) & Pixmap_Tail (Pack, 8, 1, 8)
                  & L (0) & W (0) & W (0) & Zeros (8) & Rect (0, 0, 1, 8) & Rect (0, 0, 1, 8) & W (0) & Zeros (8)
                  & W (16#00FF#)));
      Indexed_Pack_2 : aliased constant Bytes := Indexed_Packed (2);
      Indexed_Pack_3 : aliased constant Bytes := Indexed_Packed (3);
      Inverted_Bounds : aliased constant Bytes :=
        V2_Body (W (16#0098#) & W (2) & Rect (4, 0, 0, 16) & Rect (0, 0, 1, 1) & Rect (0, 0, 1, 1) & W (0)
                 & W (16#00FF#));
      Bad_Pattern : aliased constant Bytes := V2_Body (W (16#0012#) & W (3) & Zeros (8) & W (16#00FF#));
      Bad_Mask : aliased constant Bytes :=
        V2_Body (W (16#0091#) & W (2) & Rect (0, 0, 1, 16) & Rect (0, 0, 1, 16) & Rect (0, 0, 1, 16) & W (0)
                 & W (2) & W (16#00FF#));
   begin
      Recorders.Expect_Failure (Short_Region, Pictlib.Errors.Region_Invalid, "short region", 16#0001#);
      Recorders.Expect_Failure (Odd_Polygon, Pictlib.Errors.Polygon_Invalid, "odd polygon", 16#0070#);
      Recorders.Expect_Failure (Huge_Table, Pictlib.Errors.Color_Table_Invalid, "huge color table", 16#0098#);
      Recorders.Expect_Failure (Odd_Depth, Pictlib.Errors.Pixmap_Invalid, "3-bit pixels", 16#0098#);
      Recorders.Expect_Failure (Bad_Pack, Pictlib.Errors.Pixmap_Invalid, "pack type 5", 16#009A#);
      Recorders.Expect_Failure (Indexed_Direct, Pictlib.Errors.Pixmap_Invalid, "8-bit direct pixels", 16#009A#);
      Recorders.Expect_Failure (Pad_Dropped_16, Pictlib.Errors.Pixmap_Invalid, "pack type 2 at 16 bits", 16#009A#);
      Recorders.Expect_Failure (Indexed_Pack_2, Pictlib.Errors.Pixmap_Invalid, "pack type 2 at 8 bits", 16#0098#);
      Recorders.Expect_Failure (Indexed_Pack_3, Pictlib.Errors.Pixmap_Invalid, "pack type 3 at 8 bits", 16#0098#);
      Recorders.Expect_Failure (Inverted_Bounds, Pictlib.Errors.Pixmap_Invalid, "inverted bounds", 16#0098#);
      Recorders.Expect_Failure (Bad_Pattern, Pictlib.Errors.Pattern_Invalid, "pattern type 3", 16#0012#);
      Recorders.Expect_Failure (Bad_Mask, Pictlib.Errors.Region_Invalid, "short mask region", 16#0091#);
      Recorders.Expect_Failure (Short_Region, Pictlib.Errors.Region_Invalid, "short region, lenient", 16#0001#,
                      Options => (Strictness => Pictlib.Recover_When_Safe, others => <>));
   end Malformed_Structures;

   procedure Truncation_And_End (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Truncated : aliased constant Bytes := V2_Body (W (16#0030#) & W (0) & W (0));
      Half_Opcode : aliased constant Bytes := V2_Body (B (0));
      Truncated_Rows : aliased constant Bytes :=
        V2_Body (W (16#0098#) & W (16) & Rect (0, 0, 3, 128) & Rect (0, 0, 3, 128) & Rect (0, 0, 3, 128) & W (0)
                 & B (2) & Zeros (2) & B (5) & Zeros (1));
      Missing_End : aliased constant Bytes := V2_Body (W (16#001E#));
      Missing_End_After_Pad : aliased constant Bytes := V2_Body (W (16#0028#) & W (0) & W (0) & B (0));
      V1_Missing_End : aliased constant Bytes := V1_Prefix (0, 0, 1, 1) & B (16#1E#);
      Decoder : Decoding.Decoder;
      Events : Recorders.Recorder;
      Outcome : Pictlib.Results.Result;

      --  Both lenient modes finish with a warning: a missing end opcode is no partial picture.
      procedure Accept_Missing_End (Input : aliased Bytes) is
      begin
         for Mode in Pictlib.Compatible .. Pictlib.Recover_When_Safe loop
            declare
               Lenient : Decoding.Decoder;
               Seen : Recorders.Recorder;
            begin
               Recorders.Decode (Input, Lenient, Seen, Outcome, (Strictness => Mode, others => <>));
               Assert (Pictlib.Results.Succeeded (Outcome) and then Decoding.State (Lenient) = Decoding.Finished,
                       "a lenient decoder rejected a missing end opcode in " & Mode'Image);
               Assert (Recorders.Has_Warning (Lenient, Pictlib.Errors.Compatibility_Issue)
                       and then not Recorders.Has_Warning (Lenient, Pictlib.Errors.Partial_Picture),
                       "a missing end opcode was not reported as a compatibility issue in " & Mode'Image);
            end;
         end loop;
      end Accept_Missing_End;
   begin
      Recorders.Expect_Failure (Truncated, Pictlib.Errors.Source_Unexpected_End, "truncated rect", 16#0030#);
      Recorders.Decode (Truncated, Decoder, Events, Outcome);
      Assert (Outcome.First_Error.Context.Ordinal = 2, "a truncated opcode lost its ordinal");
      Recorders.Expect_Failure (Half_Opcode, Pictlib.Errors.Source_Unexpected_End, "half an opcode",
                      Options => (Strictness => Pictlib.Compatible, others => <>));
      Recorders.Expect_Failure (Truncated_Rows, Pictlib.Errors.Source_Unexpected_End, "truncated rows", 16#0098#);
      Recorders.Decode (Truncated_Rows, Decoder, Events, Outcome);
      Assert (Outcome.First_Error.Context.Row = 1, "a truncated row was not identified");

      Recorders.Expect_Failure
        (Missing_End_After_Pad, Pictlib.Errors.Missing_End_Opcode, "missing end after a pad byte");
      Recorders.Expect_Failure (Missing_End, Pictlib.Errors.Missing_End_Opcode, "missing end");
      Recorders.Expect_Failure (V1_Missing_End, Pictlib.Errors.Missing_End_Opcode, "v1 missing end");
      Accept_Missing_End (Missing_End);
      Accept_Missing_End (Missing_End_After_Pad);
      Accept_Missing_End (V1_Missing_End);
   end Truncation_And_End;

   procedure Trailing_Data (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Trailing : aliased constant Bytes := V1_Picture & Zeros (3);
      Require : constant Decoding.Options := (Require_End_Of_Input => True, others => <>);
      Decoder : Decoding.Decoder;
      Events : Recorders.Recorder;
      Outcome : Pictlib.Results.Result;
   begin
      Recorders.Decode (Trailing, Decoder, Events, Outcome);
      Assert (Pictlib.Results.Succeeded (Outcome), "trailing bytes are not read by default");
      Recorders.Expect_Failure (Trailing, Pictlib.Errors.Trailing_Data, "trailing data", Options => Require);
      Events := (others => <>);
      Recorders.Decode (Trailing, Decoder, Events, Outcome, (Require with delta Strictness => Pictlib.Compatible));
      Assert (Pictlib.Results.Succeeded (Outcome)
              and then Recorders.Has_Warning (Decoder, Pictlib.Errors.Compatibility_Issue),
              "compatible trailing data was not reported");
      Events := (others => <>);
      Recorders.Decode (V1_Picture, Decoder, Events, Outcome, Require);
      Assert (Pictlib.Results.Succeeded (Outcome), "a picture ending at end of input was rejected");
   end Trailing_Data;

   procedure Stream_Limits (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Defaults : constant Pictlib.Limits.Limit_Set := Pictlib.Limits.Default_Limits;
      Huge_Long : aliased constant Bytes := V2_Body (W (16#00D0#) & L (16#7FFF_FFFF#) & W (16#00FF#));
   begin
      Recorders.Expect_Failure (V2_Picture, Pictlib.Errors.Limit_Exceeded, "opcode count",
                      Budget => (Defaults with delta Max_Opcodes => 5), Limit => Pictlib.Opcode_Count_Limit);
      Recorders.Expect_Failure (V2_Picture, Pictlib.Errors.Limit_Exceeded, "header opcode count",
                      Budget => (Defaults with delta Max_Opcodes => 1), Limit => Pictlib.Opcode_Count_Limit);
      Recorders.Expect_Failure (V2_Picture, Pictlib.Errors.Limit_Exceeded, "opcode bytes", 16#0098#,
                      Budget => (Defaults with delta Max_Opcode_Bytes => 31), Limit => Pictlib.Opcode_Byte_Limit);
      Recorders.Expect_Failure (Huge_Long, Pictlib.Errors.Limit_Exceeded, "a 2 GB reserved opcode", 16#00D0#,
                      Limit => Pictlib.Opcode_Byte_Limit);
      Recorders.Expect_Failure (V2_Picture, Pictlib.Errors.Limit_Exceeded, "region bytes", 16#0001#,
                      Budget => (Defaults with delta Max_Region_Bytes => 9), Limit => Pictlib.Region_Byte_Limit);
      Recorders.Expect_Failure (V2_Picture, Pictlib.Errors.Limit_Exceeded, "polygon points", 16#0071#,
                      Budget => (Defaults with delta Max_Polygon_Points => 0), Limit => Pictlib.Polygon_Point_Limit);
      Recorders.Expect_Failure (V2_Picture, Pictlib.Errors.Limit_Exceeded, "picture bytes",
                      Budget => (Defaults with delta Max_Picture_Bytes => 700), Limit => Pictlib.Picture_Byte_Limit);
      Recorders.Expect_Failure (V1_Picture, Pictlib.Errors.Limit_Exceeded, "picture bytes inside the look-ahead",
                      Budget => (Defaults with delta Max_Picture_Bytes => 30), Limit => Pictlib.Picture_Byte_Limit);
   end Stream_Limits;
end Pictlib_Testing.Test_Enumeration;
