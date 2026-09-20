#!/usr/bin/env bash
# Tests for scripts/assemble.sh
set -uo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
fail=0

check() {
  if [ "$2" = "$3" ]; then printf 'ok   %s\n' "$1"
  else printf 'FAIL %s\n     expected: %s\n     actual:   %s\n' "$1" "$2" "$3"; fail=1; fi
}

fixture() {  # fixture <dir> ; builds a manifest, a root/ and artifacts/
  mkdir -p "$1/root" "$1/artifacts/manual-alpha" "$1/artifacts/manual-beta"
  printf 'docs.example.test\n' > "$1/root/CNAME"
  printf '<!doctype html><title>root</title>\n' > "$1/root/index.html"
  printf '<!doctype html><title>alpha</title>\n' > "$1/artifacts/manual-alpha/index.html"
  printf '<!doctype html><title>beta</title>\n'  > "$1/artifacts/manual-beta/index.html"
  cat > "$1/products.json" <<'JSON'
[ { "name": "alpha", "repo": "Org/Alpha", "ref": "aaa" },
  { "name": "beta",  "repo": "Org/Beta",  "ref": "bbb" } ]
JSON
}

run() {  # run <dir> -> exit code, output in $out
  out="$("$here/scripts/assemble.sh" --artifacts "$1/artifacts" --root "$1/root" \
        --out "$1/site" --manifest "$1/products.json" 2>&1)"
}

t="$(mktemp -d)"; fixture "$t"
run "$t"; check "happy path exits 0" 0 "$?"
check "alpha landed"      "alpha" "$(cat "$t/site/alpha/index.html" | sed -n 's/.*<title>\(.*\)<\/title>.*/\1/p')"
check "beta landed"       "beta"  "$(cat "$t/site/beta/index.html"  | sed -n 's/.*<title>\(.*\)<\/title>.*/\1/p')"
check "root page landed"  "root"  "$(cat "$t/site/index.html"       | sed -n 's/.*<title>\(.*\)<\/title>.*/\1/p')"
check "CNAME landed"      "docs.example.test" "$(cat "$t/site/CNAME")"
rm -rf "$t"

# The guardrail: a manual the manifest names but the run did not build.
t="$(mktemp -d)"; fixture "$t"; rm -rf "$t/artifacts/manual-beta"
run "$t"; check "missing manual exits 1" 1 "$?"
case "$out" in *beta*) printf 'ok   %s\n' "names the missing product" ;;
  *) printf 'FAIL %s\n     stderr: %s\n' "names the missing product" "$out"; fail=1 ;; esac
rm -rf "$t"

# An empty index.html is as bad as a missing one.
t="$(mktemp -d)"; fixture "$t"; : > "$t/artifacts/manual-beta/index.html"
run "$t"; check "empty index.html exits 1" 1 "$?"
rm -rf "$t"

# SKIP excuses a product this run did not build on purpose.
t="$(mktemp -d)"; fixture "$t"; rm -rf "$t/artifacts/manual-beta"
out="$(SKIP=beta "$here/scripts/assemble.sh" --artifacts "$t/artifacts" --root "$t/root" \
       --out "$t/site" --manifest "$t/products.json" 2>&1)"
check "SKIP excuses the absence" 0 "$?"
rm -rf "$t"

# A missing CNAME would publish the site on the wrong domain.
t="$(mktemp -d)"; fixture "$t"; rm -f "$t/root/CNAME"
run "$t"; check "missing CNAME exits 1" 1 "$?"
rm -rf "$t"

# The output directory is rebuilt, never merged with an older run.
t="$(mktemp -d)"; fixture "$t"
mkdir -p "$t/site/stale"; printf 'old\n' > "$t/site/stale/index.html"
run "$t"
check "stale directory is gone" "absent" "$([ -e "$t/site/stale" ] && echo present || echo absent)"
rm -rf "$t"

# An unknown flag is rejected outright.
"$here/scripts/assemble.sh" --nope >/dev/null 2>&1
check "unknown flag exits 2" 2 "$?"

# The equals form is exactly what getopt buys; it must match the space form.
t="$(mktemp -d)"; fixture "$t"
out="$("$here/scripts/assemble.sh" --artifacts="$t/artifacts" --root="$t/root" \
       --out="$t/site" --manifest="$t/products.json" 2>&1)"
