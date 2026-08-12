#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

if ! command -v carve >/dev/null 2>&1; then
  echo "SKIP: carve is not installed"
  exit 0
fi

json=$(carve "$repo_dir/examples/smoke.crv" --json)
printf '%s' "$json" | grep -q '"type": "document"'
printf '%s' "$json" | grep -q '"type": "heading"'

if ! command -v sile >/dev/null 2>&1; then
  echo "PASS: Carve exchange AST (SILE is not installed; PDF check skipped)"
  exit 0
fi

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT INT TERM
cd "$work_dir"
sile -o "$work_dir/smoke.pdf" -u inputters.carve "$repo_dir/examples/smoke.crv"
test -s smoke.pdf
echo "PASS: examples/smoke.crv -> smoke.pdf"
