# pictlib

Native Ada 2022 Apple QuickDraw PICT codec. It decodes PICT version 1, version
2 and extended version 2 pictures, with or without the 512-byte file header:
it enumerates every opcode under explicit resource limits, retains comments,
font names and other metadata on request, and renders the picture into a
caller-owned RGB or RGBA view -- bitmaps and pixmaps, QuickDraw's vector shapes
with patterns, colors, transfer modes and clipping, text in TrueType fonts the
caller maps to the picture's font names and IDs, and JPEG images embedded
through QuickTime. It encodes raster PICT version 2. `Pictlib.Capabilities`
lists what is implemented.

- [Specification](docs/SPECIFICATION.md)
- [Implementation plan](docs/IMPLEMENTATION_PLAN.md)
- [Public API notes](docs/PUBLIC_API.md)
- [Limits and safety](docs/limits_and_safety.md)
- [Invariant registry](docs/invariants.md)
- [Proof profile](docs/proof_profile.md)
- [Security policy](SECURITY.md)
- [Agent instructions](AGENTS.md)

The reference architecture is [bracke/jpeglib](https://github.com/bracke/jpeglib).
`jpeglib` decodes JPEG images embedded in pictures and
[textrender](https://github.com/bracke/textrender) rasterizes TrueType text; they are the only
production dependencies. No C library is used by the production crate.

## Capabilities

| Area | Status |
| --- | --- |
| Containers | PICT version 1, 2 and extended 2, with or without the 512-byte file header |
| Opcodes | every opcode enumerated with ordinal, offset and length; metadata retained on request |
| Raster | BitMaps and PixMaps at every depth and pack type, scaling, clip and mask regions |
| Vector | lines, rects, round rects, ovals, arcs, polygons, regions; patterns, colors, transfer modes |
| Text | TrueType fonts the caller maps to Mac font names and IDs, through textrender |
| QuickTime | embedded JPEG through jpeglib |
| Encoding | raster PICT 2: 32-bit direct, 8-bit indexed, 1-bit |
| Assurance | hostile-input limits, SPARK proofs, fuzzing, a real-world corpus, independent-reader conformance |

Open: the shape and text rules have not been compared with real QuickDraw
(that needs classic Mac OS under emulation), and rendering at an extended
header's native resolution is not implemented. See
[the plan](docs/IMPLEMENTATION_PLAN.md).

## Use

Encode an image into a picture, then decode the picture and render it into a
view of its frame's size. This is the body of
[`pictlib_example`](tests/src/mains/pictlib_example.adb), which the tests crate
builds, so the code stays true to the API (`pictlib_check` holds this README to
it):

```ada
   --  Encode: one image becomes one picture.
   Pictlib.Streams.Open (Output, Picture);
   Pictlib.Encoding.Initialize (Encoder, Output'Access);
   Outcome := Pictlib.Encoding.Encode (Encoder, (Descriptor => Layout, Storage => Pixels));
   if Pictlib.Results.Succeeded (Outcome) then
      Outcome := Pictlib.Encoding.Finish (Encoder);
   end if;
   if not Pictlib.Results.Succeeded (Outcome) then
      Ada.Text_IO.Put_Line ("encode failed: " & Outcome.First_Error.Code'Image);
      return;
   end if;

   --  Decode: read the header for the frame, then render into a view of the frame's size.
   declare
      Length : constant Natural := Natural (Pictlib.Encoding.Bytes_Written (Encoder));
      Input : aliased Pictlib.Streams.Memory_Source;
      Decoder : Pictlib.Decoding.Decoder;
      Canvas : constant Pictlib.Streams.Byte_Array_Access := new Pictlib.Streams.Byte_Array (1 .. Image_Bytes);
   begin
      Pictlib.Streams.Open (Input, new Pictlib.Streams.Byte_Array'(Picture (1 .. Length)));
      Pictlib.Decoding.Initialize (Decoder, Input'Access);
      Outcome := Pictlib.Decoding.Read_Header (Decoder);
      if Pictlib.Results.Succeeded (Outcome) then
         Outcome := Pictlib.Decoding.Render (Decoder, (Descriptor => Layout, Storage => Canvas));
      end if;
      if Pictlib.Results.Succeeded (Outcome) and then Canvas.all = Pixels.all then
         Ada.Text_IO.Put_Line ("a" & Length'Image & "-byte picture decoded back to its pixels");
      else
         Ada.Text_IO.Put_Line ("decode failed: " & Outcome.First_Error.Code'Image);
      end if;
   end;
```

Run it with `alr --chdir tests exec -- ./bin/pictlib_example`.

## Build and test

All commands use Alire so the declared GNAT 15 toolchain is selected, and all
tooling is Ada, in the `tests` crate. The day-to-day gate builds the library on
its own, checks the source policy and runs the AUnit suite:

```sh
alr --chdir tests build
alr --chdir tests run --skip-build pictlib_check
```

`alr test` runs the same. The library-complete gate adds the real-world corpus,
fuzzing, the SPARK proofs and encoder conformance against ImageMagick and
LibreOffice (test-time only; `--args=--without-conformance` leaves that out):

```sh
alr --chdir tests run --skip-build pictlib_complete
```

`pictlib_generate` regenerates the external fixtures with ImageMagick and
Netpbm.

## License

MIT; see [LICENSE](LICENSE).
