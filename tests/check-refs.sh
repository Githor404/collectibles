#!/usr/bin/env bash
# CROSS-REFERENCE CENSUS -- every identifier the docs cite must RESOLVE, and the
# brief's rule list must have no duplicate numbers.
#
# WHY IT EXISTS. Renumbering is a RENAME, and a rename that consumers do not
# follow is D3 every time. Inserting two rules into the middle of the brief's
# domain-rule list left it numbered 1-7 then 3,4 -- two duplicates -- with seven
# references pointing at the wrong rules across four files. Nothing failed.
# Attention did not catch it; this does.
#
# Checked over CLAUDE.md, DECISIONS.md and GATES.md:
#   Dnn        -> a "## Dnn" heading exists in DECISIONS.md
#   HT-Dnn     -> a "## Dnn" heading exists in INHERITED-DECISIONS.md
#   HT-Rnn     -> an "### Rnn" heading exists in INHERITED-GATES.md
#   Rn / Rn.m / Rna -> a heading exists in GATES.md
#   "rule(s) N, M and P" -> each N is a number in the brief's domain-rule list
#   the domain-rule list itself -> 1..N, no duplicates, no gaps
#
# A PLANTED CONTROL runs first: a matcher that cannot match reads exactly like a
# clean pass (HT-R6.1's lesson, and HT-D60 Clause 2's).
#
# Deliberately NOT checked: harness case names (ID15, PACE1, ...). Those live in
# the suite, where the assertion-count pin already guards them; matching prose
# against them would be a second, looser census with a worse false-positive rate.
set -uo pipefail

DIR=$(cd "$(dirname "$0")/.." && pwd)
cd "$DIR"

DOCS="CLAUDE.md DECISIONS.md GATES.md"

# ---- definition sets, from the headings that define each identifier ----------
def_D=$(grep -hoE '^## D[0-9]+' DECISIONS.md | grep -oE 'D[0-9]+' | sort -u)
def_R=$(grep -hoE '^#{2,3} R[0-9]+[a-z]?(\.[0-9]+)?' GATES.md | grep -oE 'R[0-9]+[a-z]?(\.[0-9]+)?' | sort -u)
def_HTD=$(grep -hoE '^## D[0-9]+' INHERITED-DECISIONS.md | grep -oE 'D[0-9]+' | sort -u)
def_HTR=$(grep -hoE '^#{2,4} R[0-9]+(\.[0-9]+)?' INHERITED-GATES.md | grep -oE 'R[0-9]+(\.[0-9]+)?' | sort -u)

has() { printf '%s\n' "$2" | grep -qxF "$1"; }

# ---- the scanner: prints one line per unresolved citation -------------------
# $1 = files to scan (space separated), $2 = the brief whose rule list defines rules
scan() {
  local files="$1" brief="$2" out=""
  local rules; rules=$(sed -n '/^## Domain rules/,/^## [A-Z]/p' "$brief" | grep -oE '^[0-9]+\.' | tr -d '.' | sort -un)

  # duplicate / gap check on the rule list itself
  local raw dups n i
  raw=$(sed -n '/^## Domain rules/,/^## [A-Z]/p' "$brief" | grep -oE '^[0-9]+\.' | tr -d '.')
  dups=$(printf '%s\n' "$raw" | sort -n | uniq -d | tr '\n' ' ')
  [ -z "$dups" ] || out="${out}rule list has DUPLICATE number(s): ${dups}\n"
  n=$(printf '%s\n' "$raw" | grep -c .)
  i=1
  while [ "$i" -le "$n" ]; do
    has "$i" "$rules" || out="${out}rule list has a GAP at ${i} (list has ${n} entries)\n"
    i=$((i + 1))
  done

  # Dnn (this repo's) -- never matched when prefixed HT- , because '-' is excluded
  local c
  for c in $(grep -hoE '(^|[^A-Za-z0-9-])D[0-9]+' $files | grep -oE 'D[0-9]+' | sort -u); do
    has "$c" "$def_D" || out="${out}cites ${c}, which is not a heading in DECISIONS.md\n"
  done
  for c in $(grep -hoE 'HT-D[0-9]+' $files | sed 's/HT-//' | sort -u); do
    has "$c" "$def_HTD" || out="${out}cites HT-${c}, which is not a heading in INHERITED-DECISIONS.md\n"
  done
  for c in $(grep -hoE 'HT-R[0-9]+(\.[0-9]+)?' $files | sed 's/HT-//' | sort -u); do
    has "$c" "$def_HTR" || out="${out}cites HT-${c}, which is not a heading in INHERITED-GATES.md\n"
  done
  for c in $(grep -hoE '(^|[^A-Za-z0-9-])R[0-9]+[a-z]?(\.[0-9]+)?' $files | grep -oE 'R[0-9]+[a-z]?(\.[0-9]+)?' | sort -u); do
    has "$c" "$def_R" || out="${out}cites ${c}, which is not a heading in GATES.md\n"
  done

  # "rule 7" / "rules 3, 4 and 7" / "rules 3-5" -- every number must be a rule
  local phrase num
  while IFS= read -r phrase; do
    [ -n "$phrase" ] || continue
    for num in $(printf '%s' "$phrase" | grep -oE '[0-9]+'); do
      has "$num" "$rules" || out="${out}cites \"${phrase}\" but ${num} is not a rule in the brief\n"
    done
  done <<< "$(grep -hoE '[Rr]ules?[[:space:]]+[0-9]+([[:space:],–-]+(and[[:space:]]+)?[0-9]+)*' $files | sort -u)"

  printf '%b' "$out"
}

