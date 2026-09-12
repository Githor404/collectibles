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

## R1 — Identification: the model reads the cover, the human confirms it — PRE-REGISTERED, FORKS OPEN (received 2026-09-12; NOT built)

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
