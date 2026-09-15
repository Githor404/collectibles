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

### Distrust the grep before distrusting the record — 2026-09-14

**The reflex, named because it recurred.** Reading D1's deferral of the service worker, I searched `INHERITED-DECISIONS.md` for its cited `HT-D45 Fork G`, found seven "Fork G" hits — substitution-by-acknowledgment, lane hues, a `bm`-local band — and none of them a service-worker bypass. **I concluded the citation was imprecise.** It was exact: the clause sits at line 1237, inside HealthTracker's own **HT-D45** (*BYOK vision calls*), and my search had surfaced every *other* Fork G in a long file. The record was right; the search was too coarse to find what it pointed at.

**And then this paragraph broke the census — twice.** The sentence above first named that entry with the `HT-` prefix dropped, so the census read it as a claim about *this* repo and failed by name. The rewrite that explained the mistake then **quoted the unprefixed form in order to describe it**, and failed identically. The entry recording a mis-read citation contained a mis-written one, and its own correction contained another.

**Third and fourth instances of one hazard**: this census's very first run caught *"an unprefixed decision number, from writing the pair as `HT-D55` followed by a second number that never got its prefix"*. **A decision number written without the `HT-` prefix always means this repo**, and the census catches it every time — which is the argument for having the census rather than for being more careful.

#### A limit of the census, recorded because this paragraph is what found it

**It cannot distinguish a citation from a quotation of one.** The matcher takes any decision number at a word boundary, and a backtick is a boundary — so prose that *quotes* an unprefixed identifier in order to discuss it is indistinguishable from prose that *cites* it. Any document writing about citation errors will trip this.

**The remedy is to restructure, not to escape.** Naming the form descriptively — *"with the prefix dropped"* — says the same thing and leaves nothing for the matcher to misread. An escape sequence would be a trick the next reader has to decode, and this census is deliberately blind to intent: **that blindness is what makes it reliable, and this limit is its price.** It sits alongside the limit already recorded above — the census catches an *unresolvable* citation, never one that resolves to the wrong thing.

**Why this is the more expensive habit of the two.** A wrong count corrects itself the moment something is measured. **A wrong conclusion about the record is acted on** — it invites "repointing" a citation that was already correct, editing a decision entry to match a misreading, or writing an amendment to fix nothing. The cost is not the lost minute; it is the damage a confident correction does to a record whose only value is that it is trustworthy.

**The rule, and it is the same one this file keeps arriving at from other directions:** when a search contradicts the record, **the search is the hypothesis**. Narrow it, anchor it, verify it resolves to a line number and a heading — *then* doubt the record. Verified citation beats inferred error, exactly as measured cost beat estimated cost and a read mutation beat a mutation assumed to apply.

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

### DEVICE PASS — R3 end to end on a real book, 2026-09-14

**Amazing Spider-Man #151.** Grok identified it, the reading was confirmed, Apify returned **98 sold** sorted by price. **Ask entered at $10 → "8 sold below · 76 sold above"**, marker placed, three nearest either side with prices and verbatim titles. **No caret loss.** Read in about a second, and the subscriber would have bought the book.

**The range is the strongest evidence the refusals have produced: $2.00 to $2,300**, the top being a CGC 9.8 white-pages copy. A beaten reading copy and a slab in the same list, a **1000× spread**, and nothing but the seller's own title separating them. **D7 and D8 were argued from a vocabulary mismatch and a principle; this is the demonstration.** An average across that describes no book anyone can buy, and the scatter is the only honest rendering of it.

**D11's truncation line was NOT observed.** The three nearest below happened to be distinct prices, so the tie-cluster branch never fired. **Untested in the wild, not broken** — the gate passes against a fixture built to force the cluster, and Clause 1's distinction holds: *seen to fail* is not *seen to occur*. It remains the one R3 behaviour with no real-world sighting.

**Open from this pass:** 8 + 76 = 84 against 98 returned. The rendered count is the **kept** count, so the likeliest reading is that `compsFilter` dropped 14 lots or reprints — which would mean the footer's *"N hidden — the title said so"* disclosure fired **on live data at scale for the first time**, something the eight-row probe could not exercise since it contained no lots at all. Whether that disclosure and the middle term (`N at your price`) both rendered is unconfirmed and worth the next glance.

### What this pre-registration does not settle

The forks above; whether the ask or the grade persist into any record (schema v2 remains unwritten, and R3 is memory-only until it is); and whether the comparison needs a second device pass of its own, which it probably does — the first one found a layout defect that every string gate had passed.

## Version legibility — the app says which build it is running — BUILT AND GATED (D14, 2026-09-14)

**Why this went before the service worker, and not after.** The subscriber asked for the worker slice because *"I have no way to tell which build I'm running or when a new one lands, and that's now costing me on every device pass."* The worker is what would **cause** that problem at its worst — a cached shell served silently over a new one — and the version surface is what makes it **visible**. Building them together would mean introducing the failure and its diagnostic in one commit, with no period in which the diagnostic had been observed working on its own. So the slice was split: **legibility now, offline later**, and D14 records the general form — *the gate ships before the mechanism it exists to diagnose.*

### What was ruled, and what shipped

| ruling | shipped as |
|---|---|
| **Start at 0.1.0** | `APP_VERSION = '0.1.0'`; single `VERSION_LOG` entry |
| **No invented entries for the three unversioned releases** | the log begins at 0.1.0 and claims nothing about what came before |
| **`d:` mandatory on every entry** | gated twice — `check-version.sh` and a suite assertion; HealthTracker's pre-convention exemption was **not** ported, because there are no pre-convention entries here for it to protect |
| **Build line in `.about` only** | `renderBuildLine()` writes `#buildLine`, and an assertion requires it to live inside `.about` — reference information, not a control |
| **`check-version.sh` joins the suite immediately** | runs inside `run-data-layer.sh` with the other static checks, not as a separate optional step |

**The two surfaces.** `#versionNotice` sits **above** the Capture card — it is the app interrupting, never an answer to something the user did — and starts hidden; `checkVersionNotice()` reveals it only on a real change. `#buildLine` sits in `.about`, painted by `refresh()` on every render.

**First-run suppression reads `APP_SOURCE`, not "nothing stored".** A fresh install (`empty`) sees no notice. A **restore onto a new device** (`restored`) and, crucially, **the people already running the three unversioned builds** (`store`) do see one — for them this genuinely is an update, and *nothing stored is not the same as nothing installed*.

### Assertion delta: 386 → 408 (+22), re-pinned in this commit

**+17 (VN1–VN8)** — `cmpVersion` compares numerically per segment (a string compare puts `0.10.0` before `0.2.0` and would silently stop showing notices after the ninth release); a downgrade shows nothing; the newest log entry **is** `APP_VERSION`; every entry carries a date; fire-once; dismiss; and D1's storage-key prefix.

**+5 (SH1) — and these are the ones that matter.** All 17 VN assertions run against the harness's synthetic `mk('div','versionNotice')`. Until these five lines, **nothing proved the shipped shell had either element** — and `index.html` in fact had neither while all 17 were green. That is the identical shape to the `__setComps` seam divergence that survived 27 passing assertions one slice earlier, so it was closed in the same commit that created the risk:

- the shipped shell carries `#versionNotice` **and** `#buildLine`;
- the shipped shell carries CSS for `.vnotice`, `.vnhead`, `.vnrow` — `renderVersionNotice` **emits** the latter two, and emitting a class is not shipping a layout (the comps row shipped with class names and no stylesheet once already);
- **content, not presence** (HT-D63): the build line must *hold* `collectibles v0.1.0` after boot. "The span exists" is the assertion that let HealthTracker tell people to copy from an empty box for weeks;
- the build line is inside `.about` and nowhere else — a second copy of one value is a pair that can disagree;
- the notice is **either hidden or has genuinely rendered a heading** — never a blank accent-bordered card sitting on the page. Written to be deterministic whichever way the iframe booted, rather than asserting a display state that depends on suite ordering.

**Layout gate: PASS** at 360×690, 390×745, 1200×900 and 360×520 with the new card present. `display:none` contributes no height and the comps and ask rectangles are unchanged — measured, because the previous slice's "should be fine" was a layout defect that every string gate had passed.

### The stand-down, and what is NOT yet proven about it

