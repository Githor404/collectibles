#!/usr/bin/env bash
# THE DEFECT PASS (HT-D60, adopted as binding by D1).
#
# "A gate is not evidence until it has been run against the defect it closes and
# seen to fail." HealthTracker records that this rule is NOT machine-enforced
# there, and names the missing mechanism exactly: "the enforcing mechanism would
# be a mutation pass -- a runner that flips a known set of properties false and
# asserts that a named gate fails for each". This is that runner.
#
# For each planted defect it mutates the shipped file, runs the gate, and reports
# the verdict AND the first case that failed BY NAME. A defect whose gate fails
# without naming a case is reported as SUSPECT THE FIXTURE -- Clause 4's own
# diagnostic, since an assertion that never runs is not the assertion that caught
# the defect.
#
# Every mutation is perl -0pi, so | and & in the target text cannot be misread as
# regex operators. The file is restored after every run, VERIFIED BY HASH (a
# restore is verified with a hash, never with the next run), and an EXIT TRAP
# restores it even if this script is interrupted.
#
# Usage:  bash tests/defect-pass.sh
# Expect: every row FAIL, each naming its own case. Any row that PASSes is a gate
# that does not gate what it claims.
set -uo pipefail
cd "$(dirname "$0")/.."

TMP="tests/.tmp"
mkdir -p "$TMP"

# MANDATORY under `set -u` above: mutate() increments these, and an unset name in
# $(( )) is a hard error -- so a "fix" that forgot to initialise them would abort
# on the FIRST mutation and break every row while claiming to protect them.
#
# They exist because A MUTATION THAT DOES NOT APPLY MUST BE FATAL (see mutate()).
#
# AND A SECOND REASON THE `git checkout --` BAN BELOW IS RIGHT. That rule was
# written because checkout restores from HEAD and discards uncommitted work. On
# 2026-09-14 it cost something else entirely: under core.autocrlf=true a checkout
# rewrites the working file to CRLF, and every multi-line perl pattern here uses
# \n, which cannot match \r\n. Seven rows stopped planting anything and reported
# GATE: PASS. The blobs were LF the whole time; only the working copy converted,
# and only because the RECOVERY step touched it. Restore with
#   git show HEAD:<file> > <file>
# which writes the blob verbatim, never `git checkout -- <file>`.
ROTTED=0
ROTTED_LIST=""
# EVERY mutated file is backed up by COPY and restored by COPY, verified by hash.
# NEVER `git checkout --` : that restores from HEAD, so it silently discards
# UNCOMMITTED work. One row here did exactly that and destroyed edits made
# minutes earlier. A restore must return the file to what it was, not to what
# was last committed.
# ONE PASS AT A TIME, ENFORCED. Two concurrent passes share one set of .orig
# backups and destroy each other: whichever finishes first deletes them, and the
# other is left with a mutation applied and nothing to restore from. That is not
# hypothetical -- a backgrounded row-37 run was still in its cleanup when a
# rows-38-39 run started, its trailing `rm -f *.orig` removed the newer run's
# backups mid-flight, and all four files reported RESTORE FAILED.
#
# A process check is NOT a substitute for this: the running process is `bash`,
# not `defect-pass`, so `ps | grep defect-pass` returns nothing while a pass is
# very much alive. The lock is the only honest answer.
LOCK="$TMP/.pass.lock"
if [ -e "$LOCK" ] && kill -0 "$(cat "$LOCK" 2>/dev/null)" 2>/dev/null; then
  echo "!! ANOTHER DEFECT PASS IS RUNNING (pid $(cat "$LOCK"))."
  echo "!! Refusing to start: two passes share one set of backups and will"
  echo "!! destroy each other's, leaving files mutated with nothing to restore."
  exit 2
fi
echo $$ > "$LOCK"

MUTATED="app.js index.html CLAUDE.md GATES.md"
for f in $MUTATED; do cp "$f" "$TMP/$(basename "$f").orig"; done
ORIG_APP=$(sha256sum app.js | cut -d' ' -f1)
ORIG_IDX=$(sha256sum index.html | cut -d' ' -f1)
MOVED=""

restore() {
  local f bad=""
  for f in $MUTATED; do
    cp "$TMP/$(basename "$f").orig" "$f"
    cmp -s "$TMP/$(basename "$f").orig" "$f" || bad="$bad $f"
  done
  [ -z "$MOVED" ] || { mv "$MOVED" tests/layout-gate.ps1 2>/dev/null; MOVED=""; }
  [ -z "$bad" ] || { echo "!! RESTORE FAILED for:$bad -- check git status before doing anything else"; return 9; }
}
trap 'restore >/dev/null 2>&1; rm -f "$LOCK"' EXIT INT TERM

