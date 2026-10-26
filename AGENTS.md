# Agent instructions — pictlib

Native Ada 2022 Apple QuickDraw PICT decoder, renderer and encoder. `docs/SPECIFICATION.md` is the authoritative
implementation contract; `docs/IMPLEMENTATION_PLAN.md` is the dependency-ordered execution plan. Follow the earliest
incomplete task and its acceptance gate.

Use `../jpeglib` (https://github.com/bracke/jpeglib) as the architectural reference for source/destination
interfaces, structured errors and results, resource budgets, package organization, tests and Alire conventions.
`jpeglib` is a production dependency: it decodes JPEG images embedded through QuickTime opcodes (`16#8200#`,
`16#8201#`), and only through its public API. `../textrender` is the other one: it rasterizes the TrueType fonts
text is drawn with, through its public API. Do not copy JPEG-only abstractions, and do not introduce any other
production dependency or any binding to a C library. pictlib ships no fonts; tests use the committed DejaVu
fixtures.

This crate pins its GNAT toolchain via Alire (`gnat_native = "^15"`). Build and test with `alr`, not system
GNAT / GPRBuild / GNATprove / GNATdoc tools on `PATH` — `alr exec -- gnatls --version` must report the pinned GNAT.

```sh
alr --chdir=tests build
alr --chdir=tests run --skip-build pictlib_check
```

`pictlib_check` is the day-to-day gate: it builds the library on its own, checks the source policy and runs the
AUnit suite (`alr test` runs it too). `pictlib_complete` is the library-complete gate and needs ImageMagick,
LibreOffice and GNATprove. All tooling and scripting is Ada, in the tests crate: add a tool there rather than a
shell or Python script, and keep CI steps to single commands. Keep the repository buildable after every change and
add a `CHANGELOG.md` entry for each change. Incremental builds report style diagnostics only for units they
recompile: rely on `pictlib_check`, not on a quiet build.

PICT input is hostile input. Every feature requires checked arithmetic, bounded memory and work under
`Pictlib.Limits`, non-raising diagnostic behavior, malformed-input tests and state machine consistency. Output
pixels go to caller-owned views; large working buffers live on the heap, not the stack. A `Capabilities` constant
is `True` only when its feature is exercised by tests; unimplemented paths report `Unsupported_Feature`, never a
stub success.

Never accept a test passing only because `pictlib` encodes and decodes its own incorrect output: use independent PICT
fixtures and test-only external oracles. Tests use AUnit in the child `tests` crate; test and release tooling uses
`../project_tools`. Resolve contract mismatches by revising the specification first.
