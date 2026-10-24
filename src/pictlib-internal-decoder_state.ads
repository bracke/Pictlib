with Pictlib.Internal.Container;
with Pictlib.Internal.Sessions;
with Pictlib.Pictures;

--  What a public decoder holds besides its lifecycle and options: the session, and the header and its opcodes
--  once read. The public Decoding spec names only this, as jpeglib's names its internal decoder.
package Pictlib.Internal.Decoder_State is
   type State is limited record
      Session : Sessions.Session;
      Info : Pictures.Header_Info;
      Header_Events : Container.Header_Events;
      Header_Event_Count : Natural := 0;
   end record;
end Pictlib.Internal.Decoder_State;
