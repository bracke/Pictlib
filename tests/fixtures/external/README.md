# External-oracle fixtures

Produced by `generate.sh`: each source raster (`.ppm`, `.pbm`) was drawn by
ImageMagick and written as PICT by Netpbm `ppmtopict` or ImageMagick, neither of
which shares code with pictlib. The test `external.*` renders every `.pict`
and requires the pixels of its source raster exactly.

| PICT | Writer | Content |
| --- | --- | --- |
| `palette_netpbm.pict` | Netpbm `ppmtopict` | 21x9, 4 colors, 8-bit `PackBitsRect`, odd rowBytes, header version -1 |
| `palette_magick.pict` | ImageMagick 7.1.1 | 21x9, 32-bit `DirectBitsRect` pack type 4, extended header |
| `truecolor_magick.pict` | ImageMagick 7.1.1 | 37x23, 851 colors, `DirectBitsRect` |
| `mono_magick.pict` | ImageMagick 7.1.1 | 30x30 from a 1-bit source, `DirectBitsRect` |
