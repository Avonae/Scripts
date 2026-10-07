#!/usr/bin/env bash
# Compresses images (PNG, JPEG, WebP) in place with the TinyPNG API.
# Usage: TINIFY_API_KEY=... tinify.sh [-c cachedir] <files...>
set -uo pipefail

cache="${XDG_CACHE_HOME:-$HOME/.cache}/tinify"
if [ "${1:-}" = "-c" ]; then cache=$2; shift 2; fi

if [ -z "${TINIFY_API_KEY:-}" ]; then
  echo "TINIFY_API_KEY is not set" >&2; exit 1
fi
if [ $# -eq 0 ]; then
  echo "Usage: $0 [-c cachedir] <files...>" >&2; exit 1
fi
mkdir -p "$cache"

fail=0
for f in "$@"; do
  # Results are cached by content hash, so re-runs on the same files cost no API calls.
  h=$(sha256sum "$f" | cut -d' ' -f1)
  if [ ! -s "$cache/$h" ]; then
    url=$(curl -sf --user "api:$TINIFY_API_KEY" --data-binary @"$f" -D - -o /dev/null https://api.tinify.com/shrink \
      | awk 'tolower($1)=="location:"{print $2}' | tr -d '\r')
    if [ -z "$url" ] || ! curl -sf --user "api:$TINIFY_API_KEY" -o "$cache/$h" "$url"; then
      echo "FAIL $f" >&2; rm -f "$cache/$h"; fail=1; continue
    fi
  fi
  before=$(stat -c%s "$f"); after=$(stat -c%s "$cache/$h")
  [ "$after" -lt "$before" ] && cp "$cache/$h" "$f"
  printf '%d -> %d %s\n' "$before" "$after" "$f"
done
exit $fail
