#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

if ! command -v carve >/dev/null 2>&1; then
  echo "SKIP: carve is not installed"
  exit 0
fi

if ! command -v sile >/dev/null 2>&1; then
  echo "SKIP: sile is not installed"
  exit 0
fi

# SILE runs the assertions, so SU.ast and pl.class are the real ones. The
# script puts the working tree ahead of any installed copy on package.path, so
# what it measures is the file you just edited.
#
# The path travels in the environment rather than being interpolated into the
# Lua snippet: a checkout path containing a quote would otherwise be spliced
# into the source SILE evaluates.
CARVE_SILE_REPO="$repo_dir" exec sile \
  -e 'dofile(os.getenv("CARVE_SILE_REPO") .. "/test/renderer.lua")'
