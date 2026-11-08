#!/bin/zsh
# Builds and runs the CXF placement comparison harness (Scripts/cxf_compare.swift).
#
# Usage:
#   Scripts/cxf_compare.sh [--width N] [--out DIR] [--fit] [--picasa-ini] [--rules a,b] <file.cxf> <picasa-export.jpg> ...
#
# Each .cxf is paired with the JPEG Picasa exported for it. The harness composites the real
# source photos with the CXF geometry and reports the mean pixel error per placement rule;
# `production` is the importer's own CXFCanvasGeometry.layerCenter. --fit adds a per-photo
# offset search (the residual left after the production rule), and --out writes side-by-side
# PNGs (Picasa left, Pearblossom right) for visual checks. --picasa-ini draws each source
# with the rotate/crop edits from its Picasa.ini, which the importer does not yet read.
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
)

# Rebuild when any source is newer than the binary.
if [[ ! -x "$binary" ]] || [[ -n "$(find "${sources[@]}" -newer "$binary" 2>/dev/null)" ]]; then
  swiftc -O -parse-as-library "${sources[@]}" -o "$binary"
fi

exec "$binary" "$@"
