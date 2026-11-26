#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

if ! command -v carve >/dev/null 2>&1; then
  echo "SKIP: carve is not installed"
  exit 0
fi

json=$(carve ast "$repo_dir/examples/smoke.crv")
printf '%s' "$json" | grep -q '"type":"document"'
printf '%s' "$json" | grep -q '"type":"heading"'

# The composite-figure example only tests something if the installed engine
# actually emits the node, or the renderer's group handler would never run.
json=$(carve ast "$repo_dir/examples/composite-figure.crv")
printf '%s' "$json" | grep -q '"type":"figure_group"'

if ! command -v sile >/dev/null 2>&1; then
  echo "PASS: Carve tree (SILE is not installed; PDF check skipped)"
  exit 0
fi

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT INT TERM
cd "$work_dir"
sile -o "$work_dir/smoke.pdf" -u inputters.carve "$repo_dir/examples/smoke.crv"
test -s smoke.pdf
echo "PASS: examples/smoke.crv -> smoke.pdf"
sile -o "$work_dir/composite-figure.pdf" -u inputters.carve "$repo_dir/examples/composite-figure.crv"
test -s composite-figure.pdf
echo "PASS: examples/composite-figure.crv -> composite-figure.pdf"
# SILE prints one [n] per shipped page.
sile -o "$work_dir/page-break.pdf" -u inputters.carve "$repo_dir/examples/page-break.crv" > page-break.log 2>&1 \
  || { cat page-break.log; exit 1; }
test -s page-break.pdf
pages=$(grep -o '\[[0-9]*\]' page-break.log | wc -l)
test "$pages" -eq 2 || { echo "FAIL: examples/page-break.crv gave $pages pages, expected 2"; exit 1; }
echo "PASS: examples/page-break.crv -> 2 pages"
