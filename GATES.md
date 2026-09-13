# collectibles — Gate Record

Pre-registered, re-runnable gate evidence. **HT-D60 binds** (adopted by D1): a new or changed gate is not evidence until it has been **run against the defect it closes and seen to fail**, with a fixture capable of exhibiting that failure (Clause 4). The failing run is part of the evidence and is recorded here beside the passing one.

Run everything: `bash tests/run-all-gates.sh`. Defect pass: `bash tests/defect-pass.sh`.

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

### `capture-outcome-gate.ps1` — the layout claim, measured (HT-D51)

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
| a gate script renamed away | GATE: FAIL | `GATE-SCRIPT CENSUS: FAIL — capture-outcome-gate.ps1 missing` |

**One finding from the pass itself, recorded because it is Clause 4 in miniature.** With the leash case placed late, removing the leash **did not fail it**: the first capture step stalled for the whole decode budget, the step chain aborted, and the suite died at 73 of 248 assertions. The defect was caught — by the count pin — but *the gate written for it never ran*. The case now runs **first among the capture cases**, with the decode budget shortened so only the leash can satisfy it, and it fails by name. A gate that cannot run while its defect is present is weaker evidence than one that speaks.

### Limits of this evidence, stated

- **No device pass, and no live credential.** Every call in both gates is stubbed. The first real capture is also the first proof of the model string, of a real photo's latency, and of the provider's actual error text. Same for PriceCharting: **the success body on a comics subscription and the wording of a wrong-token error are unverified** — Test connection is what will show them (D1).
- **The harness cannot exercise `createImageBitmap`** (HT-D47): it never settles under `--virtual-time-budget`. The harness proves the leash and the fallback; `capture-outcome-gate.ps1` runs the preferred decoder in real time.
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
- **`capture-outcome-gate.ps1` now measures the shipped identity draft**, not the synthetic contract's generic readout — measuring the stand-in would have kept the gate green while saying nothing about what ships. Its long-list case became a **short-viewport** case (360×520), because the identity draft is a fixed set of fields rather than a list: there, the body scrolls and the footer does not.

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

## R2b — Price via eBay sold comps — PRE-REGISTERED, FORKS OPEN (received 2026-09-13; NOT built)

**What it is for:** the number that makes the triage a decision — *"N recent solds at $X–$Y, they're asking $Z, you'd grade it W."* **Actual sales, not guide values.** It is the first slice that prices anything.

### Verified against Apify's public API, 2026-09-13

| probe | result |
|---|---|
| CORS | **`access-control-allow-origin: *`**, methods `GET, POST`, `Authorization` permitted — **the page can call it**, unlike GCD |
| store search `?search=ebay` | **2,532 actors**; six on page one, including four sold-listings scrapers |
| candidate actor | **`caffein.dev/ebay-sold-listings`** — "eBay Sold Listings Search". **574,056 runs · 3,139 users · 4.38★ (14 reviews) · last run 2026-09-13** |
| its cost model | `PAY_PER_EVENT`: **"1000 items (no details)" = $2.00**, "result" = $0.00001, "Actor Start" = $0.00005 |
| its stated filters | *"date window, result limit, category/subcategory selection (subcategory overrides category), marketplace"* |
| its stated result fields | sale price + currency, **sale completion timestamp**, listing title, item URL and identifier, **localized condition label plus a mapped numeric condition code**, **category label/ID**, listing type, best-offer-accepted flag, bid count, shipping cost and type, combined total price, images, **seller identifier and feedback metrics**, scrape timestamp |
| a two-stage alternative | **`blackfalcondata/ebay-sold-listings-scraper`** prices **"Fast item (search-card / sold)"** separately from **"Detailed item (full item page)" at $0.005** |
| `exampleRunInput` | **a placeholder** (`{"helloWorld": 123}`) — **the actual parameter names are NOT verified** |

**Three findings:**

1. **The ~$2/1,000 estimate is exact, not approximate** — it is a literal charge event, *"1000 items (no details)"*, $2.00. "No details" is the important half: it is the **cheap search-card tier**, and Item Specifics are not in it.
2. **The two-stage pipeline has a price tag per stage.** One actor already sells exactly that split — cheap search-card events versus $0.005 per full item page. So "how many survivors do we deepen?" is a **cost fork**, not a style question: 200 survivors deepened = $1.00 on top of a $0.20 search.
3. **Condition arrives as a label plus a numeric code, and category as a label plus ID** — so category 259104 and raw-vs-slab have real fields behind them rather than string-matching hope.

**Not verified, and blocking the build:** the actor's **input parameter names** (the example input is a placeholder), whether **Item Specifics** are exposed at all by any of these actors, whether category can be pinned to **259104**, and what a real comics query actually returns. Those need one paid run against a token — **the subscriber's**, per D1.

### Ruled 2026-09-13 — all six forks as leaned

| fork | ruling |
|---|---|
| **A** | **one stage first**, on the $2/1,000 tier. The $0.005-per-item deepening is **deferred until stage one's output is seen** — HT-D65's discipline (measure before tuning), and it makes the first probe cost pennies |
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

**Paste back four things:**
1. **The Input JSON** the console shows for the run (its **parameter names** are what we cannot get any other way).
2. **Two or three complete result objects**, verbatim — field names and values as returned.
3. **The run's cost/usage summary.**
4. **Whether anything resembling Item Specifics** (Grade, Certification, Variant Type, Signed, Reprint) appears in a result, or only in the listing page the result links to.

**Do not paste the token.** Nothing about the run needs it here, and D1's hygiene applies to this transcript as much as to the app.

**One design note that comes out of the probe's own shape:** when the app calls this, the token rides as an **`Authorization` header**, never as a URL parameter — Apify's CORS response permits `Authorization`, and D1 forbids a credential in a request URL after PriceCharting's `t=` lesson.

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

**Fork A — which actor, and one-stage or two.** A1 (leaning): `caffein.dev/ebay-sold-listings` for stage one on its $2/1,000 tier, and **stage two deferred until stage one's output is seen** — if titles alone separate raw from slabbed well enough, the $0.005-per-item stage may be unnecessary for most lookups. A2: `blackfalcondata`'s split actor, which sells both stages natively. **Unresolvable without the paid probe.**

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

### What this pre-registration does not settle

The actor's real input schema and output for a comics query (needs the paid probe); whether Item Specifics are reachable at all through any of these actors; N, the window, and the deepening budget, all of which want real noise data; eBay's terms position beyond "grey zone, personal tool"; and whether comps persist into any record — schema v2 is still unwritten.
