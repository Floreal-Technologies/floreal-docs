#!/usr/bin/env bash
# Print the build matrix as one line of JSON, from the product manifest.
#
# Usage: scripts/plan.sh [manifest]
# Env:   SKIP   comma separated product names to leave out of this run.
set -euo pipefail

manifest="${1:-products.json}"

if [ ! -f "$manifest" ]; then
  echo "plan: $manifest does not exist" >&2
  exit 1
fi

if ! jq -e 'type == "array" and length > 0' "$manifest" >/dev/null 2>&1; then
  echo "plan: $manifest is not an array with at least one entry" >&2
  exit 1
fi

if ! jq -e 'all(.[]; has("name") and has("repo") and has("ref"))' "$manifest" >/dev/null 2>&1; then
  echo "plan: every entry needs name, repo and ref" >&2
  exit 1
fi

if ! jq -e 'all(.[]; (.name|type == "string") and (.name|test("\\A[a-z0-9][a-z0-9._-]*\\z")))' "$manifest" >/dev/null 2>&1; then
  bad="$(jq -r '[.[] | select((.name|type != "string") or ((.name|test("\\A[a-z0-9][a-z0-9._-]*\\z"))|not)) | (.name|tojson)][0]' "$manifest")"
  echo "plan: invalid product name $bad" >&2
  exit 1
fi

jq -c --arg skip "${SKIP:-}" '
  ($skip | split(",") | map(select(. != ""))) as $drop
  | map(select(.name as $n | $drop | index($n) | not))
' "$manifest"
