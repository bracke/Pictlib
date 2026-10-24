#!/bin/sh
# Regenerates the external-oracle fixtures: source rasters drawn by ImageMagick,
# written as PICT by two independent encoders. Tests render each PICT with
# pictlib and require the source raster exactly. Test-time tooling only.
#
# Generated 2026-10-24 with ImageMagick 7.1.1-43 Q16 and Netpbm ppmtopict.
set -eu
cd "$(dirname "$0")"

magick -size 21x9 xc:white -fill red -draw "rectangle 2,1 8,5" \
  -fill '#0080ff' -draw "rectangle 12,2 18,7" -fill black -draw "point 20,8" -depth 8 palette.ppm
magick -size 37x23 xc: -channel R -fx 'i/w' -channel G -fx 'j/h' -channel B -fx '(i*j)%7/7' +channel \
  -depth 8 truecolor.ppm
magick -size 30x30 xc:white -fill black -draw "rectangle 3,3 20,20" -monochrome mono.pbm

ppmtopict palette.ppm > palette_netpbm.pict     # 8-bit PackBitsRect, header version -1
magick palette.ppm palette_magick.pict          # 32-bit DirectBitsRect, pack type 4, extended header
magick truecolor.ppm truecolor_magick.pict      # 851 colors, DirectBitsRect
magick mono.pbm mono_magick.pict                # a 1-bit source, written as DirectBitsRect
