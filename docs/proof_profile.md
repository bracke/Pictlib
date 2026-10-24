# Proof Profile

`pictlib_prove` runs GNATprove, through `alr exec` (never from `PATH`), at
`--level=0` on the proof-designated units of `proof/pictlib_proof.gpr`, and
fails on any unproved check, any medium or high diagnostic, or a declared SPARK
body that was skipped:

```sh
alr --chdir tests exec -- ./bin/pictlib_prove
```

| Unit | What is proved |
| --- | --- |
| `Pictlib.Internal.Checked_Arithmetic` | `Add` and `Multiply` never overflow and report overflow instead of wrapping. |
| `Pictlib.Images` | `Bytes_Per_Pixel`, `Minimum_Row_Bytes` and `Descriptor_Is_Valid`: the stride is compared before `stride * (height - 1)` is formed, so the row-span check cannot overflow. The access-bearing `Is_Valid` checks only add the null test and stay outside SPARK. |
| `Pictlib.Opcodes` | `Rule_For`, `Is_Reserved` and `Name` are total over all 65 536 opcodes, free of runtime errors. |
| `Pictlib.Internal.PackBits` | `Unpack` -- which reads hostile pixel rows -- never indexes outside its input or output and writes at most the output's length (its postcondition); `Worst_Case` cannot overflow. `Pack` (the encoder's, over its own rows) is runtime-checked. |

Everything else is runtime-checked: the code that reads streams, renders and
calls jpeglib and textrender. The invariant registry, `docs/invariants.md`,
names the runtime coverage of each.
