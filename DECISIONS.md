# collectibles — Decision Log

Ruled implementation contracts. The brief (`CLAUDE.md`) says **what** and **why**; this log says exactly **how**, as ruled. Both bind equally. Entries are append-only and dated; once ruled, supersede with a new entry rather than editing an old one.

**References.** `Dnn` is an entry in *this* log. `HT-Dnn` / `HT-Rnn` is an entry in HealthTracker's log or gate record, copied here byte-identical as `INHERITED-DECISIONS.md` / `INHERITED-GATES.md` — the reason ported code is shaped as it is, not governance of this repo (see D1).

---

## D1 — Credentials: BYOK now, a metering server before anyone else; and the port is a copy, not a shared library (2026-09-11)

**Doc-only when ruled.** It is enforced by the gates that land with the port, which follows it.

Two credentials exist:

- a **Grok (xAI) API key** for vision, billed to the user's own xAI account;
- a **PriceCharting Prices API token**, a *paid-subscription credential*. The docs say: "This token is specific to your guide and grants access to the data you've purchased. Please keep this token private."

### The ruling: BYOK, for the subscriber's own browser only

For now both credentials are **brought by the one user and kept in that user's browser storage**. That is acceptable **only while every browser holding the PriceCharting token belongs to the person who pays for it.**

### Hygiene: inherited from HT-D45 Fork F, and by construction rather than by rule

- **Each credential lives in its own storage key**: `collectibles-cred-vision` and `collectibles-cred-prices`. Neither is ever in the state object. Export, the pre-restore backup and restore all serialize the state object, so **none of them can carry a credential**. No exclusion filter exists to be broken by a later normalizer change; HT-D49 is the record of an allowlist rebuild eating a field inside a single slice.
- **Never written to a log, console, toast, error string or the capture trace**, including every failure path.
- **Egress only on an explicit user action**: a capture-send, a Test connection, and (once built) a price lookup the user asked for. Nothing goes out on boot, render, opening settings, restore or a failed parse.
- **Masked wherever it is shown.** The input is write-only and cleared after save. Replacing a credential resets its status to `unverified` (HT-D49).
- **Every write to a credential store is a merge** (HT-D49), per role. Patching one role can never touch the other, because they are different keys.

### What changes relative to HT-D45, because PriceCharting authenticates differently

**The token travels in the URL.** Verified in the live docs 2026-09-11: "Each API call is authenticated by including this token as the `t` parameter in the HTTP request." A bearer header never appears in a URL; this token always does. So "never logged" has to cover the request URL too:

- no surface, trace, error or log line may carry a request URL;
- a provider's error text is **redacted of the credential** before it reaches any surface. HealthTracker surfaces provider text verbatim, which is safe against xAI (its bad-key message does not echo the key). It is not safe against a provider that echoes what it was sent, and this repo does not assume it knows which kind it is talking to.

**The rate limit is enforced at the single point every call passes through.** The docs say: "The API is limited to 1 call every second. Any more than that and your calls will be blocked and your account permissions revoked if it persists." The penalty is losing the paid subscription, so the limit is not left to each future feature to remember. Pacing is declared on the provider row (`minIntervalMs`) and applied inside the egress function, which serializes calls to that provider.

**CORS: open, so a browser-only call is feasible.** This is the same pre-build probe HT-D45 ran against xAI. A no-token `GET https://www.pricecharting.com/api/products?q=spawn` with an `Origin` header on 2026-09-11 returned **`HTTP 400`, `access-control-allow-origin: *`**, body `{"error":"Must provide an access token","error-message":"Must provide an access token","status":"error"}`. The docs agree: "Responses include liberal CORS headers to facilitate cross-site requests."

**Not verifiable without a token:** the success body on a comics subscription, and the wording of a *wrong*-token error. **Test connection is the verification mechanism** for both, exactly as HT-D45 ruled for the model string.

### This does not scale, recorded as a boundary

A token in a browser is **extractable** by anyone with that browser's devtools: from localStorage, from the network panel, and here from every request URL. The rate limit is also **per token**, so N people sharing one token share one call per second, and the consequence of exceeding it falls on the subscriber's account.

**The bright line:** the first time this app would run, with the PriceCharting token, in a browser whose user is not the token's subscriber. That includes "let a friend try it on their phone". **Before that point, a server must hold the token and meter the calls.** A trusted tester who brings their *own* subscription and token is still BYOK and does not cross the line.

