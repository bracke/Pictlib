# Test fixtures

Fixtures must be independent of pictlib's own encoder. Each directory's README
records where its files came from:

- `external/` — pictures written by ImageMagick and Netpbm `ppmtopict` from
  rasters ImageMagick drew, reproduced by `pictlib_generate`, with the source
  rasters the `external.*` tests require exactly;
- `real_world/` — LibreOffice's PICT test files, their origin, commit and
  license, and a reference raster where another decoder could read one;
- `fonts/` — the DejaVu fonts the text tests draw with, and their license.

Pictures the unit tests build in code are hand-assembled from the opcode tables
of *Inside Macintosh: Imaging With QuickDraw* Appendix A (`Pictlib_Testing.Builders`).
Expected rasters come from an external decoder (ImageMagick, LibreOffice) or are
worked out by hand, and are reviewed before they are committed. External tools
are test-only oracles.