A defect pass mutates `app.js` 53 times; `check-version.sh` compares the tree to HEAD, so **every row would fail on "shell changed, APP_VERSION did not bump" before reaching its own case** — 53 vacuous rows. So the pass stands the check down. But a gate with an off switch is a gate whose off switch gets left on, so the switch is **not a boolean**: `DEFECT_PASS` carries the pass's **PID** and must match the live lockfile that `defect-pass.sh` alone writes. Set by hand, it matches nothing and fails loudly.

**Rows 54, 55 and 56 were run against their defects and each was SEEN TO FAIL** (HT-D60 Clause 1), on a tree committed first at `b63a36f` — so a restore failure would have been recoverable from git rather than only from `.orig` copies:

| row | planted defect | verdict | first named failure |
|---|---|---|---|
| 54 | `DEFECT_PASS` forged **from inside a real pass** | `GATE: FAIL` | `check-version: FAIL - DEFECT_PASS=999999 was set, but no live defect pass holds …` |
| 55 | `APP_VERSION` bumped to 0.9.9, no changelog entry | `GATE: FAIL` | `check-version: FAIL - APP_VERSION 0.9.9 has no VERSION_LOG changelog entry` |
| 56 | the one entry stripped of its `d:` | `GATE: FAIL` | `check-version: FAIL - 1 VERSION_LOG entries but 0 carry d: 'YYYY-MM-DD' …` |

**Row 54 is the one worth reading twice.** It sets `DEFECT_PASS` to a PID that no process holds, *while a genuine pass is running and holding a different PID in the lockfile* — so the flag is live, the lock is live, and only the **match** is false. That is the precise failure a boolean could not distinguish, and the gate refused it by name rather than standing down. All four files restored identical to their pre-run copies and the tree was clean afterward.

Row 55 and 56 reach `check-version.sh` **directly** rather than through `run-data-layer.sh`, via `run_cv()`, because the stand-down suppresses it inside a pass — a row that tested the suppressed path would assert nothing. `run_cv` translates the script's exit code into the `GATE:` vocabulary the report reads.

### What this does not cover (HT-D60 Clause 2)

- **`check-version.sh` compares the working tree to HEAD. It cannot see what was DEPLOYED.** A commit that never reaches Pages passes it. Deploy verification is still a separate byte-fingerprint check.
- **The build line reports a constant compiled into `app.js`.** It cannot detect a *stale cached `app.js` served under a fresh `index.html`* — which is precisely the service worker's failure mode. This slice makes that failure *legible* when it happens; it does not detect it. That detection is the worker slice's own obligation, and it now has a surface to report on.
- **Nothing gates that a `VERSION_LOG` note describes the change it is attached to.** The note is prose; the gate checks that it exists, is dated, and matches `APP_VERSION`.
- **VN4's multi-version accumulation is unreachable against the real one-entry log**, so it runs against an **injected synthetic log** — HT-D60 Clause 4: a fixture that cannot exhibit the failure is not a gate. The `log` parameter on `versionNotesBetween` exists for that reason and for no production caller.
- **A user who clears storage looks exactly like a first run**, and will not be told what changed. There is no way to distinguish the two from inside the page, and inventing one would mean writing a second record to detect the loss of the first.

### Deployed and verified (8e4f99c)

| file | before | after |
|---|---|---|
| `index.html` | `a843d7f639394d17` | `c7965be5c83d2e6e` |
| `app.js` | `18204c050e559ac4` | `ea70d2d2d1aaabde` |

Both matched `HEAD` about 15s after the push. The build line served to a device now reads `collectibles v0.1.0`.

### The deploy target, recorded so it is never re-derived

- **Live:** `https://githor404.github.io/collectibles`
- **Remote:** `github.com/Githor404/collectibles`, branch `main`

**Verify by byte fingerprint, never by the push succeeding.** For `index.html` and `app.js`:

```sh
curl -fsS -H 'Cache-Control: no-cache' "$BASE/$f" | tr -d '\r' | sha256sum | cut -c1-16   # served
git show "HEAD:$f"                                | tr -d '\r' | sha256sum | cut -c1-16   # intended
```

**Why it is written down.** Until this entry the repo contained **no `github.io` string anywhere**, so every deploy check re-derived its own target from the remote. *A deploy check that re-derives its target is one bad remote away from verifying the wrong thing* — and it would report PASS while doing it. The URL was confirmed on 2026-09-14 by measurement rather than memory: a 200, plus bytes identical to `HEAD~1`, which is what makes the *after* comparison mean anything at all.

## Want-list as a capture-time filter, and schema v2 — PRE-REGISTERED, ONE FORK OPEN (2026-09-14; NOT built)

**Ruled in advance** (D15): the want-list is a **filter that fires on capture**, not a list to browse. The match is **generous**, never silent. v1 holds **exact issues only** (looser wanting — *"any pre-1975 Marvel key"*, *"the rest of the Byrne FF run"* — is named and deferred). The flag fires on the **draft** and re-evaluates as the reading is corrected. **The flag is a prompt to look, never a claim, and nothing about it is written to a record before confirm.** Still out: collection management, marketplace, sharing, accounts.

### The fork, and why it is open rather than decided

I reported a collision — *`normalizeState` is an allowlist rebuild that would silently discard a new key* — and the want-list and schema v2 were ruled into **one slice on that basis.** Reading the code rather than my own report: **the collision is avoidable, and the pairing may not be needed.**

`normalizeState` allowlists **top-level** keys, but `settings` is deep-copied **wholesale** (`JSON.parse(JSON.stringify(o.settings))`) with no filtering inside it. Existing assertions already pin arbitrary nested content surviving there (`settings: { a: { b: [1,2,{c:'x'}] }, flag: true }`).

- **Option A — `settings.wants`. No schema bump, no migration, no wipe risk.** The want-list persists today, under machinery already gated.
- **Option B — top-level `wants`, `SCHEMA_VERSION = 2`.** Cleaner shape, and the cost is below.

### What Option B costs — stated before anything touches storage

`boot()` has exactly three paths: `v > SCHEMA_VERSION` (future — preserved, never overwritten, HT-D7); `v === SCHEMA_VERSION` (normalize); and **no branch at all for `v < SCHEMA_VERSION`**, which falls through to `state = emptyState(); dirty = true` and then `Store.saveState(state)`. Every existing user's stored state would be **silently overwritten with an empty one on their next load** — an erase on disk, at boot, with no error and no undo slot.

**This is not a defect today.** With `SCHEMA_VERSION = 1` and a minimum valid version of 1, `v < SCHEMA_VERSION` is unreachable, which is exactly why no assertion covers it — HT-D60 Clause 4: a fixture that cannot exhibit the failure is not a gate. **The bump is what creates the case.** So Option B is not "add a key and bump a number"; it is a migration branch, a backup written before any rewrite, and a gate seeded with a real v1 state — in the same commit as the bump, or it ships a wipe.

**My leaning: Option A**, and the reason is D14's shape rather than convenience — the want-list does not need a schema bump, so taking one on buys the wipe risk for nothing and couples a user-facing feature to the riskiest change in the codebase. Schema v2 is worth doing on its own terms, with the migration branch as its subject rather than its side effect.

### RULED: Option A — `settings.wants`, no schema bump (2026-09-14)

The want-list does not need the bump, so taking it on would buy the wipe risk for nothing. The want-list slice proceeds against `settings`, which existing assertions already pin as free-form and deeply preserved.

### Schema v2 — NAMED AND PARKED, not vaguely deferred

Schema v2 gets **its own slice, with the migration branch as its subject** rather than as a side effect of shipping a feature. Its three obligations, ruled in advance:

1. **A migration branch for `v < SCHEMA_VERSION`.** `boot()` has none: a v1 state read by a v2 app falls through to `emptyState()` and `Store.saveState()` **overwrites the user's data at boot, silently, with no undo slot.** That is data loss *created by the bump itself*, in a repo whose discipline is largely about not doing that.
2. **A backup written before any rewrite** — the rolling undo slot (HT-D3/HT-D5), taken before the migrated state is saved, never after.
3. **A gate seeded with a real v1 state**, exercising the migration end to end.

**Not a defect today, and the reason matters:** with `SCHEMA_VERSION = 1` and a minimum valid version of 1, `v < SCHEMA_VERSION` is **unreachable** — which is exactly why nothing gates it (HT-D60 Clause 4: a fixture that cannot exhibit the failure is not a gate). **The bump is what would create the case.** So the gate cannot be written ahead of the slice; it must land in the same commit as the bump, which is D14's shape applied to storage.

