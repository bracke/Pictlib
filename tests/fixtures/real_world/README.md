# Real-world corpus

Run with `alr --chdir tests exec -- ./bin/pictlib_real_world`. Every picture is
enumerated strictly and rendered compatibly and recoverably with the DejaVu
test fonts; an exception escaping pictlib is a defect, and every outcome must
match `expected.txt` (`--update` rewrites it after review; `--opcodes`
prints each picture's opcode counts). A picture with a `<name>.reference.ppm`
beside it must also render, compatibly, to that raster within 2 of each
component: the outcomes alone are pictlib's own record, the raster another
decoder's.

## `libreoffice/`

LibreOffice's PICT import-filter test files, from
`vcl/qa/cppunit/graphicfilter/data/pict/` of https://github.com/LibreOffice/core
at commit `c678e1be21149d9473c4c85a1571c47735eb7d77` (downloaded 2026-10-24), under the Mozilla Public License 2.0
(`libreoffice/COPYING.MPL`). LibreOffice expects the `pass/` files to load and
the `fail/` files to be rejected without harm.

| File | What it is | pictlib |
| --- | --- | --- |
| `pass/ooo25876-2.pct` | bug report picture: lines and `patOr` polygons on a 16001 x 12828 frame, no file header | decodes and renders; no reference raster: ImageMagick cannot read it, and LibreOffice exports it only placed and antialiased on an A4 page |
| `pass/tdf92789.pct` | bug report picture, 188 x 188 | decodes and renders, as `tdf92789.pct.reference.ppm`: ImageMagick 7.1.1-43's decoding (`magick tdf92789.pct tdf92789.pct.reference.ppm`), reviewed |
| `fail/CVE-2008-1097-1.pct`, `CVE-2012-0277-1.pct`, `CVE-2013-2577-1.pct`, `EDB-19332-1.pct` | exploit reproductions, stored scrambled in LibreOffice's repository, so opaque bytes here | rejected: no version opcode |
| `fail/exception-1.pct` | a picture that made LibreOffice throw | strict: no HeaderOp; compatible: a malformed region; recovering: a partial picture |
| `fail/hang-1.pct` | a picture that made LibreOffice hang | truncated; recovering: a partial picture; no hang |