check "equals form exits 0" 0 "$?"
check "equals form alpha landed" "alpha" "$(cat "$t/site/alpha/index.html" | sed -n 's/.*<title>\(.*\)<\/title>.*/\1/p')"
check "equals form beta landed"  "beta"  "$(cat "$t/site/beta/index.html"  | sed -n 's/.*<title>\(.*\)<\/title>.*/\1/p')"
check "equals form root page landed" "root" "$(cat "$t/site/index.html" | sed -n 's/.*<title>\(.*\)<\/title>.*/\1/p')"
check "equals form CNAME landed" "docs.example.test" "$(cat "$t/site/CNAME")"
rm -rf "$t"

# A root/ directory named after a product must not bury the manual under it.
t="$(mktemp -d)"; fixture "$t"
mkdir -p "$t/root/alpha"
printf '<!doctype html><title>placeholder</title>\n' > "$t/root/alpha/index.html"
run "$t"
check "colliding root dir: manual content wins" "alpha" "$(cat "$t/site/alpha/index.html" | sed -n 's/.*<title>\(.*\)<\/title>.*/\1/p')"
check "colliding root dir: no leftover manual-alpha" "absent" "$([ -e "$t/site/alpha/manual-alpha" ] && echo present || echo absent)"
rm -rf "$t"

# A degenerate "manual-" artifact (empty product name) must not be let near
# rm -rf: it must not wipe out content already placed in $out.
t="$(mktemp -d)"; fixture "$t"
mkdir -p "$t/artifacts/manual-"
run "$t"; rc="$?"
check "empty product name exits 1" 1 "$rc"
check "empty product name: root CNAME survives" "docs.example.test" "$(cat "$t/site/CNAME" 2>/dev/null)"
case "$out" in *"unsafe product name"*) printf 'ok   %s\n' "empty product name: names the reason" ;;
  *) printf 'FAIL %s\n     stderr: %s\n' "empty product name: names the reason" "$out"; fail=1 ;; esac
rm -rf "$t"

# A "manual-.." artifact must also be rejected outright, not acted on.
t="$(mktemp -d)"; fixture "$t"
mkdir -p "$t/artifacts/manual-.."
run "$t"; rc="$?"
check "dotdot product name exits 1" 1 "$rc"
case "$out" in *"unsafe product name"*) printf 'ok   %s\n' "dotdot product name: names the reason" ;;
  *) printf 'FAIL %s\n     stderr: %s\n' "dotdot product name: names the reason" "$out"; fail=1 ;; esac
rm -rf "$t"

# A "manual-." artifact must also be rejected outright, not acted on.
t="$(mktemp -d)"; fixture "$t"
mkdir -p "$t/artifacts/manual-."
run "$t"; rc="$?"
check "dot product name exits 1" 1 "$rc"
case "$out" in *"unsafe product name"*) printf 'ok   %s\n' "dot product name: names the reason" ;;
  *) printf 'FAIL %s\n     stderr: %s\n' "dot product name: names the reason" "$out"; fail=1 ;; esac
rm -rf "$t"

# A product legitimately named "index.html" passes the name regex and the
# ''|.|..|*/* guard. It must not be allowed to delete the site's root landing
# page: assemble must refuse to replace a destination that already exists and
# is not a directory, and the root index.html must survive intact.
t="$(mktemp -d)"; fixture "$t"
mkdir -p "$t/artifacts/manual-index.html"
printf '<!doctype html><title>evil</title>\n' > "$t/artifacts/manual-index.html/index.html"
cat > "$t/products.json" <<'JSON'
[ { "name": "alpha",       "repo": "Org/Alpha", "ref": "aaa" },
  { "name": "beta",        "repo": "Org/Beta",  "ref": "bbb" },
  { "name": "index.html",  "repo": "Org/Evil",  "ref": "ccc" } ]
JSON
run "$t"; rc="$?"
check "product named index.html exits 1" 1 "$rc"
check "product named index.html: root index.html survives" "root" \
  "$(cat "$t/site/index.html" 2>/dev/null | sed -n 's/.*<title>\(.*\)<\/title>.*/\1/p')"
case "$out" in *"index.html"*) printf 'ok   %s\n' "product named index.html: names the reason" ;;
  *) printf 'FAIL %s\n     stderr: %s\n' "product named index.html: names the reason" "$out"; fail=1 ;; esac
rm -rf "$t"

exit "$fail"
