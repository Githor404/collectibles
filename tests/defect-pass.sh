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
cp app.js "$TMP/app.js.orig"
cp index.html "$TMP/index.html.orig"
ORIG_APP=$(sha256sum app.js | cut -d' ' -f1)
ORIG_IDX=$(sha256sum index.html | cut -d' ' -f1)
MOVED=""

restore() {
  cp "$TMP/app.js.orig" app.js
  cp "$TMP/index.html.orig" index.html
  [ -z "$MOVED" ] || { mv "$MOVED" tests/capture-outcome-gate.ps1 2>/dev/null; MOVED=""; }
  local a i
  a=$(sha256sum app.js | cut -d' ' -f1); i=$(sha256sum index.html | cut -d' ' -f1)
  [ "$a" = "$ORIG_APP" ] && [ "$i" = "$ORIG_IDX" ] || { echo "!! RESTORE FAILED -- check git status before doing anything else"; return 9; }
}
trap 'restore >/dev/null 2>&1' EXIT INT TERM

mutate() { # perl-expression, file
  perl -0pi -e "$1" "$2"
  local n want
  n=$(sha256sum "$2" | cut -d' ' -f1)
  case "$2" in app.js) want="$ORIG_APP" ;; index.html) want="$ORIG_IDX" ;; *) want="" ;; esac
  [ "$n" != "$want" ] || echo "!! MUTATION DID NOT APPLY (the code moved): $1"
}
run_dl() { timeout 300 bash tests/run-data-layer.sh 2>&1; }
report() { # name, expected-case-pattern, output
  local name="$1" pat="$2" out="$3" verdict named
  verdict=$(printf '%s\n' "$out" | grep -oE 'GATE: (PASS|FAIL)' | tail -1)
  named=$(printf '%s\n' "$out" | grep -E "^FAIL +.*(${pat})" | head -1 | sed -E 's/^FAIL +//' | cut -c1-80)
  [ -n "$named" ] || named=$(printf '%s\n' "$out" | grep -E "(${pat})" | head -1 | cut -c1-80)
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
printf '\nfunction phoneHome(u) { return fetch(u); }\n' >> app.js
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
mv tests/capture-outcome-gate.ps1 "$TMP/capture-outcome-gate.ps1.moved"; MOVED="$TMP/capture-outcome-gate.ps1.moved"
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

echo "-------------------------------------------------------------------"
echo "restored: app.js $(sha256sum app.js | cut -c1-12) (was ${ORIG_APP:0:12}) · index.html $(sha256sum index.html | cut -c1-12) (was ${ORIG_IDX:0:12})"
echo "git status (expect nothing but untracked tests/.tmp):"
git status --short
