# Test fixtures

Fixtures must be independent of pictlib's own encoder. Each fixture records its
provenance next to it (`<name>.txt`): hand-assembled from the opcode tables of
*Inside Macintosh: Imaging With QuickDraw* Appendix A, or a real-world file with
its origin and license. Expected rasters come from an external reference decoder
(ImageMagick, Netpbm `picttoppm`, macOS `sips`) and are reviewed before they are
committed. External tools are test-only oracles.
