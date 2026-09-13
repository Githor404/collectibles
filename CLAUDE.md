# collectibles — Agent Brief (v1)

A flea-market triage tool for comics. **Photo → identify → price range across grades → the human decides.** It is **not a valuation oracle** and **not a marketplace**.

Structure and discipline are ported from HealthTracker (`../healthtracker`). The domain and the data source are new. Ruled contracts live in `DECISIONS.md` and bind equally with this brief.

## Status

**R1 — identification — is built and gated** (D2, 2026-09-12), awaiting review. Photo → a confirmed reading → the PriceCharting search string it implies.

**R1 is a milestone, not a release: there is no price in this build.** It stops at the identity, saves nothing, and says so where the result is. The port's infrastructure and gates are D1 / `GATES.md`. R2 — resolving a reading to a PriceCharting product — is blocked on a live search probe only the subscriber can run.

## Domain rules (from the brief that opened this repo, 2026-09-11)

1. **The model perceives; the deterministic layer prices.** Vision (BYOK Grok) identifies what is *printed or visible*: title, issue number, publisher, cover date, **cover price** (a printed fact on the cover, not a valuation — and **never a price from a sticker, bag, board or label**, which is the asking price and only the user supplies it: D2's R1.1 amendment), and visible variant markers (newsstand vs direct, foil, facsimile). **It never returns a market value, and never a grade.** This is HealthTracker's D8 rule transposed, and a value in a reply is refused actively and said so, not dropped as a side effect (HT-D45 Fork H).
   **The brief's "whether it looks like a key issue" was DROPPED by D2/C1** — market memory is not a property of a photograph, and it is on the refusal list for that reason.
2. **The anchor is GRADE, not quantity.** A phone photo cannot establish grade, so the output is a **range across plausible grades**, never one number. **The user picks the grade; the app never guesses it.**
3. **Two things only the human can supply: the grade, and the ASKING PRICE** (added 2026-09-12). The asking price is what the seller wants — a sticker, a sign, a verbal quote, or a bulk rate ("3 for $10"). It is **attested by the user, never read from the photo**.
4. **The triage output is a COMPARISON, not a valuation:** *"raw modelled at $X, they're asking $Y."* Without the asking price the app values a book and leaves the user to do the comparison in their head — and that comparison **is the decision** the tool exists to serve.
5. **Cover price and asking price must never be conflated, in the record or on a surface.** The cover price is **printed on the book, read from the photo, identification data** (`cover_price`, D2). The asking price is **the seller's number, attested by the user, pricing data**. They are different kinds of fact with different provenance, and a record that blurs them is a record that cannot be trusted about either.
3. **Identity is confirmed, never assumed** (HT-R30's identity-first rule, for the same reason). A confidently wrong identification attached to a confident price is *the* failure mode. The evidence: PriceCharting's own photo appraiser returned the same wrong book for three different covers, with a value and no uncertainty shown.
4. **Guide values, not comps, and the product says so where the number is.** The PriceCharting API has **no historic prices and no sold comps** — "The API and CSV only support current item values in various grades and conditions. Historic prices and historic sales are not supported." (docs, 2026-09-11).

## Data source: PriceCharting Prices API (verified against the live docs 2026-09-11)

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

BYOK: the user's Grok key and PriceCharting token, each in its own `localStorage` key, **outside the state object**, never exported, never logged, egress only on explicit action. **This does not scale.** Before the token runs in any browser whose user is not its subscriber, a server must hold it and meter calls. The provider table plus the single `egress()` function make that a configuration change.

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
- Gate artifacts (browser profiles, defect-pass backups) live under `tests/.tmp/`, never `%TEMP%`.
- Ask before adding scope; name conflicts between patterns rather than silently resolving them.
