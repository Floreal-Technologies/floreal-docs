#!/usr/bin/env bash
# Tests for scripts/plan.sh
set -uo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fail=0

check() {  # check <label> <expected> <actual>
  if [ "$2" = "$3" ]; then
    printf 'ok   %s\n' "$1"
  else
    printf 'FAIL %s\n     expected: %s\n     actual:   %s\n' "$1" "$2" "$3"
    fail=1
  fi
}

cat > "$tmp/good.json" <<'JSON'
[
  { "name": "alpha", "repo": "Org/Alpha", "ref": "aaa" },
  { "name": "beta",  "repo": "Org/Beta",  "ref": "bbb" }
]
JSON

out="$("$here/scripts/plan.sh" "$tmp/good.json")"
check "prints both products" \
  '[{"name":"alpha","repo":"Org/Alpha","ref":"aaa"},{"name":"beta","repo":"Org/Beta","ref":"bbb"}]' \
  "$out"

out="$(SKIP=alpha "$here/scripts/plan.sh" "$tmp/good.json")"
check "SKIP drops a product" \
  '[{"name":"beta","repo":"Org/Beta","ref":"bbb"}]' \
  "$out"

out="$(SKIP= "$here/scripts/plan.sh" "$tmp/good.json" | jq length)"
check "empty SKIP drops nothing" 2 "$out"

echo '[]' > "$tmp/empty.json"
"$here/scripts/plan.sh" "$tmp/empty.json" >/dev/null 2>&1
check "empty manifest exits 1" 1 "$?"

echo '[{"name":"alpha","repo":"Org/Alpha"}]' > "$tmp/partial.json"
"$here/scripts/plan.sh" "$tmp/partial.json" >/dev/null 2>&1
check "entry without ref exits 1" 1 "$?"

echo '[{"name":"","repo":"Org/Alpha","ref":"aaa"}]' > "$tmp/emptyname.json"
"$here/scripts/plan.sh" "$tmp/emptyname.json" >/dev/null 2>&1
check "empty name exits 1" 1 "$?"

echo '[{"name":"..","repo":"Org/Alpha","ref":"aaa"}]' > "$tmp/dotdot.json"
"$here/scripts/plan.sh" "$tmp/dotdot.json" >/dev/null 2>&1
check "dotdot name exits 1" 1 "$?"

echo '[{"name":"media-copy.3000","repo":"Org/Alpha","ref":"aaa"}]' > "$tmp/dotted.json"
"$here/scripts/plan.sh" "$tmp/dotted.json" >/dev/null 2>&1
check "legitimate dotted/dashed/digit name is accepted" 0 "$?"

# jq's "$" matches end of LINE, not end of string, in Oniguruma. A trailing
# newline in the name must still be rejected.
echo '[{"name":"alpha\n","repo":"Org/Alpha","ref":"aaa"}]' > "$tmp/trailingnl.json"
"$here/scripts/plan.sh" "$tmp/trailingnl.json" >/dev/null 2>&1
check "trailing newline in name exits 1" 1 "$?"

# A non-string name must not crash jq past the intended exit 1 / message.
echo '[{"name":123,"repo":"Org/Alpha","ref":"aaa"}]' > "$tmp/nonstring.json"
err="$("$here/scripts/plan.sh" "$tmp/nonstring.json" 2>&1 >/dev/null)"
rc=$?
check "non-string name exits 1" 1 "$rc"
case "$err" in *"invalid product name"*) printf 'ok   %s\n' "non-string name: prints its own message" ;;
  *) printf 'FAIL %s\n     stderr: %s\n' "non-string name: prints its own message" "$err"; fail=1 ;; esac

exit "$fail"
