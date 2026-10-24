# Contributing

Follow the milestone order documented in `docs/IMPLEMENTATION_PLAN.md`; the
contract is `docs/SPECIFICATION.md`. Production code must remain Ada-only, must
not introduce codec wrappers or C bindings, and may depend only on `jpeglib` and `textrender`
beyond the toolchain. Test-only dependencies stay in the `tests` crate.

Use Alire for all GNAT/GPR/toolchain work. Do not call system GNAT, GPRBuild,
GNATprove, or GNATdoc directly from `PATH`; use `alr` so the pinned toolchain is
selected.

Tests use AUnit. All test and release tooling and scripting is Ada, in the tests
crate, using `../project_tools` for test/release policy; CI steps are single
commands that run those tools.

Keep the repository buildable after every change. The day-to-day gate is:

```sh
alr --chdir tests build
alr --chdir tests run --skip-build pictlib_check
```