# RUN A SUBSET:  ROWS=31-40 bash tests/defect-pass.sh
#
# Forty rows is forty headless browser launches, and this machine has had ~1.3 GB
# free with the user's own browsers resident -- a single forty-row job was killed
# by the OS mid-run, and that kill is what left stale backups for a later step to
# trust. Batching is a data-safety measure here, not a convenience.
#
# KEYED ON `report`, NOT ON `mutate`. There are 38 mutates and 40 reports: rows 5
# and 15 plant their defect WITHOUT one (row 5 moves the gate script aside). A
# mutate-keyed counter would mis-number every row after 5, so `ROWS=31-40` would
# quietly run the wrong ten and report them under the right names -- a worse
# outcome than not batching at all.
#
# The mutation happens BEFORE its report, so the counter has to look ahead: a row
# is in range if the report it is heading for is in range.
ROWS="${ROWS:-1-999}"
ROW_LO=${ROWS%-*}; ROW_HI=${ROWS#*-}
ROW=0
row_wanted() { local n=$((ROW + 1)); [ "$n" -ge "$ROW_LO" ] && [ "$n" -le "$ROW_HI" ]; }

mutate() { # perl-expression, file, [literal-target-for-the-occurrence-check]
  row_wanted || return 0
  # OCCURRENCE CHECK (2026-09-15). A pattern whose target appears MORE THAN ONCE
  # is fragile whatever it happens to hit today, because `perl -0pi` without /g
  # takes the FIRST match -- and the first match is decided by file order, not by
  # intent. Three rows failed this way in one session:
  #   row 55  pinned '0.1.0' and this repo's own version bump silenced it
  #   row 79  matched ` not recognised`, and applied to the LABEL only because a
  #           comment forty lines up writes `as "not recognised"` with a quote
  #           rather than a space before the word
  #   row 82  matched `title mentions CGC`, which occurs THREE times -- the
  #           module comment, the label, and the changelog note. It took the
  #           comment, APPLIED, planted nothing, and the fatal check below stayed
  #           silent because the file HAD changed. GATE: PASS, testing nothing.
  #
  # Row 82 is the one this exists for. The fatal check below catches a mutation
  # that does not apply; it cannot catch one that applies to the WRONG TARGET,
  # and that failure is silent where the other is loud.
  #
  # ROUTED THROUGH ROTTED, not a second failure path. That machinery already
  # stops the pass, prints the loud block and exits 1; a parallel mechanism would
  # be one more thing to keep in step, which is the drift this file keeps paying
  # for.
  #
  # OPT-IN, AND THAT IS A REAL LIMITATION. The check needs the literal target,
  # and recovering it from an arbitrary s/// expression means parsing escaped
  # delimiters -- fragile in exactly the way this guard exists to prevent. So a
  # row passes its target as a third argument, and a row that does not pass one
  # is unprotected. It covers the population that actually fails: all three
  # misfires above were in NEWLY WRITTEN rows, where the author is right there
  # and can add it. A guard that protects only the rows that ask is weaker than
  # one that protects all 83, and that is stated rather than glossed.
  if [ -n "${3:-}" ]; then
    local hits
    hits=$(grep -cF -- "$3" "$2" 2>/dev/null || echo 0)
    if [ "$hits" -ne 1 ]; then
      ROTTED=$((ROTTED + 1))
      ROTTED_LIST="$ROTTED_LIST
    row $((ROW + 1)) ($2): target occurs $hits times, needs exactly 1 -- '$3'"
      echo "!! AMBIGUOUS TARGET ($hits occurrences, need 1): $3"
      return 0
    fi
  fi
  # The guard compares against the file's OWN backup, so it covers every file in
  # MUTATED. Keyed to two hardcoded hashes it silently skipped the rest, and a
  # mutation that failed to apply would have produced a row that proves nothing --
  # a vacuous gate, which is what HT-D60 Clause 4 is about.
  perl -0pi -e "$1" "$2"
  # FATAL SINCE 2026-09-14, and the reason is a full pass that lied.
  #
  # This detection has always worked. What it did was ECHO A LINE and return 0 --
  # so the row went on to run a CLEAN suite, and report() printed GATE: PASS for a
  # row that had planted nothing. Seven rows did exactly that in one run, each
  # announcing its own failure, in a 61-row table where seven warnings scroll past.
  # They were found only because the danger signals were grepped for deliberately,
  # and the pass exited 0 throughout.
  #
  # A warning that does not change the verdict is not a gate. A row that cannot
  # plant its defect must STOP THE PASS: the run is not evidence, and the one
  # thing worse than no evidence is evidence that reads green.
  if cmp -s "$TMP/$(basename "$2").orig" "$2"; then
    ROTTED=$((ROTTED + 1))
    ROTTED_LIST="$ROTTED_LIST
    row $((ROW + 1)) ($2): $1"
    echo "!! MUTATION DID NOT APPLY (the text moved): $1"
  fi
}
# REAP AFTER EVERY ROW. Forty rows is forty headless Chrome launches, and a
# profile process that outlives its --dump-dom accumulates. A backgrounded pass
# was killed by the OS partway through with 75 browsers alive -- and the kill is
# what left stale backups lying around for a later step to trust, which cost
# three hours of work. Flat memory is therefore a DATA-SAFETY property here, not
# a tidiness one.
#
# Matched on `--headless`, NOT on the profile path: an earlier attempt keyed to
# the profile found ZERO while 51 browsers were running, so that discriminator
# does not hold. Nobody browses headless, so this cannot touch a real window.
reap() {
  powershell -NoProfile -Command "
    Get-CimInstance Win32_Process -Filter \"Name='chrome.exe' OR Name='msedge.exe'\" |
      Where-Object { \$_.CommandLine -like '*--headless*' -or \$_.CommandLine -like '*dl-profile*' } |
      ForEach-Object { try { Stop-Process -Id \$_.ProcessId -Force -ErrorAction Stop } catch {} }
  " >/dev/null 2>&1 || true
}
# GUARDED -- and the absence of this guard was costing ~20x on every subset run.
#
# `report "name" "pat" "$(run_dl)"` evaluates the command substitution BEFORE
# calling report, so an unguarded run_dl ran the FULL SUITE for all 40 rows on
# every invocation. ROWS= skipped the mutation and the reporting; it never
# skipped the expensive part.
#
# The evidence was visible and was misread: ROWS=31-32 took 497s, ROWS=34-36 took
# 494s, ROWS=40-41 took 541s. A constant elapsed time with NO relationship to the
# number of rows selected is the signature of a fixed cost -- it was read as
# "~250s per row" instead, and every batching and timeout decision was built on
# that. One data-layer run was ~12s; a full 41-row pass was ~500s (2026-09-13;
# current figures, each with its size, are in tests/README.md).
run_dl() {
  row_wanted || return 0
  # DEFECT_PASS carries THIS pass's PID, which is also what the lock holds. The
  # version gate stands down only on a match, so the flag cannot be forged from a
  # shell and cannot outlive the pass that set it. See run-data-layer.sh.
  local o; o=$(DEFECT_PASS=$$ timeout 300 bash tests/run-data-layer.sh 2>&1); reap; printf '%s' "$o"
}
# Same runner, with a CHOSEN DEFECT_PASS value -- the seam that lets a row forge
# the stand-down from inside a real pass and prove it fails loudly.
run_dl_as() {
  row_wanted || return 0
  local o; o=$(DEFECT_PASS="$1" timeout 300 bash tests/run-data-layer.sh 2>&1); reap; printf '%s' "$o"
}
# check-version.sh DIRECTLY, because the stand-down suppresses it inside a pass --
# so a row testing the version gate's OWN arms cannot reach it through run_dl.
# The script speaks its own vocabulary ("check-version: FAIL"), not the runner's,
# so the exit code is translated into the GATE: line `report` reads. Cheap: no
# browser, no suite.
run_cv() {
  row_wanted || return 0
  local o rc
  o=$(bash tests/check-version.sh 2>&1); rc=$?
  printf '%s\nGATE: %s\n' "$o" "$([ "$rc" = 0 ] && echo PASS || echo FAIL)"
}
# THE LAYOUT GATE, for rows whose claim is GEOMETRIC. run_dl() runs the
# data-layer suite, which sees markup and cannot see geometry -- the comps row
# shipped as three unstyled inline spans, reached a phone as one run of text, and
# every data-layer assertion was green while it did. A row planting a layout
# defect must run the gate that can measure one.
#
# Invocation mirrors run-all-gates.sh exactly rather than being reinvented.
# MEASURED COST: ~140s, against ~12s for run_dl -- a row using this is worth
# about twelve ordinary rows, and the full pass goes ~500s -> ~645s.
run_layout() {
  row_wanted || return 0
  local o; o=$(timeout 400 powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/layout-gate.ps1 2>&1)
  reap; printf '%s' "$o"
}
report() { # name, expected-case-pattern, output
  local name="$1" pat="$2" out="$3" verdict named
  ROW=$((ROW + 1))
  # Advance unconditionally so numbering is identical whether or not a subset is
  # running -- a row's number must mean the same thing in every invocation.
  if [ "$ROW" -lt "$ROW_LO" ] || [ "$ROW" -gt "$ROW_HI" ]; then return 0; fi
  verdict=$(printf '%s\n' "$out" | grep -oE 'GATE: (PASS|FAIL)' | tail -1)
  named=$(printf '%s\n' "$out" | grep -E "^FAIL +.*(${pat})" | head -1 | sed -E 's/^FAIL +//' | cut -c1-80)
  # SECOND STRICT ARM: a failure reported by a SCRIPT rather than by res(). The
  # censuses, check-egress, check-version and the layout gate print their own
  # "<name>: FAIL - ..." or "NOT MEASURABLE" lines, which structurally cannot
  # carry res()'s "FAIL  " prefix. In the first full pass after the WEAK-MATCH
  # label shipped, NINE of its ten hits were exactly this -- strong evidence
  # wearing a weak label. That is the want-list's own noise argument pointed at
  # the harness: a label that cries wolf on good evidence gets ignored, and then
  # the one hit that MATTERED (row 47, matching on a PASS line) reads like the
  # other nine. Narrowing the weak arm is what keeps the label worth reading.
  [ -n "$named" ] || named=$(printf '%s\n' "$out" \
    | grep -E "(FAIL -|FAIL:|NOT MEASURABLE).*(${pat})|(${pat}).*(FAIL -|FAIL:|NOT MEASURABLE)" \
    | head -1 | cut -c1-80)
  # THE WEAK ARM, and it now says so. When no FAILING line carries the pattern
  # this greps the WHOLE output -- PASS lines, assertion labels, comments. A row
  # whose pattern matched only a PASSING line would otherwise print a plausible
  # "first named failure" and no warning: the CQ7 tautology, living in the
  # reporting function instead of in one assertion, where it would corrupt every
  # row's evidence rather than a single row's. The only tell was that the strict
  # arm strips a "FAIL " prefix and this one does not -- inside an 80-column cut.
  #
  # KEPT, not deleted: it is what yields a usable diagnostic when a gate fails in
  # an UNEXPECTED way. Labelled, so a weak match can never be read as a strong one.
  [ -n "$named" ] || { named=$(printf '%s\n' "$out" | grep -E "(${pat})" | head -1 | cut -c1-80)
                       [ -z "$named" ] || named="WEAK-MATCH: $named"; }
  printf '%-34s %-9s %s\n' "$name" "${verdict:-NO-VERDICT}" "${named:-(NOTHING NAMED MATCHED -- SUSPECT THE FIXTURE)}"
}

echo "=== defect pass (HT-D60) =========================================="
printf '%-34s %-9s %s\n' "planted defect" "verdict" "first named failure"
echo "-------------------------------------------------------------------"

# 1. the decode leash removed (HT-D47: the version without it hung)
mutate 's/Promise\.race\(\[byokDecodeBitmap\(file\), leash\]\)/Promise.race([byokDecodeBitmap(file)])/' app.js
report "decode leash removed" "LE1" "$(run_dl)"; restore

# 2. the first reply thrown away on a failed retry (HT-D64)
mutate 's/return byokFallback\(r1\.text, String\(r2\.error/return byokFallback(String(), String(r2.error/' app.js
report "fallback discards raw reply" "VR4" "$(run_dl)"; restore

# 3. the trace never reaches the surface (HT-D65)
mutate 's/const traceHTML = traceTxt \?/const traceHTML = false ?/' app.js
report "trace not rendered" "TR3" "$(run_dl)"; restore

# 4. the credential written into the state object (HT-D45 Fork F)
mutate 's/  const ok = credPatch\(role, next\);/  const ok = credPatch(role, next); try { APP_STATE.settings._k = next.key; } catch (e) {}/' app.js
report "key written into APP_STATE" "K1" "$(run_dl)"; restore

# 5. a second network site, outside egress (D1)
# GUARDED, like mutate(). This plant does NOT go through mutate(), so a ROWS=
# subset executed it anyway -- appending phoneHome to app.js on every run whatever
# the range. Harmless while the restore works; when a concurrent pass destroyed
# the backups it survived, failed the egress census, and the diagnosis had to
# start from "+44 unexplained bytes" because a mutation-signature sweep does not
# know about a defect planted by append.
row_wanted && printf '\nfunction phoneHome(u) { return fetch(u); }\n' >> app.js
report "a second fetch site" "egress: FAIL" "$(run_dl)"; restore

# 6. credential writes REBUILD instead of merging (HT-D49)
mutate 's/const o = credRead\(role\) \|\| \{\};\n  Object\.keys/const o = {};\n  Object.keys/' app.js
report "credential write rebuilds" "K2" "$(run_dl)"; restore

# 7. pacing removed (D1: 1 call/s, and the penalty is the subscription)
mutate 's/  if \(!\(gap > 0\)\) return Promise\.resolve\(\);/  return Promise.resolve();/' app.js
report "pacing removed" "PACE1" "$(run_dl)"; restore

# 8. redaction removed (D1: a provider that echoes the credential back)
mutate "s/s = s\.split\(String\(secret\)\)\.join\('\[redacted\]'\)/s = s/" app.js
report "redaction removed" "PC3|TC4" "$(run_dl)"; restore

# 9. the product check removed from restore (D1: two apps, one origin)
mutate 's/Array\.isArray\(o\) \|\| o\.kind !== STATE_KIND\)/Array.isArray(o))/' app.js
report "wrong-product export accepted" "E2" "$(run_dl)"; restore

# 10. a success becomes dismissable (HT-D51)
mutate "s/  if \(captureOutcomeState\(\) !== 'error'\) return \{ ok: false, kind: 'not-dismissable' \};//" app.js
report "success dismissable" "OM3" "$(run_dl)"; restore

# 11. the blank-canvas floor removed (HT-D47: iOS returns a blank canvas)
mutate 's/out\.length < BYOK_MIN_DATAURL/false/' app.js
report "blank-canvas floor removed" "EN1" "$(run_dl)"; restore

# 12. the EXIF pin removed (HT-D58): the STRUCTURAL case must fail; the
#     behavioural one cannot on this browser, which is why both exist.
mutate "s/createImageBitmap\(file, \{ imageOrientation: 'from-image' \}\)/createImageBitmap(file)/" app.js
report "EXIF pin removed" "CL5" "$(run_dl)"; restore

# 13. auth 'none' still demands a credential (D1: the server move)
mutate "s/  const needsKey = row\.auth === 'bearer' \|\| row\.auth === 'query';/  const needsKey = true;/" app.js
report "auth none demands a key" "CFG1" "$(run_dl)"; restore

# 14. a synchronous throw mid-suite: the count pin and harness integrity
mutate "s/function credMask\(role\) \{/function credMask(role) { throw new Error('planted');/" app.js
report "a case throws mid-suite" "HARNESS|ASSERTION COUNT" "$(run_dl)"; restore

# 15. the gate-script census: a gate renamed away
# GUARDED for the same reason as row 5's plant: it bypasses mutate(), so a ROWS=
# subset moved the gate script aside regardless of range.
row_wanted && { mv tests/layout-gate.ps1 "$TMP/layout-gate.ps1.moved"; MOVED="$TMP/layout-gate.ps1.moved"; }
report "gate script renamed away" "CENSUS" "$(run_dl)"; restore

# ---- R1 / D2: the identification contract ---------------------------------

# 16. the refusal emptied (D2, HT-D45 Fork H): a value or a grade would ride in
mutate 's/const ID_REFUSED_KEYS = \[[\s\S]*?\];/const ID_REFUSED_KEYS = [];/' app.js
report "value/grade refusal removed" "ID2" "$(run_dl)"; restore

# 17. absence zero-filled instead of left absent (D2 Fork B1)
mutate "s/    if \(v && !ID_ABSENT_RE\.test\(v\)\) fields\[k\] = v;/    fields[k] = v || 'unknown';/" app.js
report "absent fields guessed" "ID4" "$(run_dl)"; restore

# 18. the marker vocabulary opened (D2 Fork B1: only what is visible, from a list)
mutate 's/    if \(ID_MARKERS\.indexOf\(s\) >= 0\) \{ if \(markers\.indexOf\(s\) < 0\) markers\.push\(s\); \}/    if (true) { if (markers.indexOf(s) < 0) markers.push(s); }/' app.js
report "marker vocabulary opened" "ID5" "$(run_dl)"; restore

# 19. a correction overwrites what the model read (HT-D55/D57 correction loop)
mutate 's/  if \(s\) v\.fields\[key\] = s; else delete v\.fields\[key\];/  if (s) { v.fields[key] = s; v.ai.fields[key] = s; } else delete v.fields[key];/' app.js
report "correction erases the original" "ID7" "$(run_dl)"; restore

# 20. the query built from the model's originals rather than the confirmed fields
mutate 's/  const f = \(v && v\.fields\) \|\| \{\};/  const f = (v \&\& v.ai \&\& v.ai.fields) || {};/' app.js
report "query ignores corrections" "ID8" "$(run_dl)"; restore

# 21. the prompt boxes stop being filled -- HealthTracker's dead floor, exactly (HT-D63)
mutate 's/\n  renderPromptCard\(\);\n  renderConfirmed\(\);/\n  renderConfirmed();/' app.js
report "no-key floor unfilled" "ID11" "$(run_dl)"; restore

# 22. a grade control planted above the identity question (D2: identity first,
#     and the app never takes a grade from the model)
mutate 's/<div class="idq">Is this the book\?<\/div>/<label>Grade<\/label><select id="idGrade"><option>9.4<\/option><\/select><div class="idq">Is this the book?<\/div>/' app.js
report "grade control in the draft" "ID6" "$(run_dl)"; restore

# 23. the shipped sample drifts from the parser (HT-D11 self-consistency)
mutate 's/const ID_SAMPLE = .\{"title"/const ID_SAMPLE = \x27{"titel"/' app.js
report "sample drifts from the parser" "ID1" "$(run_dl)"; restore

# ---- R1.1: the asking price (D2 amendment) --------------------------------

# 24. the asking price accepted as identification data
mutate "s/'key_issue', 'key', 'asking_price'/'key_issue', 'key'/" app.js
report "asking price accepted" "ID14" "$(run_dl)"; restore

# 25. the refusal OVER-REACHES and swallows the printed cover price -- the other
#     direction, and the error R1-identity-first made once already
mutate "s/const ID_REFUSED_KEYS = \['value',/const ID_REFUSED_KEYS = ['cover_price', 'value',/" app.js
report "refusal swallows cover price" "ID14|ID3" "$(run_dl)"; restore

# 26. the template's sticker line removed (the copy-prompt path has only words)
mutate 's/\x27- "cover_price" is the price PRINTED[\s\S]*?anyone is asking for the book\.\\n\x27 \+\n//' app.js
report "sticker line removed" "ID14" "$(run_dl)"; restore

# 27. the header prepends a # to an issue that already carries one -- the bug the
#     first device capture reported, as "STAR WARS ##2" (R1.2)
mutate "s/issueLabel\(f\.issue\)/(f.issue ? '#' + f.issue : '')/g" app.js
report "double # in the header" "ID15" "$(run_dl)"; restore

# ---- D9: no credential field without a call behind it ----------------------

# 30. the deferred provider's settings card put back
mutate 's{<div class="card" data-setting="vision">}{<div class="card" data-setting="prices"><details><summary>Price-guide token (PriceCharting)</summary><div id="credBox-prices"></div></details></div>\n      <div class="card" data-setting="vision">}' index.html
report "deferred provider's field restored" "D9" "$(run_dl)"; restore

# ---- the cross-reference census: renumbering is a rename (D3) --------------
# CLAUDE.md and GATES.md are in MUTATED, so restore() covers them by copy.

# 28. a duplicate rule number -- the exact break that went unnoticed
mutate 's/^7\. \*\*Cover price and asking price/3. **Cover price and asking price/m' CLAUDE.md
report "duplicate rule number" "DUPLICATE" "$(run_dl)"; restore

# 29. a citation to a rule that does not exist.
#
# A LIMIT OF THIS GATE, not a detail. The break that prompted it was "rules 3-5"
# pointing at the WRONG rules after a renumber -- and 3, 4 and 5 all still EXIST,
# so RESOLUTION ALONE CANNOT SEE IT. The first version of this row planted exactly
# that and the gate PASSED, which is why it is written this way instead.
#
# What the census does catch: an unresolvable citation, and a duplicated or gapped
# rule list. The original break is caught by the NUMBERING half (row 28), which is
# what was inconsistent at the time. A citation that resolves to the wrong thing,
# while the list is consistent, is beyond a mechanical check -- stated here rather
# than left for someone to assume otherwise (HT-D60 Clause 2).
mutate 's/brief rules 3, 4 and 7/brief rules 3, 4 and 77/' GATES.md
report "citation to a nonexistent rule" "not a rule in the brief" "$(run_dl)"; restore

# ============ R2b / D10 — the sold-comps rows (31-40) ============
# Thirteen CQ cases arrived with R2b and NONE of them was evidence until it had
# been seen to fail. These are the defects each one closes.

# --- 31. the asking price wears the sold price's clothes ---------------------
# The worst failure available to this product, and it is ONE BOOLEAN. The actor's
# own docs: with includeCompletedListings false, a Best-Offer sale reports the
# seller's ASKING price in `soldPrice`. Brief rule 7's conflation, committed
# inside the data source, in the single field the app reads, with nothing on any
# surface to show it happened.
mutate 's/    includeCompletedListings: true,/    includeCompletedListings: false,/' app.js
report "asking price as soldPrice" "includeCompletedListings is pinned TRUE" "$(run_dl)"; restore

# --- 32. the window quietly becomes the vendor's default ---------------------
# Fork C ruled 90 days. The actor defaults to 30. Deleting the line does not
# error, does not warn, and still renders "last 90 days" from the constant --
# a surface stating a window the request never asked for.
mutate 's/    daysToScrape: COMPS_WINDOW_DAYS,\n//' app.js
report "window falls back to the default" "the window is pinned to 90" "$(run_dl)"; restore

# --- 33. the mixed scatter gets a range across it ---------------------------
# D8 as amended. The endpoints come from two different markets, so "$9-$145"
# describes no book anyone can buy -- and it reads as a valuation exactly the way
# an average would.
# NO TEMPLATE LITERAL IN THE REPLACEMENT. A first version spliced `${...}` and
# backticks into the replacement half and perl never saw them intact: it died with
# "syntax error near sorted[", the mutation did not apply, and the row reported
# GATE: PASS against UNMUTATED source -- a vacuous row, Clause 4's own failure.
# The repo moved every mutation to perl -0pi to fix this class on the PATTERN
# half; the REPLACEMENT half was never covered. Plain concatenation instead.
mutate 's/  const head = .<div class="cmphead">\$\{n\} sold · last \$\{esc\(win\)\}<\/div>.;/  const head = "<div class=\\"cmphead\\">" + n + " sold · last " + esc(win) + " · " + compsMoney(sorted[0].soldPrice) + "-" + compsMoney(sorted[sorted.length - 1].soldPrice) + "<\/div>";/' app.js
report "a range across two markets" "no range spans them" "$(run_dl)"; restore

# --- 34. raw and slabbed, split on what the title says -----------------------
# THE defect D10 exists to refuse, and the fixture is built to catch it in the
# adversarial direction: a $9 RAW book titled "CGC READY". A grader's name in a
# title is a marketing claim, not a certification field.
# Same lesson as the row above: no inline function, no template literal, no
# backtick in the replacement. The defect is planted UPSTREAM instead -- `sorted`
# is reordered into slabbed-then-raw with a heading injected between, which is
# exactly the grouping D10 forbids, and the render below is left untouched.
mutate 's/  const sorted = COMPS\.rows\.slice\(\)\.sort\(function \(a, b\) \{ return a\.soldPrice - b\.soldPrice; \}\);/  var _slab = COMPS.rows.filter(function (r) { return \/CGC|CBCS|PGX\/i.test(r.title); });\n  var _raw = COMPS.rows.filter(function (r) { return !\/CGC|CBCS|PGX\/i.test(r.title); });\n  const sorted = _slab.concat(_raw);\n  COMPS.groupHeadings = "Slabbed\/Raw";/' app.js
# PATTERN REPOINTED. It used to grep for "never as group headers" -- a phrase that
# stopped existing when the tautological CQ7 assertion was replaced by three real
# ones. The row still FAILED correctly; it just could not name what caught it, and
# reported (NOTHING NAMED MATCHED -- SUSPECT THE FIXTURE) instead. D3 at its
# smallest: an assertion was renamed and its consumer did not follow. The
# cross-reference census cannot see this, because it scans the DOCS, not these
# patterns. The mutation reorders comps to 145,9,16.21,... so the ordering
# assertion is the one that fires.
report "groups from a title heuristic" "ASCENDING PRICE" "$(run_dl)"; restore

# --- 35. D4's GCD rule is applied to eBay again ------------------------------
# The over-generalisation this slice found: "never append the issue number" was
# measured on GCD, where it is right, and written as binding on any catalog
# search. On eBay it returns every issue of the series ever sold.
mutate 's/  return \[title, issue\]\.filter\(Boolean\)\.join\(. .\)/  return [title].filter(Boolean).join(" ")/' app.js
report "issue number dropped from eBay" "THE ISSUE NUMBER STAYS" "$(run_dl)"; restore

# --- 36. the query goes back to read-only ------------------------------------
# D4 recorded that making it editable was R2's job. A query you can see but not
# send is a label, not a control.
# NO BACKTICK IN THE REPLACEMENT (the third row to carry this shape; two of them
# reported a vacuous GATE: PASS before it was caught). The target line lives
# INSIDE a backticked template string, so the mutation matches only the attribute
# text and leaves every backtick where it is.
mutate 's/oninput="compsSetQuery\(this\.value\)" aria-label="Search eBay/readonly aria-label="Search eBay/' app.js
report "query editable in name only" "no longer read-only" "$(run_dl)"; restore

# --- 37. the grade rides along in the request body ---------------------------
# Brief rules 3 and 4. The surface would look identical; only the body changes.
mutate 's/    includeCompletedListings: true,/    includeCompletedListings: true,\n    grade: "9.4",/' app.js
# REPOINTED 2026-09-14 (HT-D60 Clause 3 -- repointed, not weakened). The old
# expected string was "carrying the grade or the asking price is REFUSED", which
# matches a PASSING assertion: there are TWO under the CQ4 prefix, and that one
# tests the REFUSAL MECHANISM against a synthetic body, so it still passes when
# the REAL body is polluted. The mechanism was never the thing that broke.
#
# Found by report()'s WEAK-MATCH label on its first full pass, and settled by a
# probe rather than a source reading: the planted grade makes TWO assertions fail
# -- this one and AK11 -- so the suite was never blind to the defect. The ROW was
# reporting the wrong line, which is a defect in the evidence, not in the gate.
report "grade enters the lookup" "a real body carries no grade and no asking price" "$(run_dl)"; restore

# --- 38. the spending token loses its warning --------------------------------
# The defect found while building: gated on a role NAME, the one credential that
# can spend money was the one with no warning at all.
mutate "s/  const warn = row\.warn/  const warn = (role === 'prices') \&\& row.warn/" app.js
report "spend warning re-gated to a role" "SPENDS" "$(run_dl)"; restore

# --- 39. a second keyword quietly doubles the bill ---------------------------
# `count` is PER KEYWORD, so keywords.length is half the bill. A bound that reads
# only `count` cannot see this.
mutate 's/    keywords: \[String\(query == null \? .. : query\)\],/    keywords: [String(query == null ? "" : query), "comic"],/' app.js
report "a second keyword doubles cost" "EXACTLY ONE keyword" "$(run_dl)"; restore

# --- 40. the filter hides rows without saying so -----------------------------
# A filter the user cannot see is a filter they cannot correct -- and the thing
# it hid might have been the right book.
mutate 's/    if \(why\) dropped\.push\(\{ title: r\.title, why: why \}\); else kept\.push\(r\);/    if (!why) kept.push(r);/' app.js
report "silent exclusions" "COUNTED ON THE SURFACE" "$(run_dl)"; restore

# --- 41. the Publisher aspect is used because it demonstrably works ----------
# Measured queryable 2026-09-13 ({"Publisher":"DC Comics"} -> ZERO) and refused
# anyway. eBay aspects are filled by the sellers who fill structured fields, so
# filtering on one drops the raw majority and biases the scatter toward the
# graded end. A filter that narrows CORRECTLY can still corrupt, by selection --
# and a dropped row leaves no trace on the surface.
mutate 's/    includeCompletedListings: true,/    includeCompletedListings: true,\n    aspectFilter: { Publisher: "Marvel Comics" },/' app.js
report "publisher aspect biases the sample" "sends NO aspectFilter" "$(run_dl)"; restore

# --- 42. provenance stripped from a rendered number --------------------------
# Pre-registered in R2b's demand list and never written, so CQ7's count-and-
# window assertion had NEVER been seen to fail -- HT-D60 Clause 1, live in the
# repo. A number without its count and its window is a claim with no denominator.
mutate 's/  const head = .<div class="cmphead">\$\{n\} sold · last \$\{esc\(win\)\}<\/div>.;/  const head = "<div class=\\"cmphead\\">Recent sales<\/div>";/' app.js
report "provenance stripped from the render" "the count is the KEPT count" "$(run_dl)"; restore

# --- 43. a synthesised ladder ------------------------------------------------
# The other pre-registered row never written. Plants exactly what D8 forbids: an
# AVERAGE of the scatter, rendered as though it were a sale. It is a number
# BETWEEN the sales that nothing sold for -- which is why the gate it fails is
# "every price is one something actually sold for" rather than a search for the
# word "ladder". Checking for the absence of a ladder is unbounded; checking that
# every price traces to a sale is not.
mutate 's/  const sorted = COMPS\.rows\.slice\(\)\.sort\(function \(a, b\) \{ return a\.soldPrice - b\.soldPrice; \}\);/  var _avg = COMPS.rows.reduce(function (a, r) { return a + r.soldPrice; }, 0) \/ (COMPS.rows.length || 1);\n  const sorted = COMPS.rows.concat([{ title: "estimated at this grade", soldPrice: _avg, soldCurrency: "USD", endedAt: "", bestOffer: false }]).sort(function (a, b) { return a.soldPrice - b.soldPrice; });/' app.js
report "a synthesised ladder" "ACTUALLY SOLD FOR" "$(run_dl)"; restore

# --- 44. the comps row collapses back into one run of text -------------------
# The first live device pass, verbatim off a phone:
#   "$52.46The Incredible Hulk #271 First Rocket Raccoon Appearance 198217/08"
# Three fields with no elements and no CSS between them. This restores exactly
# that concatenation -- price, title and date emitted bare into one div, with the
# title's trailing year running into the date.
mutate 's/function compsRowHTML\(r\) \{[\s\S]*?\n\}/function compsRowHTML(r) {\n  return "<div class=\\"cmprow\\">" + esc(compsMoney(r.soldPrice, r.soldCurrency)) + esc(r.title) + esc(compsDate(r.endedAt)) + "<\/div>";\n}/' app.js
report "comps row collapses to one run" "THREE distinct elements" "$(run_dl)"; restore

# --- 45. the comps row collapses -- measured in a VIEWPORT this time ---------
# Row 44 plants this same concatenation and proves the STRUCTURAL gate. This one
# proves the LAYOUT gate: the half that could have caught the defect that
# actually shipped, because --dump-dom sees markup and geometry is invisible to
# it. Two rows, one mutation, two different claims.
#
# THE PATTERN IS TAKEN FROM THE STRING THE GATE WAS OBSERVED TO PRINT, not from
# this file's source: a prediction of it said "price=False" where the gate
# prints "price=false". "not its own element" is case-stable and was copied out
# of a real failing run.
mutate 's/function compsRowHTML\(r\) \{[\s\S]*?\n\}/function compsRowHTML(r) {\n  return "<div class=\\"cmprow\\">" + esc(compsMoney(r.soldPrice, r.soldCurrency)) + esc(r.title) + esc(compsDate(r.endedAt)) + "<\/div>";\n}/' app.js
report "comps row, measured in a viewport" "not its own element" "$(run_layout)"; restore

# ============ R3 / D11-D13 -- the ask against the scatter (46-52) ============

# --- 46. the marker placed by a wrong comparator -----------------------------
# Reversing the test puts the ask at the FRONT of the scatter instead of at its
# position. Note the mutation that does NOT work: `>` -> `>=` is inert at ask=30
# because no sale equals 30, which is why AK14's tie case had to exist first.
mutate 's/    if \(!placed && r\.soldPrice > ASK\) \{ out\.push\(mk\); placed = true; \}/    if (!placed \&\& r.soldPrice < ASK) { out.push(mk); placed = true; }/' app.js
report "ask marker placed by wrong test" "the ask renders INTO the scatter at its position" "$(run_dl)"; restore

# --- 47. an off-by-one at the tie boundary -----------------------------------
# Sales at exactly the ask get counted as "at" AND as "above", so the three terms
# no longer sum to the rendered count. Inert wherever at === 0, which is every
# case except AK14 -- the reason that case was written before this row.
mutate 's/  const at = rows\.filter\(function \(r\) \{ return r\.soldPrice === ASK; \}\);/  const at = rows.filter(function (r) { return r.soldPrice >= ASK; });/' app.js
report "off-by-one at the tie boundary" "sum to the rendered count" "$(run_dl)"; restore

# --- 48. a percentile reintroduced -------------------------------------------
# D13's exact defect: the same count, expressed as a ratio, which reads as a
# score out of a hundred and invites "so it's about average".
# A PRECOMPUTED LITERAL, not an expression. The first version wrote
# `${Math.round(100 * c.below / c.total)}%` into the replacement and perl read
# the `/` as opening a regex: "Illegal division by zero", mutation never applied,
# row would have been vacuous. 2 of 9 below the ask is 22%; hardcoding it
# exhibits the identical defect without asking perl to evaluate arithmetic.
# EVERY `$` IN THE REPLACEMENT IS ESCAPED. The first version left `${c.below}`
# bare and perl read it as a deref, emptying it -- the row still reported the
# right verdict because AK7 fires on percentile words and does not care that the
# count went blank. An impure mutation that happened to land.
mutate 's/    `<div class="askcount"><b>\$\{c\.below\}<\/b> sold below/    `<div class="askcount">cheaper than 22% of sales · <b>\${c.below}<\/b> sold below/' app.js
report "a percentile on the surface" "no percentage, percentile, median" "$(run_dl)"; restore

# --- 49. the grade wired into the filter -------------------------------------
# Rule 2 as amended, and D10's adversarial reason: an advisory attestation that
# quietly starts selecting comps.
mutate 's/  const below = rows\.filter\(function \(r\) \{ return r\.soldPrice < ASK; \}\)/  const below = rows.filter(function (r) { return r.soldPrice < ASK \&\& (!GRADE || r.title.indexOf(GRADE) >= 0); })/' app.js
# PATTERN REPOINTED. It named AK8's FIRST clause, which passes: the mutation
# touches askComparison's `below` filter, not the scatter, so "byte-identical"
# still holds. What fails is AK8's SECOND clause, on the counts.
report "grade wired into the filter" "counts are untouched by it" "$(run_dl)"; restore

# --- 50. the bulk rate divided -----------------------------------------------
# D12: $40 / 5 = $8, a number the seller never said, rendered exactly like a fact.
# THE DIVIDED FIGURE AS A LITERAL. The first version computed it in the
# replacement and perl ate it twice over: the `/` opened a regex and `"$"` is
# perl's list separator. "5 for $40" divided is $8, so plant $8 -- the defect is
# identical and perl evaluates nothing.
mutate 's/  const src = ASK_TERMS \? .your figure, from: . \+ ASK_TERMS : .the price you were quoted.;/  const src = "\$8 each";/' app.js
report "a bulk rate divided per book" "appears NOWHERE" "$(run_dl)"; restore

# --- 51. a second, unlabelled number on the surface --------------------------
# CQ7 as extended: exactly ONE price may be something nobody paid, and only while
# it carries its label. This adds a bare number with no provenance at all.
# A PRECOMPUTED LITERAL again. The first version used `.toFixed(2)` and perl
# parsed it as a subroutine call -- "Undefined subroutine &main::toFixed". $37.50
# is a price no comp in the fixture holds and the ask is not, which is precisely
# the defect: a number on the surface that nobody paid and nothing labels.
mutate 's/    `<div class="askcount"><b>\$\{c\.below\}<\/b> sold below/    `<div class="askcount"><span class="cmpprice">\$37.50<\/span> <b>\${c.below}<\/b> sold below/' app.js
report "an unlabelled second number" "ACTUALLY SOLD FOR" "$(run_dl)"; restore

# --- 52. the ask reaches the request body ------------------------------------
# Brief rules 3 and 5. CQ4 was theoretical until R3 gave the ask a real input;
# this is the row that makes it load-bearing.
mutate 's/    includeCompletedListings: true,/    includeCompletedListings: true,\n    maxPrice: ASK,/' app.js
report "the ask reaches the request body" "neither the ask nor the grade reaches a request body" "$(run_dl)"; restore

# --- 53. the ask surface never painted -- measured in a VIEWPORT --------------
# A REAL BUG, RE-PLANTED. __setComps stood in for a completed lookup and called
# renderComps alone, so the ask inputs were never painted. The data-layer suite
# stayed green throughout, because its fixture called CT.renderAsk() by hand --
# 27 assertions passing against a sequence the shipped app never performed.
#
# The layout gate caught it: askBox present, phase done, rows 4, innerHTML
# length 0. Two hypotheses read off the source were both wrong before a
# four-fact probe inside the gate's own browser settled it.
#
# Pattern copied from the OBSERVED failure string, not written from source.
mutate 's/  renderComps\(\); renderAsk\(\);\n  return COMPS;/  renderComps();\n  return COMPS;/' app.js
report "ask surface never painted" "marker=true input=false" "$(run_layout)"; restore

# --- 54. the version gate's stand-down, FORGED -------------------------------
# NO MUTATION -- the defect IS the flag. DEFECT_PASS is set to a PID no live pass
# holds, which is the "someone left the off switch on" case: a hand-set flag, a
# stale value from an earlier run, a copied command line. It must fail LOUDLY
# rather than skip quietly.
#
# This row is why the stand-down is keyed to a PID instead of a boolean. A boolean
# could not be tested from inside a pass at all -- the flag would be legitimately
# set, and the row would prove nothing. A stand-down that cannot be seen to
# misfire is the same vacuous shape every other gate here guards against.
report "version stand-down forged" "no live defect pass holds that PID" "$(run_dl_as 999999)"; restore

# --- 55. a shipped version with no changelog line ----------------------------
# HT-D6's first arm. Force-and-notify makes the bump the user-facing event, so a
# version with no VERSION_LOG entry ships an update that announces nothing.
# VERSION-AGNOSTIC since 2026-09-14, and the reason is this row's own failure.
# It pinned the LITERAL '0.1.0', and the v0.2.0 bump silently invalidated it: the
# mutation stopped applying, the suite ran clean, and the row reported GATE: PASS
# -- a defect row that had quietly stopped testing anything.
#
# Two mechanisms caught it, which is the machinery working: mutate()'s own
# "MUTATION DID NOT APPLY (the text moved)" and report()'s "NOTHING NAMED MATCHED
# -- SUSPECT THE FIXTURE". But both fire only on the first run AFTER the bump,
# and by then the bump was committed, pushed and deployed.
#
# THE GENERAL FORM: a row that pins a value the product legitimately CHANGES rots
# on a schedule. Match the SHAPE, not the value. 9.9.9 is in no VERSION_LOG entry,
# which is what makes the first arm fire.
mutate "s/const APP_VERSION = '[0-9]+\.[0-9]+\.[0-9]+';/const APP_VERSION = '9.9.9';/" app.js
report "version with no changelog line" "has no VERSION_LOG changelog entry" "$(run_cv)"; restore

# --- 56. a changelog entry with no release date ------------------------------
# Ruled 2026-09-14: every entry carries d:. The date is what the build line shows,
# so an undated entry renders a version with no answer to "released when".
mutate "s/\{ v: '0\.1\.0', d: '2026-09-14', note:/{ v: '0.1.0', note:/" app.js
report "changelog entry with no date" "every entry needs one" "$(run_cv)"; restore

# --- 57. an element the harness constructs, GONE from the shipped shell -------
# D16's first arm, and the exact defect the version slice shipped: 17 assertions
# green while index.html contained neither #versionNotice nor #buildLine, because
# every one of them ran against the harness's own mk('div','versionNotice').
#
# The expected string is the DIAGNOSTIC, not the assertion label. The label prints
# on the PASS line too, so matching it would let this row match its own success --
# the tautology that made CQ7 unfailable for 347 consecutive runs.
mutate 's/ *<div id="versionNotice"[^\n]*\n//' index.html
report "shell element the census constructs is missing" ":: versionNotice" "$(run_dl)"; restore

# --- 58. accepted, but the shipped surface never painted ---------------------
# D16's SECOND arm, and the one the presence census CANNOT see: the element is
# present the whole time. This re-plants __setComps' own shape one layer over --
# identityAccept sets CONFIRMED and then does not paint it, exactly as __setComps
# set COMPS and did not call renderAsk(). 27 assertions survived that, because the
# fixture called the renderer by hand; this row is what proves the replacement
# assertion does not.
#
# shellLen=0 comes from the probe, which prints only on failure -- and it is the
# fact that separates "never painted" from "painted something wrong".
mutate 's/  renderConfirmed\(\);\n  return \{ ok: true, query: q \};/  return { ok: true, query: q };/' app.js
report "identity accepted but never painted" "shellLen=0" "$(run_dl)"; restore

# --- 59. THE SILENT MISS -- a want that should fire, and does not -------------
# D15's asymmetry makes this the WEIGHTED row of the three: a miss means walking
# past the book you wanted, which is the error the whole feature exists to
# prevent. A false positive costs a two-second look; this costs the book.
#
# The mutation matches on the RAW typed line instead of the normalised title, so
# "The Amazing Spider-Man #129" stops matching a reading of "Amazing Spider-Man"
# -- generosity about FORMAT removed, which is the one kind of generosity D15
# actually grants. Nothing errors; the flag simply never appears.
mutate 's/w\.title === t\) return w;/w.raw === f.title) return w;/' app.js
report "a want that should fire, does not" "W4 GATE" "$(run_dl)"; restore

# --- 60. THE NOISE CASE -- the issue test dropped -----------------------------
# The other direction, and the reason issue-must-match was ruled: without it,
# every Amazing Spider-Man in the box flags. That is not generosity, it is noise
# -- and noise is not a cheap error repeated, it is the EXPENSIVE one, because a
# flag that gets ignored turns every later false hit into a miss.
mutate 's/w\.matchable && w\.issue === i && w\.title === t/w.matchable \&\& w.title === t/' app.js
report "issue ignored -- every ASM in the box flags" "W5 GATE" "$(run_dl)"; restore

# --- 61. THE SEAM -- the flag paints once, then lies --------------------------
# D16's shape again, in the newest code. identitySetField deliberately does not
# rebuild the draft (retyping must not cost the caret), so removing this one call
# leaves a flag that is CORRECT when first painted and stale for every correction
# after it -- the worst version, because it is right often enough to be believed.
mutate 's/  renderWantFlag\(\);\n  return \{ ok: true, query: identityQuery\(v\) \};/  return { ok: true, query: identityQuery(v) };/' app.js
report "flag never re-evaluates on correction" "W9 GATE" "$(run_dl)"; restore

# --- 62. a sale that is drawn NOWHERE -------------------------------------------
# R5 rests on one property: ONE MARK, ONE SALE. This drops the first mark of every
# column into neither `marks` nor `hidden`, so the plot quietly shows fewer sales
# than it was given -- no error, no gap, just a distribution that is not the data.
# It is the D8 failure in a new medium: a picture that asserts more agreement than
# the sales support.
mutate 's/buckets\[k\]\.forEach\(function \(m, lvl\) \{/buckets[k].forEach(function (m, lvl) { if (lvl === 0) return;/' app.js
report "a sale drawn nowhere" "PL5 GATE" "$(run_dl)"; restore

# --- 63. a fitted line through the scatter ---------------------------------------
# D8, refused for the reason n=98 is enough to SEE modes and not to CHARACTERISE
# them. A polyline is the cheapest way to imply a trend that was never computed,
# and a reader cannot tell a drawn line from a fitted one.
mutate 's/<line class="paxis"/<polyline class="paxis"/' app.js
report "a fitted line through the scatter" "PL10 GATE" "$(run_dl)"; restore

# --- 64. the fold stops folding --------------------------------------------------
# HT-D53's cut only works if the fold actually folds. This moves citeBlock's body
# OUTSIDE its <details>, so the provenance and the full list spill back onto the
# surface -- the wall of text R5 exists to remove, restored silently while every
# string the gates look for is still present.
mutate 's/<div class="citebody">\$\{innerHTML\}<\/div><\/details>/<\/details>\${innerHTML}/' app.js
report "the fold stops folding" "R5 GATE" "$(run_dl)"; restore

# --- 65. an unknown listing type silently absorbed -------------------------------
# D5's shape. listingType's enum is UNMEASURED, so the one thing the surface must
# do with a value nobody mapped is SAY SO. Absorbed into a default it becomes a
# mark that looks exactly like a known one, and the census that was ruled to come
# free from the next device pass would report a type the provider never sent.
mutate "s/if \(!hit\) return \{ kind: 'unstated', stated: true, known: false,/if (!hit) return { kind: 'bin', stated: true, known: true,/" app.js
report "an unknown listing type absorbed" "CQ12 GATE" "$(run_dl)"; restore

# --- 66. a field consumed but never declared -------------------------------------
# The D3 divergence R5 closed: COMP_KEYS declared listingType and conditionId while
# parseComps dropped both, for two whole slices, with nothing pinning them. The row
# builder now DERIVES from COMP_FIELDS, so the failure mode inverts -- the danger is
# consuming a field the contract never promised.
#
# NOTE: deleting a COMP_FIELDS entry does NOT fail, and that is the derivation
# working: both sides of the "exactly the declared fields" assertion come from the
# same list, so they move together. Only an undeclared `from` is a real defect.
mutate "s/from: 'conditionId'/from: 'conditionCode'/" app.js
report "a field consumed but never declared" "CQ11 GATE" "$(run_dl)"; restore

# --- 67. the permanent list returns ------------------------------------------
# R6's central move: the plot IS the list, and 84 rows do not sit under it by
# default. A fold was not enough -- it kept the wall of text and closed a drawer
# over it. This makes the list unconditional again, which is the exact state the
# slice removed, and nothing errors: the surface simply fills up.
mutate 's/\(LIST_SHOWN \? `<div class="cmplist">/(true ? `<div class="cmplist">/' app.js
report "the permanent list returns" "R6 GATE" "$(run_dl)"; restore

# --- 68. the affordance goes back into the paragraph -------------------------
# It WAS the last clause of a four-sentence paragraph about ratio spacing, and it
# was found by accident. An instruction buried in provenance text reads as
# provenance -- HT-D53's cut applied to itself. Deleting the element restores
# exactly that, and the tap still works, so nothing fails except findability.
mutate 's/    `<div class="plottap">Tap any mark to see that sale<\/div>` \+\n//' app.js
report "the tap affordance buried again" "R6 GATE" "$(run_dl)"; restore

# --- 69. a label back below the floor ----------------------------------------
# D17: a slice's own chrome is sized last and smallest, because its author reads
# it at desk distance on a large screen. The axis ticks were 9px -- the smallest
# text in the app, on the surface built to be readable. This puts them back.
# Caught only by a gate that measures COMPUTED sizes on the shipped page, which
# is why it runs through the layout gate rather than the suite.
mutate 's/\.ptl\{fill:var\(--muted\);font-size:12px/.ptl{fill:var(--muted);font-size:9px/' index.html
# EXPECTED STRING IS THE SHAPE, NOT THE COUNT. The first version said
# "belowFloor=1" -- a guess at output never read, and wrong: two tick labels
# render ($10 and $100), so the real count is 2. The row matched nothing and
# reported SUSPECT THE FIXTURE, which is the machinery working.
#
# "belowFloor=2" would be right today and rot the moment the plot fixture's
# price span changes how many ticks render -- D19, and exactly how row 55 died.
# The "under 12px" line prints ONLY on a violation, so it is failure-specific
# and independent of how many labels happen to be under the floor.
report "a label back below the type floor" "under 12px" "$(run_layout)"; restore

# --- 70. the summon control stops working ------------------------------------
# THE CONTROL'S OWN CONTROL. R6's absence gate asserts no list renders by
# default, and an absence gate is unfalsifiable on its own -- it would pass just
# as happily against a renderer that had simply broken. The paired assertion is
# that SUMMONING produces the rows. This breaks exactly that: the flag flips,
# nothing repaints, and the list can never be produced. The absence assertion
# still passes; only its control fails, which is the point.
mutate 's/function compsListToggle\(\) \{ LIST_SHOWN = !LIST_SHOWN; renderComps\(\);/function compsListToggle() { LIST_SHOWN = !LIST_SHOWN;/' app.js
report "summoning stops producing the list" "R6 GATE" "$(run_dl)"; restore

# ---- C1 / RP1: response replay, TEST MACHINERY ----------------------------
# The two rulings these rows exist to enforce: a replayed response MUST SAY SO
# with the date it was captured, and ARMING IS EXPLICIT. Every mutation below is
# a plausible edit -- a line deleted, a condition simplified, a date taken from
# the clock instead of the record. A defect nobody working on this file could
# credibly write proves nothing about the gate that catches it.
#
# LABELLED RP1, NOT C1. The vision-contract block already owns the label "C1" in
# the harness, and a grep for "the C1 block" returned thirteen assertions, none
# of them these. The slice is still C1 in GATES.md; the assertions are RP1.

# THE NOTICE, on each of renderComps' TWO early returns. One row per branch,
# because a single row would leave whichever branch it did not touch free to
# drop the notice while the pass still read green.
mutate 's/\n    replayNoticeHTML\(\) \+/\n/' app.js
report "replay notice deleted (main branch)" "RP1 GATE" "$(run_dl)"; restore

mutate 's/\n      replayNoticeHTML\(\) \+/\n/' app.js
report "replay notice deleted (thin branch)" "RP1 GATE" "$(run_dl)"; restore

# THE DATE ITSELF, and this is the row the "not today" clause was written for.
# A notice reading the clock still SAYS it is a replay, still renders, still
# looks right -- and is wrong about the one fact it exists to carry.
mutate 's/const d = String\(COMPS\.replay\.at \|\| \x27\x27\)\.slice\(0, 10\);/const d = new Date(nowMs()).toISOString().slice(0, 10);/' app.js
report "notice prints TODAY, not the capture date" "RP1 GATE" "$(run_dl)"; restore

# ARMING. The whole of the second ruling: a saved response present is not a
# reason to replay. This is the silent-substitution failure, and it is the one
# that would make every measurement taken afterwards untrustworthy.
mutate 's/function replayArmed\(\) \{ return REPLAY_ARMED \&\& !!replayRead\(\); \}/function replayArmed() { return !!replayRead(); }/' app.js
report "arming becomes implicit (saved = armed)" "RP1 GATE" "$(run_dl)"; restore

# THE COST LINE, claiming a charge for a call that never happened.
mutate 's/\(COMPS\.replay \? `no charge/(false ? `no charge/' app.js
report "replayed lookup claims the \$0.40 charge" "RP1 GATE" "$(run_dl)"; restore

# THE EXPORT, carrying what is not the subscriber's data (K1's property).
#
# THE PATTERN CARRIES NO PARENTHESES, and that is not a style choice. report()
# interpolates it into `grep -E "^FAIL +.*(${pat})"`, so the argument is an ERE,
# not a literal: "RP1 GATE (K1 shape)" matches the text `RP1 GATE K1 shape`,
# which no assertion contains. This row and the next both reported
# `NOTHING NAMED MATCHED -- SUSPECT THE FIXTURE` on their first run while the
# gate was failing exactly as intended. Match a paren-free substring that is
# SPECIFIC to this row's own assertion, so the row names its own defect rather
# than whichever RP1 failure happens to print first.
mutate 's/function exportJSON\(\) \{ return JSON\.stringify\(APP_STATE, null, 2\); \}/function exportJSON() { return JSON.stringify(APP_STATE, null, 2) + String(Store.readRaw(REPLAY_KEY) || \x27\x27); }/' app.js
report "saved response leaks into the export" "K1 shape" "$(run_dl)"; restore

# DIVERGENCE. The claim that makes every downstream surface safe is that replay
# substitutes the raw string AND NOTHING ELSE. This breaks exactly that, and
# nothing else about the app changes: the plot still draws, the ask still counts.
mutate 's/\? Promise\.resolve\(\{ transport: true, httpOk: true, status: 200, raw: saved\.raw \}\)/? Promise.resolve({ transport: true, httpOk: true, status: 200, raw: JSON.stringify(JSON.parse(saved.raw).slice(0, 3)) })/' app.js
report "replay returns a TRUNCATED response" "IDENTICAL parsed rows" "$(run_dl)"; restore

# ---- DROP1: the structural fix that makes `hidden` mean something -----------
# Removing this one rule restores the defect exactly as it shipped: the
# attribute stays set, .cmpdrop{display:block} wins again, and the disclosure is
# open while claiming to be closed. Pattern is PAREN-FREE -- report() greps with
# -E, which is what silently blanked rows 76 and 77.
mutate 's/\[hidden\]\{display:none!important\}//' index.html
report "hidden stops hiding (the shipped defect)" "ZERO RENDERED HEIGHT" "$(run_dl)"; restore

# ---- PL9b: an unrecognised listing type must NAME the value ------------------
# Mapping best_offer_accepted to bin leaves the real data with ZERO unrecognised
# marks, so the only remaining specimen is synthetic -- which is exactly why the
# self-naming property needs a gate rather than a fixture. This silences the
# label while leaving the shape alone: the diamond still draws, PL8 still passes,
# and the mark stops saying which value it failed to recognise.
# PATTERN IS ASCII-ONLY AND ANCHORED ON THE RETURN'S TAIL, for two reasons that
# both cost a row elsewhere in this file.
#
# 1. NO \x{201C}. The label wraps the value in curly quotes, and `perl -0pi`
#    without -C reads the file as BYTES, where U+201C is the three-byte sequence
#    E2 80 9C. A \x{201C} in the pattern asks for one character and matches
#    nothing -- dry-run confirmed. Under the fatal mutate() that is an aborted
#    pass reported as rotted, not a silent pass, but it is still a dead row.
# 2. ANCHORED ON `not recognised' };`, not on ` not recognised`. The looser form
#    works only because a comment forty lines up writes `as "not recognised"`
#    with a quote before the word rather than a space. Reword that comment and
#    the mutation retargets the COMMENT, plants nothing meaningful, and still
#    APPLIES -- so mutate()'s fatal check would not catch it. That is row 55's
#    rot: matching something incidental rather than the thing meant.
mutate 's/not recognised\x27 \};/not stated\x27 };/' app.js
report "unrecognised type stops naming itself" "NAMES THE VALUE" "$(run_dl)"; restore

# ---- FLT (R6b): the filters count and list, and the plot must not move -------
# The ruling these rows enforce is HIGHLIGHT NEVER FILTERS OUT. It is currently
# true by construction -- the plot holds no selection state, because at 5.31px no
# channel could carry one. Row 80 is the row that would catch someone restoring
# the design the measurement refused.
mutate 's/const mk = compsMarks\(rows, sc\);/const mk = compsMarks(compsSelected(rows), sc);/' app.js 'const mk = compsMarks(rows, sc);'
report "a filter removes marks from the plot" "PLOT UNCHANGED" "$(run_dl)"; restore

# D5's shape: a button that matches nothing is a control that has stopped
# controlling, and it looks exactly like one that works.
mutate 's/if \(n > 0\) out\.push/out.push/' app.js 'if (n > 0) out.push'
report "empty categories render as buttons anyway" "EIGHT categories with no match" "$(run_dl)"; restore

# D10: the label states what was MATCHED, never what it might imply.
#
# ANCHORED ON `label: '...',` BECAUSE THE LOOSE FORM WAS SILENTLY DEAD. The
# string "title mentions CGC" occurs THREE times in app.js -- in the module's own
# comment (line ~2194), in the COMPS_CATS label, and in the v0.9.0 changelog
# note. perl -0pi without /g takes the FIRST, which is the comment: the mutation
# APPLIES, so mutate()'s fatal check stays silent, the suite runs clean, and the
# row reports GATE: PASS while testing nothing at all.
#
# That is row 55's rot for the third time in this file -- and it was written
# directly beneath the comment warning about it, because that warning was about
# BYTE-safety and this row was about label semantics. The transferable rule is
# neither: A PATTERN WHOSE TARGET OCCURS MORE THAN ONCE IS FRAGILE WHATEVER IT
# HAPPENS TO HIT TODAY. Count the occurrences before trusting the anchor.
mutate "s/label: 'title mentions CGC',/label: 'slabbed',/" app.js "label: 'title mentions CGC',"
report "a label becomes a claim about the book" "title mentions X" "$(run_dl)"; restore

# OR -> AND. The selection shrinks toward nothing, which is filtering by another
# name -- and the row count is the only thing that would say so.
mutate 's/return COMPS_FILTERS\.some\(/return COMPS_FILTERS.every(/' app.js 'return COMPS_FILTERS.some('
report "filters combine with AND instead of OR" "combine with OR" "$(run_dl)"; restore

echo "-------------------------------------------------------------------"
for f in $MUTATED; do
  printf 'restored: %-11s %s\n' "$f" "$(cmp -s "$TMP/$(basename "$f").orig" "$f" && echo 'identical to its pre-run copy' || echo 'DIFFERS -- INVESTIGATE')"
done
# A BACKUP MUST NOT OUTLIVE ITS RUN. These .orig copies were left behind on exit,
# and a later session found them, compared a file against a backup FROM A
# DIFFERENT RUN, read the legitimate difference as mid-mutation corruption, and
# overwrote three hours of work with a three-hour-old copy. The file was restored
# correctly by copy, exactly as the rule above demands -- and the rule was not
# enough, because it says nothing about WHICH run the copy came from.
#
# Deleting them on a clean exit makes the presence of .orig meaningful: it now
# means A RUN IS IN PROGRESS OR WAS KILLED, which is the one question the restore
# could not answer. A kill still leaves them, and that is the point.
rm -f "$TMP"/*.orig
echo "backups cleared (a leftover .orig now means a run was interrupted, not that one finished)"
echo "git status (expect nothing but untracked tests/.tmp):"
git status --short

# THE PASS IS NOT EVIDENCE IF ANY ROW PLANTED NOTHING. Loud, last, and non-zero.
# The previous design printed each failure inline and still exited 0, so a run
# with seven dead rows was indistinguishable at a glance from a clean one -- and
# was read as clean, committed, pushed and deployed.
if [ "${ROTTED:-0}" -gt 0 ]; then
  echo
  echo "==================================================================="
  echo "!! $ROTTED ROW(S) PLANTED NOTHING -- THIS PASS IS NOT EVIDENCE"
  echo "==================================================================="
  echo "A row whose mutation does not apply runs a CLEAN suite and reports"
  echo "GATE: PASS while testing nothing at all."
  echo "$ROTTED_LIST"
  echo
  echo "FIRST check line endings. A multi-line pattern using \\n cannot match a"
  echo "CRLF file, and 'git checkout -- f' rewrites line endings under"
  echo "core.autocrlf. Restore with 'git show HEAD:f > f' instead. Measure with"
  echo "  perl -ne '\$c++ if /\\r\$/; END { print 0+\$c }' <file>"
  echo "and NOT with grep -c on a CR pattern, which reported every line as CRLF"
  echo "on a known-LF control file."
  echo
  echo "THEN check the pattern itself: match the SHAPE, never a literal the"
  echo "product legitimately changes (a version string, a date, a count)."
  exit 1
fi
