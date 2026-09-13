#!/usr/bin/env bash
# Re-runnable data-layer gate. Drives headless Chrome/Edge against
# tests/data-layer.test.html (which loads the real ../app.js and, in an iframe,
# the real ../index.html), extracts per-assertion results, and exits non-zero
# unless every check passes AND the executed count matches the pin.
# No Node, no build step -- just a browser. Ported from HealthTracker.
set -uo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
HTML="$DIR/data-layer.test.html"
TMP="$DIR/.tmp"                      # gate artifacts stay inside the repo (D1 scope)
mkdir -p "$TMP"

# GATE-SCRIPT CENSUS (HT-D53). A CDP gate is PowerShell driving headless Chrome,
# a profile that antivirus heuristics have quarantined mid-session. A gate that
# is absent does not run and does not say so. Pinned as a MANIFEST, not a count:
# naming the file ends the hunt, and a manifest also catches a rename.
#
# Adding a gate: add its name here, in the same commit, deliberately.
GATE_SCRIPTS="capture-outcome-gate.ps1"
EXPECTED_GATE_SCRIPTS=1

GS_MISSING=""
for g in $GATE_SCRIPTS; do [ -f "$DIR/$g" ] || GS_MISSING="$GS_MISSING $g"; done
GS_FOUND=$(ls "$DIR"/*-gate.ps1 2>/dev/null | wc -l | tr -d ' ')
GS_EXTRA=$(ls "$DIR"/*-gate.ps1 2>/dev/null | xargs -n1 basename 2>/dev/null | grep -vxF "$GATE_SCRIPTS" | tr '\n' ' ')
if [ -n "$GS_MISSING" ]; then
  echo "GATE-SCRIPT CENSUS: FAIL -$GS_MISSING missing (expected $EXPECTED_GATE_SCRIPTS, found $GS_FOUND)"
  echo "  A gate script that is absent does not run and does not report."
  echo "  SUSPECT ANTIVIRUS QUARANTINE FIRST (tests/README.md). Recover:"
  for g in $GS_MISSING; do echo "    git checkout -- tests/$g"; done
  echo "GATE: FAIL"
  exit 1
fi
if [ -n "$GS_EXTRA" ]; then
  echo "GATE-SCRIPT CENSUS: FAIL - unpinned gate script(s): $GS_EXTRA"
  echo "  A new gate joins the manifest deliberately, in the commit that adds it."
  echo "GATE: FAIL"
  exit 1
fi
echo "gate-script census: $GS_FOUND of $EXPECTED_GATE_SCRIPTS present, manifest matches"

# PORT RESIDUE (D1). Nothing domain-specific or HealthTracker-addressed survives
# the port in shipped code: no healthtracker- storage key (a shared origin would
# make it READABLE), no HT console seam, no meal-domain identifiers. Matched on
# CODE shapes (quoted keys, identifiers), never on prose -- comments cite HT-Dnn
# with a hyphen, which this does not match (HT-D58: a structural gate must match
# a shape that cannot occur in prose).
RESIDUE_RE="['\"\`]healthtracker-|HealthTracker/|window\.HT\b|[^A-Za-z_]HT\.[A-Za-z]|PHOTO_DRAFT|parsePhotoMeal|photoSave|photoDraft|AI_PROMPT_TEMPLATE|ingestBox|MICRO_KEYS|per100"
if grep -nE "$RESIDUE_RE" "$DIR/../app.js" "$DIR/../index.html" >/dev/null 2>&1; then
  echo "PORT RESIDUE: FAIL - HealthTracker or meal-domain code remains in the shell:"
  grep -nE "$RESIDUE_RE" "$DIR/../app.js" "$DIR/../index.html" | sed 's/^/    /'
  echo "GATE: FAIL"
  exit 1
fi
if ! printf "const K = 'healthtracker-byok';\n" | grep -qE "$RESIDUE_RE"; then
  echo "PORT RESIDUE: FAIL - the CONTROL did not match; a clean scan would mean nothing"
  echo "GATE: FAIL"
  exit 1
fi
echo "port residue: clean (control matched)"

# EGRESS CENSUS (D1): exactly one network site, inside egress().
if ! bash "$DIR/check-egress.sh"; then
  echo "EGRESS CHECK: FAIL"
  echo "GATE: FAIL"
  exit 1
fi

if command -v cygpath >/dev/null 2>&1; then
  URL="file:///$(cygpath -m "$HTML")"
  PROFILE="$(cygpath -w "$TMP/dl-profile")"
else
  URL="file:///$(printf '%s' "$HTML" | sed -E 's#^/([a-zA-Z])/#\U\1:/#')"
  PROFILE="$TMP/dl-profile"
fi

BROWSER=""
for c in \
  "/c/Program Files/Google/Chrome/Application/chrome.exe" \
  "/c/Program Files (x86)/Google/Chrome/Application/chrome.exe" \
  "/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe" \
  "/c/Program Files/Microsoft/Edge/Application/msedge.exe"; do
  if [ -x "$c" ]; then BROWSER="$c"; break; fi
done
if [ -z "$BROWSER" ]; then echo "ERROR: no headless Chrome/Edge found" >&2; echo "GATE: FAIL"; exit 2; fi

# --virtual-time-budget: the shell cases load index.html into an iframe and the
# async cases wait on timers (pacing, budgets), so the dump must wait for them.
# HT-D47: createImageBitmap NEVER settles under virtual time; the harness proves
# the leash and the fallback, and capture-outcome-gate.ps1 runs in REAL time.
OUT=$("$BROWSER" --headless --disable-gpu --no-sandbox --allow-file-access-from-files \
  --user-data-dir="$PROFILE" --no-first-run --no-default-browser-check \
  --virtual-time-budget=60000 --dump-dom "$URL" 2>/dev/null \
  | grep -oE '<p class="(r|s)">[^<]*</p>' | sed -E 's/<[^>]+>//g')

echo "$OUT"
echo "-----------------------------------------"

# ASSERTION-COUNT DISCIPLINE (HT-D35 addendum). A synchronous throw once aborted
# HealthTracker's suite while still printing a green-looking SUMMARY with ~40
# assertions silently missing. The harness records such a throw as a failure;
# this pin is the second line of defence -- the EXECUTED count must match.
#
# Re-pin deliberately, in the same commit that adds or removes cases, and state
# the delta in GATES.md.
EXPECTED_ASSERTIONS=305
TOTAL=$(printf '%s\n' "$OUT" | grep -oE 'SUMMARY [0-9]+/[0-9]+' | head -1 | sed -E 's#.*/##')
AUTHORED=$(grep -cE '(^|[^A-Za-z_.])res\(' "$HTML")
echo "assertions: executed ${TOTAL:-0} · pinned $EXPECTED_ASSERTIONS · authored-lines(static lower bound) $AUTHORED"
if [ -z "$TOTAL" ]; then
  echo "ASSERTION COUNT: FAIL - no SUMMARY line (the suite did not finish)"
  echo "GATE: FAIL"
  exit 1
fi
if [ "$TOTAL" -ne "$EXPECTED_ASSERTIONS" ]; then
  echo "ASSERTION COUNT: FAIL - executed $TOTAL, pinned $EXPECTED_ASSERTIONS (delta $((TOTAL - EXPECTED_ASSERTIONS)))"
  echo "  A DROP means cases stopped running - find out why before re-pinning."
  echo "  A RISE means cases were added - re-pin deliberately in the same commit."
  echo "GATE: FAIL"
  exit 1
fi
if printf '%s\n' "$OUT" | grep -q 'ALL PASS'; then
  echo "GATE: PASS"
  exit 0
fi
echo "GATE: FAIL"
exit 1
