# collectibles — Agent Brief (v1)

A flea-market triage tool for comics. **Photo → identify → price range across grades → the human decides.** It is **not a valuation oracle** and **not a marketplace**.

Structure and discipline are ported from HealthTracker (`../healthtracker`). The domain and the data source are new. Ruled contracts live in `DECISIONS.md` and bind equally with this brief.

## Status

**R1 — identification — is built, gated and deployed** (D2 + R1.1 + R1.2), and has passed a two-capture device test. Photo → a confirmed as-printed reading → the catalog query it implies.

**R1 is a milestone, not a release: there is no price in this build.** It stops at the identity, saves nothing, and says so where the result is. The port's infrastructure and gates are D1 / `GATES.md`.

**R2 is two slices, and R2b goes first** (ruled 2026-09-13). **R2a** — canonical identity via the Grand Comics Database — is **ruled and deferred (D6)**: GCD sends no CORS headers, and the proxy that would fix it is the first infrastructure in either project that must exist and stay up, seeing every lookup against a no-telemetry promise. **R2b** — price via eBay sold comps through an Apify scraper — is **built, gated and probed** (2026-09-13); Apify **is** callable from the page. PriceCharting stays deferred (see Data sources). **D4's query rules are adopted now for any catalog search**, eBay's title filter included.

## Domain rules (from the brief that opened this repo, 2026-09-11)

