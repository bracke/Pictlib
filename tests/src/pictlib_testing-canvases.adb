with Ada.Strings.Unbounded;
with AUnit.Assertions;
with Pictlib_Testing.Recorders;

package body Pictlib_Testing.Canvases is
   use type Pictlib.Images.RGB_Color;

   function View
     (Storage : not null access Pictlib.Streams.Byte_Array;
      Width, Height : Positive;
      Format : Pictlib.Pixel_Format := Pictlib.RGB_24;
      Stride : Natural := 0) return Pictlib.Images.Mutable_Image_View
   is
      Row : constant Natural := Width * Natural (Pictlib.Images.Bytes_Per_Pixel (Format));
      Step : constant Natural := (if Stride = 0 then Row else Stride);
   begin
      return
        (Descriptor =>
           (Width => Pictlib.Image_Width (Width),
            Height => Pictlib.Image_Height (Height),
            Format => Format,
            Stride => Pictlib.Row_Stride (Step),
            Accessible_Bytes => Pictlib.Byte_Count (Step * (Height - 1) + Row)),
         Storage => Storage);
   end View;

   procedure Render
     (Input : aliased Pictlib.Streams.Byte_Array;
      Decoder : in out Pictlib.Decoding.Decoder;
      Output : Pictlib.Images.Mutable_Image_View;
      Outcome : out Pictlib.Results.Result;
      Options : Pictlib.Decoding.Options := (others => <>);
      Budget : Pictlib.Limits.Limit_Set := Pictlib.Limits.Default_Limits;
      Max_Transfer : Pictlib.Byte_Count := Pictlib.Byte_Count'Last)
   is
   begin
      Recorders.Start (Input, Decoder, Options, Budget, Max_Transfer);
      Outcome := Pictlib.Decoding.Read_Header (Decoder);
      if Pictlib.Results.Succeeded (Outcome) then
         Outcome := Pictlib.Decoding.Render (Decoder, Output);
      end if;
   end Render;

   procedure Expect_Raster
     (Input : aliased Pictlib.Streams.Byte_Array;
      Width, Height : Positive;
      Expected : String;
      Label : String;
      Options : Pictlib.Decoding.Options := (others => <>);
      Max_Transfer : Pictlib.Byte_Count := Pictlib.Byte_Count'Last)
   is
      use AUnit.Assertions;
      use type Pictlib.Decoding.Decoder_State;
      Storage : aliased Pictlib.Streams.Byte_Array := [1 .. 3 * Width * Height => 16#EE#];
      Output : constant Pictlib.Images.Mutable_Image_View := View (Storage'Access, Width, Height);
      Decoder : Pictlib.Decoding.Decoder;
      Outcome : Pictlib.Results.Result;
   begin
      Render (Input, Decoder, Output, Outcome, Options, Max_Transfer => Max_Transfer);
      Assert (Pictlib.Results.Succeeded (Outcome),
              Label & ": render failed with " & Outcome.First_Error.Code'Image & " at opcode"
              & Outcome.First_Error.Context.Op'Image);
      Assert (Pictlib.Decoding.State (Decoder) = Pictlib.Decoding.Finished, Label & ": the decoder did not finish");
      Assert (Picture_Of (Output) = Expected, Label & ": rendered " & Picture_Of (Output) & ", expected " & Expected);
   end Expect_Raster;

   procedure Expect_Failure
     (Input : aliased Pictlib.Streams.Byte_Array;
      Width, Height : Positive;
      Code : Pictlib.Errors.Error_Code;
      Label : String;
      Op : Pictlib.Opcode := 0;
      Options : Pictlib.Decoding.Options := (others => <>);
      Budget : Pictlib.Limits.Limit_Set := Pictlib.Limits.Default_Limits;
      Limit : Pictlib.Limit_Kind := Pictlib.No_Limit;
      State : Pictlib.Decoding.Decoder_State := Pictlib.Decoding.Failed)
   is
      use AUnit.Assertions;
      use type Pictlib.Decoding.Decoder_State;
      use type Pictlib.Errors.Error_Code;
      use type Pictlib.Limit_Kind;
      use type Pictlib.Opcode;
      Storage : aliased Pictlib.Streams.Byte_Array := [1 .. 3 * Width * Height => 0];
      Decoder : Pictlib.Decoding.Decoder;
      Outcome : Pictlib.Results.Result;
   begin
      Render (Input, Decoder, View (Storage'Access, Width, Height), Outcome, Options, Budget);
      Assert (Outcome.First_Error.Code = Code,
              Label & ": expected " & Code'Image & ", got " & Outcome.First_Error.Code'Image);
      Assert (Op = 0 or else (Outcome.First_Error.Context.Has_Opcode and then Outcome.First_Error.Context.Op = Op),
              Label & ": the failing opcode was not recorded");
      Assert (Limit = Pictlib.No_Limit or else Outcome.First_Error.Context.Limit = Limit,
              Label & ": expected the " & Limit'Image & ", got " & Outcome.First_Error.Context.Limit'Image);
      Assert (Pictlib.Decoding.State (Decoder) = State,
              Label & ": the decoder is " & Pictlib.Decoding.State (Decoder)'Image & ", expected " & State'Image);
      Assert (Pictlib.Decoding.Last_Error (Decoder).Code
              = (if State = Pictlib.Decoding.Failed then Code else Pictlib.Errors.No_Error),
              Label & ": the decoder's last error is " & Pictlib.Decoding.Last_Error (Decoder).Code'Image);
   end Expect_Failure;

   procedure Expect_Lenient
     (Input : aliased Pictlib.Streams.Byte_Array;
      Width, Height : Positive;
      Expected : String;
      Code : Pictlib.Errors.Warning_Code;
      Label : String;
      Strictness : Pictlib.Strictness_Mode := Pictlib.Compatible)
   is
      use AUnit.Assertions;
      Storage : aliased Pictlib.Streams.Byte_Array := [1 .. 3 * Width * Height => 0];
      Output : constant Pictlib.Images.Mutable_Image_View := View (Storage'Access, Width, Height);
      Decoder : Pictlib.Decoding.Decoder;
      Outcome : Pictlib.Results.Result;
   begin
      Render (Input, Decoder, Output, Outcome, (Strictness => Strictness, others => <>));
      Assert (Pictlib.Results.Succeeded (Outcome), Label & ": lenient render failed with "
              & Outcome.First_Error.Code'Image);
      Assert (Recorders.Has_Warning (Decoder, Code), Label & ": no " & Code'Image & " warning");
      Assert (Picture_Of (Output) = Expected, Label & ": rendered " & Picture_Of (Output) & ", expected " & Expected);
   end Expect_Lenient;

   function Least_Drawing_Work
     (Input : aliased Pictlib.Streams.Byte_Array;
      Width, Height : Positive;
      Label : String;
      Options : Pictlib.Decoding.Options := (others => <>);
      Budget : Pictlib.Limits.Limit_Set := Pictlib.Limits.Default_Limits;
      High : Pictlib.Pixel_Count := 1_073_741_824) return Pictlib.Pixel_Count
   is
      use AUnit.Assertions;
      use type Pictlib.Errors.Error_Code;
      use type Pictlib.Limit_Kind;
      use type Pictlib.Pixel_Count;
      Storage : aliased Pictlib.Streams.Byte_Array := [1 .. 3 * Width * Height => 0];
      Decoder : Pictlib.Decoding.Decoder;
      Outcome : Pictlib.Results.Result;
      Low : Pictlib.Pixel_Count := 0;
      Top : Pictlib.Pixel_Count := High;
      Middle : Pictlib.Pixel_Count;
   begin
      while Low < Top loop
         Middle := (Low + Top) / 2;
         Render (Input, Decoder, View (Storage'Access, Width, Height), Outcome, Options,
                 (Budget with delta Max_Drawing_Work => Middle));
         if Pictlib.Results.Succeeded (Outcome) then
            Top := Middle;
         else
            Assert (Outcome.First_Error.Code = Pictlib.Errors.Limit_Exceeded
                    and then Outcome.First_Error.Context.Limit = Pictlib.Drawing_Work_Limit,
                    Label & ": failed with " & Outcome.First_Error.Code'Image & " under a drawing budget of"
                    & Middle'Image);
            Low := Middle + 1;
         end if;
      end loop;
      return Top;
   end Least_Drawing_Work;

   function Pixel (Output : Pictlib.Images.Mutable_Image_View; X, Y : Natural) return Pictlib.Images.RGB_Color is
      At_Pixel : constant Positive :=
        Output.Storage'First + Y * Natural (Output.Descriptor.Stride) + 3 * X;
   begin
      return (Output.Storage (At_Pixel), Output.Storage (At_Pixel + 1), Output.Storage (At_Pixel + 2));
   end Pixel;

   function Letter (Color : Pictlib.Images.RGB_Color) return Character is
     (if Color = (16#FF#, 16#FF#, 16#FF#) then 'W'
      elsif Color = (0, 0, 0) then 'B'
      elsif Color = (16#FF#, 0, 0) then 'R'
      elsif Color = (0, 16#FF#, 0) then 'G'
      elsif Color = (0, 0, 16#FF#) then 'U'
      elsif Color = (16#FF#, 16#FF#, 0) then 'Y'
      else '?');

   function Picture_Of (Output : Pictlib.Images.Mutable_Image_View) return String is
      Result : Ada.Strings.Unbounded.Unbounded_String;
   begin
      for Y in 0 .. Natural (Output.Descriptor.Height) - 1 loop
         if Y > 0 then
            Ada.Strings.Unbounded.Append (Result, '/');
         end if;
         for X in 0 .. Natural (Output.Descriptor.Width) - 1 loop
            Ada.Strings.Unbounded.Append (Result, Letter (Pixel (Output, X, Y)));
         end loop;
      end loop;
      return Ada.Strings.Unbounded.To_String (Result);
   end Picture_Of;
end Pictlib_Testing.Canvases;
