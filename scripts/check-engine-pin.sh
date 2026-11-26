#!/bin/sh
# Fails when the Dockerfile's engine pin is not a full carve-js commit, and in
# drift mode when that commit is behind the head of the branch it follows.
#
# On the Carve 0.2 line the engine is unreleased, so the image installs
# carve-js from git by commit (`github:markup-carve/carve-js#<sha>`) and the pin
# follows the `main` branch rather than an npm dist-tag. The pinned value is
# parsed out of the Dockerfile, the branch head is read from the GitHub API.
#
# Usage: check-engine-pin.sh [local|drift]. `local` checks only what this repo
# controls and runs on every pull request; `drift` checks only the comparison
# with upstream and runs on a schedule. No argument runs both.
#
# Exit codes: 0 clean, 1 a failure (including the check itself breaking), 3 in
# drift mode when the only finding is a pin behind the branch head.
set -eu

mode=${1:-all}
case "$mode" in
  all|local|drift) ;;
  *) echo "usage: $0 [local|drift]" >&2; exit 2 ;;
esac

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
dockerfile="$repo_dir/Dockerfile"
repo="markup-carve/carve-js"
branch="main"

pinned=$(sed -n 's|.*--prefix /opt/carve .*github:'"$repo"'#\([0-9a-f]*\).*|\1|p' "$dockerfile")

if [ -z "$pinned" ]; then
  echo "FAIL: no engine pin found in Dockerfile."
  echo "      expected a '--prefix /opt/carve ... github:$repo#<sha>' install line."
  exit 1
fi

echo "engine pin (Dockerfile): $repo@$pinned"

if [ "$mode" != drift ]; then
  if [ "${#pinned}" -ne 40 ]; then
    echo "FAIL: the engine pin is not a full 40-character commit SHA."
    exit 1
  fi
  echo "OK: the engine pin is a full commit SHA."
fi

if [ "$mode" = local ]; then
  exit 0
fi

auth=""
if [ -n "${GITHUB_TOKEN:-}" ]; then auth="Authorization: Bearer $GITHUB_TOKEN"; fi
head=$(curl -fsSL ${auth:+-H "$auth"} "https://api.github.com/repos/$repo/commits/$branch" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["sha"])') || head=""

if [ -z "$head" ]; then
  echo "FAIL: could not read the head of $repo $branch from the GitHub API."
  exit 1
fi

echo "branch head ($branch): $head"

if [ "$pinned" = "$head" ]; then
  echo "OK: the engine pin is the head of $branch."
  exit 0
fi

echo "DRIFT: the engine pin is behind $repo $branch."
echo "       move the Dockerfile pin to $head."
if [ "$mode" = drift ]; then exit 3; fi
exit 1
