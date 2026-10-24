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
- [Agent instructions](AGENTS.md)

The reference architecture is [bracke/jpeglib](https://github.com/bracke/jpeglib).
`jpeglib` decodes JPEG images embedded in pictures and
[textrender](../textrender) rasterizes TrueType text; they are the only
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

## Build and test

All commands use Alire so the declared GNAT 15 toolchain is selected:

```sh
alr build
alr --chdir tests build
alr --chdir tests exec -- ./bin/pictlib_tests
```

`./scripts/check_all.sh` runs the same sequence. AUnit failures produce a
nonzero process exit status.

The library-complete gate runs every check -- source policy, unit tests, the
real-world corpus, fuzzing, the SPARK proofs and encoder conformance against
ImageMagick and LibreOffice (test-time only):

```sh
alr --chdir tests exec -- ./bin/pictlib_complete
```

## License

MIT; see [LICENSE](LICENSE).