## D16 — the constructed-element census, and content checks on the shipped shell — BUILT (2026-09-14)

Ruled as D16 after **two instances in two consecutive slices**: `__setComps` (the harness supplied the *call*) and the version slice (the harness supplied the *element*). The generalisation is the subscriber's: **any assertion that runs against a constructed element proves the function, never the shipped page.**

### What shipped

**`mk()` records every id it constructs.** Structural, not a hand-kept list — a new `mk()` call enrols automatically. This mattered concretely: a list transcribed from the array literal would have covered **14** ids and silently missed the **10** built individually, which is the same looks-complete-and-isn't failure the census exists to catch.

**The census (SH1).** Every constructed id must exist in the shipped shell, with:

- a **pinned manifest of deliberate absences** — exactly one, `credBox-prices`, because D9 requires no field where no call exists. Without the manifest the census would demand the app re-ship the dead end D9 deleted;
- a **control in the other direction** (D3): the exception must still be *absent*, or it has quietly come back;
- a **control on the census itself**: `MK_IDS.length === 24`. An empty list would make it pass vacuously — the empty-grep error rebuilt as a gate.

**Content assertions against the shipped shell**, for `storeBadge` and `captureBox` (SH1) and `confirmedBox` (SH2).

### The coverage finding, measured at ruling

24 ids constructed, 30 declared by the shell, **23 in both, 1 deliberately absent**. Of the 23, **13 carried a shipped-shell assertion and 10 did not**.

**Closed by this slice:** `confirmedBox`, `storeBadge`, `captureBox`.

**Parked by name, with what each needs** — not deferred vaguely:

| id | why it is not covered yet |
|---|---|
| `replyReport` | painted only after a paste attempt; needs a driven paste in the iframe |
| `toast` | transient, cleared on a timer; needs the clock seam to assert deterministically |
| `prerestoreBox`, `prerestoreWrap` | exist only during a restore; need a driven restore in the iframe |
| `outcomeTitle`, `outcomeX`, `outcomeScrim` | modal internals. OM3 gates the dismiss *behaviour* in the harness, so the specific gap is that the **shipped** modal's wiring is unasserted |

### The probe episode, recorded because it repeated a lesson and paid

The `confirmedBox` assertion was first placed inside SH2 **while SH2's synthetic contract was installed** — `TEST_CONTRACT.accept` sets a window flag and returns `{ok:true}` without touching `CONFIRMED`. Rather than act on that hypothesis, a **multi-fact probe** was run: `acc={"ok":true} resultBefore=true confirmed=false boxInShell=true shellLen=0 harnessLen=0 foot=">Use this<"`.

Two facts that probe earned and a source reading would not have: **`harnessLen=0` ruled out a cross-document paint** (the renderer writing into the wrong `document`, a different defect with the same symptom), and **`acc.ok` was TRUE** — so an assertion trusting the accept's return value would have passed against a surface that never painted. **D16's own failure mode, reappearing inside D16's gate.**

The fix restores the shipped contract, drives the real one-door path with the app's **own** `ID_SAMPLE` (ID1 gates that the sample and parser cannot drift apart), and accepts through `captureAccept()` — the shipped button's entry point. `renderConfirmed()` is never called by hand. It also **hands the borrowed contract back**, and `NS` passing 16/16 is the evidence that worked, since NS parses under whichever contract is installed.

### Assertion delta: 408 → 416 (+8), re-pinned in this commit

3 census (presence, deliberate-absence control, enumeration control) + 2 SH1 content (`storeBadge`, `captureBox`) + 3 SH2 (`confirmedBox` paint, identity text by name, gated cleanup).

### DEMONSTRATED — rows 57 and 58, each seen to fail (HT-D60 Clause 1)

Run on a tree committed first at `0e46a6d`, so a clobber would have cost one `git checkout` rather than the working copy being the only copy.

| row | planted defect | verdict | first named failure |
|---|---|---|---|
| 57 | the `#versionNotice` element **deleted** from `index.html` | `GATE: FAIL` | `SH1 GATE (D16): EVERY element the harness constructs also exists in the SHIPPED …` |
| 58 | `renderConfirmed();` **stripped out of** `identityAccept` | `GATE: FAIL` | `SH2 GATE (D16): accepting through the SHIPPED BUTTON PATH paints #confirmedBox …` |

**Row 58 is the one that mattered.** It re-plants `__setComps`' own shape one layer over: state set, surface never painted, **element present the entire time**. The presence census cannot see that — only the content assertion catches it. Had row 58 passed, the content assertion would have been decorative, and D16 would have shipped half a gate while claiming a whole one.

**Both expected strings were deliberately failure-specific**, and both matched on a genuine `FAIL` line: row 57 on `:: versionNotice` (the census diagnostic) and row 58 on `shellLen=0` (the probe, which prints only on failure). Matching the assertion **label** instead would have let each row match its own *passing* line — the tautology that made CQ7 unfailable for 347 consecutive runs.

### A defect found in `report()` while verifying the above

`report()` matches its expected pattern in two arms: a strict one, `^FAIL +.*pattern`, and — if that finds nothing — **a fallback that greps the whole output**, PASS lines, labels and comments included. Only if *both* miss does it print `NOTHING NAMED MATCHED -- SUSPECT THE FIXTURE`.

So **a row whose pattern matches only a passing line prints a plausible-looking "first named failure" and no warning at all.** That is the CQ7 tautology relocated out of an assertion and into the reporting function, where it would corrupt every row's evidence rather than one row's. The only tell was that the strict arm strips a `FAIL ` prefix and the fallback does not, so a weak match leaves `PASS ` visible — inside an 80-column truncation. That is how rows 57 and 58 were confirmed genuine, and it is far too quiet a signal for what it distinguishes.

**The fallback now labels itself `WEAK-MATCH:`.** The arm is kept rather than deleted: it is what produces a usable diagnostic when a gate fails in an *unexpected* way, and removing it would trade a quiet ambiguity for a blind spot. This is a harness defect, not an app defect — it could not have produced a wrong app behaviour, only a wrong belief about which gate was holding.

### What it does not cover (Clause 2)

- **The census is presence-only.** It cannot distinguish a painted element from an unpainted one — `#askBox` was present throughout the slice in which nothing painted it. That is what the content assertions are for, and they cover **3 of 10**.
- **It censuses what the HARNESS constructs.** The shell declares 30 ids; 6 are outside the census entirely because no harness block builds them.
- **`MK_IDS.length` is a pin, not a property.** Adding a `mk()` call requires a deliberate re-pin, in the same commit. It was 24 when D16 was ruled and is **26** since the want-list enrolled `wantsBox` and `wantsReport` — the pin moving is the census working, not noise.

## The want-list — a capture-time filter — BUILT, v0.2.0 (D15 amended, 2026-09-14)

**Option A as ruled: `settings.wants`, no schema bump.** `normalizeState` preserves `settings` wholesale, so wants survive a boot untouched and the slice took on **none** of the wipe risk a `SCHEMA_VERSION` bump carries. Schema v2 stays named and parked with the migration branch as its own subject.

**This is the first thing the app persists beyond credentials.** Everything before it was memory-only (R1, R2b, R3) or a credential held outside the state object (D1). So `wantsSave` carries `Store.saveState`'s boolean **to the surface** rather than assuming it: a want that was not saved must not claim it was, and on the memory tier the card says so.

### The rulings, and where each is enforced

