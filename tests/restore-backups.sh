#!/usr/bin/env bash
# THE RECOVERY PATH -- restoring after an interrupted defect pass, with the check
# that was missing on the day it mattered.
#
# A killed pass leaves tests/.tmp/*.orig behind and may leave a file mutated.
# Restoring from those backups is correct -- IF THEY BELONG TO THE RUN THAT WAS
# KILLED. On 2026-09-13 they did not. A previous session's backups were still on
# disk, three hours old, and an ad-hoc restore from them overwrote three hours of
# uncommitted work in four files.
#
# That restore obeyed every rule this repo had written down. It was BY COPY, not
# `git checkout --`. It was VERIFIED BY cmp. It returned each file to what it was
# AT SOME POINT -- and that was the entire defect. The rules governed the METHOD
# of a restore and said nothing about the PROVENANCE of the backup.
#
# Usage:
#   bash tests/restore-backups.sh            # dry run: report only, change nothing
#   bash tests/restore-backups.sh --apply    # restore the files that differ
#   MAX_AGE_MIN=30 bash tests/restore-backups.sh --apply
set -uo pipefail
cd "$(dirname "$0")/.."

TMP="tests/.tmp"
MUTATED="app.js index.html CLAUDE.md GATES.md"
MAX_AGE_MIN="${MAX_AGE_MIN:-120}"
APPLY=0
[ "${1:-}" = "--apply" ] && APPLY=1

COMMIT_EPOCH=$(git log -1 --format=%ct 2>/dev/null || echo 0)
COMMIT_HUMAN=$(git log -1 --format=%cd --date=format:'%Y-%m-%d %H:%M:%S' 2>/dev/null || echo '(no commits)')
NOW=$(date +%s)

echo "=== restore-backups: FRESHNESS GATE ================================="
echo "HEAD commit at $COMMIT_HUMAN   max backup age ${MAX_AGE_MIN}min"

FAIL=0
for f in $MUTATED; do
  O="$TMP/$(basename "$f").orig"

  if [ ! -f "$O" ]; then
    printf '  %-12s NO BACKUP\n' "$f"
    echo "    FRESHNESS GATE: FAIL - no backup for $f; there is nothing to restore from."
    FAIL=1; continue
  fi

  M=$(stat -c %Y "$O" 2>/dev/null || echo 0)
  AGE_MIN=$(( (NOW - M) / 60 ))
  WHEN=$(date -d "@$M" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo '?')

  # THE CHECK THAT WOULD HAVE CAUGHT IT. The stale backups were stamped 10:39:36
  # against a 10:49:04 commit -- older than HEAD, so they could not possibly
  # contain anything committed since, let alone work done after that.
  if [ "$M" -le "$COMMIT_EPOCH" ]; then
    printf '  %-12s %s  age %smin\n' "$f" "$WHEN" "$AGE_MIN"
    echo "    FRESHNESS GATE: FAIL - $(basename "$O") is OLDER THAN HEAD."
    echo "      A backup predating the last commit cannot hold work done since it."
    echo "      This is the exact shape of the 2026-09-13 loss. REFUSING."
    FAIL=1; continue
  fi

  if [ "$AGE_MIN" -ge "$MAX_AGE_MIN" ]; then
    printf '  %-12s %s  age %smin\n' "$f" "$WHEN" "$AGE_MIN"
    echo "    FRESHNESS GATE: FAIL - $(basename "$O") is ${AGE_MIN}min old (limit ${MAX_AGE_MIN})."
    echo "      A pass writes its backups at startup, so a backup this old belongs"
    echo "      to an earlier run. REFUSING."
    FAIL=1; continue
  fi

  printf '  %-12s %s  age %smin  FRESH\n' "$f" "$WHEN" "$AGE_MIN"
done

if [ "$FAIL" != "0" ]; then
  echo "-------------------------------------------------------------------"
  echo "FRESHNESS GATE: FAIL - refusing to restore from a backup that cannot"
  echo "be shown to belong to the interrupted run."
  echo
  echo "If the work is COMMITTED, the correct recovery is git, not these files:"
  echo "    git status --short && git checkout HEAD -- <file>"
  echo "If it is NOT committed, stop and inspect before overwriting anything."
  exit 1
fi

echo "FRESHNESS GATE: PASS - every backup postdates HEAD and is under the age limit"
echo "-------------------------------------------------------------------"

CHANGED=0
for f in $MUTATED; do
  O="$TMP/$(basename "$f").orig"
  if cmp -s "$O" "$f"; then
    printf '  %-12s clean (matches its backup)\n' "$f"
  else
    CHANGED=1
    if [ "$APPLY" = "1" ]; then
      cp "$O" "$f"
      cmp -s "$O" "$f" && printf '  %-12s RESTORED, verified by cmp\n' "$f" \
                       || { printf '  %-12s RESTORE FAILED\n' "$f"; exit 2; }
    else
      printf '  %-12s DIFFERS -- would restore (dry run; pass --apply)\n' "$f"
    fi
  fi
done

[ "$CHANGED" = "0" ] && echo "nothing to restore: the interruption left no mutation behind"
echo "==================================================================="

# WHAT THIS GATE DOES NOT COVER -- stated the way the cross-reference census
# states its own limit, because a check whose blind spots are unlisted invites
# the belief that it has none:
#
# 1. It cannot tell a backup of the RIGHT content from a backup of the WRONG
#    content. It proves only that the file was written after the last commit and
#    recently. A pass that backed up an already-mutated file would produce a
#    backup that passes this gate and restores a defect.
# 2. It is useless on a repo with no commits, and weak on one committed rarely --
#    its strongest signal is "newer than HEAD", so the more often you commit, the
#    more it can prove. COMMITTING BEFORE A PASS REMAINS THE REAL PROTECTION;
#    this gate is the backstop for when that was not done.
# 3. It does not run automatically. defect-pass.sh writes its own backups at
#    startup and restores from them in its exit trap, so its restores are fresh
#    by construction. This guards the AD-HOC recovery path -- which is where the
#    loss actually happened -- and only if someone runs it instead of typing cp.
# 4. It says nothing about concurrency. Two passes racing is the PID lock's job;
#    a backup written by a second pass moments ago passes this gate cleanly.
