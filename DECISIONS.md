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
- **The service worker and HT-D6's update machinery** (`SHELL_HASH`, precache and version-drift gates, changelog notice). These were not on the port list. They arrive together, as one slice, if installability is wanted. **When they do, HT-D45 Fork G's explicit SW bypass for cross-origin and non-GET requests arrives with them.** A cache-first worker that could see a request URL carrying the token would contradict this entry.
- **The copy-prompt card** (HT-D11 / HT-D63). With no vision contract ruled there is no prompt to copy. The **paste box is ported**, because the fallback needs somewhere to put the raw reply. Whether collectibles has a no-key vision floor at all is a question for the identification slice.
- **HT-D7 migration machinery.** There is nothing to migrate at schema v1. The forward-version guard is ported.
