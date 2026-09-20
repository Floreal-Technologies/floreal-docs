#!/usr/bin/env bash
# Check a published docs host. Run this before the irreversible step of the
# cutover, while the old URL is still up.
#
# Usage: scripts/verify.sh [host] [product]
set -uo pipefail

host="${1:-docs.floreal.tech}"
product="${2:-mediacopy3000}"
fail=0

ok()   { printf 'ok   %s\n' "$1"; }
bad()  { printf 'FAIL %s\n       %s\n' "$1" "$2"; fail=1; }

code() { curl -so /dev/null -w '%{http_code}' --max-time 20 "https://$host$1"; }

for path in "/" "/$product/" "/$product/fr/" "/$product/installation"; do
  c="$(code "$path")"
  if [ "$c" = "200" ]; then ok "GET $path"; else bad "GET $path" "status $c"; fi
done

page="$(curl -s --max-time 20 "https://$host/$product/")"

# A wrong base gives a page that answers 200 and renders blank, because only
# its assets are missing. So the prefix is checked, then every asset is fetched.
css="$(printf '%s' "$page" | grep -o 'href="/[^"]*\.css"' | head -1 | cut -d'"' -f2)"
case "$css" in
  "/$product/"*) ok "stylesheet carries the /$product/ prefix" ;;
  "") bad "stylesheet prefix" "no stylesheet found in the page" ;;
  *)  bad "stylesheet prefix" "got $css, DOCS_BASE did not reach the build" ;;
esac

assets="$(printf '%s' "$page" | grep -o -E '(href|src)="/[^"]*\.(css|js)"' | cut -d'"' -f2 | sort -u)"
if [ -z "$assets" ]; then
  bad "assets" "the page references no stylesheet or script"
else
  for a in $assets; do
    c="$(code "$a")"
    if [ "$c" = "200" ]; then ok "asset $a"; else bad "asset $a" "status $c"; fi
  done
fi

# The sitemap decides the canonical address search engines keep.
loc="$(curl -s --max-time 20 "https://$host/$product/sitemap.xml" | grep -o '<loc>[^<]*</loc>' | head -1)"
case "$loc" in
  *"https://$host/$product/"*) ok "sitemap hostname" ;;
  "") bad "sitemap hostname" "no sitemap at /$product/sitemap.xml" ;;
  *)  bad "sitemap hostname" "got $loc" ;;
esac

# The French locale is a separate entry point and breaks separately.
fr="$(curl -s --max-time 20 "https://$host/$product/fr/" | grep -o 'href="/[^"]*\.css"' | head -1 | cut -d'"' -f2)"
case "$fr" in
  "/$product/"*) ok "french page carries the /$product/ prefix" ;;
  *) bad "french page prefix" "got ${fr:-nothing}" ;;
esac

if [ "$fail" -eq 0 ]; then
  printf '\nverify: %s looks right\n' "$host"
else
  printf '\nverify: %s is not ready\n' "$host"
fi
exit "$fail"
