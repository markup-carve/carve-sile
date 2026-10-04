#!/bin/sh
# Fails when the Dockerfile's current-lane engine pin is not the newest release
# of @markup-carve/carve on npm, and when the fixture lane's version is spelled
# inconsistently across the files that have to agree on it.
#
# The two compared values come from different places on purpose: the pinned one
# is parsed out of the Dockerfile, the current one is read from the npm registry.
#
# Usage: check-engine-pin.sh [local|drift]. `local` checks only what this repo
# controls and runs on every pull request; `drift` checks only the comparison
# with the npm registry and runs on a schedule. No argument runs both.
set -eu

mode=${1:-all}
case "$mode" in
  all|local|drift) ;;
  *) echo "usage: $0 [local|drift]" >&2; exit 2 ;;
esac

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
dockerfile="$repo_dir/Dockerfile"
package="@markup-carve/carve"
status=0

pinned=$(sed -n 's|.*--prefix /opt/carve .*'"$package"'@\([0-9][0-9A-Za-z.-]*\).*|\1|p' "$dockerfile")
fixture=$(sed -n 's|.*--prefix /opt/carve-\([0-9][0-9A-Za-z.-]*\) .*'"$package"'@\([0-9][0-9A-Za-z.-]*\).*|\1 \2|p' "$dockerfile")

if [ -z "$pinned" ]; then
  echo "FAIL: no current-lane engine pin found in Dockerfile."
  echo "      expected a '--prefix /opt/carve ... $package@<version>' install line."
  exit 1
fi

echo "current-lane pin (Dockerfile): $pinned"

if [ "$mode" != local ]; then
  latest=$(curl -fsSL "https://registry.npmjs.org/$(printf %s "$package" | sed 's|/|%2f|')" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["dist-tags"]["latest"])')

  if [ -z "$latest" ]; then
    echo "FAIL: could not read the latest dist-tag for $package from the npm registry."
    exit 1
  fi

  echo "latest release (npm registry): $latest"

  if [ "$pinned" = "$latest" ]; then
    echo "OK: the current lane is pinned at the newest release."
  else
    echo "FAIL: the current-lane engine pin is stale."
    echo "      bump $package@$pinned to $package@$latest in the Dockerfile."
    status=1
  fi
fi

# The fixture lane is a deliberate older engine, so it is never compared against
# the latest release. What it does have to satisfy: the version in its install
# line, the prefix directory it installs into, its wrapper and the name the tests
# invoke all have to name the same version. Three spellings of one pin in one
# repo is how a pin drifts without anybody noticing.
if [ -z "$fixture" ]; then
  echo "FAIL: no fixture-lane engine pin found in Dockerfile."
  exit 1
fi

fixture_dir=${fixture% *}
fixture_version=${fixture#* }
echo "fixture-lane pin (Dockerfile): $fixture_version, installed into /opt/carve-$fixture_dir"

if [ "$mode" != drift ] && [ "$fixture_dir" != "$fixture_version" ]; then
  echo "FAIL: the fixture lane installs $package@$fixture_version into /opt/carve-$fixture_dir."
  echo "      the prefix directory has to name the version it holds."
  status=1
fi

if [ "$mode" != local ] && [ "$fixture_version" = "$latest" ]; then
  echo "FAIL: the fixture lane names the newest release, $latest."
  echo "      it exists to hold an older engine, so it cannot track latest."
  status=1
fi

if [ "$mode" = drift ]; then
  exit "$status"
fi

for spelling in \
  "docker/carve-$fixture_version-wrapper.sh" ; do
  if [ ! -f "$repo_dir/$spelling" ]; then
    echo "FAIL: $spelling is missing, so the fixture wrapper does not match the pin."
    status=1
  else
    echo "OK: $spelling matches the fixture pin."
  fi
done

if ! grep -q "carve-$fixture_version" "$repo_dir/Dockerfile"; then
  echo "FAIL: the Dockerfile does not copy or expose a carve-$fixture_version wrapper."
  status=1
fi

if ! grep -rq "carve-$fixture_version" "$repo_dir/test"; then
  echo "FAIL: no test invokes carve-$fixture_version, so the fixture lane is unused."
  status=1
fi

exit "$status"
