#!/bin/sh
# Fails when a source revision the Dockerfile clones no longer matches what
# scripts/upstream-pins.tsv says that pin follows, and when the resilient.sile
# rockspec the image builds stops satisfying this project's own dependency floor.
#
# The two compared values come from different places on purpose: the pinned SHA
# is parsed out of the Dockerfile, the target is read from the GitHub API. A pin
# the Dockerfile clones but the policy file does not name is a failure, so a new
# source cannot enter the image unwatched.
#
# Usage: check-upstream-pins.sh [local|drift]. `local` checks only what this
# repo controls (every pin has a valid policy row, the rockspec floor) and runs
# on every pull request; `drift` checks only the pins against their upstream
# targets and runs on a schedule. No argument runs both.
#
# Exit codes: 0 clean, 1 a failure (including the check itself breaking), 3 in
# drift mode when the only findings are pins behind their upstream targets.
set -eu

mode=${1:-all}
case "$mode" in
  all|local|drift) ;;
  *) echo "usage: $0 [local|drift]" >&2; exit 2 ;;
esac

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
dockerfile="$repo_dir/Dockerfile"
policy="$repo_dir/scripts/upstream-pins.tsv"
rockspec="$repo_dir/carve-sile-dev-1.rockspec"
status=0
drift=0
tab=$(printf '\t')

finish() {
  if [ "$status" -ne 0 ]; then exit 1; fi
  if [ "$drift" -ne 0 ]; then
    if [ "$mode" = drift ]; then exit 3; fi
    exit 1
  fi
  exit 0
}

api() {
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    curl -fsSL -H "Authorization: Bearer $GITHUB_TOKEN" "https://api.github.com/$1"
  else
    curl -fsSL "https://api.github.com/$1"
  fi
}

newest_tag() {
  api "repos/$1/tags?per_page=100" | python3 -c '
import json, re, sys
tags = [(tuple(int(p) for p in m.groups()), t["name"], t["commit"]["sha"])
        for t in json.load(sys.stdin)
        for m in [re.match(r"^v?(\d+)\.(\d+)\.(\d+)$", t["name"])] if m]
if not tags:
    sys.stderr.write("no semver tag found\n")
    sys.exit(1)
print("%s %s" % max(tags)[1:])'
}

# owner/repo and SHA per clone, pairing each clone line with the checkout under it.
pins=$(awk '
  match($0, /github\.com\/[A-Za-z0-9._-]+\/[A-Za-z0-9._-]+\.git/) {
    slug = substr($0, RSTART + 11, RLENGTH - 15)
  }
  match($0, /git checkout [0-9a-f][0-9a-f]*/) && slug != "" {
    sha = substr($0, RSTART + 13, RLENGTH - 13)
    if (length(sha) == 40) { print slug "\t" sha; slug = "" }
  }
' "$dockerfile")

if [ -z "$pins" ]; then
  echo "FAIL: no cloned source pins found in the Dockerfile."
  exit 1
fi

while IFS="$tab" read -r slug sha; do
  [ -n "$slug" ] || continue
  rule=$(awk -F'\t' -v s="$slug" '$1 == s && $0 !~ /^#/ { print $2 }' "$policy")

  if [ -z "$rule" ]; then
    echo "FAIL: $slug is cloned by the Dockerfile but scripts/upstream-pins.tsv does not rule it."
    echo "      add a release-tag or default-branch row for it, with the reason."
    status=1
    continue
  fi

  case "$rule" in
    release-tag|default-branch) ;;
    *)
      echo "FAIL: $slug has an unknown policy '$rule' in scripts/upstream-pins.tsv."
      status=1
      continue
      ;;
  esac

  if [ "$mode" = local ]; then
    echo "OK: $slug follows its $rule row."
    continue
  fi

  case "$rule" in
    release-tag)
      target=$(newest_tag "$slug")
      target_sha=${target#* }
      what="newest release tag ${target% *}"
      ;;
    default-branch)
      branch=$(api "repos/$slug" | python3 -c 'import json,sys; print(json.load(sys.stdin)["default_branch"])')
      target_sha=$(api "repos/$slug/commits/$branch" | python3 -c 'import json,sys; print(json.load(sys.stdin)["sha"])')
      what="tip of $branch"
      ;;
  esac

  if [ "$sha" = "$target_sha" ]; then
    echo "OK: $slug is at the $what."
  else
    echo "FAIL: $slug is pinned at $sha, but the $what is $target_sha."
    echo "      bump the pin in the Dockerfile, or change its row in scripts/upstream-pins.tsv."
    drift=1
  fi
done <<PINS
$pins
PINS

if [ "$mode" = drift ]; then
  finish
fi

# The rockspec the image builds out of the resilient.sile checkout has to satisfy
# this project's own floor, and has to exist at the revision actually cloned.
floor=$(sed -n 's|.*"resilient\.sile *>= *\([0-9][0-9.]*\)".*|\1|p' "$rockspec")
built=$(sed -n 's|.*rockspecs/resilient\.sile-\([0-9][0-9.]*\)-[0-9]*\.rockspec.*|\1|p' "$dockerfile")
resilient_sha=$(printf '%s\n' "$pins" | awk -F'\t' '$1 == "Omikhleia/resilient.sile" { print $2 }')

if [ -z "$floor" ] || [ -z "$built" ] || [ -z "$resilient_sha" ]; then
  echo "FAIL: could not read the floor ($floor), the built rockspec version ($built)"
  echo "      or the pinned resilient.sile revision ($resilient_sha)."
  exit 1
fi

echo "resilient.sile floor (rockspec): $floor, built rockspec (Dockerfile): $built"

if [ "$(printf '%s\n%s\n' "$floor" "$built" | sort -V | head -1)" != "$floor" ]; then
  echo "FAIL: the image builds resilient.sile $built, below this project's floor of $floor."
  status=1
else
  rockspecs=$(api "repos/Omikhleia/resilient.sile/contents/rockspecs?ref=$resilient_sha" 2>/dev/null \
    | python3 -c 'import json,sys
try:
    print("\n".join(e["name"] for e in json.load(sys.stdin)))
except Exception:
    pass' || true)
  if ! printf '%s\n' "$rockspecs" | grep -qx "resilient.sile-$built-1.rockspec"; then
    echo "FAIL: resilient.sile-$built-1.rockspec is not in rockspecs/ at the pinned revision $resilient_sha."
    echo "      the image builds a rockspec the cloned resilient.sile does not carry."
    status=1
  else
    echo "OK: resilient.sile-$built-1.rockspec exists at the pinned revision and meets the floor."
  fi
fi

finish
