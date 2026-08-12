#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

if ! command -v pandoc-carve >/dev/null 2>&1; then
  echo "SKIP: pandoc-carve is not installed"
  exit 0
fi

json=$(pandoc-carve "$repo_dir/examples/smoke.crv" -t json)
printf '%s' "$json" | grep -q '"pandoc-api-version"'
printf '%s' "$json" | grep -q '"t":"Header"'

if ! command -v sile >/dev/null 2>&1; then
  echo "PASS: Carve to Pandoc JSON (SILE is not installed; PDF check skipped)"
  exit 0
fi

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT INT TERM
cd "$work_dir"
sile -u inputters.carve "$repo_dir/examples/smoke.crv"
test -s smoke.pdf
echo "PASS: examples/smoke.crv -> smoke.pdf"
