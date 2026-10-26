package body Pictlib.Internal.Decoder_Core is
   procedure Discard (Object : in out Core) is
   begin
      Object.Info := (others => <>);
      Object.Header_Events := [others => (others => <>)];
      Object.Header_Event_Count := 0;
   end Discard;
end Pictlib.Internal.Decoder_Core;
