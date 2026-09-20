#!/usr/bin/env bash
# Move the pin of one product, or of every product, in the manifest.
#
# Usage: scripts/bump.sh --product NAME --sha SHA [--manifest FILE]
#        scripts/bump.sh --all [--manifest FILE]        needs gh and GH_TOKEN
set -euo pipefail

getopt_rc=0
getopt -T >/dev/null 2>&1 || getopt_rc=$?
if [ "$getopt_rc" -ne 4 ]; then
  echo "bump: needs enhanced getopt (util-linux)" >&2
  exit 2
fi

parsed="$(getopt -o '' --long product:,sha:,manifest:,all -n 'bump.sh' -- "$@")" || exit 2
eval set -- "$parsed"

manifest="products.json"
product=""; sha=""; all="no"
while true; do
  case "$1" in
    --product)  product="$2";  shift 2 ;;
    --sha)      sha="$2";      shift 2 ;;
    --manifest) manifest="$2"; shift 2 ;;
    --all)      all="yes";     shift ;;
    --) shift; break ;;
    *) echo "bump: unexpected argument $1" >&2; exit 2 ;;
  esac
done

# --all takes every pin from main, so a pin given by hand cannot also apply.
if [ "$all" = "yes" ] && { [ -n "$product" ] || [ -n "$sha" ]; }; then
  echo "bump: --all cannot be combined with --product or --sha" >&2
  exit 2
fi

if [ ! -f "$manifest" ]; then
  echo "bump: $manifest does not exist" >&2
  exit 1
fi

pin() {  # pin <name> <sha>
  jq --arg n "$1" --arg s "$2" 'map(if .name == $n then .ref = $s else . end)' \
    "$manifest" > "$manifest.new"
  mv "$manifest.new" "$manifest"
}

if [ "$all" = "yes" ]; then
  while read -r name repo; do
    head="$(gh api "repos/$repo/commits/main" --jq .sha)"
    pin "$name" "$head"
    echo "bump: $name -> $head"
  done < <(jq -r '.[] | "\(.name) \(.repo)"' "$manifest")
  exit 0
fi

if [ -z "$product" ] || [ -z "$sha" ]; then
  echo "bump: --product and --sha are both required" >&2
  exit 2
fi

if ! jq -e --arg n "$product" 'any(.[]; .name == $n)' "$manifest" >/dev/null; then
  echo "bump: $product is not in $manifest" >&2
  exit 1
fi

pin "$product" "$sha"
echo "bump: $product -> $sha"
