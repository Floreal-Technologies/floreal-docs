#!/usr/bin/env bash
# Tests for scripts/bump.sh
set -uo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fail=0

check() {
  if [ "$2" = "$3" ]; then printf 'ok   %s\n' "$1"
  else printf 'FAIL %s\n     expected: %s\n     actual:   %s\n' "$1" "$2" "$3"; fail=1; fi
}

manifest() {
  cat > "$tmp/products.json" <<'JSON'
[ { "name": "alpha", "repo": "Org/Alpha", "ref": "aaa" },
  { "name": "beta",  "repo": "Org/Beta",  "ref": "bbb" } ]
JSON
}
ref_of() { jq -r --arg n "$1" '.[] | select(.name == $n) | .ref' "$tmp/products.json"; }

manifest
"$here/scripts/bump.sh" --product alpha --sha newsha --manifest "$tmp/products.json" >/dev/null
check "pins the named product"        "newsha" "$(ref_of alpha)"
check "leaves the other product"      "bbb"    "$(ref_of beta)"
check "manifest is still valid json"  "2"      "$(jq length "$tmp/products.json")"

manifest
"$here/scripts/bump.sh" --product gamma --sha x --manifest "$tmp/products.json" >/dev/null 2>&1
check "unknown product exits 1" 1 "$?"
check "unknown product changes nothing" "aaa" "$(ref_of alpha)"

manifest
"$here/scripts/bump.sh" --product alpha --manifest "$tmp/products.json" >/dev/null 2>&1
check "missing --sha exits 2" 2 "$?"

# --all, with a fake gh that answers every repository with the same commit.
mkdir -p "$tmp/bin"
cat > "$tmp/bin/gh" <<'SH'
#!/usr/bin/env bash
echo headsha
SH
chmod +x "$tmp/bin/gh"

manifest
PATH="$tmp/bin:$PATH" "$here/scripts/bump.sh" --all --manifest "$tmp/products.json" >/dev/null
check "--all pins alpha" "headsha" "$(ref_of alpha)"
check "--all pins beta"  "headsha" "$(ref_of beta)"

# --all takes every pin from main, so it cannot be combined with a pin given by hand.
manifest
"$here/scripts/bump.sh" --all --product alpha --manifest "$tmp/products.json" >/dev/null 2>&1
check "--all with --product exits 2" 2 "$?"

manifest
"$here/scripts/bump.sh" --all --sha x --manifest "$tmp/products.json" >/dev/null 2>&1
check "--all with --sha exits 2" 2 "$?"

# An unknown flag is rejected outright.
"$here/scripts/bump.sh" --nope >/dev/null 2>&1
check "unknown flag exits 2" 2 "$?"

# The equals form is exactly what getopt buys.
manifest
"$here/scripts/bump.sh" --product=alpha --sha=abc --manifest "$tmp/products.json" >/dev/null
check "equals form pins alpha" "abc" "$(ref_of alpha)"

exit "$fail"
