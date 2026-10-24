# pictlib

Native Ada 2022 Apple QuickDraw PICT codec under active implementation. The
target is decoding of PICT version 1, version 2 and extended version 2 pictures
— raster opcodes, a QuickDraw renderer for vector and text opcodes, and
QuickTime-embedded JPEG images — and encoding of raster PICT version 2.

The current library (Gate M1) reads PICT version 1, version 2 and extended
version 2 containers, with or without the 512-byte file header, and enumerates
every opcode of the picture under explicit resource limits, retaining comments,
font names and other metadata on request. Rendering is not available yet. `Pictlib.Capabilities` lists what is
implemented; everything else is unavailable until its implementation-plan gate
passes.

- [Specification](docs/SPECIFICATION.md)
- [Implementation plan](docs/IMPLEMENTATION_PLAN.md)
- [Public API notes](docs/PUBLIC_API.md)
- [Agent instructions](AGENTS.md)

The reference architecture is [bracke/jpeglib](https://github.com/bracke/jpeglib).
`jpeglib` is also the only production dependency, used to decode JPEG images
embedded in pictures. No C library is used by the production crate.

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
