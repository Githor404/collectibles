#!/usr/bin/env bash
# APP_VERSION drift gate. Ported from HealthTracker's check-version.sh (HT-D6's
# force-and-notify amendment and its converse arm), adapted in two ways:
#
#   1. This repo has NO manifest and NO icons, so the shell is index.html +
#      app.js and the binary-comparison arm is REMOVED rather than left pointing
#      at files that do not exist. A clause that can never fire is the vacuous
#      shape this repo keeps catching in its own gates.
#   2. `d:` is required on EVERY entry (ruled 2026-09-14). HealthTracker exempts
#      entries predating its date convention; there are none here, so the
#      exemption would protect nobody.
#
# D14 -- THIS SHIPS BEFORE THE MECHANISM THAT MAKES IT NECESSARY. HealthTracker
# shipped the service worker first with a hand-bumped integer, missed the bump on
# every slice after Phase 0, and served a frozen first-deploy shell with nothing
# to say so. Here the drift gate exists while there is still no cache that could
# serve one, so it guards every deploy in the interval and has a track record by
# the time it becomes load-bearing.
#
# BOTH DIRECTIONS ARE GATED:
#   shell changed + APP_VERSION did not move  -> FAIL (an update with no notice)
#   APP_VERSION moved + shell otherwise same  -> FAIL (a notice with no update)
#
# The second needed thought. Bumping APP_VERSION EDITS app.js, which is itself a
# shell file, so "the shell changed" is trivially true on every bump and a plain
# diff could never catch a hollow one. The shell is therefore fingerprinted with
# its version metadata STRIPPED -- the APP_VERSION assignment and the VERSION_LOG
# entry lines removed -- and compared against HEAD. Identical fingerprint with a
# moved version means the version was the only thing that changed.
#
# Drift is measured against the LAST COMMIT, not a stamped baseline, so iterating
# within a release is friction-free. No --fix, no baseline file.
set -uo pipefail

DIR=$(cd "$(dirname "$0")/.." && pwd)
cd "$DIR"
SHELL_FILES="index.html app.js"

# Version metadata, removed so the REST of the shell can be compared. Matches the
# APP_VERSION assignment and VERSION_LOG entry lines only; references such as
# `'collectibles v' + version` are not assignments and are deliberately kept.
#
# The entry pattern keys on `{ v: 'X.Y.Z'` ALONE and not on what follows.
# HealthTracker's once required `, note:` and that was a latent silent-skip:
# inserting the `d:` field between them would have stopped the line matching, the
# two fingerprints would then differ on any changelog edit, and since the converse
# arm fires only when they are EQUAL it would have quietly stopped catching hollow
# bumps forever. A gate must not depend on the shape of a field it is not checking.
strip_vmeta() {
  sed -E \
    -e "/APP_VERSION[[:space:]]*=[[:space:]]*'[^']*'/d" \
    -e "/^[[:space:]]*\{[[:space:]]*v:[[:space:]]*'[0-9]+\.[0-9]+\.[0-9]+'/d"
}
# Line endings normalized so the fingerprint is platform-stable.
subst_hash_work() {
  for f in $SHELL_FILES; do
    if [ "$f" = app.js ]; then strip_vmeta < "$f"; else cat "$f"; fi
  done | tr -d '\r' | sha256sum | cut -d' ' -f1
}
subst_hash_head() {
  for f in $SHELL_FILES; do
    if [ "$f" = app.js ]; then git show "HEAD:$f" | strip_vmeta; else git show "HEAD:$f"; fi
  done | tr -d '\r' | sha256sum | cut -d' ' -f1
}

extract_appv() { grep -oE "APP_VERSION[[:space:]]*=[[:space:]]*'[^']*'" | head -1 | sed -E "s/.*'([^']*)'.*/\1/"; }
APPV=$(extract_appv < app.js)
LOGV=$(grep -oE "v: '[0-9]+\.[0-9]+\.[0-9]+'" app.js | sed -E "s/.*'([^']*)'.*/\1/")

fail() { echo "check-version: FAIL - $1"; exit 1; }
[ -n "$APPV" ] || fail "no APP_VERSION in app.js"
[ -n "$LOGV" ] || fail "no VERSION_LOG entries in app.js"

# Changelog discipline: APP_VERSION must have a line, and be the newest.
printf '%s\n' "$LOGV" | grep -qx "$APPV" || fail "APP_VERSION $APPV has no VERSION_LOG changelog entry"
NEWEST=$(printf '%s\n' "$LOGV" | sort -V | tail -1)
[ "$APPV" = "$NEWEST" ] || fail "APP_VERSION $APPV is not the newest VERSION_LOG entry (newest: $NEWEST)"

# EVERY entry carries a release date -- it is what the build line shows.
NENTRIES=$(printf '%s\n' "$LOGV" | grep -c .)
NDATED=$(grep -cE "\{[[:space:]]*v:[[:space:]]*'[0-9]+\.[0-9]+\.[0-9]+',[[:space:]]*d:[[:space:]]*'[0-9]{4}-[0-9]{2}-[0-9]{2}'" app.js)
[ "$NENTRIES" = "$NDATED" ] || \
  fail "$NENTRIES VERSION_LOG entries but $NDATED carry d: 'YYYY-MM-DD' -- every entry needs one (ruled 2026-09-14)"

TODAY=$(date +%F)
for D in $(grep -oE "d: '[0-9]{4}-[0-9]{2}-[0-9]{2}'" app.js | cut -d"'" -f2); do
  [ "$D" \> "$TODAY" ] && fail "VERSION_LOG release date $D is in the future (> $TODAY) - likely a typo"
done

# Drift, both arms, measured against the last commit.
if git rev-parse HEAD >/dev/null 2>&1; then
  if ! git diff --quiet HEAD -- $SHELL_FILES 2>/dev/null; then
    PREV=$(git show HEAD:app.js 2>/dev/null | extract_appv)
    if [ -n "$PREV" ] && [ "$PREV" = "$APPV" ]; then
      fail "shell changed since last commit but APP_VERSION did not bump (still $APPV) - bump it + add a VERSION_LOG line"
    fi
    if [ -n "$PREV" ] && [ "$PREV" != "$APPV" ] && [ "$(subst_hash_work)" = "$(subst_hash_head)" ]; then
      echo "check-version: FAIL - APP_VERSION bumped $PREV -> $APPV but the shell is"
      echo "  otherwise UNCHANGED: stripped of the version line and the VERSION_LOG"
      echo "  entries, the shell fingerprint is identical to HEAD. That ships a"
      echo "  changelog line announcing work no user can see. Infrastructure --"
      echo "  gates, harness, docs -- is not a release; a user's device is not the"
      echo "  audience for a test runner."
      echo "  fix: ship a real shell change with the bump, or hold the version."
      exit 1
    fi
    echo "check-version: OK ($APPV; shell changed since last commit, APP_VERSION bumped $PREV -> $APPV)"
    exit 0
  fi
fi
echo "check-version: OK ($APPV, changelog present and dated; shell unchanged since last commit)"
exit 0
