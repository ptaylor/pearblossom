#!/bin/zsh
# Builds and runs the CXF placement comparison harness (Scripts/cxf_compare.swift).
#
# Usage:
#   Scripts/cxf_compare.sh [--width N] [--out DIR] [--fit] [--picasa-crop] [--rules a,b] <file.cxf> <picasa-export.jpg> ...
#
# Each .cxf is paired with the JPEG Picasa exported for it. The harness composites the real
# source photos with the CXF geometry and reports the mean pixel error per placement rule;
# `production` is the importer's own CXFCanvasGeometry.layerCenter. --fit adds a per-photo
# offset search (the residual left after the production rule), and --out writes side-by-side
# PNGs (Picasa left, Pearblossom right) for visual checks. Picasa.ini rotations are always
# applied, as the importer applies them; --picasa-crop also applies Picasa.ini crops, which
# the importer does not import yet.
set -euo pipefail

repo="${0:A:h:h}"
import_dir="$repo/Sources/Pearblossom/Import"
build_dir="$repo/.build/cxf-compare"
binary="$build_dir/cxf_compare"
mkdir -p "$build_dir"

sources=(
  "$repo/Scripts/cxf_compare.swift"
  "$import_dir/CXFDocument.swift"
  "$import_dir/CXFError.swift"
  "$import_dir/CXFCanvasGeometry.swift"
  "$import_dir/WinePathTranslator.swift"
  "$import_dir/PicasaINI.swift"
  "$repo/Sources/Pearblossom/Utilities/ImageDimensions.swift"
)

# Rebuild when any source is newer than the binary.
if [[ ! -x "$binary" ]] || [[ -n "$(find "${sources[@]}" -newer "$binary" 2>/dev/null)" ]]; then
  swiftc -O -parse-as-library "${sources[@]}" -o "$binary"
fi

exec "$binary" "$@"
