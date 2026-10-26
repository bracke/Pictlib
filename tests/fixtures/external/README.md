# External-oracle fixtures

Produced by `pictlib_generate` (`alr --chdir=tests run --skip-build pictlib_generate`), which reproduces
these files byte for byte with ImageMagick 7.1.1-43 Q16 and Netpbm 11.5.2 `ppmtopict`, as
`pictlib_generate --check` verifies (it prints the versions it ran with): each source raster (`.ppm`, `.pbm`) was drawn by
ImageMagick and written as PICT by Netpbm `ppmtopict` or ImageMagick, neither of
which shares code with pictlib. The test `external.*` renders every `.pict`
and requires the pixels of its source raster exactly.

| PICT | Writer | Content |
| --- | --- | --- |
| `palette_netpbm.pict` | Netpbm `ppmtopict` | 21x9, 4 colors, 8-bit `PackBitsRect`, odd rowBytes, header version -1 |
| `palette_magick.pict` | ImageMagick 7.1.1 | 21x9, 32-bit `DirectBitsRect` pack type 4, extended header |
| `truecolor_magick.pict` | ImageMagick 7.1.1 | 37x23, 851 colors, `DirectBitsRect` |
| `mono_magick.pict` | ImageMagick 7.1.1 | 30x30 from a 1-bit source, `DirectBitsRect` |
| `truecolor_jpeg.pict` | ImageMagick 7.1.1 | 37x23, `CompressedQuickTime` with a JPEG at quality 95; reference `truecolor_embedded.ppm` |
| `palette_jpeg.pict` | ImageMagick 7.1.1 | 21x9, `CompressedQuickTime` with a JPEG at quality 90; reference `palette_embedded.ppm` |

For the QuickTime pictures the reference raster is the embedded JPEG decoded by
libjpeg (through ImageMagick), and the tests allow the small differences two
conforming JPEG decoders may show. `small.jpg` (8x6, quality 100, no chroma
subsampling) and its libjpeg decoding `small_decoded.ppm` are wrapped by the
tests in hand-built QuickTime opcodes.