# ---- GATE-SCRIPT FILENAME CENSUS (D3) ---------------------------------------
# The citation census above resolves Dnn / HT-Dnn / Rnn identifiers. It CANNOT
# see a FILENAME -- and a gate script is referenced by filename in prose, in
# run-data-layer.sh's census manifest, and in defect-pass.sh's row that MOVES it
# by name. Renaming the capture-outcome gate to the layout gate touched FOURTEEN
# references across five files; the reference count was estimated by eye three
# times (10, then 12) and was wrong every time. A single missed one would have
# left a live file pointing at a script that does not exist, and nothing in this
# repo would have said so.
#
# SCANNED OVER A WIDER SET than the citation census: gate filenames appear in the
# test scripts and the harness, not only in the three documents. INHERITED-*.md
# are excluded -- they are frozen at healthtracker@dcf3d78 and name HealthTracker's
# own gates, which do not exist here and must not be rewritten to pretend they do.
#
# WRITING ABOUT A RENAME: this census scans itself and its neighbours, so a
# historical mention of a retired gate WITH its .ps1 suffix would fail the very
# check it documents. Name retired gates without the extension.
# THIS FILE IS DELIBERATELY NOT IN THE SCAN SET, and the reason is structural
# rather than incidental: the planted control below must name a gate script that
# DOES NOT EXIST. A census whose fixture is a nonexistent filename cannot scan
# its own source without failing on its own fixture -- the first version did
# exactly that, reported a clean repo as broken, and made its own defect proof
# vacuous, because the "planted" name was the string the control already emits.
#
# THE LIMIT THIS BUYS, stated so it is not assumed away: a gate filename written
# into check-refs.sh's own prose is outside this census's reach. Nothing else is.
GATE_FILE_SCAN="$DOCS tests/README.md tests/run-all-gates.sh tests/run-data-layer.sh"
GATE_FILE_SCAN="$GATE_FILE_SCAN tests/defect-pass.sh tests/check-egress.sh"
GATE_FILE_SCAN="$GATE_FILE_SCAN tests/restore-backups.sh tests/data-layer.test.html"

gate_files() {   # $1 = files to scan
  local out="" f
  for f in $(grep -hoE '[A-Za-z0-9_-]+-gate\.ps1' $1 2>/dev/null | sort -u); do
    [ -f "tests/$f" ] || out="${out}cites ${f}, which is not a script in tests/\n"
  done
  printf '%b' "$out"
}

# ---- PLANTED CONTROL --------------------------------------------------------
mkdir -p tests/.tmp
CTRL=tests/.tmp/refs-control.md
{
  printf '## Domain rules\n'
  printf '1. **A rule**\n2. **Another**\n2. **A duplicate**\n\n'
  printf '## Elsewhere\n'
  printf 'See D999 and HT-D998 and R997 and HT-R996, per brief rules 3-5.\n'
  printf 'Driven by no-such-layout-gate.ps1, which does not exist.\n'
} > "$CTRL"

# The filename census proves itself on EVERY run, not once when it was written:
# a matcher that cannot match reads exactly like a clean sweep.
CTRL_G=$(gate_files "$CTRL")
if [ -z "$CTRL_G" ]; then
  echo "refs: FAIL - the gate-filename CONTROL did not match a script that does not exist."
  echo "  The matcher is broken, so a clean scan of the real files would mean nothing."
  exit 1
fi
CTRL_OUT=$(scan "$CTRL" "$CTRL")
CTRL_HITS=$(printf '%s' "$CTRL_OUT" | grep -c .)
if [ "$CTRL_HITS" -lt 5 ]; then
  echo "refs: FAIL - the CONTROL found only $CTRL_HITS problems in a file planted with 6."
  echo "  The scanner is broken, so a clean scan of the real docs would mean nothing."
  printf '%s' "$CTRL_OUT" | sed 's/^/    /'
  exit 1
fi

# ---- the real documents -----------------------------------------------------
OUT=$(scan "$DOCS" CLAUDE.md)
if [ -n "$OUT" ]; then
  echo "refs: FAIL - a citation does not resolve, or the rule list is inconsistent:"
  printf '%s\n' "$OUT" | grep -v '^$' | sed 's/^/    /'
  echo "  A rename that consumers do not follow is D3. Repoint the citation, or add the heading."
  exit 1
fi
GOUT=$(gate_files "$GATE_FILE_SCAN")
if [ -n "$GOUT" ]; then
  echo "refs: FAIL - a live file names a gate script that does not exist:"
  printf '%s\n' "$GOUT" | grep -v '^$' | sed 's/^/    /'
  echo "  A rename is only complete when its consumers follow. The citation census"
  echo "  cannot see filenames; this is the half that can."
  exit 1
fi

echo "refs: OK (control caught $CTRL_HITS planted problems and a nonexistent gate script; every citation in $DOCS resolves, rule list contiguous, every gate filename in $(printf '%s' "$GATE_FILE_SCAN" | wc -w | tr -d ' ') live files exists)"
exit 0