The Grok key carries a weaker version of the same argument (the cost is the key-holder's own spend). A cohort would need either their own keys or the same server.

**Not built, not scheduled.** What is built now is the structure that makes the move a configuration change.

### The structure that makes the server a configuration change

1. **A provider table.** Each row declares its **role** (`vision` | `prices`), **base URL**, **auth style** (`bearer` header, `query` parameter with the parameter's name, or `none`) and **pacing**. HT-D45's "a second provider is a table row, not a code change" is kept and extended to the prices role.
2. **The credential comes from settings**, from its own store, looked up by role at the moment of the call. It is never captured into state or closures.
3. **Every outbound request goes through one function, `egress(role, request)`.** It resolves the row, attaches the credential as the row declares, applies pacing, bounds the call with a timeout, classifies transport failure, and returns the response. **Nothing else in the app calls the network.** Gated twice: statically, by a census of network primitives in the shell that must find exactly one site inside `egress`, and behaviourally.
4. **The move itself:** point the prices row's `base` at the server and set its `auth` to `none`. The client then sends no token and requires none; the server attaches the token and meters. No feature code changes. **A row with `auth: 'none'` is gated now** to send no credential and require none, so "it is a config change" is proven rather than asserted.

**What this does not solve:** the server itself, how the server authenticates the app's users, and the metering policy. Those arrive with the escalation, as their own entry.

### Port, don't share

HealthTracker's capture chain, credential store and settings surface, validate→retry→fallback, trace, outcome modal, local storage with export/restore, and gate machinery are **copied into this repo, not factored into a shared package.** One developer and two products: a shared library would put a versioning and cross-repo compatibility question on every future slice of both. The two will diverge anyway, and this port already had to, for PriceCharting's query-parameter auth, a second credential, and a success state that is not a meal draft.

Accepted consequences:

- **Fixes do not propagate.** A defect found in ported code is **flagged** for the other repo, not silently fixed there. HealthTracker is read-only from this repo's sessions.
- **The inherited record is reference, not governance.** `INHERITED-DECISIONS.md` and `INHERITED-GATES.md` are byte-identical to `healthtracker@dcf3d78` (git blobs `7b70060c…` and `0fd6edfb…`). They explain why the ported code is shaped as it is. **A ported mechanism must not be simplified away without reading the inherited entry that produced it.** The standing example: the 5-second leash on `createImageBitmap` (HT-D47) exists because the version without it hung, first on the device and then in the harness.
- **Shared origin means shared storage.** Two project sites under one GitHub Pages user domain share an origin, and therefore share `localStorage`. **Every storage key here is prefixed `collectibles-`**, and nothing here reads a `healthtracker-` key. That includes a Grok key already saved there: it is entered again. Gated by the port-residue check.
- **Governance that DOES port, adopted here as binding by this entry:** HT-D60, *a gate is not evidence until it has been run against the defect it closes and seen to fail*, all four clauses including Clause 4 (the fixture is as falsifiable as the assertion); HT-D56's *presence and a verdict, or fail*; the pinned assertion count; and the gate-script census.

### Deliberately not ported

- **Anything domain-specific:** the micros corpus design, nutrient masks, regimen, the rhythm ring, the meal draft and its sliders, the prompt template.
- **The service worker and HT-D6's update machinery** (`SHELL_HASH`, precache and version-drift gates, changelog notice). These were not on the port list. ~~They arrive together, as one slice, if installability is wanted.~~ **When they do, HT-D45 Fork G's explicit SW bypass for cross-origin and non-GET requests arrives with them.** A cache-first worker that could see a request URL carrying the token would contradict this entry.

  **AMENDED 2026-09-14 — the premise is answered, and the bundle is split.** *"If installability is wanted"* was written as a condition and then never asked. **Asked and answered: not yet.** Offline at a flea market is a genuine feature and it is the reason the worker exists — but it is not what is costing anything today. What is costing is that **nothing inside the app can say which build is running**, which made every device pass guesswork.

  So the slice splits, and **the order is the point, not the sequencing** (D14):

  - **NOW — legibility.** `APP_VERSION`, `VERSION_LOG`, the post-update notice, a visible build line, and `check-version.sh`'s two-armed drift gate. **All of it is page-side**; not one line of HealthTracker's version machinery lives in `sw.js`. No manifest, no icons, no precache list, no new gate script.
  - **LATER — the worker**, as its own slice, when offline is wanted for its own sake. It brings `manifest.json`, an icon set, a precache list and three gates (`check-sw-hash`, `check-precache`, and CDP work for offline/update), none of which collectibles has today.

  **The precondition stands unchanged and is now verified portable**: HealthTracker's fetch handler opens `if (req.method !== 'GET') return;` *before* the URL is parsed, then restricts to same-origin. Collectibles now has **three** egress roles, two of them token-bearing cross-origin POSTs — so they are excluded twice over. D1's clause was written before the second and third roles existed and still binds them.
- **The copy-prompt card** (HT-D11 / HT-D63). With no vision contract ruled there is no prompt to copy. The **paste box is ported**, because the fallback needs somewhere to put the raw reply. Whether collectibles has a no-key vision floor at all is a question for the identification slice.
- **HT-D7 migration machinery.** There is nothing to migrate at schema v1. The forward-version guard is ported.

## D3 — A contract and its consumer can disagree about one field, and neither side's assertions catch it (governance, 2026-09-12)

Doc-only. The instance is R1.2; **the rule is general and binds future slices.**

### What happened

D2 Fork B1 promises the fields **as printed** — a cover printing `#2` yields `#2`. The header that renders them assumed the **normalised** form and prepended a `#` unconditionally. Both sides were individually correct, and both were gated: the parser's cases assert the field keeps what was printed, the header's cases assert a header renders. **The bug lived in the space between them**, where no assertion on either side was looking.

### Why the gates could not see it

An assertion on the producer states what the field holds. An assertion on the consumer states that the consumer renders something. **Neither states what the consumer must do with the RANGE OF FORMS the contract permits.** "As printed" permits `2`, `#2`, `1/2`, `Annual 1`, absent — and a consumer exercised with one specimen has been tested at one point of that range.

### The rule

**Where a contract promises a range of forms, its consumer is gated ACROSS that range, not on a specimen** — the permitted forms in one case, each with its asserted output, and in both directions: that the consumer normalises what needs normalising **and** still does the work it did before (the control). R1.2's case is the shape: `#2` → one, bare `1` → gains one, `##2` → collapses, and the field itself still shows what arrived.

### And why it surfaced on a device rather than in a gate

**The model's output form varies between captures.** The first returned `#2`; the second returned a bare `151`. A stub returns whatever the fixture's author imagined; a model returns what it read. **A fixture is a specimen of a contract, never the contract** — which is the standing reason a device pass is evidence the gates cannot substitute for, and why the unmeasured items in `GATES.md` are listed rather than assumed.

## D4 — The reading and the query are two objects; the query is computed, visible and editable (R2, ruled in advance, 2026-09-12)

Ruled **before** R2 is pre-registered, so the slice is built on it rather than discovering it.

- **The as-printed reading is EVIDENCE** of what the cover says, and it is what the human confirms. **It is never normalised** — not for a search, not for tidiness, not to match a catalog.
- **The catalog query is DERIVED from it**, and is a different object with its own rules: drop leading articles, normalise the issue marker, and decide what to do with the publisher (open — R2's to settle).
- **The query is VISIBLE AND EDITABLE.** A normalisation that silently mangles a search is worse than one the user can see and fix. R1 renders it read-only; making it editable is R2's.
- **The evidence:** capture 2's query reads `the AMAZING SPIDER-MAN 151` — faithful to the cover, and almost certainly not how PriceCharting catalogs the book.
- **Consequence for R1, already correct:** R1.2 normalises the **display** only and leaves the query untouched. That stands under this ruling — the query's rules belong where they can be checked against a real search.

**What this does not settle:** the rules themselves (which articles, what happens to `#`, whether the publisher enters the query), and whether a query survives into any record. Those are R2's forks; this ruling fixes their **shape** — two objects, one derived from the other, the derivation inspectable.

### Amendment — the rules, measured rather than assumed (2026-09-13)

D4 fixed the shape and left the rules open. **The GCD probe (2026-09-12) measured them**, and they are adopted **now**, for **any catalog search** — including eBay's title filter — rather than waiting for R2a:

- **Drop the leading article.** `Amazing Spider-Man` → 322 matches; `the AMAZING SPIDER-MAN` → 146, a *different and worse* set whose top hit was *"Adventures in Reading Starring the Amazing Spider-Man"*.
- **Never append the issue number to a series query.** `the AMAZING SPIDER-MAN 151` → **0 results**. The issue is a separate lookup, not part of the series name.
- **Case is free.** `AMAZING` / `amazing` / `Amazing` are identical to the catalog.
- **The publisher RANKS candidates; it never enters the query string.** It is not part of the catalog's series name, so including it narrows to nothing.

**And Fork E, ruled:** a **canonical identity is `(source, series id, issue index)`** plus the **as-printed reading kept beside it**. Two objects, per this entry — the identity names a row in someone else's catalog, the reading is what the cover said, and neither is ever rewritten into the other.

### Amendment — the rules are PER SOURCE; "never append the issue number" is not universal (2026-09-13)

The amendment above adopted the GCD-measured rules **"now, for any catalog search — including eBay's title filter."** **That generalisation was wrong, and R2b's probe falsified it inside a day.**

- **GCD:** `the AMAZING SPIDER-MAN 151` → **0 results.** The catalog has a **series/issue hierarchy**; the number belongs to a second lookup, not to the series name.
- **eBay:** `amazing spider-man 151` → **clean, on-target results, no lots in the first eight.** It is **full-text search over listing titles**, where the issue number is the single most **discriminating** token in the query. Removing it returns every issue of the series ever sold.

**Same rule, opposite outcomes — because these are not the same kind of source.** A hierarchical catalog resolves *series, then issue*. A full-text index over listings has no hierarchy to walk, so every token has to earn its place in one string.

**So a query builder belongs to its source, and the rules are scoped to one.** What survives as universal is the **shape** this entry ruled: the reading is never normalised, the query is derived from it, the derivation is inspectable. What does not survive is **any rule phrased "for any catalog search."**

| rule | scope |
|---|---|
| drop the leading article · case is free | **universal** — these are facts about the *reading*, not about a catalog |
| the issue number is a **separate lookup**; the publisher **ranks, never queries** | **GCD only** |
| the issue number is **required**; the `#` marker is dropped; the publisher stays out, untested | **eBay only (R2b)** |

**This is D3 again, and it is worth naming as a pattern rather than filing as an incident.** A contract measured against **one** consumer was written as though it bound **all** of them. The measurement was sound; the generalisation was the defect. **A rule should carry the scope of the evidence that produced it** — and where this entry said "any catalog search," it had evidence from exactly one.

## D2 — Identification: the model reads the cover, the human confirms it (R1, 2026-09-12)

Forks **A1, B1, C1, D1, E1, F1, G1** ruled as recommended. Two of them carry a note that belongs in the record rather than in a commit message.

### A1 — and its cost, stated where a future session will read it

R1 ends at a **confirmed reading and the query it implies**. There is no price in this slice, and no product id.

**R1 is a MILESTONE, NOT A RELEASE.** It is a seam with a confirmed reading on one side and nothing on the other. The copyable search string is genuinely usable by hand at a table, and that is the whole of what this build does. Recorded in these words because "identification" is exactly the kind of slice name a later session reads as *identification shipped, the app works*.

### C1 — the key-issue field is DROPPED, and the reason is the record

The brief that opened this repo asked vision for *"whether it looks like a key issue"*. **It should not have, and the correction is the author's own:** that is market memory, not a property of the photograph — the one field the model would **recall rather than see**, the one most likely to be confidently wrong, and the one where being wrong **costs money at a table**.

**Dropped, not deferred.** And it does not merely go unasked: `key_issue` is on the refusal list, so a model that volunteers it anyway is refused, counted, and the refusal is said on the surface (HT-D45 Fork H). A photograph cannot show whether a book is a key issue, so nothing in this app will take that answer from a model.

### The contract (Fork B1)

`title`, `issue`, `publisher`, `cover_date`, `cover_price`, `markers` — **every field optional**, and **absent when not legible**. Strings exactly as printed (`"300"`, `"1/2"`, `"$1.00"`, `"75c"`, `"MAY 88"`): a number would invent precision the cover does not offer. `markers` comes from a **closed vocabulary of what is visible** — `newsstand, direct, foil, facsimile, variant-cover, price-variant` — and anything else is dropped and counted.

**Absence is a state.** A field the model writes as `unknown`, `n/a` or `none` is read as absence, because those words would otherwise travel into a search query as though they had been read off the cover.

**`notes` is dropped from the contract** — a deviation from Fork B's own sketch, ruled here. A free-text field is a hole in a structural refusal: a valuation can simply be written into it. Everything legitimate it could have carried is either already structured (markers) or is condition information this app refuses by design.

**The refusal covers value, grade and key-issue alike.** A phone photo cannot establish grade any more than it can establish worth, so a grade from the model is refused exactly like a price. The **printed cover price survives** the same reply — that distinction is gated in both directions rather than left to a comment.

### Correction, query, confirmation, floor

- **A correction keeps what the model read** beside the accepted value (HT-D55 / HT-D57's correction-loop shape). Clearing a field restores *absent*, never an empty string.
- **The query is derived from the CONFIRMED fields**, never the model's originals: correcting a misread issue number changes what will be searched. Title and issue only — whether publisher or date help the search is R2's probe to answer, not this slice's guess.
- **Confirm** (Fork E1) produces the identity and its query, and the surface states plainly, where the result is, that pricing is not built. **Nothing persists** (Fork F1): no record, no schema change, and the export is byte-unchanged.
- **The no-key floor ships** (Fork G1) and is gated on **content and outcome** — every prompt box holds the prompt, Copy fills the box unconditionally, and a pasted reply opens the same modal. HT-D63 is the reason that wording matters: HealthTracker's floor sat dead for weeks behind a gate that asserted a box *existed*.

### Corrections to the pre-registered gates, recorded as corrections

1. **R1-identity-first was wrong as pre-registered.** It said *no price field exists anywhere in the draft*, with a planted `$` proving it could fail — but the **printed cover price is a field and must render**. The gate now forbids a **grade control** and **valuation vocabulary**, and carries a control asserting the printed price **is** on the surface, so it is a gate about valuation and grade rather than about the character `$`.
2. **R1-refuse's fixture** carries a value, a grade **and** a key-issue claim, so C1's ruling is gated rather than only written down.
3. **Repointed, not weakened** (HT-D60 Clause 3): the two cases asserting the seam ships empty now assert that the shipped contract *is* the identification contract, and the empty-seam guard is asserted by clearing it. The viewport gate now measures the **shipped identity draft** rather than the synthetic contract's generic readout — measuring the stand-in would have kept it green while saying nothing about what ships — and its long-list case became a **short-viewport** case, because the identity draft is a fixed set of fields rather than a list.

**Count: 248 → 294.** Re-pinned in the same commit.

### Amendment — the sticker price (R1.1, 2026-09-12)

**Ruled: take it, and do not wait for the device test to justify it.**

**The reason is the shape of the failure, not its likelihood: it is SILENT.** A sticker price sitting in `cover_price` looks exactly like a printed one, nothing downstream can tell them apart, and catching it depends on someone noticing that a 1988 book claims a $5 cover. That is not a hypothesis a device test can cheaply confirm — it is one whose **confirmation is unreliable**. One template line and a refusal-list entry against that is a good trade.

What changed:

- **The template names the case.** A price on a sticker, a bag, a label, a board or a shop tag is **not** the cover price: leave it out entirely, and never report what anyone is asking for the book.
- **`asking_price`, `sticker_price`, `seller_price` and `sale_price` join the refusal list**, so a volunteered asking price is refused and counted exactly like a value or a grade. The set is deliberately small and unambiguous — each of those names pricing data. **A bare `price` was not added**: it is ambiguous enough that refusing it would fire on replies that meant the cover price, and the template already asks for `cover_price` by name.
- **`ID_TEMPLATE_VERSION` holds at 1.** The field contract does not change — only what may fill one of its fields. That is HT-D64's distinction, applied as D2 applied it.

**Gated in both directions**, the way the cover-price control was: a sticker or asking price is refused **and counted**, *and* the printed cover price **survives the same reply**. A refusal that killed the legitimate field would be the R1-identity-first error over again — so that direction is itself defect-tested, by planting `cover_price` onto the refusal list and watching the gate fail.

**The device test still runs, reframed:** it is evidence about **model behaviour**, not the gate on whether to close the hole. Photograph a stickered book — if the reply leaves the sticker out, the template is working; if it does not, that is a template-hardening finding on the copy-prompt path, where words are the only mechanism there is (HT-D64).

### Amendment — exactly one `#` on the header, whatever arrives (R1.2, 2026-09-12)

Found on the **first device capture**: the confirmed header rendered `STAR WARS ##2`.

**Cause.** The issue is stored **as printed** (Fork B1), so a cover printing `#2` yields `#2` — and both headers prepended a `#` unconditionally. The derived query was unaffected, because it never prepends.

**The second capture is what sharpened it.** That reply returned a bare `151` and rendered `#151` correctly. **The model's output form varies between captures**, so this is not a parser rule — the parser must keep what was printed — but a **display** rule: `issueLabel()` collapses any run of leading hashes to one and adds one when absent. Normalise at render, never at parse.

**Deliberately not changed: the derived query.** It reads the field as printed. What a search string should look like belongs to R2 — capture 2's query reads `the AMAZING SPIDER-MAN 151`, and the catalog almost certainly spells it *Amazing Spider-Man #151*; the as-printed reading and the catalog's spelling are different objects (carried forward in `GATES.md`). Normalising the query now would be guessing at a search whose behaviour is unverified.

**Gated in both directions, with a control:** an arriving `#2` renders one `#`, a bare `1` still *gains* one, and `##2` collapses to one — on the draft header **and** the confirmed header, plus a defect row that reproduces the device bug by restoring the unconditional prepend.

### What R1 does not do

It does not price, grade, save, or match a reading to any catalog. **Superseded detail (2026-09-12):** this entry originally said the match was blocked on a PriceCharting probe. That probe was **withdrawn** and PriceCharting deferred; the match is now R2a (GCD), itself deferred by D6, and price is R2b.

## D5 — A filter that does not filter looks exactly like success (governance, 2026-09-13)

Doc-only, general, and binding on **every future data source**.

**The finding.** GCD's API **ignores query parameters**. `?name=`, `?search=`, `?name__icontains=` and `?q=` each return **HTTP 200**, well-formed JSON, and the **full unfiltered count** — 232,776 every time. Nothing errors, nothing warns, and the first page of results looks entirely plausible. A client built on any of them would quietly search the whole catalog forever.

**The rule.** **Any source integration must prove its filter NARROWS — not merely that the call returns 200.** The gate asserts that a filtered call returns **fewer** results than the unfiltered one, and where possible that a known match is present and a known non-match is absent. Where the working search is a path form, the gate matches **the path shape**, not the status code.

**Family.** This is D3 one layer out. There, a contract and its consumer disagreed while both passed their own assertions; here, a client and a server disagree about what a parameter *means*, and the server's success code hides it. The defence is identical: **assert the property, never the proxy for it.**

### Amendment — it binds a SOURCE'S OWN filters too, not only the ones we invent (2026-09-13)

D5 was written against a query parameter this app constructs. It binds equally to **a filter the source advertises**: if we pass `category=259104` to a scraper that documents category selection, **the gate proves the result set NARROWED** — a known out-of-category item present in the unfiltered call and absent from the filtered one. Not that the call returned 200.

### Amendment — the METHOD: prove a filter with a value that must exclude everything (2026-09-13)

**This entry named the problem and left the method to invention, and the method I invented was the weak one.** For R2b I designed a four-run set difference — the same query filtered and unfiltered, twice, at **$1.60** — and read *"fewer results"* as narrowing. **That inference does not hold.** Fewer results is equally consistent with a filter that works and with a query that happened to match less; a proper subset is suggestive, never conclusive.

**The subscriber's probe settled it in one run, with a FALSE value.** `aspectFilter {"Publisher":"Marvel Comics"}` on an *Amazing Spider-Man* query returned ~100 — **uninformative by construction**, because the true value cannot distinguish a working filter from an ignored one. `{"Publisher":"DC Comics"}` returned **ZERO**. Nothing but a live, narrowing filter produces that.

**So the rule, and it is general:**

> **To prove a filter narrows, pass a value that must exclude everything.** A true value tests nothing — an ignored filter returns the same rows the keyword would have. **The falsifying value is the evidence; the confirming one never was.**

It is cheaper (one run, not four), it is conclusive rather than suggestive, and it is the same discipline the gate scripts already use in the other direction: **a planted control that must fail.** This entry had the control idea for *our* filters and lost it for a *source's*.

**Adopted for `categoryId` too**, retiring the four-run design in `GATES.md`: one run with a category that cannot contain comics, expecting zero.

A vendor that silently ignores a documented parameter is exactly GCD's failure wearing a supplier's badge, and it is **more** likely, not less, when the parameter is one of many on a scraper whose upstream layout can change under it.

## D6 — No standing infrastructure before the table (Fork A ruled A5, 2026-09-13)

**R2a is deferred; R2b is built first.** The reasoning is recorded because it will be re-litigated the next time something is easier with a server:

- A proxy for GCD would be **the first infrastructure in either project that must exist and stay up** — a thing to deploy, watch and pay for, in a codebase whose whole posture is a static page and the user's own keys.
- It would **see every lookup**, against a README that promises no telemetry and data staying on the device.
- **Neither cost is worth paying for a tool that has not yet been used at a table.**

**When canonical identity is actually needed, A1 is the named path** — a credential-free, read-only, caching proxy. Two things are decided **then**, not now: **logging off by design, or the promise reworded**; and whether a data dump can serve instead of a live call.

**What this does not forbid:** the metering server D1 anticipates for a paid credential. That is a different server for a different reason, and D1's bright line still governs it.

## D9 — A credential field exists only where a call exists that uses it (2026-09-13)

**Reported from the device:** *"I went looking for how to get a PriceCharting token because the app asked for one."* The shipped Settings carried a price-guide token field for a provider **D6 had deferred and R2b had replaced** — an empty input that sent the person testing off to buy a ~$600/year subscription nothing in the app would have called.

**The rule.** A settings field for a credential ships **when, and only when, a call exists that uses it**. Machinery may land first — the provider row, pacing, the `auth: 'none'` server-move proof, the credential store — and **none of that needs a surface**. An input is a request; an unbuilt thing should **say so**, not offer one (D3's seam, applied to UI).

**The exception, because removal has its own failure mode:** a credential **already saved by an earlier build** must not be **stranded** where it cannot be seen or deleted. It appears in Storage, **with a way to remove it, and only when it exists** — an exit, never an entrance. Gated in both directions, plus the token itself never printing.

**What was removed, and what was not.** The prices Settings card is gone; the prices **role keeps every piece of its machinery**, which the gates still exercise — pacing at 1 call/s, redaction of an echoing provider, and the `auth: 'none'` proof that the metering server of D1 is a table edit. **The capability is intact; only the invitation is gone.**

## D24 — A selector that reaches an element's CONTENTS proves nothing about the element (governance, 2026-09-15)

**Where it happened.** `.cmpdrop{display:block}` overrode the UA's `[hidden]{display:none}`, so the dropped-listings disclosure was open on the page from R2b until 2026-09-15 — **1332px, 69% of the comps surface** on the first real response, under a button that relabelled itself and moved nothing. The layout gate's type-floor selector is `#compsBox *`. **It reached inside those sixteen rows, measured their text, and passed them** — every one met the 12px floor. The gate inspected the defect's own contents and reported health.

**Why this is a new failure mode rather than an instance of an old one.** This repo already records three:

- **An instrument that cannot fail** (`grep -c $'\r'` reporting every line as CRLF). Not this: the selector worked perfectly.
- **A fixture that cannot exhibit the failure** (HT-D60 Clause 4). Not this: the rows were right there, rendered, measurable.
- **An assertion against a constructed element rather than the shipped page** (D16). Not this: it was the shipped page.

The selector **could** fail, the fixture **could** exhibit it, and the element **was** reached. It passed anyway, because the question it asked — *how big is this text* — is a property of the **contents**, while the defect was a property of the **container**. A descendant selector silently takes its subject's existence and visibility as **given**. It is a gate looking *through* the thing it should have seen.

**The rule.** Before a gate asserts anything about what an element holds, it must establish **that the element should be on the screen at all** — presence, display, geometry. A `#thing *` selector inherits `#thing`'s visibility as an assumption, and an assumption inside a gate is exactly what a gate is for removing. Where an element's whole purpose is to be *conditionally* present, the condition is the assertion: `DROP1` measures a **rendered rectangle**, not `hasAttribute('hidden')` — which was `true` for the entire four slices the defect was live.

**The cheap test:** *if this element should not have been on screen at all, would my selector have told me?* If it only reads descendants, the answer is no, and it will keep saying so in green.

**Family: D5.** A filter that does not filter looks exactly like success. A container that does not contain looks exactly like a container.

## D23 — A coverage claim can be true of the mechanism and false of the arrangement (governance, 2026-09-15)

**Where it happened.** C1's pre-registration listed six gate obligations and dismissed one of them in parentheses: *"The storage key is **prefixed** (PFX1 already sweeps this)."* Every word about PFX1 was true — it sweeps **every** storage key written in the whole run and fails on any that is not prefixed. What the sentence never asked is **when PFX1 runs**. It is a `step()`, not synchronous, and steps execute in registration order: it reads `__keysEverWritten` **at the moment it runs**. A C1 block registered after it would have written the replay key *after* the sweep had already read the dictionary. The suite would have stayed green while the one key C1 adds went uncovered by the sweep cited to cover it.

**The mechanism, which is the generalisable part.** A coverage claim has **two halves**: does the instrument look for *this class of thing*, and does it look at a **time and place where this instance exists**. The first half is a property of the instrument, and reading the instrument answers it. The second is a property of the **arrangement** — ordering, scope, timing, lifetime — and it is **invisible in the instrument's own source**. Citing the instrument answers only the first half in a sentence that sounds like it answered both. Nothing about PFX1 was wrong; the question was never about PFX1.

**Family: D19.** There, a quantifier was doing argumentative work it had not earned because it was unmeasured. Here the claim *was* checked — against the wrong half. **D19 says measure before you argue; this says make sure you measured the half the argument rests on.** It is also HT-D60 Clause 4 wearing different clothes: an instrument that cannot exhibit the failure, because of *when* it looks rather than *what* it looks for.

**The rule.** When a gate obligation is dismissed because an existing gate already covers it, state **where and when that gate runs relative to the thing it is claimed to cover** — and then **assert the coverage rather than inferring it**. C1's block is registered **before** PFX1 deliberately, the placement carries a comment saying it is load-bearing, and `RP1` asserts that the sweep **actually saw** the key rather than trusting that it would.

**The cheap test:** *would this still be true if the new code ran later?* If the answer depends on ordering, the claim is about the arrangement, and the arrangement is where it has to be checked.

## D22 — Shared mutable state between steps means one failure can masquerade as several (2026-09-15)

**Where it happened.** C1's harness block ran as a `step()` and assumed the shipped vision contract. Steps registered earlier install **synthetic** contracts, and nothing restores the shipped one. So `openCaptureResult` parsed against whatever happened to be current, `captureAccept()` produced nothing, `compsLookup` returned early on *"Confirm a book first"*, `COMPS` stayed `null`, and reading `.rows` threw **inside a promise**. The harness's own design then did what it is written to do: the steps after an async throw do not run. **PFX1, ID11 and ID13 never executed.** The reported count *fell*, 473 → 466 — eight assertions lost, six of them belonging to blocks with nothing whatsoever to do with replay.

**The mechanism.** Steps share one app instance. A step that mutates state and does not restore it hands the next step a different starting position, so a failure **appears where it lands, not where it was caused**. An async throw makes this much worse than a wrong verdict: it converts one defect into an **arbitrary number of missing assertions**, and a suite reporting "eight fewer assertions" is reporting a symptom whose cause is one line three blocks earlier. The same failure in the synchronous section would have cost exactly one assertion.

**Two rules, and the second is the one that generalises furthest.**

1. **A step ESTABLISHES the state it depends on; it never inherits it.** This is already the rule R6's absence gate follows — it establishes the state it measures rather than depending on file order, *because an assertion that passes or fails according to which block ran before it is not measuring the app*. D22 says the same thing about **preconditions** rather than about subjects.
2. **A precondition gets its own assertion, before the work that needs it.** A precondition that fails silently into a crash is strictly worse than one that fails loudly as itself: the crash names a null dereference eight assertions downstream, while the assertion **names the cause**. Paired with an **unconditional** state check and an early return, so one failure stays one failure and the pinned count cannot move with the outcome.

**Why the count mattered more than the failure.** A red assertion is a defect to fix. A **falling count** is a defect that has silently taken evidence with it — and this repo pins the count precisely because a silently reduced one reads almost exactly like a clean run. That pin is what turned an eight-assertion loss into something visible in one line.

## D21 — Test machinery is numbered apart, armed explicitly, and says so on the surface (2026-09-15)

**Ruled with the slice it governs (C1, response replay).** A comps lookup costs about **$0.40** and returns the same sales every time; with the subscriber's Apify credits exhausted, the alternative to replaying a saved response is not "pay per check", it is **cannot check at all**. That makes the capability necessary. It also makes it dangerous, because everything a testing aid needs in order to be useful is also what it would need in order to quietly become a product feature.

**The rule, in four parts. Each one is a fence, and each is gated.**

1. **Numbered apart.** Test-phase machinery takes a **C-series** number, never an R. The R-series is what the product does; C is what the workshop needs. A reader scanning `GATES.md` must be able to tell which of the two a slice is **without reading it**.
2. **Armed explicitly, and never persistently.** A saved response present is **not** a reason to replay. The arm lives **in memory only**, so it cannot outlive a reload — a persisted arm would replay silently in a later session and make **every measurement taken afterwards untrustworthy while nothing looked wrong**. One click per session is the price of that guarantee, and it is cheap.
3. **Never a fallback.** There is no "use the last result if the call fails" path, and there must not be one. That single line is how a testing aid becomes a cache, then an offline mode, then a behaviour nobody remembers is there. **The absence is the feature.**
4. **It says so, where the numbers are.** A replayed surface states that it is replayed **and the date it was captured**, because those sales were a moving 90-day window on that date. Same reasoning that already puts the count and the window beside the prices: anything that changes what a number *means* is stated where the number is, never in a footnote. Its **cost line must not claim a charge** — telling the subscriber they were billed for a call that never happened is brief rule 7's conflation aimed at their own money.

**And it is held outside the state object**, like a credential (D1). It is not the subscriber's data, so `exportJSON` — which serialises `APP_STATE` — must be **unable** to carry it. By construction, not by a filter someone has to remember.

**Why this is a decision and not a comment in the file.** The fences are individually reasonable to remove. Each one, taken alone, looks like a small convenience: *persist the arm so you don't have to click*; *fall back on the saved copy when the network is down*; *drop the banner, it's noisy*. Ruled together and gated, removing one becomes a decision against a record rather than a tidy-up. **The naming is the first fence; the gates are the rest.**

## D20 — Say what was DONE; mark intent as intent (governance, 2026-09-15)

**Where it happened.** A turn ended with *"I'm doing this as one coherent repointing pass rather than piecemeal"* — and no work was performed. The sentence describes a pass in progress. None had started. The subscriber read the report as work underway and **held a queued slice back waiting for it**, so the cost of the ambiguity landed on them rather than on me.

**The mechanism, which is the generalisable part.** The writer always knows which half of a report is finished and which is intended. **The reader cannot tell them apart**, because completed and planned work are described in the same register — the same verbs, the same confidence, the same level of detail. A plan written fluently is indistinguishable from a result. Nothing in the text marks the boundary, so the reader supplies the more natural reading, which is that it happened.

**This repo already draws exactly this line everywhere else.** A gate is *designed, not demonstrated* until it has been run against its defect and seen to fail; `GATES.md` carries "NOT YET DEMONSTRATED" sections precisely so a reader cannot mistake an intention for evidence. D20 is that discipline applied to prose about one's own work rather than to gates.

**The rule.** Report in two registers, and keep them apart:

- **Past tense for what was done**, and only for what was actually run, edited or measured.
- **"Next I will…" for intent**, in a sentence that cannot be read as a report.

Never narrate a plan in the present progressive — *"I'm doing X"*, *"taking these together"* — at the end of a turn that does not contain X. If a turn ends without the work, the honest line is **"next I will"**, or better, the work.

**The cheap test:** if a sentence would need a tense change to remain true after the tool calls it describes, it is intent and must be marked as such.

## D19 — An unmeasured quantifier is an argument, not a description (governance, 2026-09-15)

**Where it happened.** Asked whether R6 should split, I wrote that removing the permanent comps list would mean repointing the gates "a lot of gates are asserted against" — and used that to argue for a particular shape of split. Measured: **five sites.** Three in the harness, two in the layout gate.

**The claim had been doing argumentative work it hadn't earned.** It was not wrong so much as *unweighed*: "a lot" was chosen to convey difficulty, and difficulty was the premise of the recommendation. Had the number been five all along, the recommendation might still have been right — but it would have had to be argued on something else.

**The rule.** A quantity that appears in a recommendation is part of the argument, so it is measured before the recommendation is made, not after it is questioned. Words like *a lot*, *most*, *scattered throughout*, *everywhere* are **claims about counts**, and this repo already treats an unverified count as a defect everywhere else: the assertion pin, the gate-script census, the egress census, the `MK_IDS` control. The same standard applies to prose.

**And it is cheap.** The measurement that corrected this was one `grep`. The asymmetry — seconds to count, and a recommendation shaped by the answer — is the whole argument for counting first.

## D18 — The cross-reference census also stops the record's structure being written by proposals (governance, 2026-09-15)

**Where it happened.** R6's pre-registration proposed splitting the slice in two and gave each half a suffixed slice identifier. `check-refs.sh` refused both: they resolved to no heading. Its own message offers two remedies — *"repoint the citation, or add the heading."*

**They are not equivalent, and that is the entry.** Adding the headings would have satisfied the gate in seconds. It would also have written a **proposed** split into the record's structure before it was **ruled**. A heading in `GATES.md` is the record asserting that a slice exists; creating one because I had suggested it would make the record describe my proposal rather than the subscriber's decision.

**So the census does more than resolve identifiers.** It is the mechanism that keeps the record's shape downstream of rulings. An identifier that resolves to nothing is usually a typo — but sometimes it is a thing that does not exist yet *because nobody has decided it should*, and the census cannot tell those apart. **The author can, and must.** Identifiers follow the ruling.

**A limit, recorded twice now and hit a third time here.** The census cannot distinguish a citation from a **quotation** of one, so the sentence *explaining* the repoint tripped the same gate. Fixed by describing the identifiers rather than spelling them — which keeps the census strict. Weakening the scan to allow quoted forms would trade a real guarantee for two characters of convenience.

## D17 — A slice's own chrome is sized last and smallest (2026-09-15)

**Measured, not impressionistic.** The comps surface exists to make a price distribution readable. The two smallest text declarations in the entire app are **its own**: the plot's axis tick labels and the "YOUR ASK" rule label, both **9px**, against a `body` that declares `16px/1.5`. Eleven distinct sizes are in play and eight sit below the declared base.

**The mechanism, which is the generalisable part.** The author reads their own chrome **at desk distance on a large screen**, while writing it, dozens of times — and at that distance 9px is legible. It is the one surface whose legibility is never tested by its author under the conditions it ships into. Every *other* surface gets read on the device eventually, because using the product means reading it; the labelling on a chart is read by the person who built the chart, who already knows what it says.

**So it is sized last, and sized to fit rather than to be read.** Axis labels, legends, units, affordance hints and provenance lines are the parts that lose when space is tight, and they lose silently, because nothing fails.

**The rule.** When a slice adds chrome — labels, legends, keys, hints — its type is set **from the scale**, not from the space remaining. If it will not fit at the scale's floor, that is a finding about the layout, not a licence to shrink the label. **The instinct to shrink a label to make it fit is the instinct that produced 9px axis ticks on a surface whose entire purpose is legibility.**

**Corollary, and it is why R6 exists at all:** a device pass reads the *data*. It does not necessarily read the *chrome*, because the person holding the phone already knows what the axis says. Chrome legibility needs its own look, deliberately, at arm's length.

## D16 — An assertion against a constructed element proves the function, never the shipped page (governance, 2026-09-14)

**Two instances in two consecutive slices. That makes it a pattern, not an incident.**

**R3.** `#askBox` existed in the shipped shell, but `__setComps` called `renderComps()` where the real path calls `renderComps(); renderAsk();`. **27 assertions were green** because `akSeed()` called `CT.renderAsk()` by hand — the fixture supplied exactly what the seam omitted. Found by the layout gate, which has no fixture to help it, and only after two hypotheses read off the source were both wrong.

**The version slice.** **17 VN assertions were green while `index.html` contained neither `#versionNotice` nor `#buildLine`.** Every one ran against the harness's `mk('div','versionNotice')`. The machinery was shipped code with no gate on the page at all.

### The rule

A harness that constructs its own DOM proves the **function under test**. It proves **nothing** about the page that ships. Where a function writes to a named element, the suite must **also** assert against the **shipped shell, loaded as served** — and assert **content, not presence** (HT-D63: HealthTracker told people to copy from an empty box for weeks because its gate asserted that a box *existed*).

### Two sub-failures under one banner, and they need different gates

- **The harness supplies the ELEMENT.** The shell lacks it entirely. Caught by a **presence census**: every id the harness constructs must exist in the shipped shell, except a **pinned manifest of deliberate absences with their reasons** — today exactly one, `credBox-prices`, which D9 requires to be absent because no call uses it. Without the manifest the census would demand the app ship the field D9 removed, so the exception carries a control asserting it stays absent (D3's both-directions convention).
- **The harness supplies the CALL.** The element exists, but nothing on the real path paints or wires it. **A presence census cannot see this** — `#askBox` was present throughout. Only a content assertion against the shipped shell catches it.

### Measured when this was ruled (2026-09-14)

24 ids constructed by the harness, 30 declared by the shell, **23 in both, 1 deliberately absent**. Of the 23, **13 carry a shipped-shell assertion and 10 do not**: `confirmedBox`, `captureBox`, `storeBadge`, `replyReport`, `toast`, `prerestoreBox`, `prerestoreWrap`, `outcomeTitle`, `outcomeX`, `outcomeScrim`. **`confirmedBox` is the sharpest** — R1's primary surface, ten harness references, and `renderConfirmed()` on the live `refresh()` path: the exact configuration `__setComps` was in.

**The presence census is a REGRESSION gate, not a discovery gate.** It finds nothing today, because both known instances were fixed in the slices that produced them. It would have caught the version slice at the moment of introduction, and `#askBox` before R3. Saying it finds something now would be the empty-grep error again — a clean scan is only evidence once a control has shown the scan can fail.

## D15 — The want-list is a capture-time FILTER, and it errs toward firing (2026-09-14)

**Scope correction, ruled.** The want-list is **in**, and the reason it is in is what it does: **not a list to browse, but a filter that fires on capture.** Photograph a box at a flea market and the app says which of these you were already looking for. Browsing a list you wrote is something a notes app does; recognising an entry in a box you are standing in front of is not.

**It is the single-player residue of the sighting-network idea, and it is the half that works** — no counterparty, no enforcement, no adverse selection. One person, one box, one list they wrote themselves. Everything that made the networked version hard is absent because the second party is absent.

### The match is GENEROUS, not exact — and the asymmetry is the reason

**A miss means walking past the book you wanted. A false hit costs a two-second look.** Those are not comparable costs, so the filter is not tuned for balance: **it errs toward firing.** Match on title and issue, surface it as a **flag**, and let the person confirm. **Never silent** — a filter that quietly decides you were not interested has spent the expensive error to save the cheap one.

**This does NOT contradict D8, D10 or D13, and the distinction is the whole reason it is safe.** Those entries refuse to *assert* more than the data supports — no average, no group without a field, no ratio dressed as a score. **A flag asserts nothing.** It is a question — *"is this one of yours?"* — put to the person holding the book, and answered by them. **Precision is owed to claims; generosity is owed to questions.** The same brief that forbids the app guessing a grade (rule 2) requires it to surface a candidate rather than suppress one.

### AMENDED 2026-09-14 — generosity is about FORMAT, and the asymmetry has a BOUND

Ruled when the want-list was built, and the second point is a correction to the entry above rather than an addition to it.

**1. Generosity is about FORMAT, not about widening what counts as a want.** *"The Amazing Spider-Man #129"* and *"Amazing Spider-Man 129"* are **one want typed twice** — case, a leading article, punctuation, the `#` and leading zeros are all format, and the match forgives every one of them. **A different issue is a different book.** The match is exact after normalisation, not a prefix: once case, a leading "the" and punctuation are stripped, *"The Amazing Spider-Man"* and *"Amazing Spider-Man"* are already identical, so a prefix rule would buy nothing except firing *"Amazing Spider-Man"* on *"Amazing Spider-Man Annual"*.

**2. And that is the BOUND on this entry's own asymmetry.** The rule above says err toward firing because the errors are not comparable: a miss costs a walked-past book, a false hit costs a two-second look. **That holds per event and stops holding in aggregate.** False hits do not stay independent — they compound into a flag that gets **ignored**, and an ignored flag turns every later false hit into a **MISS**. The cheap error, repeated, becomes the expensive one. *"A flag I learn to ignore is worse than no flag."* This is not an exception to the asymmetry; **it is the limit condition the asymmetry needs in order to stay true**, and firing on title alone would breach it immediately by flagging every Amazing Spider-Man in the box.

**3. `raw` and the normalised form are TWO OBJECTS, in D4's shape.** The normalised title and issue are the **app's working object**; `raw` is **the line the person typed**, and it is what every surface shows back — the card, and the flag itself. The app never shows its own normalisation in place of someone's own words. A line with no issue number is **kept and counted as unmatchable**, never silently dropped, and the card says how many: a filter that quietly ignores part of your list has spent the expensive error to save the cheap one.

**4. Storage: `settings.wants`, and NO schema bump (Option A, ruled 2026-09-14).** `normalizeState` preserves `settings` wholesale, so wants survive a boot untouched. The alternative — a top-level key and `SCHEMA_VERSION = 2` — would have required a migration branch `boot()` does not have: a v1 state read by a v2 app falls through to `emptyState()` and is **overwritten at boot, silently, with no undo slot**. The want-list needed none of that, so it took on none of that risk; schema v2 is named and parked with the migration as its own subject. **This is also the first thing the app persists beyond credentials**, so `wantsSave` carries `Store.saveState`'s boolean to the surface rather than assuming success — a want that was not saved must not claim it was.

### v1 holds EXACT ISSUES ONLY

*"Amazing Spider-Man #129."* Title and issue, both named.

**The looser kinds of wanting are real and are deliberately NOT half-built**: *"any pre-1975 Marvel key"*, *"the rest of the Byrne FF run"*. These are genuine — arguably the more common way collectors want things — and **none of them is matchable at this tier**. A key-issue list is market memory, which D2/C1 already dropped for exactly this reason; a run is a range plus an inventory of what is already held, and holdings are out (below). **Recorded as a named later question, not attempted**: *how does the app represent wanting something it cannot enumerate?*

### Still out, with the reason rather than just the exclusion

**Collection management** — what is owned, purchase prices, portfolio value. Out, and **not merely as scope**: owned + paid + current-worth **is** a valuation surface, and D8 exists to refuse exactly that. A want-list says *"I am looking for this"*; a holdings list with prices says *"this is what mine are worth"*, which is the claim this product was built not to make.

**Marketplace, sharing, accounts** — out. D1's bright line stands: no counterparty, no server holding anyone's data.

## D14 — The gate that catches a failure class ships BEFORE the mechanism that produces it (2026-09-14)

**Ruled on the service-worker split, and it is the reason for the split rather than a description of it.**

**What happened in HealthTracker, from its own record.** The worker shipped first, with a manual `VERSION` integer that had to be bumped by hand on every shell change. It was **missed on every slice after Phase 0**. The deployed worker therefore never installed an update and served a **frozen first-deploy shell** — and the "update ready" hint had nothing to fire on, so the failure was silent in both directions. The content-derived `SHELL_HASH` and its gate were built **afterwards, in response**.

**So the order is inverted here.** `check-version.sh` and the version machinery ship **now**, while there is no worker at all; the worker follows as its own slice. Three things follow from that, and only the first is obvious:

1. **The gate guards every deploy in the interval.** From today until the worker exists, a shell change without a version bump fails — so the class is closed before the mechanism that makes it dangerous arrives.
2. **The gate accrues a track record before it is load-bearing.** By the time a cache can serve a stale shell, the drift check will have run against dozens of real commits. A gate first exercised on the day it becomes critical is a gate nobody has watched fail.
3. **A gate written ALONGSIDE its mechanism encodes the author's model of how that mechanism fails — and HT-D6 is the proof that model was wrong.** The manual integer *seemed* sufficient to the person who wrote it. Written first, against a failure class rather than against an implementation, the gate cannot be shaped by assumptions about a mechanism that does not exist yet.

**The general form.** A detector built *after* the thing it detects is built in response to damage already done; the first instance is always the one that escapes. Built *before*, the first instance is the one it catches. **Where the failure class is known in advance — and a stale shell is very well known — the detector does not wait for the mechanism.**

**Not a claim that every gate precedes every feature.** It applies where the failure class is *already documented* and the mechanism is *optional or deferrable*. Both hold here: HT-D6 records the trap in detail, and installability was deferred by the amendment above.

## D11 — A cap that truncates a tie group must say what it truncated (2026-09-14)

**Ruled on R3's Fork B.** With 98 sales, ties are certain, and a "nearest three" cap will routinely cut through a group of sales that all went at the same price.

**A cluster at one price is SIGNAL, not noise.** Twelve sales at $25 is the densest fact on the surface — it says the market has a floor there — and showing three arbitrary examples of it hides exactly that. Silent truncation does not lose an edge case; it loses the finding.

**So: where a cap cuts a group sharing a value, the surface states what it cut** — *"3 of 12 at $25"*. The user can see that eleven more sat at that price without the surface having to render all twelve.

**The general form, and it is D8's family:** D8 forbids *manufacturing* a number the data does not contain. This forbids *concealing* a number the data does contain, by presentation. **A display rule that changes what the data says is a claim, not a layout**, and both directions are the same offence against a scatter that is supposed to be the claim.

## D12 — The app never divides a seller's quote (2026-09-14)

**Ruled on R3's Fork C.** A flea-market price is often a bulk rate: *"$10 each, 5 for $40."* Dividing 40 by 5 produces **$8 — a number the seller never said**.

**The app does not do that arithmetic, at all.** The user enters the figure **they** want compared; the seller's terms ride alongside **verbatim**, labelled as the source of that figure. The record reads *"$8 — your figure, from: 5 for $40"*, and the $8 is attributable to the person who chose it.

**Why not just divide.** It looks like arithmetic and it is a judgement: whether the bulk rate is even available for one book, whether the other four are wanted, whether the seller would split it. The division smuggles all of that in behind a number that renders exactly like a fact. **Brief rule 3 says the asking price is attested, never derived — and $40 ÷ 5 is derivation wearing attestation's clothes.**

**Consequence:** the per-book figure exists nowhere in state and nowhere on the surface unless the user typed it.

## D13 — Counts, never percentiles (2026-09-14)

**Ruled on R3's Fork E.** The comparison reports how the ask sits among the sales. *"47 sold below · 2 at your price · 49 above"* is a **count**: a fact about the rows, checkable by pointing at them.

***"Cheaper than 52% of sales"* is the same fact dressed as a score.** It reads as a grade out of a hundred, and it invites the single inference this product exists to refuse: *"so it's about average."* D8 forbids the average; a percentile reintroduces it by implication and without the arithmetic being visible.

**The rule: a count is a fact and may render; a ratio derived from the scatter is a verdict and may not.** No percentile, no percentage, no rank-as-score, no "better than", no band.

**The test, for the next case that is not this one:** can the user verify it by counting rows on the surface? A count can. A ratio requires trusting a computation they cannot see, which is exactly what a scatter was chosen over a modelled value to avoid.

## D10 — A group exists only where a field exists that constitutes it (2026-09-13)

**Ruled on R2b's probe, and it resolves a collision between two already-ruled forks.** Fork E had ruled *"raw and slabbed are two markets; show them as two groups, never blend."* Fork A had ruled **one stage**. The probe then showed the search tier returns **no Grade, no Certification and no Variant field** — **the split E requires is not in the data A buys.** Both were ruled before anyone had seen a real result.

**The ruling: the app does not render the groups, and says why.** One scatter; each comp beside **the seller's own title, verbatim** — which is where the grade actually is, as free text in no consistent format (*"VF- 7.5"*, *"GD"*, *"VF- 1 CF staple detached"*) — and the surface **states plainly that this tier cannot tell raw from slabbed**. The human reads the titles and splits them by eye. That is the same division of labour as the grade and the asking price (brief rule 3): the app supplies what it can evidence, the person supplies the judgement.

**What was rejected, and it is the interesting half.** Parsing `CGC`/`CBCS`/`PGX` out of the title would have produced two groups for free. It fails in a **known adversarial direction**: sellers write *"CGC READY"*, *"would grade 9.8"*, *"CGC candidate"* on **raw** books precisely to borrow a slab's credibility. The heuristic would move cheap raw copies **into** the slabbed group — **lowering the slabbed floor and the raw ceiling at once, corrupting both groups rather than one**, and doing it invisibly behind a layout that looks authoritative. A heuristic that fails *randomly* degrades; one that fails *where sellers have an incentive to push it* is being aimed.

**The general rule — and it is D9's shape applied to data.** D9: a **credential field** exists only where a call exists that uses it. This: a **grouping exists only where a field exists that constitutes it.** An absent distinction is **stated as absent** — never inferred from free text, never implied by a layout. **A group header is a claim about what the app knows.**

**Not deferred, and the door is named.** The **Aspect Filter** (a JSON object input, and eBay aspects *are* Item Specifics) may filter on Grade or Certification as a *query parameter*; the **$0.005 deepening tier** definitely reaches the listing page. Either would supply the constituting field, and either turns the groups back on. **Until one is probed, the groups do not exist.**

### The door was probed, and it is shut — measured, not inferred (2026-09-13)

**The Aspect Filter reaches eBay, but not for the fields this needed.**

| aspect | result | reading |
|---|---|---|
| `{"Publisher":"Marvel Comics"}` | ~100 | uninformative **by construction** — a true value cannot separate a working filter from an ignored one (D5's amendment) |
| `{"Publisher":"DC Comics"}` | **ZERO** | **live and narrowing** |
| `{"Grade": …}` | 100, unfiltered | **ignored** — never reaches eBay's aspect layer through this actor |
| `{"Certification": …}` | 100, unfiltered | **ignored** |

**So D10 stands on measurement rather than on inference, and the cheap escape is gone.** Grade and Certification are not queryable here, and **deepening would buy a field that cannot be queried anyway**. Fork E stays closed.

**And a standing fact that closes it more firmly than the measurement does.** Even a *working* Grade aspect would have covered only the slabbed minority: **most raw books are sold by people who never fill a structured grade field at all.** The structured path was never going to reach the majority of this market. **Grade lives in the title text regardless** — which is what D7 ruled from vocabulary alone, now with evidence behind it.

### The Publisher aspect is REFUSED, and it is refused *because* it works

Publisher is live and narrowing, so using it looks free. **It is not.** An eBay aspect is populated by the seller, and **the sellers who fill structured fields are the slabbed, professional minority** — the same population the standing fact above identifies. Filtering on Publisher would **silently drop the raw listings whose sellers left it blank**, pulling the scatter toward the graded end and thinning exactly the half a flea-market buyer is standing in front of.

**This is the CGC-READY heuristic's corruption reached by a different route.** That one mislabelled comps; this one **removes them before they are ever seen** — and a missing row leaves no trace on the surface, where a mislabelled one at least renders. **A filter that narrows correctly can still corrupt, by selection.**

**Gated, not merely noted** (`CQ3`, defect row 41): the request body carries **no `aspectFilter` at all**. A future session will rediscover that Publisher works, and the gate is what tells it why that is not the question.

## D7 — Never map a marketplace condition to a collectors' grade (2026-09-13)

**A rule, not a slice parameter.** eBay's condition field is a generic marketplace vocabulary — **Brand New / Like New / Very Good / Good / Acceptable** — that was never built for comics, and the collector community said so when eBay imposed it. **Mapping "Very Good" to VG 4.0 would be a false translation between two scales that share words and mean different things.**

- The condition label and its numeric code are used **only to split raw from slabbed** (with Certification and Certification Number from Item Specifics when a deepening stage exists).
- **The seller's own words are shown verbatim**, never restated in grade vocabulary.
- **No comp is ever assigned a grade the listing did not state**, and a comp without a stated grade stays ungraded rather than being placed on the ladder.

**Family: HealthTracker's ordinal contract (HT-D52).** *When a scale is defined elsewhere, you snap to its points or you do not compute on it at all.* There it forbade averaging Bristol types; here it forbids translating one scale's words into another's numbers. Same refusal, different vocabulary.

**And it is the grade half of brief rule 3:** the grade is the user's to supply. A grade inferred from a marketplace dropdown would be the app guessing exactly what it promised never to guess.

### Confirmed empirically — and one clause of it corrected (2026-09-13)

**The probe measured what this entry argued.** Three books, all at condition **`Pre-Owned / 3000`**, sold for **$9, $29.99 and $89** — a **10× spread at an identical code**. D7 was reasoned from a vocabulary mismatch; it is now a measurement, and it lands harder than the argument did: the condition field does not merely *translate badly* into grade vocabulary, it **carries no grade information whatsoever**.

**Corrected.** The first bullet said the condition label and code are used *"only to split raw from slabbed."* **They cannot do even that.** At the search tier every comic is `Pre-Owned`, slabbed or not, and a result carries **no Certification field and no Item Specifics at all**. The bullet described a capability the source does not have — it was written from the actor's *advertised* field list, before a real run.

**What this entry forbids stands unchanged. What it permitted was never available.** See **D10**.

## D8 — A scatter is the claim; a single number derived from it is not (2026-09-13)

**A rule, not a display preference.** Sold comps are individual sales at whatever grades happened to sell. **No average, no midpoint, no "estimated value" — anywhere.**

- What renders is **the scatter**: each sale with its date and its stated grade, grouped raw and slabbed, **never blended** (two markets).
- **Below N = 5 comps no range is shown at all**; 3–4 render as individual sales; below 3 the surface **says so**.
- **No ladder is synthesised** from sparse solds, and no grade is interpolated between them.

**Why it is a rule.** A single number derived from a sparse scatter *reads* as a valuation — the one claim this product exists to refuse (brief rules 4 and 7, D2's refusal of model-supplied value). The arithmetic would be easy and the sentence it produces would be false: the data cannot support it, and a user at a table cannot see that from the number alone.

**The honest output stays the comparison:** *"N recent solds at $X–$Y, they're asking $Z, you'd grade it W"* — three stated quantities from three different sources, none of them collapsed into one.

### Amendment — where the markets cannot be separated, the RANGE goes too (2026-09-13)

**This entry permits a range at N ≥ 5** — *"N recent solds at $X–$Y"*. That range is the scatter's **extent**, not a central tendency, which is exactly why it survived the no-average rule above.

**It does not survive a *mixed* scatter.** eBay's search tier carries no field that separates raw from slabbed (**D10**), so the endpoints of $X–$Y would be drawn from **two different markets**. The probe's own scatter: **9 · 16.21 · 18.88 · 29.99 · 40 · 49.99 · 89 · 145**. *"$9–$145"* describes no book anyone can actually buy. A range whose ends come from different markets is a **span, not a claim** — and on a surface it reads as a valuation in precisely the way an average would, which is the harm this entry exists to prevent.

**So: at a tier that cannot separate the markets, no range is computed at any N.** Individual sales render, each beside the seller's own words, with the count and the window riding on them. **The range returns when — and only when — a field exists that says which market a comp belongs to.**

**Recorded as a correction to my own framing, not to the subscriber's ruling.** The fork was put to them with the claim that *"D8 already forbids computing a range at all."* **It does not**, and this entry is the proof: it forbids the average, the midpoint and the estimated value, and permits the min–max span. The ruling was made on a description of D8 that was wrong. The stricter reading that ruling *implied* is what gets built — but the error is recorded here rather than the entry being quietly reshaped to match what I said about it. **A decision log that edits itself to agree with the last thing said about it is not a record.**
