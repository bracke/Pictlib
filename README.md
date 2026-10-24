# pictlib

Native Ada 2022 Apple QuickDraw PICT codec under active implementation. The
target is decoding of PICT version 1, version 2 and extended version 2 pictures
— raster opcodes, a QuickDraw renderer for vector and text opcodes, and
QuickTime-embedded JPEG images — and encoding of raster PICT version 2.

The current library (Gate M1) reads PICT version 1, version 2 and extended
version 2 containers, with or without the 512-byte file header, and enumerates
every opcode of the picture under explicit resource limits, retaining comments,
font names and other metadata on request. Since Gate M2 it renders a picture's
bitmaps and pixmaps — every depth and pack type, with scaling, clip regions and
masks — into a caller-owned RGB or RGBA view, and since Gate M3 its QuickDraw
lines, rectangles, round rects, ovals, arcs, polygons and regions with
patterns, colors, transfer modes and clipping. Since Gate M4 it draws text
with TrueType fonts the caller maps to the picture's font names and IDs
(`Pictlib.Fonts`); pictlib ships no fonts. QuickTime images are reported as
unsupported until their gate passes. `Pictlib.Capabilities` lists what is
implemented; everything else is unavailable until its implementation-plan gate
passes.

- [Specification](docs/SPECIFICATION.md)
- [Implementation plan](docs/IMPLEMENTATION_PLAN.md)
- [Public API notes](docs/PUBLIC_API.md)
- [Agent instructions](AGENTS.md)

The reference architecture is [bracke/jpeglib](https://github.com/bracke/jpeglib).
`jpeglib` decodes JPEG images embedded in pictures and
[textrender](../textrender) rasterizes TrueType text; they are the only
production dependencies. No C library is used by the production crate.

## Build and test

All commands use Alire so the declared GNAT 15 toolchain is selected:

```sh
alr build
alr --chdir tests build
alr --chdir tests exec -- ./bin/pictlib_tests
```

`./scripts/check_all.sh` runs the same sequence. AUnit failures produce a
nonzero process exit status.

## License

MIT; see [LICENSE](LICENSE).
