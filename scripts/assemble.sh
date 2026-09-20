#!/usr/bin/env bash
# Build the directory that gets published, from the downloaded manuals and the
# hand written root files.
#
# Usage: scripts/assemble.sh --artifacts DIR --root DIR --out DIR --manifest FILE
# Env:   SKIP   comma separated product names this run did not build on purpose.
set -euo pipefail

getopt_rc=0
getopt -T >/dev/null 2>&1 || getopt_rc=$?
if [ "$getopt_rc" -ne 4 ]; then
  echo "assemble: needs enhanced getopt (util-linux)" >&2
  exit 2
fi

parsed="$(getopt -o '' --long artifacts:,root:,out:,manifest: -n 'assemble.sh' -- "$@")" || exit 2
eval set -- "$parsed"

artifacts=""; root=""; out=""; manifest=""
while true; do
  case "$1" in
    --artifacts) artifacts="$2"; shift 2 ;;
    --root)      root="$2";      shift 2 ;;
    --out)       out="$2";       shift 2 ;;
    --manifest)  manifest="$2";  shift 2 ;;
    --) shift; break ;;
    *) echo "assemble: unexpected argument $1" >&2; exit 2 ;;
  esac
done

for name in artifacts root out manifest; do
  if [ -z "${!name}" ]; then
    echo "assemble: --$name is required" >&2
    exit 2
  fi
done

rm -rf "$out"
mkdir -p "$out"
cp -R "$root"/. "$out"/

for dir in "$artifacts"/manual-*; do
  [ -d "$dir" ] || continue
  base="${dir##*/}"
  product="${base#manual-}"
  # A degenerate product name would turn the next rm -rf into a wipe of $out
  # itself, or of something outside it. Fail closed instead of guessing.
  case "$product" in
    ''|.|..|*/*)
      # */* can't actually happen: base="${dir##*/}" strips everything up to
      # the last slash, so base never contains one. Kept as defence in case
      # base is ever derived differently.
      echo "assemble: unsafe product name from artifact '$base'" >&2
      exit 1
      ;;
  esac
  dest="$out/$product"
  # A product named e.g. "index.html" or "CNAME" would otherwise pass the
  # checks above and land here as a file already sitting in $out from root/.
  # rm -rf on that path deletes the root file; both guardrails below still
  # pass afterwards, so the breakage would be silent. Refuse instead.
  if [ -e "$dest" ] && [ ! -d "$dest" ]; then
    echo "assemble: refusing to replace $dest (not a directory) for product '$product'" >&2
    exit 1
  fi
  # A root/ directory of the same name would otherwise make mv move the
  # artifact inside it, burying the manual under a stale placeholder.
  rm -rf "$dest"
  mv "$dir" "$dest"
done

# Guardrail. A wrong artifact name gives a green run and a manual that is not
# there, so the absence is turned into a failure before anything is published.
skip=",${SKIP:-},"
missing=0

while read -r name; do
  case "$skip" in
    *",$name,"*) continue ;;
  esac
  if [ ! -s "$out/$name/index.html" ]; then
    echo "assemble: $out/$name/index.html is missing or empty" >&2
    missing=1
  fi
done < <(jq -r '.[].name' "$manifest")

if [ ! -s "$out/CNAME" ]; then
  echo "assemble: $out/CNAME is missing or empty" >&2
  missing=1
fi

if [ "$missing" -ne 0 ]; then
  exit 1
fi

echo "assemble: $out is ready"
