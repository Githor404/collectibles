# collectibles — Gate Record

Pre-registered, re-runnable gate evidence. **HT-D60 binds** (adopted by D1): a new or changed gate is not evidence until it has been **run against the defect it closes and seen to fail**, with a fixture capable of exhibiting that failure (Clause 4). The failing run is part of the evidence and is recorded here beside the passing one.

Run everything: `bash tests/run-all-gates.sh`. Defect pass: `bash tests/defect-pass.sh`. Recovery after an interrupted pass: `bash tests/restore-backups.sh`.

### The two recovery mechanisms, run against their own defects — 2026-09-13

**HT-D60 Clause 1 binds a safety mechanism exactly as it binds a gate: a check that has never been seen to fail is a claim, not evidence.** Both were tested by recreating the conditions that defeated their predecessors.

| test | planted condition | result |
|---|---|---|
| **PID lock — defect** | a live PID holding `tests/.tmp/.pass.lock` | **FIRED BY NAME**: `!! ANOTHER DEFECT PASS IS RUNNING (pid 357).` — **exit 2**, no backups written |
| **PID lock — control** | a lock naming a dead PID (`999999`) | **correctly ignored**, the pass ran — it refuses a live race without blocking on its own debris |
| **Freshness gate — defect** | `app.js.orig` back-dated to before HEAD (the exact 2026-09-13 shape) | **FIRED BY NAME**: `FRESHNESS GATE: FAIL - app.js.orig is OLDER THAN HEAD.` — **exit 1**, nothing written |
| **Freshness gate — control** | all four backups freshly written | **PASS**, exit 0 — the gate is not simply refusing everything, which is the only thing that makes the defect result mean anything |

**The freshness gate did not exist as code until this test.** It had been written as a *procedure* in `tests/README.md` — a promise to check, and a promise is what failed in the first place. It is now `tests/restore-backups.sh`: dry-run by default, `--apply` to act.

#### What they do NOT cover

**The PID lock:**
- **Only pass-versus-pass.** It does not stop anything *else* touching those files mid-run — and that is the deeper cause of the incident it was written for: files were edited while a pass was in flight. **The lock would not have prevented that.**
- **Checked only at startup.** A pass that begins legitimately and an edit five minutes later collide with no warning at all.
- **PID identity is environment-scoped.** `kill -0` resolves MSYS PIDs; a pass launched from a different shell environment may be invisible to it.

**The freshness gate:**
- **It proves provenance, not content.** "Newer than HEAD and recent" says nothing about whether the backup holds the *right* bytes. A pass that backed up an already-mutated file yields a backup that passes cleanly and restores a defect.
- **Its strength is proportional to commit frequency.** Its sharpest signal is "newer than HEAD" — so on a repo committed once in six hours, which is precisely what this one was on 2026-09-13, the check is weakest exactly when exposure is greatest. **Committing before a pass remains the real protection; this is the backstop for when that was not done.**
- **It does not run automatically.** `defect-pass.sh` writes and restores its own backups in the exit trap, fresh by construction. This guards the **ad-hoc** recovery path — where the loss actually happened — and only if it is run instead of typing `cp`.
- **It is blind to concurrency.** A backup written seconds ago by a *second* pass passes cleanly. That is the lock's job, and the two checks know nothing about each other.

### The cost model was wrong by 20×, and the evidence was on screen all day

`report "name" "pat" "$(run_dl)"` evaluates the substitution **before** calling `report`, so an unguarded `run_dl` ran the full suite for **all 40 rows on every invocation**. `ROWS=` skipped the mutation and the reporting; it never skipped the expensive part.

| invocation | rows selected | elapsed |
|---|---|---|
| `ROWS=31-32` | 2 | 497s |
| `ROWS=33-34` | 2 | 504s |
| `ROWS=34-36` | **3** | 494s |
| `ROWS=38-39` | 2 | 542s |
| `ROWS=40-41` | 2 | 541s |

**A constant elapsed time with no relationship to the number of rows selected is the signature of a fixed cost.** It was read as "~250s per row", and that estimate drove every batching decision, every timeout, and a planning figure given to the subscriber. Guarding `run_dl` took `ROWS=31-32` from **497s to 59s**.

**Corrected model, measured rather than estimated:** ~35s fixed (backups, 40 `report` calls, restore) **+ ~12s per selected row**. A full 41-row pass is **~8.5 minutes**, not the 2.7 hours the wrong model implied.

### The full 41-row pass, run — 2026-09-13

**The first time every row has been run since R2b rewrote the code thirty of them mutate.** It had been skipped all day because the wrong cost model priced it at 2.7 hours. At the real numbers it took **585s**, in two halves — rows 1–20 in 300s, rows 21–41 in 285s — split only to stay clear of the tool's timeout boundary, since row numbering is stable across invocations by design.

**Result: 41 rows, every one `GATE: FAIL` naming its own case. Zero vacuous, zero unnamed, zero `GATE: PASS`, zero restore failures.** `app.js` returned to 105499 bytes; no backup was left behind.

**The specific risk was Clause 4 sitting live in the repo.** Rows 1–30 anchor on `renderConfirmed`, `credTest`, `renderCred`, the `PROVIDERS` table and the brief's rule numbering — every one of which R2b changed. **A mutation whose anchor has moved reports a vacuous `GATE: PASS`**, and three rows did exactly that earlier the same day. None of the thirty had; the worry was sound and the answer is negative.

**One error found, and it was in the CHECKING rather than the pass.** The summary used `grep -cE '^[a-z].*GATE: (PASS|FAIL)'`, which silently drops the single row whose name begins with a capital — `EXIF pin removed`. So the first report listed **19 rows of 20**, and worse, the "a gate that does not gate" count used **the same anchor** and therefore could not have seen a `GATE: PASS` on that row. Re-checked with `^[A-Za-z]`: 20 of 20, row 12 named `CL5 STRUCTURAL (HT-D58)`, count genuinely zero.

**That anchor dropped that row three separate times in one day.** A counting pattern that silently omits a member **is a census that cannot count** — the precise failure the gate-script census exists to prevent, committed in the tool used to check it. The rule the census already states applies to its own summaries: **a check must be able to see every member of the set it claims to cover.**

> **Incident, 2026-09-13 — a restore destroyed uncommitted work for the second time, and the rule written after the first did not prevent it.**
>
> After the first incident this repo recorded: *restore by copy, never by `git checkout --`; a restore must return a file to what it was, not to what was last committed.* That rule was followed exactly. The work was still lost.
>
> **What happened.** A backgrounded defect pass was killed by the OS (~42 headless Chrome launches in one job, memory exhausted) during the *baseline* step — so `defect-pass.sh` never started, never wrote backups, and never mutated anything. The `tests/.tmp/*.orig` files sitting there were **the previous session's**, timestamped ten minutes before the last commit. A recovery step compared `app.js` to one of them, found the difference that was three hours of new R2b work, classified it as mid-mutation corruption, and restored. Four files were reverted to a state older than HEAD.
>
> **Why the existing rule missed it.** It governs the *method* of a restore, not the *provenance* of the backup. A copy that is verified by `cmp` and taken from the wrong run passes every check the rule imposes. Freshness was the unstated half.
>
> **Fixed structurally, not by resolve:** `defect-pass.sh` now clears `*.orig` on a clean exit, so a leftover backup means *interrupted*, never *finished* — the one question the failing step could not answer. See `tests/README.md`.
>
> **What survived is the argument for where rulings live.** `DECISIONS.md` and everything under `tests/` are not in `MUTATED`, so **D10, D4's per-source amendment, D7/D8's amendments, all thirteen R2b cases, defect rows 31–40 and the 347 pin were untouched**. Only the implementation was lost, and a gate record plus a decision log is enough to rebuild an implementation. The reverse would not have been true.

---

## Port slice — HealthTracker's infrastructure, copied (D1) — 2026-09-11

**What it is:** the capture chain, credential handling, the outcome modal, local storage with export/restore, and the gate machinery, ported from `healthtracker@dcf3d78` into a repo with **no features**. The vision contract is deliberately unruled, so the chain's cases install a **synthetic** contract: they prove the chain, never a contract.

**Result: `SUITE: PASS (2 of 2 produced a verdict, and every verdict was PASS)`, runner exit 0.**
**Assertions: executed 248 · pinned 248** (count 0 → 248, pinned deliberately in this commit).

### Static checks (inside `run-data-layer.sh`, each failing the whole gate)

| check | asserts |
|---|---|
| gate-script census (HT-D53) | the `*-gate.ps1` set equals the pinned manifest — a quarantined or renamed gate fails **by name** |
| port residue (D1) | no `healthtracker-` storage key, no HT console seam, no meal-domain identifier in `app.js` / `index.html`; matched on code shapes, with a planted control |
| egress census (D1) | every network primitive in the shell maps to its enclosing function, and there is **exactly one site, inside `egress()`**; planted control first |
| **cross-reference census (D3)** — added 2026-09-13 | every `Dnn`, `HT-Dnn`, `HT-Rnn`, `Rn` and `rule(s) N` cited in `CLAUDE.md` / `DECISIONS.md` / `GATES.md` **resolves to a heading or a rule that exists**, and the brief's rule list is **1..N with no duplicates and no gaps**; a planted control of six synthetic breaks runs first |

#### The cross-reference census — what it caught, and what it cannot

**Why it exists:** renumbering is a **rename**, and a rename its consumers do not follow is D3 every time. Inserting two rules mid-list left the brief numbered 1–7 then 3,4 with seven references pointing at the wrong rules across four files. Nothing failed; attention did not catch it.