1. **The model perceives; the deterministic layer prices.** Vision (BYOK Grok) identifies what is *printed or visible*: title, issue number, publisher, cover date, **cover price** (a printed fact on the cover, not a valuation — and **never a price from a sticker, bag, board or label**, which is the asking price and only the user supplies it: D2's R1.1 amendment), and visible variant markers (newsstand vs direct, foil, facsimile). **It never returns a market value, and never a grade.** This is HT-D8 transposed, and a value in a reply is refused actively and said so, not dropped as a side effect (HT-D45 Fork H).
   **The brief's "whether it looks like a key issue" was DROPPED by D2/C1** — market memory is not a property of a photograph, and it is on the refusal list for that reason.
2. ~~**The anchor is GRADE, not quantity.** A phone photo cannot establish grade, so the output is a **range across plausible grades**, never one number.~~ **The user picks the grade; the app never guesses it.**
   **AMENDED 2026-09-13 — at this tier grade is ADVISORY, not an index.** The struck wording was written for PriceCharting's **grade-keyed ladder**, which this build does not use. Sold comps carry **no grade field** (D10), so a grade the user picks has nothing to index and no range across grades can be produced from them. What survives: the user's grade is **recorded beside the asking price as their attestation** — the record of what a human judged, and what a later deepening tier would key against if one is ever built. The surface **states plainly that comps carry no grade field**, so the user reads grade signal from the seller titles themselves. **The scatter is NEVER filtered by a grade parsed from title text** — D10's adversarial reason applies exactly: *"CGC 9.8 READY"* sits on raw books, so a title-text grade filter selects wrongly in the direction sellers push it.
3. **Two things only the human can supply: the grade, and the ASKING PRICE** (added 2026-09-12). The asking price is what the seller wants — a sticker, a sign, a verbal quote, or a bulk rate ("3 for $10"). It is **attested by the user, never read from the photo**.
4. **The triage output is a COMPARISON, not a valuation:** ~~*"raw modelled at $X, they're asking $Y."*~~ Without the asking price the app values a book and leaves the user to do the comparison in their head — and that comparison **is the decision** the tool exists to serve.
   **AMENDED 2026-09-13 — the comparison is an ASK AGAINST A SCATTER.** The struck phrasing assumes a single modelled number. D8's amendment removed the range at any N and D10 removed the groups, so **there is no $X at this tier** and the original was written for a ladder that does not exist here. What renders instead: **where the asking price falls among the sorted sold prices**; **how many sold below it and how many above**, in the stated window; and **the nearest comps by price, with their seller titles verbatim**. No midpoint, no average, no "fair", no "estimated value", no synthesised step. The user reads where **$10** sits against nine sales between **$9 and $145** and draws the conclusion — **that reading is the whole grammar of the product**, and it is the thing the app must not do for them.
5. **A marketplace condition is never a comics grade** (D7). eBay's *Brand New / Like New / Very Good / Good / Acceptable* is a generic vocabulary that shares words with the grading scale and means different things. **Measured 2026-09-13: it cannot even do that.** Three books at an identical `Pre-Owned / 3000` sold for **$9, $29.99 and $89**, and a search result carries **no certification field at all** — so at this tier nothing splits raw from slabbed and the app says so where the numbers are (D10). The seller's words show verbatim; no comp is assigned a grade its listing did not state. *(HT-D52's rule: when a scale is defined elsewhere, snap to its points or don't compute on it.)*
6. **A scatter is the claim** (D8). Sold comps are individual sales at whatever grades happened to sell — **no average, no midpoint, no "estimated value"**, no ladder synthesised from sparse data. **No range at any N** while the markets cannot be separated (D8's amendment): the endpoints would come from two different markets — the measured scatter runs **$9 to $145** — and a span whose ends belong to different markets is not a claim, it just reads like one. Individual sales render; **below 3 the surface states absence** and says that a thin result is not a low price.
7. **Cover price and asking price must never be conflated, in the record or on a surface.** The cover price is **printed on the book, read from the photo, identification data** (`cover_price`, D2). The asking price is **the seller's number, attested by the user, pricing data**. They are different kinds of fact with different provenance, and a record that blurs them is a record that cannot be trusted about either.
8. **Identity is confirmed, never assumed** (HT-R30's identity-first rule, for the same reason). A confidently wrong identification attached to a confident price is *the* failure mode. The evidence: PriceCharting's own photo appraiser returned the same wrong book for three different covers, with a value and no uncertainty shown.
9. **Guide values, not comps, and the product says so where the number is.** The PriceCharting API has **no historic prices and no sold comps** — "The API and CSV only support current item values in various grades and conditions. Historic prices and historic sales are not supported." (docs, 2026-09-11).

## Data sources (re-scoped 2026-09-12)

**PriceCharting is deferred, not adopted.** Its API needs a ~$600/year subscription and its data is the weaker kind — modelled current values, **no sold comps, no history**. That commitment is not made before the app has been used at a table. It stays a **named provider behind the same seam** (D1's provider table), and the ladder mapping below is kept for the day it is subscribed.

**Identity comes from the Grand Comics Database** (free, official, JSON, no key) — R2a, pre-registered in `GATES.md`. **Price comes from eBay sold comps** via an Apify scraper, pay-per-lookup — R2b, **built: `caffein.dev~ebay-sold-listings`, $4.00 per 1,000 results** (~$0.40 a lookup), free tier $5.00 and no payment method required. Sold comps are *actual sales*; everything below about PriceCharting describes *guide values*, and the two are different claims that must never share a label (brief rule 7's shape, applied to sources).

### PriceCharting, if it is ever subscribed (verified against the live docs 2026-09-11)

- Base `https://www.pricecharting.com`. Auth is the 40-character token as the **`t` query parameter**. JSON responses carry `status: success|error`; an error adds `error-message` with HTTP 4xx/5xx.
- `/api/products?q=` returns up to 20 matches: **the candidate list**. `/api/product?id=` returns **the full grade ladder** for one book.
- **Prices are integer pennies** (1732 = $17.32).
- **1 call per second, hard.** "Any more than that and your calls will be blocked and your account permissions revoked if it persists." Enforced in `egress` (D1).
- Comic grade mapping (docs wording is "graded X by a grading company"):

| field | grade | field | grade |
|---|---|---|---|
| `loose-price` | ungraded (raw) | `condition-16-price` | 9.0 |
| `condition-9-price` | 2.0 | `box-only-price` | 9.2 |
| `condition-13-price` | 3.0 | `condition-17-price` | 9.4 |
| `cib-price` | 4.0 / 4.5 | `condition-10-price` | 9.6 |
| `condition-14-price` | 5.0 | `manual-only-price` | 9.8 |
| `new-price` | 6.0 / 6.5 | `bgs-10-price` | 10.0 |
| `condition-15-price` | 7.0 | | |
| `graded-price` | 8.0 / 8.5 | | |

**Open, not ruled (for the pricing slice):** every non-loose field is documented as a value for a copy *graded by a grading company*. A raw book the user judges to be 9.4 is not a slabbed 9.4. How the range is labelled against that is the pricing slice's first fork.

## Credentials (D1)

BYOK: each credential in its own `localStorage` key, **outside the state object**, never exported, never logged, egress only on explicit action. **Two roles have a settings field — vision and comps** — D9: a credential field exists only where a call exists that uses it. R2b built the comps call, so its field arrived **in the same commit, never ahead of it**; the deferred price provider keeps its machinery (provider row, 1 call/s pacing, redaction, the `auth:'none'` proof) and offers no input. **The comps token can SPEND** (~$0.40 a lookup), so its card says so — the warning is keyed to the provider row, not to a role name. A token saved by an earlier build appears in Storage with a way to delete it, and only when it exists. **This does not scale.** Before the token runs in any browser whose user is not its subscriber, a server must hold it and meter calls. The provider table plus the single `egress()` function make that a configuration change.

## Architecture constraints

Static, no build step, vanilla HTML/CSS/JS in a handful of files, no dependencies. `localStorage` primary with a truthful storage badge and memory fallback. Every storage key is prefixed `collectibles-` (a shared GitHub Pages origin shares storage with HealthTracker). **Every network call goes through `egress()`** (census-gated). Mobile-first, light and dark tokens, safe-area insets, no web fonts. No service worker yet (D1, deliberately not ported).

## Inherited record

`INHERITED-DECISIONS.md` and `INHERITED-GATES.md` are HealthTracker's log and gate record, **byte-identical to `healthtracker@dcf3d78`**. They are **reference, not governance**: the reason ported code is shaped as it is. Cite them as `HT-Dnn` / `HT-Rnn`. **Do not simplify a ported mechanism without reading the entry that produced it.** Code comments carrying an `HT-` reference mark exactly those mechanisms: the decode leash (HT-D47), two clocks (HT-D48), merge-only credential writes (HT-D49), one modal and three states (HT-D51), the EXIF pin (HT-D58), keeping the first reply (HT-D64), the trace (HT-D65).

## Working rules

- **HealthTracker is read-only from here.** Copy out, never write in. Flag defects found in ported code for the other repo; do not fix them there.
- Small single-purpose commits. Data-loss implications are stated and ruled before touching storage, export or restore.
- Pre-registered, re-runnable gate evidence, and **HT-D60 binds** (adopted in D1): a new or changed gate is not evidence until it has been run against the defect it closes and seen to fail, **and its fixture must be capable of exhibiting that failure** (Clause 4).
- **Gate a consumer across the RANGE its contract permits (D3), never on one specimen.** Where a field is promised *as printed*, the case carries the forms that promise allows — bare, prefixed, doubled, absent — each with its asserted output, and a control in the other direction. A contract and its consumer can disagree about one field while both sides pass their own assertions; that is what D3 exists to stop.
- Run gates through `bash tests/run-all-gates.sh` (presence + verdict, or fail). The assertion count is pinned and the gate-script manifest is a census; both are re-pinned deliberately, in the same commit as the change.
- **COMMIT BEFORE RUNNING THE DEFECT PASS.** It mutates `app.js`, `index.html`, `CLAUDE.md` and `GATES.md` — the files the work lives in. Committed, a clobber costs one `git checkout HEAD -- <file>`; uncommitted, the working tree is the only copy of the work and a mutation tool is actively rewriting it.
- **The measured costs — do not re-derive them by feel.** Each is approximate and carries the size it was measured at. A full suite run (`run-all-gates.sh`) is **~3m05s** (185s at 508 assertions, v0.9.1). That is the data-layer harness, **~15s**, plus the layout gate, **~170–185s** since it began driving C1's save through real taps. It was ~140s before that at both 350 and 506 assertions, because it runs none of those assertions; what moves it is what the gate itself drives. Defect rows do not enter it. A full defect pass was **~8.5 min at 41 rows**: ~35s fixed, ~12s per ordinary row. **A row that runs the layout gate costs ~175s** (rows 84–99, v0.9.1). **The pass now has 99 rows, 19 of them layout rows, and has not been measured at that size**; the layout rows alone come to ~55 min. A commit is **~10s**. **A timer is not a measurement if the machine slept under it**: check the Kernel-Power 506/507 events before recording a figure that disagrees with the rest. On 2026-09-13 the pass was estimated at *"~250s per row"* — **wrong by 20×** — and it was the estimate, not the machine, that produced a day of avoidance: the full pass went unrun (leaving thirty rows unverified against changed code), invocations were sized to ~500s against a 580s ceiling and two background jobs were killed there, and work was batched into long uncommitted stretches to amortise a cost that did not exist. **A wrong cost estimate changed the working pattern, and the working pattern produced the losses.** **A right number under the wrong name is the same failure.** Until 2026-09-16 this line said *"a suite run is ~12s"*. That was the harness's figure, and the rule above sends you to a suite that takes ~2m40s. It went three days unnoticed, and the first attempt at a correction blamed the defect-row count, which does not enter the suite time at all. Measure a number before letting it shape how the work is done, and record what it measured and at what size.
- **Commit per ruling, not per slice.** R2b landed as a single commit carrying a new decision, three amendments, the build, thirteen gates and eleven defect rows. That fusion is *why* six hours of work sat uncommitted in a tree being rewritten.
- Gate artifacts (browser profiles, defect-pass backups) live under `tests/.tmp/`, never `%TEMP%`.
- Ask before adding scope; name conflicts between patterns rather than silently resolving them.
