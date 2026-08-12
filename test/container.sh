#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
docker build --tag carve-sile-test "$repo_dir"
docker run --rm --entrypoint /bin/sh carve-sile-test -c ./test/smoke.sh