| ruling | enforced by |
|---|---|
| generosity is about FORMAT — case, a leading article, punctuation, `#`, leading zeros | W1, W2, W4 |
| **a different issue is a different book** | W5, and defect row 60 |
| `raw` and the normalised form are two objects (D4's shape) | W3, W7 |
| a line with no issue is kept, counted, **and said** | W6, both halves |
| the flag fires on the DRAFT and writes nothing | W8 |
| it re-evaluates on correction, **in both directions** | W9, and defect row 61 |
| wants survive a boot | W10 |
| the storage outcome is reported, not assumed | W11 |
| the shipped shell carries the surfaces, and the CSS | SH1 pair (D16) |

**Draft-only, and deliberately so.** The flag does not appear on the confirmed header. D15 ruled that it fires on the draft and re-evaluates as the reading is corrected; extending it past confirm was not ruled, and a flag on a settled identity reads closer to a claim than to a question. Recorded as an omission, not an oversight.

### The layout gate passed this slice while measuring nothing

**Caught before it shipped, and it is D16's failure mode inside D16's own slice.** The gate runs a fresh browser profile with empty `localStorage`, so `wantsList()` returned `[]`, `wantFlagHTML` returned `''`, and `#wantFlag` rendered **empty, contributing no height**. `LAYOUT GATE: PASS` therefore proved the draft still fits **without** the thing the slice had just added to it — a green result about a surface that was not there.

Fixed by seeding a want in `__g.key()`, measuring `wantFlag: __g.rect('#captureResult .wantflag')`, and **folding it into `$sOk`** — a measurement that does not reach the verdict is decoration. The seed is deliberately the format-generous form, `amazing spider-man 300` against `ID_SAMPLE`'s *"The Amazing Spider-Man" / "300"*, so the **shipped page** exercises the generosity rule rather than an exact-match shortcut. Now reads `wantFlag=True` at 360×690, 390×745 and 1200×900.

**Not covered:** the 360×520 scrolled case measures through a different path and does not fold the flag in.

### `report()` gained a second strict arm

The first full pass after `WEAK-MATCH:` shipped returned **ten** labelled rows. **Nine were false alarms** — failures reported by a *script* rather than by `res()` (`egress: FAIL -`, `check-version: FAIL -`, `GATE-SCRIPT CENSUS: FAIL -`, the layout gate's `NOT MEASURABLE`), which structurally cannot carry `res()`'s `FAIL␣␣` prefix. That is the want-list's own noise argument aimed at the harness: **a label that cries wolf on good evidence gets ignored**, and then the one hit that mattered reads like the other nine.

A second strict arm now matches script-reported failures. **Controlled in five cases before commit:** a `res()` FAIL line, a script `FAIL -` line and a `NOT MEASURABLE` line all return **unlabelled**; a PASS-only match **still says `WEAK-MATCH:`**; no match still warns.

**Row 37 (`grade enters the lookup`) is the one real finding and is NOT fixed here.** *(Recorded as "row 47" when first written and corrected on measurement — it is the 37th `report` call, at `defect-pass.sh:429`. Two commit messages carry the wrong number and are left as history rather than rewritten; this file is the one someone navigates by.)* Its expected string matches only a *passing* assertion, so the evidence that row has reported for weeks is not evidence of the thing it names. **A probe settled it, and disproved the worse hypothesis.** The suite's own static checks abort on a mutated shell whose `APP_VERSION` has not moved — which is why a first attempt by hand produced **no SUMMARY at all** and measured nothing, and very nearly got reported as "the suite passed with the grade in the body." (The stand-down exists for exactly this, and it is PID-keyed so it cannot be switched on by hand; the gate refusing a hand-run is the gate working.) Driving the harness directly instead gave `SUMMARY 429/431 — 2 FAILED`:

- `CQ4: a real body carries no grade and no asking price`
- `AK11 GATE (brief rules 3,5): neither the ask nor the grade reaches a request body`

**So the suite was never blind to this defect.** Two assertions catch it; the row named a third. There are **two** assertions under the `CQ4` prefix, and the row's expected string matched the **GATE** one — which tests the *refusal mechanism* against a synthetic body, and therefore still passes when the real body is polluted. The mechanism was fine; the real body was what changed. The earlier guess that CQ4 "might genuinely be unable to catch it" was wrong, which is why it went to a probe instead of into this file.

**The defect was in the EVIDENCE, not in the gate** — and that is the precise value of the `WEAK-MATCH` label: a row that had been reporting a passing assertion as its proof for weeks, while the thing it guarded was in fact guarded.

Repointed to `a real body carries no grade and no asking price`, the assertion that actually fires (HT-D60 Clause 3 — repointed, not weakened). **Re-run: `GATE: FAIL`, naming that assertion, and UNLABELLED** — so the strict arm matched it on a genuine `FAIL` line, rather than one loose match being swapped for another inside the commit that fixes loose matching.

### The second strict arm, verified against real output

The five-case control that justified it used **synthetic output written for the purpose** — good evidence about the function, none about the rows. Rows 54 and 56 are the real thing: both report through `run_cv` as `check-version: FAIL - …`, both read `WEAK-MATCH:` before the fix, and both now come back **unlabelled**. The arm is verified against the rows it was built for.

### And that run found ROW 55 HAD ROTTED — broken by this repo's own version bump

Row 55 pinned the literal `const APP_VERSION = '0.1.0';`. The want-list slice bumped it to `0.2.0`, so **the mutation stopped applying, the suite ran clean, and the row reported `GATE: PASS`** — a defect row that had quietly stopped testing anything, in a commit that was already pushed and deployed.

**Two mechanisms caught it, independently:** `mutate()`'s own `!! MUTATION DID NOT APPLY (the text moved)` and `report()`'s `(NOTHING NAMED MATCHED -- SUSPECT THE FIXTURE)`. Both fired. That is the machinery working exactly as designed — and it still only speaks on the **first run after the bump**, which is an argument for running the pass after a bump, not for trusting that a green row is a live one.

**The general form, recorded as a rule:** *a defect row that pins a value the product legitimately changes rots on a schedule.* Match the **shape**, not the value. Row 55 now mutates `const APP_VERSION = '[0-9]+\.[0-9]+\.[0-9]+';`, so no future bump can silence it.

**Open, and the reason this matters beyond one row: the full 58-row pass has not run since `2f62240`.** That slice changed `app.js`, `index.html` and `APP_VERSION`; row 55 is one casualty and there may be others. Running it is the next step, and it is the same failure `CLAUDE.md` already records — a full pass left unrun leaves rows unverified against changed code, and they fail silent rather than loud.

### VERIFIED — the full pass, clean (2026-09-14)

**61 rows, every one `GATE: FAIL` against its own defect. Exit code 0. Zero rotted mutations, zero fixture warnings**, tree clean with all four mutated files restored identical to their pre-run copies.

That closes the episode. Four things are worth keeping, in order of how far they generalise.

**1. An instrument that could not fail.** `grep -c $'\r'` was used to detect CRLF and reported **every line as CRLF on a known-LF control file** — the same number whether or not the condition held. Three claims were built on it, including *"CRLF is committed into the repo"*, which was about to be written here and is **false**: every blob was LF throughout. The correct form is `perl -ne '$c++ if /\r$/; END { print 0+$c }'`, and it was trusted only after a known-CRLF and a known-LF file made it read 2 and 0. This is the empty-grep rule one level up: the earlier version said *a silent result needs a control*; this says **a result needs a control even when it is loud**, because a confident wrong number is harder to doubt than a blank one.

**2. `git checkout -- <file>` was the cause, and the ban already existed.** `defect-pass.sh`'s own header forbids it, because it restores from HEAD and discards uncommitted work. It was used anyway, as the *safe recovery* during an unrelated probe — and under `core.autocrlf=true` it rewrote `app.js` to CRLF. Every multi-line perl pattern here uses `\n`, which cannot match `\r\n`, so **seven rows stopped planting anything**. The blobs were LF the whole time; only the working copy converted, and only because the recovery step touched it. **A standing rule was right for a second reason nobody had written down.** Restore with `git show HEAD:f > f`; `.gitattributes` now pins `*.js`, `*.html` and `*.md` to `eol=lf`.

**3. A warning that does not change the verdict is not a gate.** `mutate()` *detected* all seven failures and printed them — then returned 0. The rows ran clean suites, reported `GATE: PASS`, and the pass exited 0. Seven warnings in a 61-row table scroll past, and they did. Now fatal, with a loud terminal block and `exit 1`, **controlled in both directions**: an impossible pattern exits 1 naming the row, and a healthy row still exits 0. The second half matters as much — a guard that failed everything would be quietly worse than the silent pass it replaced, because it would train the reader to ignore the result.

**4. A row that pins a literal rots on a schedule.** Row 55 pinned `'0.1.0'` and this repo's own v0.2.0 bump silenced it. Match the **shape**, not a value the product legitimately changes.

**The `WEAK-MATCH` census landed at 3, and the prediction was wrong.** Two were predicted — the `check-refs` rows, whose matched line never identifies itself as a failure. The third, `egress`, was not: its pattern sits on a **continuation line** beneath the `FAIL -` header, so the line-based second arm cannot reach it. **Named, not fixed** — making the arm block-aware is a different mechanism with its own over-matching risk, and the label is now accurate enough to be worth reading, which was the point. The five that dropped off were the rotted rows, which had been matching on their own `PASS` lines.

**Also corrected:** the row count reads **61**, not 60. The census grep was anchored `^[a-z]`, which silently dropped `EXIF pin removed` — the same anchor bug `tests/README.md` already records happening three times.

## R5 — The distribution surface — PRE-REGISTERED, FORKS OPEN (2026-09-14; NOT built)

**The problem, measured on a real book.** Amazing Spider-Man #151: 98 sold, 84 rendered after the client-side filter, spanning **$2.00 to $2,300** — a 1000× range presented as a vertical list of 84 rows. The list is *correct*; every row is a real sale and the refusals hold. It is also unreadable, and every explanatory sentence competes with the data for the same screen.

**The core claim, and why rendering it is honest rather than decorative.** A price distribution over 98 sales is **not one population**. Raw copies, mid-grade and slabbed are superimposed, and eBay's search tier supplies no field that separates them — *measured*, not argued: three books at an identical `Pre-Owned / 3000` sold for $9, $29.99 and $89 (D7), and no Grade, Certification or Variant field exists on a result (D10). But the populations separate **by mode**. Clusters with gaps between them are distinct markets, and the gaps are the grade boundaries the data refuses to state. **This is D8's "a scatter is the claim" rendered instead of written** — the surface stops asking the reader to reconstruct a shape from 84 ordered numbers.

### What the data can support — measured before designing

The ten fields as returned (recorded in R2b's probe): `keyword · itemId · title · condition · conditionId · endedAt · soldPrice · soldCurrency · listingType · isBestOfferAccepted`.

**Four findings that shape the slice, and the first is a defect:**

1. **`listingType` arrives and `parseComps` throws it away.** `COMP_KEYS` (`app.js:1732`) *declares* `listingType` and `conditionId`; the row builder (`1745–1753`) keeps neither. **No assertion pins the two together** — `CQ5 GATE` only checks what is *absent* from `COMP_KEYS`. So a declared contract and its consumer are free to drift, and have. Nothing breaks today because nothing reads the field; **R5 is the slice that makes it matter.** This is D3's shape exactly: both sides pass their own assertions while disagreeing about one field.
2. **`listingType`'s ENUM VALUES ARE UNMEASURED.** The probe recorded the field's presence, never its range. "Listing-type encoding is exact" **cannot be gated against an unknown enum**, and a surface that renders an unrecognised value silently as "other" is D5's shape — a discriminator that stops discriminating looks exactly like one that works. **A value census is a precondition of the encoding, not a detail of it.**
3. **`listingType` and `isBestOfferAccepted` are ORTHOGONAL**, not three values of one thing: a `buy_it_now` can be best-offer-accepted. "Three marks" therefore either loses that or double-counts it. **A modelling choice, surfaced as a fork rather than assumed.**
4. **Both fields are trustworthy only because of a pin made for an unrelated reason.** With `includeCompletedListings: false` the actor reports a Best-Offer sale's **asking price in `soldPrice`** and relabels it `buy_it_now`. R2b pinned the flag `true` to protect brief rule 7; **R5 inherits that dependency and should say so**, because a vendor default flip would now corrupt the marks as well as the prices.

### Ruled in advance — not forks

- **No fitted model, kernel density, asserted cluster count, smoothing or trendline.** n=98 is enough to *see* modes and not enough to *characterise* them; mode-fitting on small samples finds structure in noise. The app draws the dots, the eye finds the modes — refused for the same reason D8 refuses an average.
- **No bins that invent counts.** One mark per sale; removing a row removes a mark.
- **Extraction only, never inference** (§5, if it ships): `"CGC 9.8"` → 9.8; `"looks like a 9.4"` → nothing; **`"CGC READY"` → NOT slabbed**, which is D10's adversarial case and the test that decides whether the feature works or poisons the data.
- **The seller's title remains the record.** An extracted grade is a derived field *beside* it, never replacing it (D4's two objects). A wrong extraction must be visible, not laundered.
- **Disclosure folding cuts where the sentence changes job** (HT-D53). Fold the *why*, keep the *what*.

### The five reads — proposal

Your lean was modes + listing type in v1, the other three named. **I'd split them differently, because two of the five are not features at all.**

| read | proposal | reason |
|---|---|---|
| **modes** | **v1** | the slice's whole point |
| **auction vs BIN within a mode** | **v1** | this *is* §2's encoding once drawn — it costs nothing beyond the marks themselves |
| **dispersion within a mode** | **free, not a feature** | an emergent property of drawing one mark per sale on a legible axis. Nothing to build and nothing to park; it arrives with the plot or the axis is wrong |
| **time-to-sell** | **parked** | needs `endedAt` as a *second visual dimension* on a 360px surface — a real design cost, and the first thing that would overload the plot |
| **best-offer density** | **parked, and blocked** | needs a third encoding channel *on top of* listing type, so it cannot be designed before the orthogonality fork is ruled |

### §5 title extraction — proposal: **its own slice, after R5**

Three reasons, the third being the one I'd argue hardest:

1. It adds a **third real call** and another beat to staged feedback — a different kind of risk from anything in R5.
2. Its failure mode is **data poisoning** (D10's adversarial case), where R5's is representational. Mixing them means one defect pass covering two unrelated hazards.
3. **The plot is the instrument that would reveal a bad extraction.** A "9.8" label sitting inside the $9 mode is visible the instant the dots are drawn — but only if the dots are already known-good. Ship the plot unlabelled, confirm it, *then* let labels land against a surface whose correctness is established. That is **D14's shape**: the diagnostic ships before the mechanism whose failures it exists to reveal.

### Disclosure folding — the inventory, and one conflict with a standing decision

**Fold** (the *why*): the query-derivation note (`app.js:1623`); the provenance half of the raw/slab paragraph — *"eBay's search results carry no grade and no certification field…"*; the trace line (note: it lives on the **capture outcome modal**, a different surface from the comps list).

**Keep** (anything that changes what a number *means*): the kept count; the 90-day window; *"this lookup cannot tell a raw copy from a graded slab"*; *"Read them — a slabbed 9.8 and a beaten reading copy are both in this list."*

**Already gate-protected, which is fortunate:** `CQ7 GATE (Fork C)` asserts the window is stated **with the count, on the surface, every render**, and `CQ8 GATE` covers the zero-comps branch. **HT-D53's safety control therefore has an existing anchor** — the folding must leave both green, and a fold that hides the count or the window fails a gate that already exists rather than one invented for this slice.

**The conflict.** *"The 'pricing is not built' notices"* does not exist in the form assumed. Three variants (`566`, `793`, `1216`) say *"Identification is not built yet"* and sit behind `!visionReady()`, which the shipped contract makes false — **unreachable scaffolding that wants deleting, not folding**. The one live notice is `2350`, *"No price lookup is built, so nothing uses this token"* — and **D9 requires that to be visible**, because it is the exit for a stranded credential. Folding it would re-strand the token D9 exists to surface. **Ruled needed.**

**Mechanism: reuse `citeBlock`** (`app.js:267`) — `<details class="cited"><summary>…</summary><div class="citebody">…</div></details>`, already shipped with CSS. A second folding mechanism would be `COMP_KEYS` vs `parseComps` all over again.

### Gate obligations

- **Every mark corresponds to exactly one row**, and removing a row removes a mark (planted control both directions).
- **No fitted curve, smoothed density or asserted band boundary** anywhere in the rendered surface — planted control.
- **Listing-type encoding is exact** — *blocked on the enum census*; plus an **unrecognised value must render visibly**, never silently absorbed.
- **A tap shows the verbatim seller title** (D10: the only grade signal there is).
- **Folded blocks are one tap from the surface; the kept statements are NOT foldable** — HT-D53's planted safety control, anchored on the existing `CQ7`/`CQ8`.
- **`COMP_KEYS` and `parseComps` agree** — the divergence above, closed and pinned.
- **Layout gate extended to the plot at 360px**, and it must measure the plot *populated*, not empty — the want-list flag passed a layout gate while rendering nothing, and that is one slice old.
- **CQ7 holds**: every price on the surface is a sale or the labelled ask.

## R5 — The distribution surface — **BUILT AND GATED**, v0.3.0 (2026-09-14)

All forks ruled as leaned. Assertions **431 → 463 (+32)**, re-pinned in this commit; the layout gate now measures the plot **populated** at every width.

### The rulings, and where each is enforced

| ruling | enforced by |
|---|---|
| log scale, because **grade bands multiply** | `PL2` — gated as a *property* (equal ratios → equal distances), not as "it calls Math.log" |
| and it is a **claim**, so it is stated on the surface | `PL11`, plus "ticks are dollars, never exponents" |
| **one mark, one sale** | `PL5` (marks + hidden = rows), `PL7` (`data-p` enumerable), layout `markCount` + `allMarksDrawn` |
| ties **stack**, never blend | `PL6` — four sales at $25 occupy four *distinct* positions |
| overflow **disclosed**, D11 reused | `compsPlotHTML`'s cut line; `PL5` accounts for `hidden` |
| **shape = type, ring = best offer** (orthogonal) | `PL9`, and layout `shapes=2c/2r/1ring` at three widths |
| an **unrecognised** value renders visibly | `CQ12` — and *absent* is distinguished from *unrecognised* in the data while identical on the surface |
| **no** fitted curve, smoothing or asserted band | `PL10`, with a **planted control** proving the detector fires |
| fold the **why**, keep the **what** | three `R5 GATE (HT-D53)` assertions — present **and not inside a fold** |
| tap → the seller's words, in place | `PL12`, `renderCompsPick` |

### Findings the build produced

**1. The `COMP_KEYS` / `parseComps` divergence is closed structurally, not by a gate.** Rows are now *derived* from `COMP_FIELDS`, so used-but-undeclared is impossible by construction. Worth recording: the defect row that deletes a field **does not fail**, and that is the derivation working — both sides of the "exactly the declared fields" assertion come from one list, so they move together. Only an *undeclared* `from` is a real defect, which is what row 66 plants.

**2. The ruled enum census needed a surface to be executable.** `listingType`'s values are unmeasured, and it was ruled the census comes free from the next real lookup. But `compTypeOf` renders `FixedPrice` as "Buy It Now" — so a reader could not report back what the provider actually sent. `compsTypeCensus` now prints the provider's **own strings verbatim** with counts, for the same reason D10 keeps the seller's title and D4 keeps `raw` beside the normalised form.

**3. Three gates were repointed (HT-D60 Clause 3), and one was a near-miss.** `AK5`'s property was *DOM order* of `.cmpprice` spans — and `<details>` keeps its content in `innerHTML`, so folding the list would have left it **passing against a surface nobody can see**. Repointed to geometry. `AK6`'s sweep reads `.cmpprice`, which marks do not have, so its coverage would have **silently shrunk** to exclude the surface where prices are now drawn. `AK9` fired on the *new folded prose*: its detector was `indexOf('$8')`, which cannot tell the forbidden quotient from `$89` — D7's measured evidence. Repointed to numeric money-token extraction, **with a planted control** proving it finds `$8` and `$8.00` while reading `$89` and `$80` as themselves. That is AK7's old failure in a new vocabulary.

**4. The layout gate could pass vacuously — in two places.** `hit()` reports two **zero-size** rectangles as not intersecting, and `titleBelowPrice` becomes `0 >= -1`; so every comps fact passes on collapsed rects. Folding the list into a `<details>` made that reachable for the first time. Both call sites now require non-degenerate rectangles and **print the measured size** — and the second site was found *only* because the first started printing its dimensions while the second did not.

**5. `PL2` was written against a fixture that could not exhibit it.** The first version tested equal-ratio spacing using $1/$10/$100 against a domain of $9–$145, where `x()` legitimately **clamps** — HT-D60 Clause 4, inside the assertion enforcing this slice's central ruling. Fixed to in-domain ratios (9→27→81), and the clamp is now **gated on purpose**, having been discovered only by colliding with it.

### DEMONSTRATED — rows 62–66, each seen to fail (HT-D60 Clause 1)

Run on a tree committed first at `9494ce1`.

| row | planted defect | verdict | first named failure |
|---|---|---|---|
| 62 | the first mark of every column dropped into **neither** `marks` nor `hidden` | `GATE: FAIL` | `PL5 GATE: ONE MARK, ONE SALE …` |
| 63 | the axis emitted as a **polyline** | `GATE: FAIL` | `PL10 GATE (D8): NO fitted curve, smoothed density, polyline …` |
| 64 | `citeBlock`'s body moved **outside** its `<details>` | `GATE: FAIL` | `R5 GATE (HT-D53): while the PROVENANCE … IS folded` |
| 65 | an unrecognised listing type **absorbed** into `bin`/known | `GATE: FAIL` | `CQ12 GATE (D5): an UNRECOGNISED value renders VISIBLY …` |
| 66 | a `from` consumed that `COMP_KEYS` never declares | `GATE: FAIL` | `CQ11 GATE (D3/R5): every field the parser CONSUMES is declared …` |

**None came back `WEAK-MATCH`**, which was the second thing being watched: all five target `res()` assertions, so a weak label would have meant the expected string matched a *passing* line — the CQ7 tautology in this slice's vocabulary. Every one landed on a genuine `FAIL` line. All four mutated files restored identical to their pre-run copies; tree clean.

**Row 62 is the weighted one.** One-mark-one-sale is the property the entire plot rests on, and the mutation breaks it *silently* — no error, no gap, just a distribution showing fewer sales than it was given. That is D8's failure transposed into a new medium: a picture asserting more agreement than the sales support, which is exactly what a fitted curve would do and why row 63 exists beside it.

**Row 64 was the one most likely to be written wrong rather than to find something.** Its pattern matches `${innerHTML}` inside a template literal, and perl's replacement half is a double-quoted string where `$` interpolates — the hazard that has bitten this repo four times. A dry-run on a copy confirmed `\${innerHTML}` yields a literal before the row was spent.

### What this does not cover (Clause 2)

- **`listingType`'s enum is still unmeasured**, so "the encoding is exact" is gated only for the documented values. The census makes the survey free on the next real lookup; it does not perform it.
- **The plot is gated at four viewports against four seeded rows.** The device pass ran 98. Stacking, column collisions and the D11 overflow line are exercised by fixtures, not yet by a real distribution.
- **No gate reads the picture as a human does.** Every assertion here is geometric or structural; that the modes are *legible* is a claim only a device pass can settle.

## R6 — The optics pass — PRE-REGISTERED, A SPLIT PROPOSED, FORKS OPEN (2026-09-15; NOT built)

R5 made the distribution correct. It still reads like a test harness: small type, a permanent 84-row list behind a toggle, the plot's own affordance buried in a paragraph about log spacing, and the whole range crushed into one screen-width.

### The type problem, measured before proposing a scale

**`body` declares `font:16px/1.5` — and almost nothing uses it.** Eleven distinct sizes are in play (9, 11, 11.5, 12, 12.5, 13, 14, 15, 16, 17, 24), **eight of them below the declared base**, and only three declarations meet or exceed it — `.top h1`, `.idhead`, `.idq`, two of which are the identity draft's headings. That is why the draft reads comfortably and nothing else does: the page states a readable default and then opts out of it nearly everywhere.

**The two smallest declarations on the surface are R5's own**: `.ptl` (axis tick labels) and `.askrulel` ("YOUR ASK"), both **9px**. The labelling on the thing this slice exists to make readable is the least readable text in the app.

### RECOMMENDED: split into two slices

Asked for, and the answer is yes — but into two rather than three.

**The legibility half.** Type scale, the tap affordance, and surface-on-demand. One theme, and one repointing pass over the gates that read the list. **Type goes first, and the ordering is load-bearing**: a readable scale is the *constraint* that makes a scrollable detail plot necessary. Building the two-view geometry at today's sizes and then enlarging type means tuning the plot twice.

**The navigation half.** The two-view plot and the highlight filters. Filters were ruled to apply to *both views simultaneously*, so building them against a one-view plot and retrofitting is wasted work. This is also the half that reshapes the layout gate's central claim, which deserves to be legible in a single commit.

**Neither half is named as a slice here, deliberately.** The first draft of this entry gave each one a suffixed slice identifier, and the cross-reference census refused both — they resolved to no heading. Its own remedy offers two routes, *"repoint the citation, or add the heading"*, and **they are not equivalent**: adding headings would write a split into the record's structure because it was *proposed*, before it was *ruled*. A ruling on a fork is not a go-ahead on a slice, and a heading is the record asserting a slice exists. Identifiers follow the ruling, so these stay descriptive until there is one.

*(The identifiers are described rather than spelled, because the census cannot tell a citation from a quotation of one — a limit this file already records from the Fork G episode, and the third time prose ABOUT a citation has read to the scanner as a citation. Describing them keeps the census strict, which is worth more than the two characters.)*

**Item 2 is cheaper than it first appears, which is what makes this a two-way split rather than three.** Removing the permanent list sounds like a broad repointing job; measured, the harness has **three** real dependencies — CQ7's price extraction, `akPrices`, and the R5 fold gate — plus **two** `.cmplist .cmprow` sites in the layout gate. Five sites. The remaining references are comments or a CSS-existence check that survives untouched.

### Ruled in advance — not forks

- **Highlight, never filter out.** Tapping "title mentions CGC" dims the others and leaves them in place. The finding is that slabbed sales sit above $200 while the raw mass sits at $20–60, and that is *only* visible with both on screen — D10's refusal to split into groups, applied to selection.
- **Label the button for what it does.** "title mentions CGC", never "slabbed". D10's adversarial case is live: *"CGC READY"* sits on raw books. The app reports a string match; the human reads the titles and decides.
- **Buttons derive from the response.** A category with no matches does not render — an empty filter cannot narrow, which is D5's shape.
- **Overview plus scrollable detail**, neither replacing the other.
- **Scanning titles must remain possible** (D7/D10: the seller's words are the only grade signal there is) — summoned, not sitting there by default.

### Findings that change the slice's shape

**1. The R5 fold gate inverts.** It currently asserts that `cmplist` is *inside* a fold. With no permanent list, that assertion has no subject. It becomes an **absence** gate — "no permanent full list renders" — and an absence gate is unfalsifiable without a **planted control** that puts one back and must fail.

**2. CQ7's sweep and `akPrices` would silently shrink.** Both read `<span class="cmpprice">` off the surface. Remove the permanent list and they keep passing while covering only the tap-detail row and the nearest-comps rows. **A gate whose coverage shrinks while still passing** is the failure R5 hit twice — in AK6's sweep and in the layout gate's second comps site. Repointing is required, not optional.

**3. Dimming looks like it contradicts PL6, and the carve-out belongs in the record.** PL6 ruled *"ties stack, never opacity — opacity makes two sales look like one darker sale, which invents a reading."* Dimming **is** opacity. The distinction: PL6 forbids opacity as an encoding of **density**, where overlapping marks blend and two read as one. Dimming is a uniform **selection state** on marks that remain individually positioned and non-overlapping. Nothing blends. The gate that keeps this honest is the one already specified — every mark present before a filter is present after it — plus a floor on the dim, so both populations stay countable.

**4. The type/layout conflict is not evenly distributed.** The layout gate requires the identity question and both actions in view **unscrolled** at 360×690, and larger type makes the draft taller — that is where a genuine conflict would appear, and its *magnitude* is a number (today's vertical slack) that the build should **measure first** rather than argue about now. The sharper conflict is on the plot: 12px tick labels inside a 320-unit viewBox will collide. **The two-view design resolves it rather than requiring a retreat** — the overview is a *locator*, not a reading surface, so its labels may stay small, while the detail plot's meet the floor.

**MEASURED 2026-09-15, and the vertical half of the finding above is WRONG.** Ruled: report the number rather than design around an estimate. The number:

| viewport | body | content | **slack** |
|---|---|---|---|
| 360×690 | 522px | 708px | **−186px** |
| 390×745 | 572px | 690px | **−118px** |
| 1200×900 | 660px | 690px | **−30px** |

**The draft already exceeds the modal body at every width, and the gate passes anyway.** That is not a defect — it is HT-D51's architecture doing its job: a footer pinned *outside* a scrolling body. `$sOk` composes `lead.inView`, both actions in view, `pageScrollY = 0` and no horizontal overflow, and **excludes `bodyScrolls` deliberately**. The identity question is in view because it sits at the top of the scroll container; the actions are in view because they never move. The 360×520 case *requires* `bodyScrolls = True` for the same reason.

**So "larger type threatens in-view-without-scrolling" was a misreading of the claim.** Type growth makes an already-scrolling body scroll further — a usability cost, and a real one at −186px, but not a gate failure and not a fitting problem.

**The binding constraints are horizontal, not vertical:** `pageOverflowX`, already gated at four viewports, and the plot's tick labels colliding inside a 320-unit viewBox. The legibility half is redirected accordingly — it has **no vertical budget to defend**, which is the opposite of how it was about to be designed.

**Recorded because the estimate would have shaped the slice.** A vertical budget would have been protected, sizes would have been held down to defend it, and the defence would have been of a constraint that does not bind. One measurement, taken before any design decision, cost a single gate run.

### Forks — the legibility half

- **The base scale.** Lean: keep `16px/1.5` as the stated base and collapse eleven sizes to about five — data above base, structure at base, provenance below, with a **floor of 12px** and nothing beneath it except the overview's ticks (see above). The two 9px declarations go.
- **What replaces the folded list as the summon path.** Lean: two paths already exist — a tap gives one sale, and R3's nearest-comps rows stay visible beside the ask. the legibility half adds a third, explicit and honest about scope: an action that lists *the current selection* ("list these N sales"), never the whole set by default. Once filters exist that becomes "title mentions CGC → list these".
- **Whether any layout claim genuinely conflicts.** Named above; the magnitude is the build's first measurement.

### Forks — the navigation half

- **How the dimmed state renders** without losing mark shape or the ask marker. Lean: opacity on fill/stroke only, shape and position untouched, a floor so dimmed marks stay countable, and **the ask rule exempt entirely** — it is not a sale, belongs to no title category, and is the reference the whole comparison hangs on.
- **Whether multiple filters combine, and how.** Lean: **OR**, multi-select, tapping an active button turns it off. AND would shrink the highlighted set toward nothing, which is filtering by another name and contradicts the highlight ruling.
- **Is the overview tappable at all, or purely a locator?** Lean: **tappable as a locator, never as a selector** — a tap scrolls the detail to that region. At overview scale a thumb covers many marks, so selection would be ambiguous and would sometimes report a sale the user did not mean; and one gesture carrying two meanings is worse than one meaning. Precise selection belongs to the detail plot.
- **What "the ask marker agrees between views" means as a gate.** Lean: **geometric, not numeric** — the same relationship to its neighbours in each view (strictly between the highest sale below and the lowest above), which is how AK5 was already repointed. Equal pixel positions across two different scales would be the wrong claim.

### Gate obligations

- No permanent full list on the surface — **with a planted control** that renders one and must fail.
- The tap affordance renders **outside** the provenance paragraph.
- Highlight **dims rather than removes**: every mark present before a filter is present after it, with a planted control where a filter removes marks and must fail.
- Buttons derive from the response; an unmatched category does not render.
- Labels read "title mentions X".
- The **overview** is fully in view without scrolling at four viewports.
- The **detail** scrolls horizontally only, with no vertical overflow.
- The ask marker agrees between views.
- The type scale is asserted at 360px.
- **CQ7's sweep and `akPrices` repointed, not weakened** — coverage must not shrink silently.
- Existing layout gate claims repointed rather than relaxed.

## R6 — the legibility half — **BUILT AND GATED**, v0.4.0 and v0.5.0 (2026-09-15)

Type first, as ruled. Assertions **431 → 473**; the layout gate gained a type dimension and a slack measurement.

### What shipped

**The type scale.** Eleven distinct sizes to **four plus one glyph** — 18 data / 16 base and controls / 14 reading / 12 floor, with 24px reserved for the close icon. The page already declared `16px/1.5` and opted out of it almost everywhere: eight of eleven sat below that base. Collapse and *assignment* are different jobs, and the uniform map only did the first, so two things were moved afterwards: the sold-below/above count (R3's entire output, sized like a note) and the count-and-window line (gated as meaning-bearing).

**The tap affordance**, in its own element beneath the marks. Gated on **rendered output, never source** — the comment explaining the move quotes the old sentence, so a source scan would match prose *about* the text. That is the census's citation-versus-quotation limit reappearing in a different file.

**Surface on demand.** No permanent list. The plot is the list; rows arrive by tap, by the nearest-comps rows beside the ask, or by an explicit control that **names its scope** — "List all 84 sales" rather than a bare "show".

### Three measurements, two of which changed what got built

**1. The slack number overturned my own framing.** I named the type/layout conflict as *larger type makes the draft taller, threatening in-view-without-scrolling*. Measured: −186px at 360×690, −118px at 390×745, −30px at 1200×900. **The draft already exceeded the modal body at every width and the gate passed anyway** — HT-D51's architecture, a footer pinned outside a scrolling body, with `bodyScrolls` deliberately excluded from the success verdict. So the legibility half had **no vertical budget to defend**, which is the opposite of how it was about to be designed. The binding constraints were horizontal all along.

**2. `<small>` renders at a size that appears nowhere in the stylesheet.** The type-floor gate failed on its first run and named two elements at **10px**: bare `<small>` applies the UA's `font-size: smaller`, about 0.83× its parent. No `font-size` declaration exists for them, so no grep of the stylesheet could ever have found them. This is why the gate measures **computed** sizes on the shipped page — a reason written into its comment before it paid. Fixed at the cause (`small{font-size:inherit}`), which also covers the settings panel and the identity draft, both outside that gate's selector scope.

**3. 16px on form controls is behavioural.** iOS zooms the viewport when focusing an input below 16px, so at the previous 15px the app zoomed on every field focus — the ask price, the query box, the want list. A live defect nobody had named, closed as a side effect.

### The five repointed sites, and one that was owed

Removing the list took the substrate out from under `akPrices`, CQ7's extraction, AK5's DOM-order sequence, AK6's sweep and the layout gate's `.cmplist .cmprow` measurement. Each block now **summons the list itself** rather than inheriting a state — CQ7's negatives (`/\bvalue\b/`, no-heading) got *stronger* for it, since they now scan the list's markup too. The R6 absence gate **establishes** the state it measures rather than depending on file order, because an assertion that passes or fails according to which block ran before it is not measuring the app.

**AK6's plot sweep was identified in R5 and never written**, which is a different fact about the record from "newly discovered". R5's own notes say `akPrices` reads `.cmpprice` spans, that marks do not have them, and that the sweep's coverage *"would silently shrink to exclude the surface where prices are now drawn"* — and then the AK5 repoint and the fold gates were written and this was not. `PL7` gated that marks *carry* `data-p`, so the property was never unguarded; what was missing was AK6's own claim reaching them. R6 made it sharper rather than softer, because the plot is now the primary surface. Written, with a paired assertion that the ask is **not** among the marks — if it ever became one, the sweep would start treating the user's figure as a sale.

### DEMONSTRATED — rows 67–70, each seen to fail (HT-D60 Clause 1)

Run on a tree committed first at `a3940fa`.

| row | planted defect | verdict | first named failure |
|---|---|---|---|
| 67 | the list rendered unconditionally again | `GATE: FAIL` | `R6 GATE: no full list renders BY DEFAULT …` |
| 68 | the `.plottap` element deleted | `GATE: FAIL` | `R6 GATE: the tap affordance renders in its OWN element …` |
| 69 | `.ptl` back to 9px | `GATE: FAIL` | `under 12px: ptl=9px:$10 \| ptl=9px:$100` |
| 70 | `compsListToggle` stops repainting | `GATE: FAIL` | `R6 GATE: and SUMMONING produces it …` |

**Row 70 is the one that proves the pair.** An absence gate — *no list renders by default* — is unfalsifiable alone: it passes just as happily against a renderer that has simply broken. Row 70 breaks precisely that, and the asymmetry is the evidence: **the absence assertion stayed green while only its control failed.** Had both failed, the control would not have been isolating what it claims to.

**Row 69 failed twice before it worked, and both failures were mine.**

First, its expected string was `belowFloor=1` — a guess at output I had never read. The real count is **2**, because two tick labels render. The row reported `NOTHING NAMED MATCHED -- SUSPECT THE FIXTURE`, which is the machinery working: the gate failed, my description of *how* it would fail did not match, and the harness refused to call that evidence. **That is D19 — an unmeasured quantifier — applied to a number in a fixture rather than to a word in a recommendation**, three hours after D19 was written. Repointed to `under 12px`, a line that prints *only* on violation, so it is failure-specific and independent of how many labels happen to be under the floor — because `belowFloor=2` would be correct today and would rot the moment the plot fixture's price span changed the tick count, which is exactly how row 55 died.

Second, planting it revealed the gate's diagnostic read `[object SVGAnimatedString]=9px:$10`. On SVG elements `className` is an object, not a string. **The one gate written for D17 — a slice's own chrome, sized last and smallest — caught SVG chrome correctly and could not say which element it was.** Useless precisely where it exists to be useful. Fixed to `getAttribute('class')`; it now reads `ptl=9px:$10`.

**Row 69's `WEAK-MATCH` label is legitimate and was predicted.** It reports through the layout gate, whose output lines are script-style and carry none of the `FAIL -` / `NOT MEASURABLE` markers `report()`'s second strict arm matches. The line genuinely does not identify itself as a failure — the same category as the two `check-refs` rows that stay weak-labelled by design.

### What this does not cover (Clause 2)

- **The type floor reports SVG text at its UNSCALED computed size.** `.ptl` reads 12px whatever the viewBox scale, so a future narrowing of the plot would not be caught. Today the plot scales up at all measured widths, so rendered size is ≥12 — true in fact, not proven by this gate.
- **The floor gate's selector set covers the main surfaces, not the settings panel.** The `<small>` fix is broader than the gate that found it.
- **Nothing here reads the surface as a person does.** That 36 of 46 declarations now sit in the bottom two tiers is a fact about the stylesheet; whether the hierarchy *reads* at arm's length is a claim only a device pass can settle.

### Assertion delta: 416 → 431 (+15), re-pinned in this commit

13 W assertions + the 2 SH1 shipped-shell checks. `APP_VERSION` moved to **0.2.0** with a dated `VERSION_LOG` entry — the shell changed, and `check-version.sh` demanding that bump is D14's machinery working rather than misfiring.

### DEMONSTRATED — rows 59, 60 and 61, each seen to fail (HT-D60 Clause 1)

Run on a tree committed first at `2f62240`.

| row | planted defect | verdict | first named failure |
|---|---|---|---|
| 59 | match on the **raw typed line** instead of the normalised title | `GATE: FAIL` | `W4 GATE (D15): a reading matches a want TYPED DIFFERENTLY …` |
| 60 | the **issue test dropped** from `wantMatch` | `GATE: FAIL` | `W5 GATE (D15 amended): a DIFFERENT ISSUE IS A DIFFERENT BOOK …` |
| 61 | `renderWantFlag();` removed from `identitySetField` | `GATE: FAIL` | `W9 GATE (D15/D16): correcting the issue REMOVES the flag …` |

**Row 59 is the weighted one**, by D15's own asymmetry: a want that should fire and does not is the error the feature exists to prevent — the walked-past book. It removes generosity about *format*, which is the only generosity D15 grants, and nothing errors; the flag simply never appears. A false positive costs a two-second look; this costs the book.

**Row 61 is D16's shape in the newest code**, and the worst version of it: with that one call removed the flag is **correct when first painted and stale for every correction after**, which is right often enough to be believed. The dry-run confirmed it spares `wantsSave`'s own `renderWantFlag()` call — the check that mattered, since `renderWantFlag` has two call sites and only one is the seam.

**All three came back UNLABELLED**, which was the second thing being watched: they match `res()` `FAIL` lines, so the second strict arm added to `report()` in the same commit had to leave them alone. Sharpening the label did not blunt it.

Tree clean afterwards; all four mutated files restored identical to their pre-run copies.

### Deployed and verified (2f62240, v0.2.0)

| file | before | after |
|---|---|---|
| `index.html` | `c7965be5c83d2e6e` | `b4485f2b07af8b28` |
| `app.js` | `ea70d2d2d1aaabde` | `0bb0109f83992d76` |

Verified on the **first** poll (~15s), against the procedure and URL recorded earlier in this file rather than re-derived from the remote. The build line served to a device now reads `collectibles v0.2.0`, and anyone arriving from 0.1.0 sees the update notice once — the first time that path has run against a real previous version rather than a synthetic one.
