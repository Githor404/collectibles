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

mutate() { # perl-expression, file
  row_wanted || return 0
  # The guard compares against the file's OWN backup, so it covers every file in
  # MUTATED. Keyed to two hardcoded hashes it silently skipped the rest, and a
  # mutation that failed to apply would have produced a row that proves nothing --
  # a vacuous gate, which is what HT-D60 Clause 4 is about.
  perl -0pi -e "$1" "$2"
  cmp -s "$TMP/$(basename "$2").orig" "$2" && echo "!! MUTATION DID NOT APPLY (the text moved): $1"
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
# that. One suite run is ~12s; a full 41-row pass is ~500s.
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
report "grade enters the lookup" "carrying the grade or the asking price is REFUSED" "$(run_dl)"; restore

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
mutate "s/const APP_VERSION = '0\.1\.0';/const APP_VERSION = '0.9.9';/" app.js
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
