#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

lua_bin=""
for candidate in lua lua5.4 lua5.3 lua5.1 luajit; do
  if command -v "$candidate" >/dev/null 2>&1; then
    lua_bin=$candidate
    break
  fi
done

if [ -n "$lua_bin" ]; then
  (cd "$repo_dir" && "$lua_bin" test/figuregroup.lua)
else
  echo "SKIP: no Lua interpreter for the carve.figuregroup unit test"
fi

if ! command -v pandoc-carve >/dev/null 2>&1; then
  echo "SKIP: pandoc-carve is not installed"
  exit 0
fi

json=$(pandoc-carve "$repo_dir/examples/smoke.crv" -t json)
printf '%s' "$json" | grep -q '"pandoc-api-version"'
printf '%s' "$json" | grep -q '"t":"Header"'

# The converter has to map a bare `::: figure` opener to a Pandoc Figure whose
# panels are nested Figures and Tables, and a titled opener to a plain Div.
# Everything this repository does with composite figures rests on that split,
# so check it rather than assume the installed converter is recent enough.
composite=$(pandoc-carve "$repo_dir/examples/composite-figure.crv" -t json)
printf '%s' "$composite" \
  | grep -q '{"t":"Figure","c":\[\["fig-mixed",\["columns-2"\],\[\]\]'
printf '%s' "$composite" | grep -q '"t":"Div","c":\[\["",\["admonition","figure"\]'

if ! command -v sile >/dev/null 2>&1; then
  echo "PASS: Carve to Pandoc JSON (SILE is not installed; PDF check skipped)"
  exit 0
fi

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT INT TERM
cd "$work_dir"
sile -o "$work_dir/smoke.pdf" -u inputters.carve "$repo_dir/examples/smoke.crv"
test -s smoke.pdf
echo "PASS: examples/smoke.crv -> smoke.pdf"

for example in composite-figure:panels composite-figure-nested:nested; do
  name=${example%:*}
  mode=${example#*:}
  cp "$repo_dir/examples/$name.crv" "$work_dir/$name.crv"
  sile -o "$work_dir/$name.pdf" -u inputters.carve "$work_dir/$name.crv"
  test -s "$work_dir/$name.pdf"
  if [ -z "$lua_bin" ]; then
    echo "SKIP: no Lua interpreter to read the list entries of $name"
    continue
  fi
  "$lua_bin" "$repo_dir/test/toccheck.lua" "$mode" "$work_dir/$name.toc"
  echo "PASS: examples/$name.crv -> $name.pdf"
done
