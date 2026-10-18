#!/bin/zsh
# Renders the Facekey icon PNGs from the committed SVG sources in tools/icons/.
#
#   tools/make_icons.sh [output-dir]      (default: build/icons)
#
# Writes the 16, 32, 64, 128, 256 and 512 px iconset, the two 1024 px PNGs and the menu bar
# template at 1x and 2x. The sources are rasterised with `qlmanage -t` (ImageMagick's own SVG
# renderer drops strokes), which paints an opaque white page, so the rounded corners and the
# template's transparency are rebuilt with ImageMagick afterwards. The small sizes use the
# design's heavier stroke and, at 32 px and below, a larger head so the frame and figure
# stay apart.
set -eu

ROOT=${0:A:h:h}
SRC=$ROOT/tools/icons
OUT=${1:-$ROOT/build/icons}
command -v magick >/dev/null || { echo "magick is required (brew install imagemagick)" >&2; exit 1; }
mkdir -p "$OUT/iconset"
WORK=$(mktemp -d /private/tmp/make_icons.XXXXXX)
trap 'rm -rf "$WORK"' EXIT

# raster <svg> <stroke-width> <head-radius> <size> <png> -> opaque PNG of the SVG with that stroke and head
raster() {
  local name="$(basename "$1" .svg)-$2-$3-$4"
  sed -E -e "s/stroke-width=\"[0-9.]+\"/stroke-width=\"$2\"/" -e "s/r=\"15\"/r=\"$3\"/" "$1" > "$WORK/$name.svg"
  qlmanage -t -s "$4" -o "$WORK" "$WORK/$name.svg" >/dev/null 2>&1
  mv "$WORK/$name.svg.png" "$5"
}

# rounded <opaque-png> <size> <png> -> the same image clipped to the icon's rounded corners (rx 45 of 200)
rounded() {
  local r=$(( $2 * 45 / 200 ))
  magick "$1" \( -size "${2}x${2}" xc:none -fill white -draw "roundrectangle 0,0,$(( $2 - 1 )),$(( $2 - 1 )),$r,$r" \) \
    -alpha set -compose DstIn -composite "$3"
}

report() { echo "wrote $1 ($(magick identify -format '%wx%h' "$1"))"; }

for size in 16 32 64 128 256 512; do
  case $size in
    16|32) stroke=16; head=18 ;;
    64)    stroke=12; head=15 ;;
    *)     stroke=10; head=15 ;;
  esac
  raster "$SRC/facekey-icon.svg" $stroke $head $size "$WORK/icon_$size.png"
  rounded "$WORK/icon_$size.png" $size "$OUT/iconset/icon_$size.png"
  report "$OUT/iconset/icon_$size.png"
done

# 1024 px: the full-bleed square for Icon Composer, and the rounded icon on the macOS grid
# (824 px inside the template margin, with the soft shadow the design export carries).
raster "$SRC/facekey-icon-square.svg" 10 15 1024 "$OUT/facekey-icon-1024-square.png"
report "$OUT/facekey-icon-1024-square.png"
raster "$SRC/facekey-icon.svg" 10 15 824 "$WORK/icon-824-opaque.png"
rounded "$WORK/icon-824-opaque.png" 824 "$WORK/icon-824.png"
magick -size 1024x1024 xc:none \
  \( "$WORK/icon-824.png" -background black -shadow 35x14+0+10 \) -gravity center -geometry +0+0 -composite \
  "$WORK/icon-824.png" -gravity center -composite "$OUT/facekey-icon-1024.png"
report "$OUT/facekey-icon-1024.png"

# Menu bar template: black on transparent, 18 px and 36 px, with a heavier stroke than the 12 of the source.
for spec in "18 18 facekeyMenuTemplate.png" "36 14 facekeyMenuTemplate-2x.png"; do
  set -- ${=spec}
  raster "$SRC/facekey-menubar-template.svg" $2 15 $1 "$WORK/template-$1.png"
  magick "$WORK/template-$1.png" -alpha off -colorspace gray -negate -write mpr:alpha +delete \
    -size "${1}x${1}" xc:black mpr:alpha -alpha off -compose CopyOpacity -composite "$OUT/$3"
  report "$OUT/$3"
done
