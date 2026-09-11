#!/usr/bin/env bash
# D1 EGRESS CENSUS -- "every call goes through one function" is a STRUCTURAL
# claim, so it is gated structurally. Every network primitive in the shipped
# shell is enumerated and mapped to the function it sits in; the ONLY permitted
# site is `egress`. A second site fails here by name -- it is the moment a token
# could leave without the pacing, the auth-by-row, or the URL discipline D1 rules.
#
# Idiom ported from HealthTracker's write-site census (HT-D29): grep matches,
# awk maps a line number to the `function NAME(` at column 0 that precedes it.
# And from its guidance check (HT-R6.1): a PLANTED CONTROL runs first, because a
# matcher that cannot match reads exactly like a clean pass.
#
# Known over-match, in the safe direction: a comment containing "fetch(" counts
# as a site. Keep comments free of that shape rather than weakening the pattern.
set -uo pipefail

DIR=$(cd "$(dirname "$0")/.." && pwd)
cd "$DIR"

PRIM='(^|[^A-Za-z0-9_$])fetch[[:space:]]*\(|XMLHttpRequest|sendBeacon[[:space:]]*\(|new[[:space:]]+(WebSocket|EventSource)[[:space:]]*\(|importScripts[[:space:]]*\('

# ---- PLANTED CONTROL -------------------------------------------------------
CONTROL=$(printf 'x = fetch(u);\nconst w = new WebSocket(u);\nnavigator.sendBeacon(u, b);\nwindow.fetch (u)\n')
CONTROL_HITS=$(printf '%s\n' "$CONTROL" | grep -cE "$PRIM")
if [ "$CONTROL_HITS" -ne 4 ]; then
  echo "egress: FAIL - the CONTROL matched $CONTROL_HITS of 4 planted sites; the matcher is broken, so a clean scan would mean nothing"
  exit 1
fi

# ---- index.html may hold no network call at all ----------------------------
if grep -nE "$PRIM" index.html >/dev/null 2>&1; then
  echo "egress: FAIL - a network primitive in index.html, outside egress():"
  grep -nE "$PRIM" index.html | sed 's/^/    /'
  exit 1
fi

# ---- app.js: exactly one site, inside egress --------------------------------
MATCHES=$(grep -nE "$PRIM" app.js | cut -d: -f1)
[ -n "$MATCHES" ] || { echo "egress: FAIL - no network primitive found in app.js at all (pattern broken, or egress removed?)"; exit 1; }

FOUND=$(printf '%s\n' "$MATCHES" | awk '
  NR == FNR { want[$1] = 1; next }
  /^function [A-Za-z0-9_]+\(/ { fn = $0; sub(/^function /, "", fn); sub(/\(.*/, "", fn) }
  (FNR in want) { print FNR ": " (fn == "" ? "(top-level)" : fn) }
' - app.js)

SITES=$(printf '%s\n' "$FOUND" | sed -E 's/^[0-9]+: //' | sort -u)
COUNT=$(printf '%s\n' "$FOUND" | grep -c .)
if [ "$SITES" = "egress" ] && [ "$COUNT" -eq 1 ]; then
  echo "egress: OK (control matched 4/4; 1 network site in app.js, inside egress(); none in index.html)"
  exit 0
fi
echo "egress: FAIL - every network call must go through egress() (D1). Sites found:"
printf '%s\n' "$FOUND" | sed 's/^/    app.js:/'
exit 1