**On its first run it found three genuine breaks** that had survived review: an unprefixed decision number (from writing the pair as `HT-D55` followed by a second number that never got its prefix, where only the first carries the prefix, so the second read as *this* repo's), an unprefixed slice number meaning HealthTracker's, and `R2` — cited twenty times across three files while only `R2a` and `R2b` had headings. The first two were repointed; `R2` was given the heading it deserved, since the docs legitimately name the pricing work as a whole.

**Defect pass:**

| planted defect | verdict | named |
|---|---|---|
| a duplicate rule number (the original break) | GATE: FAIL | `rule list has DUPLICATE number(s): 3` |
| a citation to a rule that does not exist | GATE: FAIL | named the phrase and the number: *"…but 77 is not a rule in the brief"* |

**The limit, stated because the first version of the second row PASSED against its own defect.** Planting the *original* break — `rules 3, 4 and 7` → `rules 3-5` — does **not** fail the census, because rules 3, 4 and 5 all exist. **Resolution cannot see a citation that resolves to the wrong thing.** What the census catches is an *unresolvable* citation and an *inconsistent* rule list; the original break is caught by the **numbering half**, which is what was broken at the time. A citation that quietly points at the wrong existing rule, while the list is consistent, remains beyond a mechanical check — HT-D60 Clause 2, said out loud rather than assumed away.

**Also deliberately not checked:** harness case names (`ID15`, `PACE1`, …) cited in prose. The assertion-count pin already guards the suite, and matching prose against case names would be a looser census with a worse false-positive rate.

### Behavioural cases, by group

| group | asserts |
|---|---|
| **S** storage (HT-D1) | prefixed stable key; nested settings survive a boot; a **newer-schema blob is never overwritten**; a failed write degrades to memory with a truthful badge; blocked storage → memory |
| **E** export / restore (HT-D3, HT-D5) | export→restore is **identity**, nested settings included; a **HealthTracker export is refused as another product, not as "a newer version"**; version-absent, newer, bad JSON and an array all refused with the state untouched; under a write failure restore proceeds and **does not claim a backup**; a **declined restore leaves the one level of undo exactly as it was**; smart quotes and nbsp normalized |
| **K** credentials (D1, HT-D45/46/49) | neither credential is in the state object, the export, or the pre-restore backup; a destructive restore leaves both untouched; masked everywhere; removing one leaves no residue **and does not touch the other role**; a field no writer knows survives the counter and a save; replacing a credential resets its status; a provider from another role cannot be assigned; shape checks block empty/space/short and **warn** on a surprising prefix or a non-40-character token; boot, refresh, settings, a failed read and a restore issue **zero calls** |
| **V** the contract seam (D1) | the seam ships empty, the capture surface says so and offers no button that could only fail, and a reply cannot open a result; **a capture with no contract makes zero calls and still states a failure** |
| **C** request shape (HT-D45/64/66, HT-D48) | OpenAI-classic image + text parts; `response_format` and a token bound; `reasoning_effort: low`; the two degrade flags are independent; an **undeclared provider is sent neither** (asserted through `visionCaps`, not a null — Clause 4); the shipped rows carry the verified endpoints, auth styles and the 1 call/s pacing; two clocks, with the decoder lease inside the decode budget; a retry floor inside the call budget |
| **P / R** one door, escaping, redaction | identical reply text gives a byte-identical result pasted or called; a hostile string is escaped on the result surface; **a provider echoing the credential has it redacted**; the PriceCharting error shape verified 2026-09-11 is read as written |
| **LE / PH / EN** the decode (HT-D47, HT-D58) | **the leash hands the photo to the fallback when the preferred decoder never answers**; a 2400 px photo is bounded to 1280 and encoded as a jpeg data URL, changing **only the sent bytes**; a 12 MP photo bounds with aspect kept; a small image is never upscaled; **an encode that produced almost nothing throws** |
| **VR** validate → retry → fall back (HT-D64) | a valid reply takes one call to the verified endpoint, with the key as a **Bearer header and never in the URL**, carrying the photo, the versioned prefix and the contract prompt; a reply that does not validate is retried **exactly once**; two failures stop — no third call — and the raw reply lands in the reply box; **the first reply survives a failed retry**; with no budget left the second call is **not started** |
| **TR** the trace (HT-D65, HT-D66) | payload bytes and dimensions, encode time, **TTFB separate from total**, status, reply length, whether `response_format` was sent, **which effort was sent**, and a second call when there is one; it reaches the outcome modal **on success and on failure**; it carries neither key nor URL |
| **FW / RF** failure walls | rejected key, the 400 xAI really sends, a 400 that is not about the key, rate limit, server error, dead network and timeout are each classified distinctly, each ends in a stated failure with the photo still in hand, and **none prints the key**; a 400 naming `reasoning_effort` is retried once dropping **only** that field |
| **TC / PC** test connection (HT-D46, D1) | pending paints with a spinner before any answer; success names the model; failure paints in the provider's words; timeout paints; **a throw paints, with the key redacted**; the button is never disabled; a write that did not land reports `stored:false`; the prices ping is a GET carrying the token as `t`, with no header; a PriceCharting error paints and is remembered; **the extractability warning is visible safety text, not folded into the fine print** |
| **PACE / CFG** (D1) | three price calls requested together leave **≥ 1 s apart**, with a control proving a provider that declares no pacing is not delayed; a row with **`auth: 'none'` calls with no credential saved and never attaches one that is** — the server move is a table edit; a second vision provider is a table row |
| **KV** one persisted fact (HT-D49) | a passing test persists `verified` **in the store**, the capture surface reads the same fact, and **counting a call does not cost it**; a successful capture verifies, an auth rejection demotes, a parse failure and a timeout **do not**; an untested key still gets both buttons and is never stated without an inline **verify now** |
| **OM** the outcome modal (HT-D51) | closed when nothing is happening; a validated reply opens it with the result **in the body** and exactly two actions **in the fixed footer**; **a success cannot be dismissed**, a failure can; a failure states the cause with both ways out as buttons and no result beside it; pending is a spinner, counted seconds and a cancel, and cancelling moves to a stated failure, never to nothing; **the capture surface carries no outcome in any state**; a pasted reply opens the same modal |
| **SH / NS / CL** the shipped shell (HT-D47, HT-D58, HT-D63) | no duplicate id; the result and message live in the modal body and the footer outside it; both credential cards in Settings; the shipped shell carries **no contract** and says so; the file input is wired to the shipped handler and a photo paints pending **before the decode**; the request fires and the counter moves; **four adversarial files × both inputs each end in a request or a stated failure, never in nothing**; camera-vs-library derived from the `capture` attribute; HEIC advice differs by source; the EXIF pin, structurally and behaviourally; a large library photo measured at the bound; a cancelled library pick is not a camera fault (with a camera control) |
| **CAP / PFX** | past the daily cap **no call is made at all** and it says so, with the counter living beside the key; **every storage key written in the whole run is prefixed `collectibles-`**, and the sweep saw the state, the backup and both credential stores |

### The comps row: a layout claim that escaped every string gate — 2026-09-13

**Reported from the first live device pass**, verbatim off a phone:

```
$52.46The Incredible Hulk #271 First Rocket Raccoon Appearance 198217/08
```

Three fields with nothing between them, the title's trailing `1982` merging into the date `17/08`. **The cause was worse than a missing separator: the comps surface shipped with class names and no CSS at all** — zero rules for `.cmprow` / `.cmpprice` / `.cmptitle` / `.cmpmeta` / `.cmphead`, against six for R1's surface. Inline elements do not separate.

**Every data-layer assertion was green while this shipped**, and correctly so: `--dump-dom` sees markup, and *separation is geometry*. **Emitting a class is not shipping a layout, and asserting the class exists is not asserting it separates anything.**

**Gated in two halves, because the claim has two halves.**

| half | where | asserts |
|---|---|---|
| structural | `CQ10`, data-layer | three distinct elements; the literal string `198217` absent; spelled-month date; no `D/M` form anywhere; the title byte-identical to source; and the shipped shell actually carrying the CSS |
| **geometric** | **`layout-gate.ps1`**, CDP, four viewports | price, date and title rectangles **disjoint**; the title's top **below both**; **no horizontal page overflow** |

**Both proven against the same defect, by two different rows.** Row 44 restores the concatenation and fails `CQ10 GATE: a comp is THREE distinct elements`; **row 45** restores it and fails the layout gate with `NOT MEASURABLE -- a field is not its own element: price=false date=false title=false`, `LAYOUT GATE: FAIL`, exit 1. One mutation, two claims, two gates.

**A note on how row 45's pattern was written.** It matches `not its own element`, copied out of an **observed** failing run. The prediction made from the source said `price=False`; the gate prints `price=false`. Predicting a gate's own output is how a report pattern goes stale without anyone noticing — the same class as the pattern that survived a rename earlier the same day and left a row failing correctly while naming nothing.

**Measured cost:** the layout gate is **~140s** against a data-layer run's **~12s**, so row 45 is worth about twelve ordinary rows and the full pass moves ~500s → ~645s. Recorded so it is not re-derived by feel.

### `layout-gate.ps1` — the layout claim, measured (HT-D51)

Real `index.html`, shipped capture path, CDP, **real time** (so it exercises the `createImageBitmap` decoder the harness cannot reach), at 360×690, 390×745 and 1200×900. Per state: success (first result row and both actions in view, ≥ 44 px), success with a long result (**body scrolls, footer does not**), failure (message + both ways out), pending (counted spinner + cancel), and the capture surface carrying none of it. A real capture in that gate reports `15 kB · 1280×960 · encode 0.0s`, so the decode is genuinely running.

### The defect pass — every gate seen to fail (HT-D60)

`bash tests/defect-pass.sh`. Each row: the defect planted in the shipped file, the gate run, the file restored and **verified by hash**.

| planted defect | verdict | first case to fail, by name |
|---|---|---|
| decode leash removed | GATE: FAIL | `LE1` — *the leash hands the photo to the fallback* (`Reading the photo timed out after 2 seconds`) |
| fallback discards the raw reply | GATE: FAIL | `VR4` — *the FIRST reply reaches the reply box even though the SECOND call failed* |
| trace not rendered | GATE: FAIL | `TR3` ×2 — on success **and** on failure |
| key written into `APP_STATE` | GATE: FAIL | `K1` ×2 — in the state object, and in the export |
| a second `fetch` site | GATE: FAIL | `egress: FAIL — every network call must go through egress()` |
| credential write rebuilds instead of merging | GATE: FAIL | `K2` ×2 — the unknown field, and role isolation |
| pacing removed | GATE: FAIL | `PACE1` — *leave at least ONE SECOND apart* |
| redaction removed | GATE: FAIL | `TC4` and `PC3` — the throw path and the echoing provider |
| product check removed from restore | GATE: FAIL | `E2` — the HealthTracker export is accepted |
| a success becomes dismissable | GATE: FAIL | `OM3` |
| blank-canvas floor removed | GATE: FAIL | `EN1` |
| EXIF pin removed | GATE: FAIL | `CL5 STRUCTURAL` (the behavioural twin stays green — see the limit below) |
| `auth: 'none'` demands a credential | GATE: FAIL | `CFG1` |
| a case throws mid-suite | GATE: FAIL | `HARNESS: uncaught exception aborted the synchronous suite`, and the count pin (73 of 248) |
| a gate script renamed away | GATE: FAIL | `GATE-SCRIPT CENSUS: FAIL — layout-gate.ps1 missing` |

**One finding from the pass itself, recorded because it is Clause 4 in miniature.** With the leash case placed late, removing the leash **did not fail it**: the first capture step stalled for the whole decode budget, the step chain aborted, and the suite died at 73 of 248 assertions. The defect was caught — by the count pin — but *the gate written for it never ran*. The case now runs **first among the capture cases**, with the decode budget shortened so only the leash can satisfy it, and it fails by name. A gate that cannot run while its defect is present is weaker evidence than one that speaks.

### Limits of this evidence, stated

- **No device pass, and no live credential.** Every call in both gates is stubbed. The first real capture is also the first proof of the model string, of a real photo's latency, and of the provider's actual error text. Same for PriceCharting: **the success body on a comics subscription and the wording of a wrong-token error are unverified** — Test connection is what will show them (D1).
- **The harness cannot exercise `createImageBitmap`** (HT-D47): it never settles under `--virtual-time-budget`. The harness proves the leash and the fallback; `layout-gate.ps1` runs the preferred decoder in real time.
- **`CL5 BEHAVIOURAL` cannot fail on this browser** (HT-D60 Clause 2): Chrome's default is already `from-image`, so it stays green with the pin removed. It guards a browser that is not running this suite, it says so in its own text, and it is paired with the structural case that **does** fail.
- **Nothing here proves an identification or a price.** There are no features. The vision contract is synthetic; the prices role has exactly one call (Test connection) and no lookup.
- **A corrupt blob under the state key is overwritten by a fresh state** — HealthTracker's behaviour, ported unchanged. Harmless while no user data exists; revisit when records land.

---

## R1 — Identification: the model reads the cover, the human confirms it — RULED AND BUILT (D2, 2026-09-12)

**Ruled:** Forks **A1, B1, C1, D1, E1, F1, G1** as recommended. D2 carries the two notes that belong in the record — C1's correction is the author's own (the key-issue field is **dropped, not deferred**), and A1's cost is stated: **R1 is a milestone, not a release. There is no price in this build.**

**Result: `SUITE: PASS (2 of 2 produced a verdict, and every verdict was PASS)`, runner exit 0.**
**Assertions: executed 294 · pinned 294** (248 → 294, **+46**, re-pinned in this commit).

### What R1 ships

The contract (six printed fields, a closed marker vocabulary, absence as a state, and value/grade/key-issue refused by name); an identity-first confirm surface where every field is correctable and the model's original is kept beside it; the PriceCharting search string derived from the **confirmed** fields, copyable; a confirm action that produces the identity and states plainly that pricing is not built; and the no-key floor — copy the prompt, paste the reply — gated on content and outcome.

### Behavioural cases

| case | asserts |
|---|---|
| **ID1** | the shipped sample parses through the **real parser**, field for field (HT-D11); the template asks for every field the parser reads, states the closed vocabulary, demands JSON only first and last, **refuses value, grade and key-issue by name**, and carries no free-text field |
| **ID2** | a value, a grade **and** a key-issue judgement are each detected and **counted**; none reaches the identity; the refusal is **said** on the surface |
| **ID3** | the **printed** cover price survives the same reply whose market value is refused — asserted in both directions |
| **ID4** | empty, `unknown` and `n/a` are **absent**, never guessed or zero-filled; the surface says *not legible*; a reply with nothing legible never becomes an identity to confirm |
| **ID5** | markers are closed-vocabulary, case-folded and de-duplicated; anything else is dropped, counted and said |
| **ID6** | the identity **question comes before any control**; no grade control and no grade word anywhere; no valuation vocabulary — with a **control** asserting the printed `$1.00` *is* on the surface, so it is a gate about valuation and grade rather than about the character `$` |
| **ID7** | a correction changes the accepted value and **keeps the model's original**; clearing restores *absent* rather than an empty string; a field outside the contract cannot be set at all |
| **ID8** | the query is built from the **corrected** fields, moves when they move, and is empty when nothing is legible |
| **ID9** | Confirm produces the identity and its query, the modal closes, the surface states that pricing is not built — and **nothing is saved**, not a record and not a byte of the export |
| **ID10** | hostile strings are escaped on the identity surface **and** the confirmed surface |
| **ID11** | **both** prompt boxes hold the prompt after a render (content, not presence — HT-D63); Copy fills the box **unconditionally** and fills the one the finger was on; with **no key at all**, a pasted reply opens the same modal with the same actions |
| **ID12** | no valuation or evaluative vocabulary reaches the identity surface, with a planted control |
| **ID13** | the **shipped** contract gives a byte-identical identity by call or by paste, and the call carries the contract prompt behind its version prefix |

### Repointed, not weakened (HT-D60 Clause 3)

- The two cases that asserted *the seam ships empty* now assert that the shipped contract **is** the identification contract; the empty-seam guard is still gated, by clearing the contract and driving the capture chain through it.
- **`layout-gate.ps1` now measures the shipped identity draft**, not the synthetic contract's generic readout — measuring the stand-in would have kept the gate green while saying nothing about what ships. Its long-list case became a **short-viewport** case (360×520), because the identity draft is a fixed set of fields rather than a list: there, the body scrolls and the footer does not.

### The defect pass — 23 rows, every one failing, each naming its own case

`bash tests/defect-pass.sh`. The fifteen port rows still fail as recorded above; the eight added for R1:

| planted defect | verdict | first case to fail, by name |
|---|---|---|
| the value/grade/key-issue refusal list emptied | GATE: FAIL | `ID2` |
| absent fields guessed as `unknown` | GATE: FAIL | `ID4` |
| the marker vocabulary opened | GATE: FAIL | `ID5` |
| a correction overwrites what the model read | GATE: FAIL | `ID7` |
| the query built from the model's originals | GATE: FAIL | `ID8` |
| the prompt boxes stop being filled (HealthTracker's dead floor) | GATE: FAIL | `ID11` |
| a grade control planted above the identity question | GATE: FAIL | `ID6` |
| the shipped sample drifts from the parser | GATE: FAIL | `ID1` |

### R1.1 — the sticker price (D2 amendment, 2026-09-12)

**Taken without waiting for the device test, because the failure is SILENT:** a sticker price sitting in `cover_price` looks exactly like a printed one, nothing downstream can tell them apart, and catching it depends on someone noticing that a 1988 book claims a $5 cover. A hypothesis whose *confirmation is unreliable* is not one to spend a device pass deciding.

**Changed:** the template names the case (a price on a sticker, bag, label, board or shop tag is **not** the cover price — leave it out, and never report what anyone is asking); `asking_price`, `sticker_price`, `seller_price` and `sale_price` join the refusal list. **`ID_TEMPLATE_VERSION` holds at 1** — the field contract does not change, only what may fill one of its fields (HT-D64's distinction).

**Gated in BOTH directions**, as the cover-price control was:

| case | asserts |
|---|---|
| **ID14** | the template names the sticker/bag/label/board case **by name** — on the copy-prompt path the words are the only mechanism (HT-D64); `asking_price` is on the refusal list and `cover_price` is **not**; an asking price **and** a sticker price in one reply are refused **and counted**; **the printed cover price survives that same reply**; and the asking price reaches no surface at all |

**Defect pass — three rows, each failing by name:**

| planted defect | verdict | first case to fail |
|---|---|---|
| the asking price accepted as identification data | GATE: FAIL | `ID14` (the refusal-list assertion) |
| the refusal **over-reaches** and swallows the printed cover price | GATE: FAIL | `ID3` — the earlier of the two "printed price survives" assertions; `ID14`'s half asserts the same property |
| the template's sticker line removed | GATE: FAIL | `ID14` (the wording assertion) |

That second row is the point of the both-directions rule: a refusal that killed the legitimate field would be the `R1-identity-first` error over again, so the gate is defect-tested in the direction that *keeps* the field as well as the one that refuses.

**Result: `SUITE: PASS (2 of 2)`, 299/299 assertions, pinned 294 → 299 (+5), re-pinned in this commit.**

**The device test still runs, reframed:** it is evidence about **model behaviour**, not the gate on closing the hole. Photograph a stickered book — if the reply leaves the sticker out, the template is working; if it does not, that is a template-hardening finding on the copy-prompt path.

### Corrections made to the pre-registration before building (recorded as corrections)

1. **`R1-identity-first` was wrong as pre-registered.** It asked for *no price field anywhere in the draft*, with a planted `$` as its control — but the **printed cover price is a field and must render**. Restated: no **grade control**, no **valuation vocabulary**, plus a control asserting the printed price is present.
2. **`R1-refuse`'s fixture** carries a value, a grade **and** a key-issue claim, so C1's ruling is gated rather than only written down.
3. **`notes` was dropped from the contract** (D2) — a free-text field is a hole in a structural refusal.

### Limits of this evidence, stated

- **The contract has never been sent to a model.** Every call in every gate is stubbed. The template is gated for self-consistency against its parser, not for whether a model obeys it — **that is R1's device question**, and the first real capture is the first evidence that a phone photo of a cover yields these fields at all.
- **No price, and no product match.** The derived query is unverified against PriceCharting's search behaviour; that is R2's probe, which only the subscriber can run.
- **The floor's clipboard behaviour is gated in the harness browser only.** Copy filling the box is proven; what a phone's clipboard does with it is not.
- `CL5 BEHAVIOURAL` still cannot fail on this browser (HT-D60 Clause 2) and remains paired with its structural twin.

---

### D9 — the deferred provider's credential field, removed (2026-09-13)

**Reported from the device:** *"I went looking for how to get a PriceCharting token because the app asked for one."* The shipped Settings still carried a price-guide token field for a provider **D6 deferred and R2b replaced** — an empty input inviting a ~$600/year purchase that nothing in the app would have called.

**Removed, and the removal is what is gated.** The prices **machinery is untouched** — provider row, 1 call/s pacing, redaction, the `auth: 'none'` proof that D1's metering server is a table edit — and all of it is still exercised by the suite. Only the invitation is gone.

**The failure mode of removing it, handled:** a token **already saved by an earlier build** must not be stranded where it cannot be seen or deleted. It now appears in Storage **with a remove control, and only when it exists** — an exit, never an entrance — and the line never prints the token.

| case | asserts |
|---|---|
| **SH1 (D9)** | the shipped shell carries **exactly one** credential field, the vision key; the shell **names no deferred provider at all**; with no token saved Storage says nothing about one; a token saved by an earlier build **is shown with a way to delete it**; and that line never prints the token |

**Defect pass:** restoring the deferred provider's card fails **two** D9 assertions by name, naming the offending ids (`credBox-prices,credBox-vision`) — 308/310, `GATE: FAIL`. **30 rows now, every one failing, each naming its own case.**

**Count: 305 → 310** (+5), re-pinned in the same commit. Suite `SUITE: PASS (2 of 2)`.

### Device pass — the first two captures (2026-09-12)

Reported from the device against the deployed build. **This is the first evidence that the contract survives a real model** — every gate above stubs the call, which is the limit those gates state about themselves.

| capture | reply | what it establishes |
|---|---|---|
| **1** — `STAR WARS #2 · MARVEL · $1.00 · markers: newsstand` | correct on every field | identification correct **including publisher**; **the printed cover price survived**, which is the half of R1.1's sticker rule an over-eager refusal would have killed; and the **newsstand marker was read off the barcode box**, which had been rated a coin flip |
| **2** — `the AMAZING SPIDER-MAN #151 · MARVEL COMICS GROUP · DEC · 25¢ · markers: none seen` (~2 s) | correct | **the absence contract working where guessing was tempting** — a 1975 book predates the direct-market box, and the reply said *nothing* rather than defaulting to `newsstand`; and **`DEC` stayed as printed**, not normalised to "December 1975" (Fork B1 holding) |

Capture 1 is the same book **PriceCharting's own photo appraiser identified as "Lady Death: Rules Vol. 2 (2019)"** — the failure this slice's identity-first design exists to prevent, measured against the tool that produces it.

**Still unmeasured after two captures:** the refusal counter (nothing has been volunteered yet), and **field-level** absence — capture 2 exercised absence on `markers`, not on a field that was illegible.

**One bug, found here and fixed as R1.2 below:** the confirmed header rendered `STAR WARS ##2`. The model returns the issue as printed, so capture 1 gave `#2` and the header prepended a second; capture 2 gave a bare `151` and rendered correctly. **Intermittent by the model's output form** — which is what makes render-time normalisation the fix rather than a parser rule.

### R1.2 — exactly one `#`, whatever arrives (D2 amendment, 2026-09-12)

**Fixed at render, not at parse:** `issueLabel()` collapses any run of leading hashes to one and adds one when absent, on the draft header **and** the confirmed header. The parser is untouched — the field keeps what was printed (Fork B1).

| case | asserts |
|---|---|
| **ID15** | an issue arriving as `#2` renders **exactly one** `#` in the draft header, and in the **confirmed** header — the surface the bug was reported from; a bare `1` still **gains** one (control); `##2` collapses to one; **the field still shows what the model sent**, so the normalisation is display-only and never rewrites the reading; and the derived query is untouched |

**Defect pass:** restoring the unconditional prepend fails `ID15` **by name** — the device bug, reproduced. **27 rows now, every one failing, each naming its own case.**

**The diagnosis, generalised: D3.** Fork B1 promises the fields *as printed*; the header assumed *normalised* ones. Both sides were individually correct and individually gated — **a contract and its consumer disagreeing about one field is a failure no assertion on either side alone catches.** D3 turns that into a binding rule: where a contract promises a **range** of forms, its consumer is gated **across that range**, not on a specimen. `ID15` is that shape — bare, prefixed, doubled, and the field's own value in the opposite direction.

**Result: `SUITE: PASS (2 of 2)`, 305/305 assertions, pinned 299 → 305 (+6).**

**A correction to my own first version of this gate.** It searched the whole draft for `##` and failed — because the issue **input** legitimately renders `value="##2"`, the field keeping what was printed. The assertion was measuring the document when the claim was about the header. It now reads the header element, and the field's raw value is asserted **in the opposite direction** in the same case. *The gate was wrong, not the fix* — HT-D60 Clause 4 one level out: an assertion that can fail for a reason unrelated to the property it names.

**An unexplained flake, recorded rather than smoothed over.** One run produced **no SUMMARY at all** — "the suite did not finish" — with no failing assertion and no uncaught-exception line. The same suite then ran clean **nine times** (five at the 60 s virtual-time budget, three at 180 s, and the suite run above). I raised the budget on the hypothesis that the grown suite was exhausting it; **the evidence refuted that and the change was reverted**. What is established: the runner treated it as a **loud FAIL**, never a silent pass — the property HT-D56 exists to protect. What is **not** established is the cause. Recorded so that a second occurrence is a second data point rather than a surprise.

### Carried forward to R2 — the reading and the query: **RULED IN ADVANCE (D4, 2026-09-12)**

Not a fork R2 will discover — one it starts from. **D4 rules the shape:**

- the **as-printed reading is evidence** of what the cover says and what the human confirmed, and is **never normalised**;
- the **catalog query is derived from it**, a separate object with its own rules — drop leading articles, normalise the issue marker, decide what to do with the publisher (that last one open);
- and the query is **visible and editable**, because a normalisation that silently mangles a search is worse than one the user can see and fix. R1 renders it read-only; making it editable is R2's work.

**The evidence that produced the ruling:** capture 2's query reads **`the AMAZING SPIDER-MAN 151`** — faithful to the cover, and almost certainly not how PriceCharting catalogs the book (*Amazing Spider-Man #151*).

Two facts the slice is built on:

- **The query inherits the model's variance in the `#`.** Capture 1 produced `STAR WARS #2` (issue `#2`); capture 2 produced `the AMAZING SPIDER-MAN 151` (issue `151`). **R1.2 normalises the DISPLAY only** and leaves the query alone — correct under D4, since the query's rules belong where they can be checked against a real search.
- **What R2 must still settle:** the rules themselves (which articles, what happens to `#`, publisher in or out), whether a query survives into any record, and the probe that grounds all of it — still outstanding, still the subscriber's to run.

### Carried forward to the pricing slice — the ASKING PRICE (received 2026-09-12; NOT pre-registered)

Recorded here so the pricing slice is built on it rather than discovering it. The brief's domain rules 3, 4 and 7 carry the binding form.

- **The asking price needs a home, beside the grade**, as the second thing only the user can supply: a sticker, a sign, a verbal quote, or a **bulk rate** ("3 for $10"). Attested, never perceived.
- **The output is the comparison** — *"raw modelled at $X, they're asking $Y"* — not a valuation with the comparison left to the user's head.
- **Cover price and asking price are never conflated**, in the record or on a surface: one is printed on the book and read from the photo (identification, `cover_price`); the other is the seller's number, attested (pricing).

**A hazard this exposes in the contract already shipped (R1/D2), flagged rather than silently patched.** At a flea market the *asking* price is very often **visible in the photo** — a sticker on the bag, a price written on a board behind the stack. The identification template currently says `cover_price` is "the price printed on the cover", and a model reading a $5 sticker on a 1988 book whose cover says $1.00 would be **supplying pricing data through the identification path**, which is exactly the conflation rule 7 forbids. Two candidate repairs, neither taken without a ruling:

1. **A one-line template amendment plus `asking_price` on the refusal list** (a small R1.1): the template says a price on a sticker, bag, board or label is **not** the cover price and must be left out, and a model that volunteers an asking price is refused and counted, like a value or a grade. Cheap, and it closes the hole at the perception layer where it opens.
2. **Leave R1 as it is** and handle the distinction entirely in the pricing slice's own surface. Cheaper now, but it accepts that a sticker price can enter the record labelled `cover_price`, where nothing downstream can tell it from a printed one.

Seed gates for whichever slice takes it: the asking price never enters the identification contract; a record carries both numbers under **distinct names with distinct provenance**; the comparison surface states both and never prints one where the other belongs; a bulk rate is representable without inventing a per-book number the seller did not quote.

---

### The pre-registration, as it was written before building (kept verbatim, R1)
<!-- R1's original pre-registration follows; R2a's begins after it. -->


**Numbering.** The first slice in this repo: **R1**; its ruling becomes **D2**. D1 carries no R-number because the port was not a slice.

**What it is for, in one sentence:** turn a photo of a comic into **a confirmed identity** — everything the app believes about the book, visible and correctable — and nothing else. No grade, no price, no saved record.

**The rules it inherits** (`CLAUDE.md`, binding): the model perceives and the deterministic layer prices, so **no market value may enter, and the parser refuses one actively rather than dropping it** (HT-D45 Fork H); identity is confirmed, never assumed; and a phone photo cannot establish grade, so **a grade from the model is refused exactly like a price**.

### Survey — what is actually shipped (read from `app.js` at 5d95e13)

1. **The seam is empty and the chain is complete around it.** `VISION = { version, prompt, parse, accept, acceptLabel }` (`app.js:517`); `visionReady()` is false, so `byokCapture` refuses with a stated message and **zero calls**, and the capture surface renders "not built yet" instead of buttons. Decode, budgets, egress, retry, fallback, trace and modal are built and gated around it.
2. **One door.** `openCaptureResult(text)` (`app.js:535`) is the only way a result exists; the call path and the reply box both come through it, and the parity case is green. This slice must not add a second.
3. **The success body is a placeholder.** `resultReadoutHTML` (`app.js:569`) prints escaped key/value rows of whatever `parse` returned. R1 replaces it with the confirm question; the escaping case `P2` repoints to the new fields.
4. **`captureAccept()` hands the value to `VISION.accept` and closes the modal** (`app.js:557`, footer label from `acceptLabel`, `app.js:654`). What `accept` *does* is Fork E.
5. **Nothing persists.** Schema v1 is `{kind, version, settings}` (`app.js:122`) — no records, no ids, no drafts.
6. **The prices role has exactly one call**, `pricesPing` for Test connection (`app.js:1032`). There is no search, no product fetch, no product id anywhere.
7. **Pins to re-set in the slice's commit:** `EXPECTED_ASSERTIONS=248`, the one-name census manifest, and a `defect-pass.sh` row per new gate.

### The forks

**Fork A — where identification ENDS. The central one.**

- **A1 (recommended) — the reading, confirmed, plus the query it implies.** Photo → validated perception → the human confirms or corrects each field → an in-memory identity **and the exact PriceCharting search string R2 will send**, shown and copyable. No live price call.
  - *Why:* it is the whole half that can be built and gated without the token and without a verified search shape; it decides the query R2 depends on; and it keeps the slice to one question. The copyable query is also usable at a table today — paste it into pricecharting.com by hand.
  - *Cost, stated plainly:* **R1 alone shows no price, so it is a milestone rather than a release.**
- **A2 — the reading, resolved to a PriceCharting product.** As A1, then `/api/products?q=` → candidates → the human picks one → the identity *is* a product id.
  - *Why it is tempting:* the failure the product exists to prevent lives at the **match**, not only at the reading. A confirmed reading matched to the wrong product is the wrong-book failure one layer along.
  - *Cost:* the first live PriceCharting calls, whose behaviour is unverified (prerequisite below), plus two confirm surfaces in one slice.
- **A3 — everything through to a range.** Rejected as a slice: three questions (identity, product, grade) behind one gate.

**Fork B — the contract's fields.** Proposed v1, every field **optional and ABSENT when not legible**:

```json
{"title":"The Amazing Spider-Man","issue":"300","publisher":"Marvel",
 "cover_date":"MAY 88","cover_price":"$1.00","markers":["newsstand"],
 "notes":"UPC box present and readable"}
```

- `issue` and `cover_price` are **strings** (annuals, `1/2`, letters; `75¢` as printed) — a number would invent precision and a currency the cover states.
- **B1 (recommended): as-printed strings, no normalization.** B2: a normalized `cover_date_iso` beside it — deferred, because normalization is a guess the cover does not make.
- `markers` from a **closed vocabulary of what is VISIBLE**: `newsstand | direct | foil | facsimile | variant-cover | price-variant`. Anything not visible on the cover is not a marker.

**Fork C — the key-issue flag: perception, or lore?** *(Named rather than quietly resolved: the brief lists it.)* "Whether it looks like a key issue" is **not a property of the photograph** — it is market memory, which is the one thing this design routes away from the model.
- **C1 (recommended): leave it out of the v1 contract.** It is the field most likely to be confidently wrong, and nothing in R1 or R2 consumes it.
- **C2: keep it as an attention flag only** — never a fact, never beside a number, never feeding the price path, worded as *worth a closer look* rather than *this is key*.
- **C3: keep it as the brief wrote it.** Rejected here: it puts a market claim inside the perception contract the whole design separates.

**Fork D — alternates (`alts`/`p`, HT-R30's shape).**
- **D1 (recommended): none in v1.** HT-R30 itself ruled the threshold is the weaker defence and the **shape of the question** is load-bearing. Here the question is already *what is this*, every field is correctable, and the real off-ramp is R2's candidate list. A confidence number now is a constant with no consumer and no calibration data.
- D2: per-field alternates — revisit when the candidate list exists and can be compared against them.

**Fork E — what "Use this" does** (under A1).
- **E1 (recommended):** confirm → the identity object + the derived query, with the surface **stating plainly that pricing is not built**. An honest dead end beats a button that implies more.
- E2: also copy the query to the clipboard on confirm (one extra affordance, HT-D63's copy rules apply).

**Fork F — does anything persist?**
- **F1 (recommended): nothing.** Draft only, gone on discard — HealthTracker's photo draft shape. F2 (a triage record, schema v2) waits until there is a price worth recording, and would drag in migration machinery this repo has not ported.

**Fork G — the no-key floor.** A copy-the-prompt / paste-the-reply path for when the key is absent or the cap is spent.
- **G1 (recommended): yes, and gated.** The prompt is a constant and the reply box already exists. **HT-D63 is the warning**: HealthTracker's floor sat dead for weeks because the gate asserted presence, not content — so it is gated on content and outcome, or it is not built.
- G2: no floor; the key is required.

### Prerequisite, and the one thing only you can do

**If Fork A is ruled A2, the search must be verified live before any code** — HT-D45's precedent is that following the docs alone would have shipped a payload the endpoint rejects. The token is yours, so the probe is yours:

```
curl "https://www.pricecharting.com/api/products?t=YOUR_TOKEN&q=amazing+spider-man+300"
```

What the answer has to settle: the field names per match, whether issue numbers survive inside `product-name`, whether `console-name` separates publishers/variants usefully, and how many matches come back for a title that has many printings. Paste the JSON and it becomes R2's pre-registered contract, dated.

### Pre-registered gates

| case | asserts |
|---|---|
| R1-contract | the prompt asks for exactly the ruled fields and JSON only; the shipped sample **parses through the real parser** (template↔parser self-consistency, HT-D11); the contract version is pinned and the prefix carries it |
| **R1-refuse** | a reply carrying a market value **or a grade** (`value`, `worth`, `price_estimate`, `nm_price`, `grade`, a ladder) is **stripped and SAID**, on the call path and the paste path, and none of it reaches the surface |
| R1-coverprice | the **printed** cover price survives while a market value in the same reply is refused — both directions asserted, so the distinction is the gate rather than a comment |
| R1-absent | an unreadable field is **absent**, never guessed and never zero-filled; the surface says it was not legible rather than printing an empty value |
| **R1-identity-first** | the success state asks **what it is** before anything else; no grade control and no price field exists anywhere in the draft |
| R1-correct | every perceived field is correctable, and a correction **keeps the model's original beside it** (`ai_*`, HT-D55 / HT-D57's correction-loop shape) |
| R1-query | the search string is derived from the **confirmed** fields, not the model's originals, and changes when a field is corrected |
| R1-parity | call path and paste path still produce byte-identical results — repointed to the real contract, not weakened (HT-D60 Clause 3) |
| R1-escape | hostile strings in every new field are escaped (P2 repointed) |
| R1-floor *(if G1)* | every prompt box holds the prompt after boot, copy yields the real text, and a pasted reply opens the same modal — content and outcome, not presence (HT-D63) |
| R1-vocab | no valuation or evaluative vocabulary reaches the draft surface, with a planted control |

**Defect pass required before any of this is evidence** (HT-D60, and Clause 4 applies to each fixture): at minimum **R1-refuse** (the fixture must contain a value *and* a grade that could leak), **R1-identity-first** (a `$` string planted where it could surface) and **R1-absent** must be seen to fail against their own removal, with a `tests/defect-pass.sh` row each.

### What this pre-registration does not settle

Grade and price; records and schema v2; the matcher and any corpus; the candidate off-ramp's destination (A2 / R2); and whether a wrong identification is ever recorded for calibration (HT-R30 Fork H's shape, which needs a consumer first).

---

## R2 — Pricing, re-scoped into two slices (2026-09-12)

**R2 is the pricing work as a whole**, and the docs cite it by that name. It is **not a slice**: it is two, sequenced.

- **R2a — canonical identity** via the Grand Comics Database. **Ruled and deferred** (D6).
- **R2b — price via eBay sold comps** through an Apify scraper. **Pre-registered, forks ruled**, blocked only on the subscriber's probe.

**PriceCharting was withdrawn as R2's dependency** on 2026-09-12 — ~$600/year for modelled values with no sold comps and no history, not committed before the app has been used at a table. It remains a named provider behind the same seam (D1's provider table).

## R2a — Canonical identity via the Grand Comics Database — RULED AND DEFERRED (2026-09-13; NOT built)

**Ruled 2026-09-13. Fork A → A5: defer R2a, build R2b first.**

> A1 would be **the first infrastructure in either project that must exist and stay up**, and it would see every lookup against a README that promises no telemetry. **Not a cost worth paying for a tool that has not been used at a table yet.**

**A1 is the named path for when canonical identity is actually needed** — and when it is built, the proxy means either **logging off by design or the promise reworded**, decided at that point rather than assumed away now.

**Ruled with it:** **B1** (query rules — now adopted immediately for any catalog search, see D4's amendment), **C1** (candidates ranked by country → year → publisher on the existing confirm surface), **D1** (shared descriptors become variant candidates, never a guess), **F1** (corroborate, never auto-correct), **G1** (one shared surface with R2b). **Fork E ruled:** a canonical identity is **`(source, series id, issue index)`** plus the as-printed reading beside it — two objects (D4).

**GCD's licence and attribution remain BLOCKING for R2a** and are **not** blocking for R2b. The gates below stand as pre-registered, for the day R2a is built.

### The pre-registration, as written before the deferral

**The re-scope that produced it.** PriceCharting is **withdrawn as R2's dependency**: ~$600/year for *modelled current values, no sold comps, no history* is not a commitment to make before the app has been used at a table. It remains a **named provider behind the same seam** for later. Price moves to **R2b** (eBay sold comps via Apify); identity comes first because it is free, official, and grounds D4's query rules in a real catalog instead of an assumed one. **R2a prices nothing.**

### Verified against the live API, 2026-09-12 — and the verification changed the answer

Anonymous, JSON, no key. **Probed, not assumed** (HT-D45's precedent: a vendor's own docs once described a payload its endpoint rejected).

| probe | result |
|---|---|
| API root | advertises exactly two endpoints — `series`, `publisher`. **There is no issue list.** |
| `?name=` · `?search=` · `?name__icontains=` · `?q=` | **silently ignored** — HTTP 200 with the full `count: 232776` every time |
| `/api/series/name/<name>/?format=json` | **the only working search.** `Amazing Spider-Man` → **322** |
| leading article | `the AMAZING SPIDER-MAN` → **146**, a *different and worse* set; top hit *"Adventures in Reading Starring the Amazing Spider-Man"* |
| case | irrelevant — `AMAZING` / `amazing` / `Amazing` all → 322 |
| issue number appended | `the AMAZING SPIDER-MAN 151` → **0** |
| series record | `name, country, language, active_issues[], issue_descriptors[], color, dimensions, paper_stock, binding, publishing_format, notes, year_began, year_ended, publisher` |
| **`issue_descriptors`** | parallel array to `active_issues`: `"1"`, `"2 [Regular Edition]"`, `"2 [British]"` … **967 entries for ASM 1963** |
| issue record | `series_name` ("The Amazing Spider-Man (1963 series)"), `descriptor`, `number`, `volume`, `variant_name`, `title`, `publication_date`, `key_date`, **`price` ("0.12 USD")**, `page_count`, `editing`, `indicia_publisher`, `brand_emblem`, `isbn`, `barcode`, `rating` |
| **CORS** | **ABSENT.** No `access-control-allow-origin` on a GET carrying `Origin`; preflight returns `200` with only `Allow: GET, HEAD, OPTIONS` |
| Apify, for contrast (R2b) | **`access-control-allow-origin: *`**, methods `GET, POST`, `Authorization` permitted |

**Three findings that change the slice:**

1. **The browser cannot call GCD.** This is Fork A, and it arrives at D1's territory from an unexpected direction: **the free, official source needs a server to reach, while the paid scraper is directly callable.**
2. **Resolution is a lookup, not a crawl.** `issue_descriptors` runs parallel to `active_issues`, so "#151 of the 1963 series" is **one series fetch + one issue fetch by index** — not 967 requests. Feasibility was the thing most at risk, and it holds.
3. **D4's derivation rules are now measured.** Drop the leading article (322 vs 146, and the 146 are worse); never append the issue number (0); case is free. The as-printed reading *"the AMAZING SPIDER-MAN" + "151"* would find noise or nothing — which is exactly what D4 predicted and what R1's device capture produced.

**A bonus the probe surfaced:** the issue record carries `price` (the printed cover price), `barcode` and `brand_emblem` — so the catalog can **corroborate** R1's reading rather than merely replace it (Fork F).

### Survey — what this composes with

The confirmed as-printed reading and its derived query (R1/D4), the query currently **read-only**; one `egress()` with a provider table carrying roles and auth styles including `none` (D1); the one-door result and the outcome modal's three exclusive states (HT-D51); and no records at all — schema v1 (D2 Fork F1).

### The forks

**Fork A — how the page reaches GCD. THE central one, and it may re-sequence the work.**

- **A1 (recommended): a credential-free, read-only proxy we host** (a Worker/function: forward `GET /api/...` to comics.org, add CORS, cache). **It holds no secret and meters nothing** — D1's bright line is about a *paid-subscription token in a browser*, and this crosses nothing of that. But it is **infrastructure that must exist and stay up**, and it is honest to say that is new posture, not a detail.
  - **A privacy delta that must be named:** a proxy we run **sees every lookup**. The README promises no telemetry and data staying on the device. Logging must be off by design, and the promise re-worded if it cannot be.
- **A2: a public CORS proxy.** Rejected — a third party on the identity path, rate-limited, and it sees the same traffic with none of the control.
- **A3: a different catalog that sends CORS.** Marvel's API needs a public+private key pair hashed per request (a credential in the browser again, Marvel-only coverage); ComicVine needs a key and restricts use. Both are more scope and less catalog.
- **A4: ship a GCD subset locally.** Their dumps could give a series index offline — but issue resolution still needs the API, so it does not remove A1, only shrinks it.
- **A5: defer R2a and do R2b first.** eBay needs only the derived query, and **Apify is CORS-open**, so R2b needs no new infrastructure. The cost: identity stays as-printed, and D4's rules stay ungrounded.
  - **This is the re-sequencing question.** "Do R2a first" was ruled when GCD looked directly callable. It isn't. **A1 buys the identity half at the price of running a service; A5 buys a working price path with no new infrastructure.**

**Fork B — the query derivation rules (D4 said "its own rules"; the probe now says which).**
- **B1 (recommended):** drop leading articles; **never** append the issue number to the series query; leave case alone; keep the publisher **out** of the query string (it is not part of `name`) and use it to **rank** candidates instead.

**Fork C — candidate disambiguation.** Four series are literally named "The Amazing Spider-Man" (US 1570, US 24842, PH 149585, AU 72382).
- **C1 (recommended):** rank by country → year → publisher, show `year_began–year_ended · publisher · country` per candidate, and let the human pick — **the same identity-first confirm surface R1 already has**, not a second modal (HT-D51 permits exactly one outcome state).

**Fork D — issue resolution and variants.**
- **D1 (recommended):** match `issue_descriptors` on the bare `number`; when several descriptors share it (`"2 [Regular Edition]"`, `"2 [British]"`), present them as **variant candidates** rather than guessing. This is where R1's `markers` earn their keep — `price-variant` ↔ `[British]`.

**Fork E — what a canonical identity IS, once resolved.** The GCD **issue id + series id**, kept **beside** the as-printed reading, never replacing it (D3/D4). Whether it persists is bound to F1's "nothing is saved" — still open.

**Fork F — corroboration vs correction.** GCD's `price` against R1's `cover_price`; `barcode`/`brand_emblem` against the newsstand marker.
- **F1 (recommended): surface disagreement, never auto-correct.** A catalog that silently overwrites what the human confirmed is the wrong-book failure wearing a badge of authority.

**Fork G — shared surface with R2b, or separate?** *(raised as asked)*
- **G1 (recommended): one surface.** Identity resolves, then comps attach to the resolved identity in the same view. Two confirm surfaces would mean two outcome states, which HT-D51 forbids.

### Pre-registered gates

| case | asserts |
|---|---|
| R2a-contract | the call is built as the **path form** `/api/series/name/<name>/`, never as a query parameter — with a case proving a `?name=` build returns the **unfiltered** catalog, because that trap returns HTTP 200 and looks like success |
| R2a-query | the derived query drops leading articles and excludes the issue number; it is **visible and editable** (D4), and editing it changes what is searched — round-tripped, not merely rendered |
| R2a-resolve | series → issue by descriptor index: **exactly one series fetch and one issue fetch**, asserted by call count, so a regression into a crawl fails |
| R2a-variants | descriptors sharing a number become variant candidates; none is auto-selected |
| R2a-candidates | same-name series are presented with year, publisher and country; the human picks; "none of these" reaches a stated unresolved path |
| R2a-corroborate | a disagreement between GCD's `price` and the confirmed `cover_price` is **surfaced**, and **the reading is never overwritten** (D3/D4) |
| R2a-egress | the GCD call goes through `egress()` on its own provider row with `auth: 'none'`; **no credential is attached**; and **the asking price and the grade never enter any lookup** (brief rules 3, 4 and 7) |
| R2a-absence | no match states absence; no identity is fabricated, and no candidate is invented from a partial match |
| R2a-provider | PriceCharting can still be added as a **table row** with no code change (repointed from D1's existing case, not weakened) |
| R1-repointed | every R1/R1.1/R1.2 case still holds with resolution attached — repointed, not weakened (HT-D60 Clause 3) |

**Defect pass required before any of this is evidence** (HT-D60), with rows at minimum for: the query built as a parameter, the article not dropped, the issue number appended, resolution crawling instead of indexing, corroboration overwriting the reading, and a credential attached to a `none` row.

### R2b — the constraints as first recorded (superseded by R2b's own pre-registration below)

Constraints to carry in, stated as given:

- **It is a scraper, not an API.** It reads public pages, breaks on layout changes, and sits in a grey zone against eBay's terms. Acceptable for a personal tool; **not** a dependency to build a sold product on. **P(works a year unmaintained) ≈ 0.5** — so the seam must make it replaceable **by configuration**: provider table, one egress function, exactly as vision is.
- **Provenance rides on every number.** *"14 recent eBay solds, last 90 days"* is the label — **never "value"**. A user must be able to tell a **comp** from a **guide figure** from a **modelled figure** at a glance, because they are three different claims.
- **Sold comps are not grade-ladder data.** They are a scatter of individual sales at whatever grades happened to sell. **Display the scatter with the grades stated, never a ladder** — inventing a ladder from sparse solds is fabrication. **Below N comps, say so; never extrapolate.**
- **Asking price and grade stay human-supplied** (brief rules 3, 4 and 7). The triage output is the comparison: *"N recent solds at $X–$Y, they're asking $Z, you'd grade it W."*
- **Credentials:** an Apify token is pay-per-use rather than a subscription, but it is **still extractable from a browser**. D1's bright line holds unchanged — BYOK for the subscriber and testers, server-held before anyone else.
- **Verified 2026-09-12:** Apify's API sends `access-control-allow-origin: *` and permits `Authorization`, so R2b **is** callable from the page (unlike GCD).

Open for R2b's own pre-registration: what an eBay sold-search string looks like and **how noisy the matches are** (reprints, lots, unrelated items — filtering is the real work); minimum comp count before a range is shown; the recency window; whether listing condition strings map to anything trustworthy; and Fork G's answer.

### What this pre-registration does not settle

Fork A (and with it, whether R2a or R2b goes first); the ranking rules for candidates; whether a resolved identity persists (schema v2 is still unwritten); **GCD's licence and attribution requirements for displaying its data** — not yet checked, and it must be before anything ships; GCD's rate limits, which advertise no headers; and everything in R2b.

*(Fork A was ruled A5 on 2026-09-13 — see the ruling log at the top of this section. GCD's licence remains blocking for R2a only.)*

---

## R2b — Price via eBay sold comps — **BUILT, GATED, DEFECT-PASSED** (2026-09-13)

**What it is for:** the number that makes the triage a decision — *"N recent solds at $X–$Y, they're asking $Z, you'd grade it W."* **Actual sales, not guide values.** It is the first slice that prices anything.

### Verified against Apify's public API, 2026-09-13

| probe | result |
|---|---|
| CORS | **`access-control-allow-origin: *`**, methods `GET, POST`, `Authorization` permitted — **the page can call it**, unlike GCD |
| store search `?search=ebay` | **2,532 actors**; six on page one, including four sold-listings scrapers |
| candidate actor | **`caffein.dev/ebay-sold-listings`** — "eBay Sold Listings Search". **574,056 runs · 3,139 users · 4.38★ (14 reviews) · last run 2026-09-13** |
| its cost model | `PAY_PER_EVENT`: **"1000 items (no details)" = $2.00**, "result" = $0.00001, "Actor Start" = $0.00005 — **the $2.00 read was WRONG; the console charges $4.00/1,000** (probe, 2026-09-13) |
| its stated filters | *"date window, result limit, category/subcategory selection (subcategory overrides category), marketplace"* |
| its stated result fields | sale price + currency, **sale completion timestamp**, listing title, item URL and identifier, **localized condition label plus a mapped numeric condition code**, **category label/ID**, listing type, best-offer-accepted flag, bid count, shipping cost and type, combined total price, images, **seller identifier and feedback metrics**, scrape timestamp |
| a two-stage alternative | **`blackfalcondata/ebay-sold-listings-scraper`** prices **"Fast item (search-card / sold)"** separately from **"Detailed item (full item page)" at $0.005** |
| `exampleRunInput` | **a placeholder** (`{"helloWorld": 123}`) — **the actual parameter names are NOT verified** |

**Three findings:**

1. ~~**The ~$2/1,000 estimate is exact, not approximate**~~ — **WRONG BY 2×; the probe measured $4.00/1,000.** The payload's charge event was read *as verification* and it was not one: a machine-readable number felt like evidence in a way a marketing page would not have, and only the console actually charges. The half that held: "no details" is the **cheap search-card tier**, and Item Specifics are not in it.
2. **The two-stage pipeline has a price tag per stage.** One actor already sells exactly that split — cheap search-card events versus $0.005 per full item page. So "how many survivors do we deepen?" is a **cost fork**, not a style question: 200 survivors deepened = $1.00 on top of a ~~$0.20~~ **$0.80** search — so deepening adds **125%** to a lookup, not 400% as the wrong rate implied. *(The cost fork survives the correction; its direction reverses.)*
3. ~~**Condition arrives as a label plus a numeric code, and category as a label plus ID**~~ — **FALSIFIED by the probe, and it is the finding that mattered most.** Condition does arrive as label plus code, but it carries **no grade information at all**; and **there is no category field on a result whatsoever**. The clause that was doing the work — *"raw-vs-slab have real fields behind them rather than string-matching hope"* — is **exactly backwards**: string-matching hope is precisely what stage one leaves us. This is what an actor's *advertised* field list is worth against one real run, and the advertised list is where that sentence came from.

**Not verified, and blocking the build:** the actor's **input parameter names** (the example input is a placeholder), whether **Item Specifics** are exposed at all by any of these actors, whether category can be pinned to **259104**, and what a real comics query actually returns. Those need one paid run against a token — **the subscriber's**, per D1.

### Ruled 2026-09-13 — all six forks as leaned

| fork | ruling |
|---|---|
| **A** | **one stage first**, on the ~~$2~~ **$4**/1,000 tier. The $0.005-per-item deepening is **deferred until stage one's output is seen** — HT-D65's discipline (measure before tuning), and it makes the first probe cost pennies |
| **B** | **N = 5** for a range; **3–4 shown as individual sales**; below 3 **says so** |
| **C** | **90 days**, stated on every render |
| **D** | filtering is **ours, client-side, visible and gateable** — and **D5 binds the actor's own filters too**: passing `category=259104` must be **proven to have narrowed**, not merely to have returned 200 |
| **E** | **a rule, not a choice — D7.** Never map an eBay condition to a comics grade |
| **F** | **a rule, not a choice — D8.** No average, no midpoint, no "estimated value" anywhere |

**A correction to my own framing, recorded rather than dropped.** I offered the actor's 574,056 runs and a run today as *"mild evidence against P≈0.5"*. **It is not.** It is evidence the actor works **now**; the estimate was about **surviving eBay's next layout change**, which those numbers say nothing about. **P≈0.5 stands unchanged**, and the replaceable-by-configuration seam is built on that basis.

### The probe — what to run, and what to paste back

**The token is the subscriber's (D1), so this run is yours.** It settles the three things blocking the build: the actor's **real input parameter names**, what a **comics query actually returns**, and whether **Item Specifics** are reachable at all.

**Setup (no account yet):**
1. Create a free account at **apify.com**, then open **`apify.com/caffein.dev/ebay-sold-listings`** and press **Try for free** — that opens the actor in the console with its **Input** form, which *is* the schema the payload would not give us (`exampleRunInput` is a placeholder, `{"helloWorld": 123}`).
2. If the console asks for a payment method before running a store actor, **note that** — it changes how a tester without billing could ever use this.

**The run:** query **`amazing spider-man 151`**, category/subcategory set to **Comics (259104)** *if such a field exists*, date window **90 days**, and **limit ≈ 100 results** — small on purpose, because stage one is all we are testing and the cost is per result.

**Expected cost.** The actor's charge events, read from the API on 2026-09-13: **`Actor Start` $0.00005**, **`result` $0.00001**, and **`1000 items (no details)` $2.00**. How those combine is *not* clear from the payload — which is itself worth knowing — so a 100-result run should land somewhere between a fraction of a cent and about **$0.20**. **Check the run's cost readout and paste it**; that number settles the model.

> **Settled, 2026-09-13: the estimate was wrong and the instruction that caught it was right.** The rate is **$4.00/1,000**, so a 100-result run is **$0.40** — double the top of the range predicted here. The run itself was billed **$0.00** against a **$5.00 free-tier credit that required no payment method**. Asking for the readout rather than trusting the payload is the only reason the record is now correct; the prediction was the part that failed.

**Paste back four things:**
1. **The Input JSON** the console shows for the run (its **parameter names** are what we cannot get any other way).
2. **Two or three complete result objects**, verbatim — field names and values as returned.
3. **The run's cost/usage summary.**
4. **Whether anything resembling Item Specifics** (Grade, Certification, Variant Type, Signed, Reprint) appears in a result, or only in the listing page the result links to.

**Do not paste the token.** Nothing about the run needs it here, and D1's hygiene applies to this transcript as much as to the app.

**One design note that comes out of the probe's own shape:** when the app calls this, the token rides as an **`Authorization` header**, never as a URL parameter — Apify's CORS response permits `Authorization`, and D1 forbids a credential in a request URL after PriceCharting's `t=` lesson.

### The probe RETURNED — 2026-09-13 (run by the subscriber; $0.00 charged, under 5 seconds)

**It cost nothing and needed no card.** Apify's free tier carries **$5.00 of credit and asked for no payment method**. Two consequences worth recording: the D5 follow-up below is affordable out of the same credit, and **a tester without billing can run this** — which is not true of PriceCharting, and was the open question planted at step 2 of the setup instructions above.

**The rate is $4.00 per 1,000 results, not $2.00.** Every `$2` figure above is struck. At $4.00/1,000 a 100-result lookup is **$0.40**, and the $0.005-per-item deepening is **$0.50 per 100** — so **stage two more than doubles a lookup**.

**The input schema, as the console shows it.** Exactly what the placeholder `exampleRunInput` withheld:

| input | shape |
|---|---|
| **`Keywords`** | **an ARRAY** — and **`Keyword` and `Search` are DEPRECATED**. We never guessed a parameter name, so nothing is repointed. Had we guessed, we would have guessed the deprecated singular and built against it |
| `Category`, `Subcategory` | reported as **numeric** |
| filters offered | Days to Scrape · Count · Sort order · Min/Max price · Buying format · Item location · Condition · Condition ID · **Aspect Filter (a JSON object)** |

**The result fields, as returned.** Ten — and the **absences** carry the slice:

`keyword` · `itemId` · `title` · `condition` · `conditionId` · `endedAt` · `soldPrice` · `soldCurrency` · `listingType` · `isBestOfferAccepted`

**Four findings.**

1. **The data is on-target.** Every visible row was the right book; **no lots or bundles in the first eight**. Noise is lower than this pre-registration assumed, which demotes Fork D's client-side filter from load-bearing to a safety net. *Eight rows is a thin sample and lots are a tail risk — a lead, not a settled number.*
2. **No Item Specifics at stage one.** No **Grade**, **Certification** or **Variant** field exists on a result. They live on the listing page — the $0.005 tier. **Stage one alone cannot split raw from slabbed structurally.**
3. **D7 is confirmed empirically, not merely argued.** Three books all at **`Pre-Owned / 3000`** sold for **$9, $29.99 and $89** — a **10× spread at an identical condition code**. D7 was reasoned from a vocabulary mismatch; it is now measured. **The condition field carries no grade information whatsoever.**
4. **Grade lives in the TITLE as free text**, in the seller's own words, with no consistent format: *"VF- 1 CF staple detached"*, *"GD"*, *"VG-"*, *"VF- 7.5"*. It is the **only** grade signal stage one has.

**The scatter — one book, 90 days:** **9 · 16.21 · 18.88 · 29.99 · 40 · 49.99 · 89 · 145.** Eight comps spanning **16×**. **D8 is confirmed the way D7 was:** no average across that is honest, and a refusal pre-registered on principle is now backed by data.

**What the probe BROKE — a ruled fork, not a detail.** `R2b-groups` asserted that *"a comp cannot move between them without its **certification field** changing."* **There is no certification field.** **Fork A ruled one stage; Fork E ruled two groups; finding 2 says the split needs stage two's data — A and E could not both hold.** The gate was unsatisfiable against real stage-one output: HT-D60 Clause 4's problem (a fixture that cannot exhibit the behaviour it asserts), found on the *source* rather than on the fixture, and found because the probe ran **before** the build rather than after. **Ruled 2026-09-13 → D10**, and `R2b-groups` is rewritten below to the property that replaced it.

**Newly the most interesting unknown: the Aspect Filter.** It takes a JSON object, and eBay aspects *are* Item Specifics. If it filters on **Grade** or **Certification** as a *query parameter*, it may separate raw from slabbed **without paying the deepening tier at all** — which would settle D10's fork cheaply and in the right direction. Flagged by the subscriber, and it earns its own probe.

> **PROBED, 2026-09-13 — the door is shut, and measured shut.**
>
> | aspect sent | result | reading |
> |---|---|---|
> | `{"Publisher":"Marvel Comics"}` | ~100 | **uninformative by construction** — a true value cannot separate a working filter from an ignored one |
> | `{"Publisher":"DC Comics"}` | **ZERO** | **live and narrowing** |
> | `{"Grade": …}` | 100, unfiltered | **ignored** — never reaches eBay's aspect layer through this actor |
> | `{"Certification": …}` | 100, unfiltered | **ignored** |
>
> **Grade and Certification are not queryable here, so deepening would buy a field that cannot be queried anyway.** D10 stands on measurement; Fork E stays closed.
>
> **And the standing fact closes it harder than the measurement does:** even a *working* Grade aspect would reach only the slabbed minority, because **most raw books are sold by people who never fill a structured field at all**. Grade lives in the title text regardless — D7, ruled from vocabulary, now evidenced.
>
> **Publisher is REFUSED precisely BECAUSE it works** (D10, gated at `CQ3`, defect row 41). Aspects are populated by the sellers who populate aspects — the professional, slabbed end — so filtering on Publisher would silently drop raw listings whose sellers left it blank and pull the scatter toward the graded end. **A filter that narrows correctly can still corrupt, by selection** — and a dropped row leaves no trace on a surface, where a mislabelled one at least renders.

### The input schema, fetched from the build — 2026-09-13 (unauthenticated, free)

**Why this was fetched at all.** The probe returned the console's **display labels**. Labels are not wire keys, and the request body is where a wrong guess bills money silently. Apify publishes an actor's input schema without a token: `GET /v2/acts/caffein.dev~ebay-sold-listings` → `taggedBuilds.latest.buildId` → `GET /v2/actor-builds/{id}` → `inputSchema`. **17 properties, `required: []`.**

**The labels would have produced three errors in the two fields that matter most:**

| label, as reported | actual wire key | type | note |
|---|---|---|---|
| `Keywords` | **`keywords`** | array | lowercase; the capital was the *title* |
| `Category` — *"numeric"* | **`categoryId`** | **string**, default `"0"` | **not numeric.** Maps to eBay's `_sacat`. `"0"` = All Categories |
| `Subcategory` — *"numeric"* | **`subcategoryId`** | string, default `""` | **overrides `categoryId` when set.** Left blank |
| `Days to Scrape` | **`daysToScrape`** | integer, **default 30** | **Fork C ruled 90.** Unset ships a third of the ruled window |
| `Count` | **`count`** | integer, default 100 | |
| `Sort order` | **`sortOrder`** | string, default `"endedRecently"` | |

**`count` is PER KEYWORD** — *"each keyword runs as a separate search with the same filters applied to all."* So the billable bound is **`count × keywords.length`**, not `count`. `R2b-cost` asserts on the product, and the app sends **exactly one keyword**.

**The 17th property nobody had seen, and it is the dangerous one: `includeCompletedListings` (boolean, default `true`).** Its own description makes it a trap in **both** directions:

- **`false`** → *"all results are guaranteed sold items, but Best Offer Accepted items will appear as regular `buy_it_now` **with the asking price shown as `soldPrice`**."* **An asking price silently occupying a sold-price field** — brief rule 7's conflation, committed *inside the data source*, at field level, invisibly. For this app that is the worst failure on the menu: the one distinction the product exists to keep.
- **`true`** → applies Completed alongside Sold, which is eBay's ordinary sold query (`LH_Sold=1&LH_Complete=1`), and is what makes `isBestOfferAccepted` and `listingType` trustworthy.

**Ruled: `true`, and pinned EXPLICITLY rather than taken as a default.** The safe value and the default coincide today; a vendor's default flip would move the app into the asking-price mode with **no visible change and no error**. Pinning what you depend on is D5's family — a filter that stops filtering looks exactly like one that works, and so does a flag that stops meaning what it meant.

**One documented claim contradicts the probe.** `subcategoryId`'s text says *"the output record's `categoryId` / `category` fields reflect the effective category actually used for the search."* **The returned field list has neither.** One of the two is wrong. If the documentation is right, **the D5 question below collapses from four runs and $1.60 to reading a field off the run already paid for** — so that is checked before the four runs are spent.

**Both endpoint paths confirmed against the live API, unauthenticated, $0.00, no actor started.** `GET /v2/users/me` → **401 `token-not-provided`**; `POST /v2/acts/caffein.dev~ebay-sold-listings/run-sync-get-dataset-items` → **401**, while a *misspelled* endpoint on the same actor (`…-itemz`, `run-syncX…`) → **404 `page-not-found`**. Apify resolves the endpoint name before the credential, so the 401 is a signal rather than the blanket reply. *A first attempt at this probe was unsound and is recorded as such: it hardcoded 401 as the only healthy answer and read a 402 as a wrong path, when its own control showed 402 is returned before the actor is resolved — at that endpoint a real actor and a fake one are indistinguishable. The actor's identity is established from `GET /v2/acts/…` returning its public record, not from a POST.*

### The D5 follow-up — does `Category=259104` narrow, or did the keyword do all the work?

> **SUPERSEDED 2026-09-13 — the four-run design below is retired, and the reason is worth more than the design was.**
>
> It spent **$1.60** on a filtered/unfiltered set difference and would have concluded from *"fewer results"*. **That inference does not hold:** fewer results is equally consistent with a filter that works and a query that happened to match less.
>
> The subscriber's aspect probe settled the analogous question in **one run** by sending a **value that must exclude everything** — `{"Publisher":"DC Comics"}` against a Spider-Man query, returning **ZERO**. Nothing but a live filter produces that; the true value (`"Marvel Comics"`, ~100) proved nothing at all.
>
> **The method, now D5's amendment: to prove a filter narrows, pass a value that must exclude everything.** It is the planted control the gate scripts already use, applied to a *source's* filter instead of our own — cheaper, and conclusive rather than suggestive.
>
> **So `categoryId` is settled by one run**, not four: send a category that cannot contain comics and expect zero. The design below is kept only as the record of how it was first approached.

> **PROBED AND SETTLED, 2026-09-14 — the pin narrows.**
>
> | input | value |
> |---|---|
> | `keywords` | `["amazing spider-man 151"]` |
> | `categoryId` | **`"6000"`** — eBay Motors, which cannot contain a comic |
> | `aspectFilter` | `{}` — **cleared, to isolate the variable**, so the result is attributable to the category pin and nothing else |
> | `daysToScrape` / `count` | 90 / 100 |
>
> **Result: ZERO.** Nothing but a live, narrowing filter produces that from a query whose keyword alone returns a full page.
>
> **`categoryId=259104` is therefore a real filter, not a decoration**, and stays pinned. D5's last unproven filter in this slice is closed — and closed for **$0.40 at most**, because a falsifying probe returns no rows to bill for. The four-run set-difference design would have spent $1.60 to reach a weaker conclusion.
>
> **Twice now the false value has done what the true one could not.** `{"Publisher":"Marvel Comics"}` returned ~100 and proved nothing; `{"Publisher":"DC Comics"}` returned zero and proved everything. The same shape settled the category. That is no longer an observation about one probe — it is D5's method.
>
> **What kind of evidence this is, stated because this file promises re-runnable gates.** It is **not** re-runnable and cannot become one: it needs a live token and spends money, so no automated gate can hold it. It sits with the device passes and the aspect probe — a measurement, recorded once, with its date and its exact inputs, because that is the only durability available to it. **A gate that cannot exist is better named than quietly assumed.**

**D5 requires this and there is no shortcut.** The probe set the category, and a filter that changes nothing looks exactly like one that works. **There is no category field on a result**, so narrowing cannot be checked by inspecting rows: the only available method is a **set difference between a filtered and an unfiltered run**.

**One specimen is not enough — this is D3's rule applied to a filter.** A category pin is inert on an *unambiguous* keyword (nothing but comics is called *"amazing spider-man 151"*) and can still be load-bearing on an *ambiguous* one, where toys, DVDs, shirts and trading cards share the words. **Testing only the unambiguous case would read "inert, remove it" — and remove the filter that carries the ambiguous books.**

**Four runs. `count = 100`, 90 days, everything else identical:**

| run | `keywords` | `categoryId` |
|---|---|---|
| A | `["amazing spider-man 151"]` | `"0"` (All Categories) |
| B | `["amazing spider-man 151"]` | `"259104"` |
| C | `["hulk 181"]` | `"0"` |
| D | `["hulk 181"]` | `"259104"` |

`hulk 181` is chosen for maximum ambiguity: a famous key issue, so it has deep comic listings, **and** a merchandise tail deep enough that a working filter must visibly cut it.

**Cost: 4 × $0.40 = $1.60** of the $5.00 credit. (`count = 50` halves it, at the price of seeing less of the tail — and the tail is where the merch lives.)

**Paste back the `itemId` list from each run.** Ids alone, not the rows; that is all the comparison needs.

**What each outcome means, ruled in advance so the result cannot be read to taste:**

- **B ≡ A and D ≡ C** (identical id sets) → the pin is **inert**, and **D5 says remove it** rather than ship a filter that lies about what the query did.
- **D ⊊ C** (strictly fewer, and a proper subset) → it narrows **where it matters**; keep it, and record that it is **inert on unambiguous keywords** rather than pretending it always works.
- **B ⊊ A as well** → it narrows everywhere; keep it unconditionally.
- **Any id present in a filtered set but absent from its unfiltered twin** → the pin is **not a filter at all but a different query**, and both the gate and the query builder must say so.

### Carried in, as ruled

- **eBay's structured layer:** category **259104** (Comics & Graphic Novels, flat since 2021); **Item Specifics** as the target schema — Series Title, Issue Number, Publisher, Year, Era, **Grade + Certification + Certification Number**, Variant Type, Signed, Reprint.
- **Specifics live on the listing page, not the results grid.** So the pipeline is **two stages**: a **title-convention filter first** — *"Series #Issue Year Grade Note"*, excluding **lot, bundle, reprint, facsimile, TPB** — then **read specifics per surviving listing** to confirm grade and raw-vs-slab.
- **Raw and slabbed are two markets. Two groups, never blended.**
- **Provenance rides on every number:** *"14 recent eBay solds, last 90 days"* — **never "value"**. A comp, a guide figure and a modelled figure are three different claims and must be distinguishable at a glance.
- **Sold comps are not a ladder.** They are a scatter at whatever grades happened to sell. **Below N comps, say so; never extrapolate.**
- **Asking price and grade stay human-supplied** (brief rules 3, 4 and 7) and **never enter a lookup**.
- **It is a scraper**, grey-zone against eBay's terms, **P(works a year unmaintained) ≈ 0.5** — so it is replaceable **by configuration**: provider table, one `egress()`, exactly as vision is. D1's bright line holds for the Apify token: BYOK for the subscriber and testers, server-held before anyone else.
- **D4's query rules apply to the title filter** (drop the leading article, never append the issue number, case is free, publisher ranks rather than queries) — and **D5 applies to this source**: prove the filter *narrows*, never that it merely returns 200.

### The forks

**Fork A — which actor, and one-stage or two.** A1 (leaning): `caffein.dev/ebay-sold-listings` for stage one on its ~~$2~~ **$4**/1,000 tier, and **stage two deferred until stage one's output is seen** — if titles alone separate raw from slabbed well enough, the $0.005-per-item stage may be unnecessary for most lookups. A2: `blackfalcondata`'s split actor, which sells both stages natively. **Unresolvable without the paid probe.**

**Fork B — the minimum comp count N before any range is shown.** Leaning: **N = 5**, with 3–4 shown as individual sales rather than a range, and below 3 as "too few to compare". Every option needs the real noise level first.

**Fork C — the recency window.** Leaning: **90 days**, stated on every render, with the count. Comics are not fast-moving; a 30-day window may return nothing for mid-grade back issues.

**Fork D — how much filtering happens client-side.** The actor filters by date, limit and category; **the title-convention filter and the lot/reprint exclusions are ours**. Leaning: ours runs client-side over the returned set, so the rules are visible and gateable rather than hidden in a vendor's query string.

**Fork E — condition mapping.** The actor returns a localized condition label and a numeric code; eBay's condition vocabulary is **not** a comics grade. Leaning: **never map a listing condition to a grade.** Use it only to split **raw vs slabbed** (with Certification/Certification Number from specifics when stage two runs), and show the seller's own words verbatim beside each comp.

**Fork F — what the comparison surface shows**, and whether it is the same surface as the identity (G1 ruled one shared surface). Leaning: the confirmed identity, then two groups (raw / slabbed) each with count, window, and the scatter — no average, no midpoint, no "estimated value" anywhere.

### Pre-registered gates

| case | asserts |
|---|---|
| R2b-provenance | **every rendered number carries its count and window** — "14 solds · last 90 days" — and the string "value" appears nowhere near a comp |
| R2b-groups | raw and slabbed render as **two groups**, never combined into one range, and a comp cannot move between them without its certification field changing |
| R2b-minimum | below N comps the surface **states absence**; no range, no extrapolation, no midpoint — with a fixture holding N−1 comps so the case can actually reach the branch (HT-D60 Clause 4) |
| R2b-scatter | individual sales with dates and stated grades; **no ladder is synthesised** from them, and no grade is inferred for a comp that lacks one |
| R2b-filter-narrows | **D5:** the title filter and the category pin each return **fewer** results than the unfiltered call, with a known lot/reprint present in the unfiltered set and absent from the filtered one |
| R2b-query | the eBay query derives from the **confirmed** reading under D4's rules, is **visible and editable**, and editing it changes what is searched |
| R2b-no-human-inputs | the **asking price and the grade never enter any lookup** — asserted on the request body, not just the surface |
| R2b-egress | the Apify call goes through `egress()` on its own provider row; the token rides as the row declares; **no request URL or token reaches any surface, trace or log** (D1) |
| R2b-cost | the number of billable events per lookup is **bounded and stated** — a lookup cannot silently deepen 500 listings |
| R2b-provider | PriceCharting and a replacement scraper can each be added as a **table row** with no code change (repointed from D1) |
| R1/R2a-repointed | every existing case still holds — repointed, not weakened (HT-D60 Clause 3) |

**Defect pass required** (HT-D60), with rows at minimum for: provenance stripped from a rendered number, raw and slabbed blended, a range shown below N, a synthesised ladder, a filter that does not narrow, the grade or asking price entering the request body, and the token reaching a surface.

### BUILT — evidence, 2026-09-13

**`SUITE: PASS (2 of 2 produced a verdict, and every verdict was PASS)`.**
**Assertions: executed 350 · pinned 350** — 310 → 350 across this slice (+40), re-pinned three times and **each time to a measured number, never an assumed one**.
**Defect pass: 11 rows for R2b (31–41), every one `GATE: FAIL` naming its own case.** Zero vacuous, zero unnamed, zero restore failures.

| row | planted defect | named by |
|---|---|---|
| 31 | `includeCompletedListings: false` | `CQ3 GATE (brief rule 7): includeCompletedListings is pinned TRUE` |
| 32 | `daysToScrape` left to the actor's default of 30 | `CQ3 GATE (Fork C): the window is pinned to 90` |
| 33 | a min–max range across the mixed scatter | `CQ7 GATE (D8 amended): … no range spans them` |
| 34 | raw/slabbed grouping from a title heuristic | `CQ7 GATE (D10): comps render in ASCENDING PRICE order` |
| 35 | the issue number stripped from the eBay query | `CQ1 GATE (D4 per-source): … THE ISSUE NUMBER STAYS` |
| 36 | the query made read-only again | `CQ2 GATE (D4): the query input is no longer read-only` |
| 37 | the grade entering the request body | `CQ4 GATE (brief rules 3,4): a body carrying the grade or the asking price is REFUSED` |
| 38 | the spend warning re-gated to `role === 'prices'` | `CQ9 GATE (D1/HT-D53): the card warns that this credential SPENDS` |
| 39 | a second keyword doubling the bill | `CQ3 GATE (R2b-cost): … EXACTLY ONE keyword` |
| 40 | the filter hiding rows without counting them | `CQ7: what the filter hid is COUNTED ON THE SURFACE` |
| 41 | the Publisher aspect used because it demonstrably works | `CQ3 GATE (D10): the request sends NO aspectFilter` |

#### The demand list above, answered item by item — including the three not met

**The wording above is left exactly as it was written.** It was drafted before D10 and before D8's amendment, so two of its seven demands describe defects the code can no longer commit, and three have no row behind them. **Eleven rows is not the same as seven demands satisfied**, and a future reader should not have to reconcile those numbers alone.

| the demand, as pre-registered | status |
|---|---|
| the grade or asking price entering the request body | **MET AS WRITTEN** — row 37, asserted on the request body rather than the surface |
| the token reaching a surface | **MET, by an existing row** — the ported redaction row (row 8, `PC3\|TC4`) already covers it; `CQ9` adds that the comps card never prints its token |
| **raw and slabbed blended** | **SUPERSEDED by D10.** The groups were removed, so "blended" is not a state this code can reach — there is nothing to blend. **Row 34 gates the inverse defect**, which is the live risk: grouping *introduced* from a title heuristic |
| **a range shown below N** | **SUPERSEDED by D8's amendment.** No range is computed at *any* N while the markets cannot be separated, so "below N" is no longer the boundary. **Row 33 gates the live form**: any range at all across a mixed scatter |
| provenance stripped from a rendered number | **MET 2026-09-13 — row 42.** Strips the count and window from the header; fails `CQ7: the count is the KEPT count and rides on the surface`. It had been pre-registered and never written, so that assertion had never been seen to fail — Clause 1, live in the repo until closed |
| a synthesised ladder | **MET 2026-09-13 — row 43**, and it needed a new gate to exist at all. `CQ7` could not *see* a ladder: checking for the absence of one is unbounded. The assertion added instead is D8's claim stated directly — **every price on the surface is one something ACTUALLY SOLD FOR** — because a ladder puts numbers *between* the sales and no comp has them. The row plants an average of the scatter rendered as though it were a sale |
| a filter that does not narrow | **MET 2026-09-14, in two halves.** *Ours*: row 40 gates the client-side filter hiding rows without counting them. *The source's*: `categoryId: "6000"` returned **zero**, so the pin demonstrably narrows (D5). The second half is a **measurement, not a gate** — it needs a live token and spends money, so it cannot be made re-runnable and is dated and inputs-recorded instead |

**Three demands outstanding, named rather than quietly absorbed into a count of eleven.**

**Four defects found while BUILDING — all in ported code being extended, none in new code:**

1. **`credTest` dispatched on two roles with a ternary** (`role === 'vision' ? visionCall() : pricesPing()`). A third role would have sent **the Apify token to PriceCharting as a `t=` URL parameter** — a dead test *and* a credential handed to the wrong provider in a query string, which is precisely what D1 forbids after the `t=` lesson. Replaced with a dispatch table: adding a role can no longer silently inherit another role's call.
2. **The extractability warning was gated on `role === 'prices'`**, so the one credential that can **spend money** rendered no warning at all while the subscription one had it. Keyed to the provider row now — a credential's cost is a property of the provider, so the provider declares it.
3. **`noun` was derived from the auth mechanism**, labelling the Apify row "API key" while the card summary, `ROLE_LABEL` and the settings note all said "token". D3's shape at its smallest.
4. **A connection test built the obvious way would have cost $0.40 a tap.** `compsPing` hits `/v2/users/me`, which authenticates the token and starts no actor.

**Endpoint paths confirmed against the live API — unauthenticated, $0.00, no actor started.** `/v2/users/me` and `/v2/acts/caffein.dev~ebay-sold-listings/run-sync-get-dataset-items` both answer **401 `token-not-provided`**, while a *misspelled* endpoint on the same actor answers **404 `page-not-found`** — Apify resolves the endpoint name before the credential, so the 401 is a signal rather than the blanket reply.

### What the defect pass caught in the GATES themselves

**`CQ7`'s D10 assertion was a TAUTOLOGY that had never been capable of failing.** It read `(c7.indexOf('raw') < 0 && c7.indexOf('slab') < 0) || c7.indexOf('cannot tell…') >= 0`, and `||` binds looser than `&&`, so the expression was `(A && B) || C` — where **C is the D10 warning line `renderComps` emits on every render**. It passed on every run because it could do nothing else. **Defect row 34 planted real grouping, the gate said PASS, and that is the only reason it was found.** Replaced by three independent assertions — ascending price order, no heading element, and the statement — because fusing clauses with `||` is how it happened. A sweep of every `&&`/`||` mix in the suite found no other instance.

**Two rows initially reported a vacuous `GATE: PASS`.** Their `perl -0pi` replacements embedded JS template literals and inline functions, so `$` and backticks were consumed before perl saw them (`syntax error near "sorted["`); the mutation never applied and the gate passed against unmutated source. The repo had already moved every mutation to `perl -0pi` to fix this class on the **pattern** half — the **replacement** half was never covered. Rewritten to plain concatenation, and **every remaining mutation is now dry-run against a copy before it is spent**: a one-second check that would have saved three four-minute rows.

**One row failed correctly and could not name what caught it.** Its `report` pattern still grepped for a phrase deleted when the tautology was rewritten. **D3 at its smallest — an assertion was renamed and its consumer did not follow** — and the cross-reference census cannot see it, because that census scans the *docs*, not these patterns. A sweep of all 40 patterns against every gate's printable text found no others.

*(The harness failures of the same day — a stale backup that destroyed uncommitted work, two concurrent passes that destroyed each other's backups, and a `ROWS=` filter that did not cover two rows' plants — are in `tests/README.md` and in the incident note at the top of this file.)*

### What this slice does NOT prove — stated, not left to be assumed

- **`compsLookup` has never run against the live API.** Every case drives the `__setComps` seam or a pure function. The actor id, endpoint path, bearer header and response shape are verified against Apify's published schema and unauthenticated probes — **not against a round trip with a real token**. The first real lookup is a device test, and it is exactly where a contract mismatch would surface: R1's `##` bug reached a device because a gate measured the document instead of the header.
- ~~**`categoryId=259104` is still unproven** (D5)~~ — **closed 2026-09-14.** `categoryId: "6000"` (eBay Motors) with `aspectFilter` cleared returned **zero** on a query whose keyword alone returns a full page: the pin narrows, and stays. Proven by measurement, not by a gate — it needs a live token and cannot be automated.
- ~~**Provenance-stripping and a synthesised ladder are ungated**~~ — **closed 2026-09-13**, rows 42 and 43, with a new assertion for the ladder (see the demand table).
- **No device pass on the comps surface** — the outstanding list, to be run on a real screen:
  - **the scatter at phone width** — prices, seller titles and dates legible without horizontal scroll, titles wrapping rather than truncating the grade signal they carry;
  - **the dropped-rows disclosure** — "1 lot, 1 reprint hidden" with the show/hide control, since a filter the user cannot inspect is one they cannot correct;
  - **the no-token floor** — with no comps token saved, the confirmed surface names the manual route instead of offering a button that can only fail (D2 Fork G1's shape);
  - **the D10 line where the numbers are** — that this tier cannot tell a raw copy from a slab, read on the device rather than asserted in a fixture.
- **Eight comps is a thin sample.** "No lots in the first eight" is a lead, not a settled noise level, and a lot at the top of a scatter is the tail risk the client-side filter exists for.

### What this pre-registration does not settle

The actor's real input schema and output for a comics query (needs the paid probe); whether Item Specifics are reachable at all through any of these actors; N, the window, and the deepening budget, all of which want real noise data; eBay's terms position beyond "grey zone, personal tool"; and whether comps persist into any record — schema v2 is still unwritten.

---

## R3 — The triage surface: grade and asking price — PRE-REGISTERED, FORKS OPEN (2026-09-13; NOT built)

**What it is for.** R2b produces a scatter. R3 turns it into an answer — *"you're being asked $10; 47 of these 98 sold below that."* It is the slice the product exists for, and the one where every refusal ruled so far has to hold under pressure, because a comparison is exactly where a number wants to be invented.

**Ruled already, and built to rather than re-opened:** rule 4 as amended (the comparison is an **ask against a scatter** — position, counts below and above, nearest comps with titles verbatim; no $X, no midpoint, no average, no "fair", no verdict), rule 2 as amended (grade is **advisory**, recorded as attestation, never filtering the scatter — D10's adversarial reason), and rules 3 and 5 (both inputs human-supplied and attested; the asking price never read from the photo, which `ID_REFUSED_KEYS` already refuses; cover price and asking price never conflated).

### Two hazards this slice CREATES, neither inherited

1. **It is the first surface to show two prices at once.** The confirmed identity renders `cover_price`; the comparison renders the asking price. Rule 7 has forbidden conflating them since 2026-09-12, but until now they never co-existed on screen, so the rule has never been under load. **Both must be labelled at the point of display**, and a gate must assert they are distinguishable — not merely present.
2. **`renderComps` rebuilds `innerHTML` in eleven places.** An ask input inside that block loses its caret on every keystroke. `renderConfirmQuery` already exists for exactly this reason — *"repainted without rebuilding the inputs — retyping a title must not cost the caret"* — so the precedent is in the file and the mistake is available to anyone who does not read it.

### The forks

**Fork A — where the inputs live, and how they survive a repaint.** Ruled in the brief: *after* comps return, since the comparison needs both. Open: **which block**. The ask is a property of *this seller's copy*, not of the scatter, which argues for the confirmed-identity block; but the comparison renders in the scatter, which argues for one block rather than two. **Leaning: inside the comps surface, above the scatter, with the inputs rendered ONCE and only a live comparison line repainted** — `renderConfirmQuery`'s pattern, not a second full rebuild.

**Fork B — "nearest comps" when many sales share a price.** With 98 sales ties are certain. B1: nearest by absolute price distance, ties by recency. B2: nearest by distance, ties by sorted position. B3: show every sale at a tied price. **Leaning: B1 capped at three either side, AND when the cap truncates a tie group, say so — "3 of 12 at $25".** A cluster at one price is *signal*, not noise: twelve sales at $25 tells the user more than three arbitrary examples of it, and silently truncating hides the densest fact on the surface.

> **Forks B, C and E were RULED AS RULES, 2026-09-14** — each generalises past this slice, so each became a decision rather than a choice: **B → D11** (a cap that truncates a tie group must say what it truncated), **C → D12** (the app never divides a seller's quote), **E → D13** (counts, never percentiles). The leanings below are kept as the record of how they were first put; the binding form is the decision.

**Fork C — a bulk rate, without inventing a per-book number.** *"$10 each, 5 for $40."* Dividing 40 by 5 manufactures $8, which the seller never said — D8's family, and rule 7's. C1: quantity + total fields, compared as a pair (but a pair cannot be placed on a single-price scatter). C2: one number, user's own arithmetic, bulk terms discarded. **Leaning: C3 — the user enters the figure THEY want compared, and the bulk terms ride alongside as attested text**, so the record reads *"$8 — your figure, from: 5 for $40"*. The app never divides; what it shows is a number the human chose and the words the seller used.

**Fork D — does the ask survive Start over?** **Leaning: no on Start over, yes on re-lookup.** Start over means a different book, and an ask carried onto a new identity is brief rule 8's confidently-wrong pairing. A re-lookup with an edited query is the *same* book and the same seller, so clearing the ask there would punish refining the search.

**Fork E — how D5's "no number that is not a sale or the user's own entry" extends to the marker.** E1: a row in the scatter at the ask's position, visually distinct, labelled as the user's. E2: a rank — *"47th of 98"*. E3: a percentile — *"cheaper than 52%"*. **Leaning: E1 plus counts, and explicitly NOT E3.** A count is a fact about the data; a percentile is the same fact dressed as a score, and *"cheaper than 52%"* invites *"so it's about average"* — the one inference D8 exists to refuse. **The CQ7 assertion becomes: every price on the surface is one something actually sold for, OR the single user-entered ask carrying its own label.** One exception, labelled, and a defect row that plants a second unlabelled number must fail.

**Fork F — mixed currency, which is not in the brief's list.** Comps carry `soldCurrency` per row. If a lookup returns more than one, the scatter is already incomparable and the ask cannot be placed in it. **Leaning: detect it and state it, refusing the comparison the way the below-three branch states absence** — D10's shape applied to currency instead of grade. Silently mixing is the worst option and is what naive code does.

**Fork G — the grade vocabulary.** Brief gives PR/FR/GD/VG/FN/VF/NM with common pluses and minuses, plus "not graded". Open: whether **numeric** grades (0.5–10.0) are also offered, since sellers write *"VF- 7.5"* in the titles the user is reading. **Leaning: descriptive only.** A numeric grade implies a precision that a hand-and-eye judgement at a table does not have, and the titles carry both forms anyway for the human to match against.

### Pre-registered gates

| case | asserts |
|---|---|
| R3-position | the ask's marker sits at the correct index among the sorted prices, **against a fixture containing ties** |
| R3-counts | "N sold below · M sold above" are exact, and **N + M + ties-at-the-ask = the rendered count** |
| R3-nearest | the nearest comps either side carry **verbatim titles**, and a truncated tie group states what it truncated |
| R3-one-exception | **CQ7 extended**: every price on the surface is a sale, **or** the single labelled user ask. A second unlabelled number fails |
| R3-no-verdict | with an ask entered, no average, midpoint, range, percentile or evaluative word appears anywhere on the surface |
| R3-grade-inert | changing the grade changes **no comp, no order, no count** — it is a label beside the ask and nothing else |
| R3-two-prices | **rule 7**: cover price and asking price are both labelled where shown, and neither renders adjacent to the other unlabelled |
| R3-bulk | a bulk rate is representable with **no synthesised per-book figure** anywhere in state or on the surface |
| R3-currency | a mixed-currency scatter **states the mismatch and refuses the comparison** |
| R3-no-egress | the ask and the grade **never enter a request body** — CQ4 extended from theoretical to load-bearing, now that real inputs exist |
| R3-caret | the ask input survives a comps repaint without losing focus or content |
| R3-layout | **layout-gate extended**: at 360px the ask marker, its label and the nearest comps are disjoint rectangles, no horizontal overflow |

**Defect pass required** (HT-D60), with rows at minimum for: the marker placed by a wrong comparator, a count off by one at a tie boundary, a midpoint or percentile reintroduced, the grade wired into the filter, a bulk rate divided into a per-book figure, an unlabelled second number on the surface, and the ask reaching a request body.

### BUILT — evidence, 2026-09-14

**All seven forks ruled as leaned; B, C and E recorded as D11, D12 and D13.**

**Assertions: executed 386 · pinned 386** — 357 → 386 (**+29**), taken from the suite's own output rather than computed. **Defect pass 45 → 53 rows**; rows 46–53 are R3's, **every one `GATE: FAIL` naming its own case**, zero vacuous, zero unnamed, zero `GATE: PASS`.

**The layout gate extends to the comparison**: at four viewports, the ask marker's price and its label occupy disjoint rectangles, the marker clears the comps above and below it, the input clears the scatter, the counts render, and the page does not overflow horizontally.

| row | planted defect | named by |
|---|---|---|
| 46 | the marker placed by a reversed comparator | `AK5 GATE (Fork E): the ask renders INTO the scatter at its position` |
| 47 | an off-by-one at the tie boundary | `AK14 GATE: …sum to the rendered count when the tie term is NON-ZERO` |
| 48 | a percentile reintroduced | `AK7 GATE (D13): no percentage, percentile, median…` |
| 49 | the grade wired into the filter | `AK8 GATE: and the counts are untouched by it` |
| 50 | the bulk rate divided into $8 | `AK9 GATE (D12): $40 / 5 = $8 appears NOWHERE` |
| 51 | an unlabelled second number | `AK6 GATE (CQ7 extended): every price…ACTUALLY SOLD FOR` |
| 52 | the ask reaching the request body | `AK11 GATE (brief rules 3,5): neither the ask nor the grade reaches a request body` |

**Two gate holes the defect pass found, neither visible to review.**

1. **AK7 banned a VOCABULARY and fired on the surface's own refusal.** It listed `average`, and the comps footer says *"No average, no estimate — these are the sales"* **because** the surface refuses to average. That is the CQ7 tautology's mirror image: that one could never fail, this one could never pass while the refusal was stated. Rewritten to ban only tokens that can *only* be a verdict (`%`, `percentile`, `median`, `midpoint`, `bargain`, `overpriced`), **plus a second assertion requiring the refusal to still be present** — which is the stronger claim a word-ban never made, because it catches a future edit that simply deletes the disclaimer.
2. **AK9 could not catch the defect it was named for.** It checked rendered `.cmpprice` values, `state.ask` and `state.terms` — and a divided per-book figure rendered in the *marker's title* is none of the three. Row 50 exposed it; "nowhere" now means the whole rendered surface.

**And a third hole, the most serious, found by the layout gate and invisible to 27 passing assertions: a SEAM THAT DID NOT REPRODUCE ITS PATH.**

`__setComps` stands in for a completed `compsLookup`. It called `renderComps()` alone where the real path calls `renderComps(); renderAsk();` — **so the ask inputs were never painted.** The data-layer suite was green the entire time, because `akSeed()` called `CT.renderAsk()` by hand and supplied precisely what the seam omitted. **The fixture was hiding the divergence it existed to expose**, and every assertion was true of the fixture's world rather than the app's.

The layout gate caught it because it drives the real page with no fixture to help it. **Two hypotheses read off the source were both wrong** — first "nothing calls `renderAsk`" (fixed, symptom unchanged), then "the shipped shell lacks `#askBox`" (it is at `index.html:173`). A **four-fact probe inside the gate's own browser** settled it in one run: `askBox=present askBoxHTMLlen=0 phase=done rows=4 askState={"ask":30,…}` — element present, state correct, **nothing had ever painted it**.

Fixed at the seam rather than in the gate or the fixture, so the divergence is removed at its source; `akSeed()`'s hand-written `renderAsk()` was deleted with it. **Row 53 re-plants the real bug** and fails the layout gate by name. The lesson is in `tests/README.md`: a seam mirrors its path exactly, and a fixture that supplies what a seam omits is concealing a defect in one of the two.

**And a fourth failure, in the mutations rather than the gates: `$` interpolation in the replacement half, four times.** `$37.50` became `.50` (capture group 37), `${c.below}` emptied silently, `"$"` substituted perl's list separator. **The replacement half of `s///` is a perl double-quoted string and bash single-quoting does not protect it** — an earlier note in `tests/README.md` claimed it did, which was wrong and is corrected there. One row reported the right verdict with a corrupted mutation, because the assertion that fired did not care about the part that broke, so the dry-run now **reads the mutated text** rather than only checking that the file changed.

### What this pre-registration does not settle

The forks above; whether the ask or the grade persist into any record (schema v2 remains unwritten, and R3 is memory-only until it is); and whether the comparison needs a second device pass of its own, which it probably does — the first one found a layout defect that every string gate had passed.
