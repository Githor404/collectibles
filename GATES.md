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

### Carried forward to the pricing slice — the ASKING PRICE (received 2026-09-12; NOT pre-registered)

Recorded here so the pricing slice is built on it rather than discovering it. The brief's domain rules 3–5 carry the binding form.

- **The asking price needs a home, beside the grade**, as the second thing only the user can supply: a sticker, a sign, a verbal quote, or a **bulk rate** ("3 for $10"). Attested, never perceived.
- **The output is the comparison** — *"raw modelled at $X, they're asking $Y"* — not a valuation with the comparison left to the user's head.
- **Cover price and asking price are never conflated**, in the record or on a surface: one is printed on the book and read from the photo (identification, `cover_price`); the other is the seller's number, attested (pricing).

**A hazard this exposes in the contract already shipped (R1/D2), flagged rather than silently patched.** At a flea market the *asking* price is very often **visible in the photo** — a sticker on the bag, a price written on a board behind the stack. The identification template currently says `cover_price` is "the price printed on the cover", and a model reading a $5 sticker on a 1988 book whose cover says $1.00 would be **supplying pricing data through the identification path**, which is exactly the conflation rule 5 forbids. Two candidate repairs, neither taken without a ruling:

1. **A one-line template amendment plus `asking_price` on the refusal list** (a small R1.1): the template says a price on a sticker, bag, board or label is **not** the cover price and must be left out, and a model that volunteers an asking price is refused and counted, like a value or a grade. Cheap, and it closes the hole at the perception layer where it opens.
2. **Leave R1 as it is** and handle the distinction entirely in the pricing slice's own surface. Cheaper now, but it accepts that a sticker price can enter the record labelled `cover_price`, where nothing downstream can tell it from a printed one.

Seed gates for whichever slice takes it: the asking price never enters the identification contract; a record carries both numbers under **distinct names with distinct provenance**; the comparison surface states both and never prints one where the other belongs; a bulk rate is representable without inventing a per-book number the seller did not quote.

---

### The pre-registration, as it was written before building (kept verbatim)

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
- **D1 (recommended): none in v1.** R30 itself ruled the threshold is the weaker defence and the **shape of the question** is load-bearing. Here the question is already *what is this*, every field is correctable, and the real off-ramp is R2's candidate list. A confidence number now is a constant with no consumer and no calibration data.
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
| R1-correct | every perceived field is correctable, and a correction **keeps the model's original beside it** (`ai_*`, HT-D55/D57's correction-loop shape) |
| R1-query | the search string is derived from the **confirmed** fields, not the model's originals, and changes when a field is corrected |
| R1-parity | call path and paste path still produce byte-identical results — repointed to the real contract, not weakened (HT-D60 Clause 3) |
| R1-escape | hostile strings in every new field are escaped (P2 repointed) |
| R1-floor *(if G1)* | every prompt box holds the prompt after boot, copy yields the real text, and a pasted reply opens the same modal — content and outcome, not presence (HT-D63) |
| R1-vocab | no valuation or evaluative vocabulary reaches the draft surface, with a planted control |

**Defect pass required before any of this is evidence** (HT-D60, and Clause 4 applies to each fixture): at minimum **R1-refuse** (the fixture must contain a value *and* a grade that could leak), **R1-identity-first** (a `$` string planted where it could surface) and **R1-absent** must be seen to fail against their own removal, with a `tests/defect-pass.sh` row each.

### What this pre-registration does not settle

Grade and price; records and schema v2; the matcher and any corpus; the candidate off-ramp's destination (A2 / R2); and whether a wrong identification is ever recorded for calibration (HT-R30 Fork H's shape, which needs a consumer first).
