# Tests

Gate evidence lives here so it is **re-runnable by any future session**, not attested once. No Node, no build step — just a headless browser. Ported from HealthTracker; the reasons behind each mechanism are in `../INHERITED-DECISIONS.md` (cited `HT-Dnn`).

## Run everything

```sh
bash tests/run-all-gates.sh
GATE_TIMEOUT=900 bash tests/run-all-gates.sh   # per-gate seconds, default 600
```

Every gate must print a `GATE: PASS` or `GATE: FAIL` line. One that prints neither **fails by name**. There is no third outcome called silence (HT-D56):

| outcome | verdict |
|---|---|
| hung past the timeout (`rc=124`) | FAIL — no verdict will ever arrive |
| exited, printed no `GATE:` line | FAIL — present but speechless |
| printed `GATE: FAIL` | FAIL |
| `GATE: PASS` but exited non-zero | FAIL — the two disagree |
| `GATE: PASS` and exited 0 | PASS |

## The real numbers — measured, and why a wrong estimate was expensive

| operation | measured |
|---|---|
| one suite run (`run-data-layer.sh`) | **~12s** |
| full 41-row defect pass | **~8.5 min** — ~35s fixed + **~12s per selected row** |
| a two-row subset (`ROWS=31-32`) | **59s** |
| `git commit` before a pass | **~10s** |
| the layout gate (`layout-gate.ps1`) | **~140s** — real-time CDP, Chrome bring-up, four viewports |
| a defect row that runs the layout gate | **~145s** — worth about **twelve** ordinary rows |

**These are measurements. Do not re-derive them by feel.** On 2026-09-13 the working figure was *"~250s per row"*, inferred from elapsed times that were in fact a **fixed** cost — `run_dl` was unguarded, so every invocation ran the full suite for all 40 rows whatever `ROWS=` said (see `../GATES.md`). The estimate was wrong by **20×**, and the error was not academic:

- A full pass looked like **2.7 hours**, so it was never run. Thirty rows sat unverified against code that had changed under them — **HT-D60 Clause 4 live in the repo**, which is the one thing the defect pass exists to prevent.
- Every invocation was sized to "two rows at ~250s", putting each at ~500s against a 580s ceiling. **Two background jobs were killed at that boundary**, and one of those kills is what left stale backups on disk for a later step to trust.
- Work was batched into long uncommitted stretches to amortise a cost that did not exist: **one commit in six hours**, so hours of work lived only in a working tree that a mutation tool was actively rewriting.

**A wrong cost estimate changed the working pattern, and the working pattern produced the losses.** At the real numbers both of that day's incidents cost minutes: commit first (10s), run the pass (8.5 min), and a clobbered file is one `git checkout HEAD -- <file>` away.

**So: measure a number before letting it shape how you work.** The evidence was on screen all day — 497s, 504s, 494s, 542s, 541s, for 2, 2, **3**, 2, 2 rows. A constant elapsed time with no relationship to the count is a fixed cost, not a per-unit one, and reading it as per-unit is what turned an eight-minute check into an afternoon of avoidance.

## `run-data-layer.sh` — the harness, plus the static checks that guard it

In order, each failing the whole gate:

1. **Gate-script census** (HT-D53): the `*-gate.ps1` set must equal a pinned manifest. A quarantined gate does not run and does not say so; naming it ends the hunt.
2. **Port residue** (D1): no `healthtracker-` storage key, no HT console seam, no meal-domain identifiers in `app.js` / `index.html`. The match is on code shapes, with a planted control.
3. **Egress census** (`check-egress.sh`, D1): every network primitive in the shell is enumerated and mapped to its enclosing function. **Exactly one site, inside `egress()`.** Planted control first.
4. **Cross-reference census** (`check-refs.sh`, D3): every `Dnn`, `HT-Dnn`, `HT-Rnn`, `Rn` and `rule(s) N` cited in `CLAUDE.md` / `DECISIONS.md` / `GATES.md` must resolve to a heading or rule that exists, and the brief's rule list must be 1..N with no duplicates or gaps. Planted control first. **It catches unresolvable citations and an inconsistent list — not a citation that resolves to the wrong thing.**
5. **`data-layer.test.html`** in headless Chrome: the real `app.js`, plus the real `index.html` in an iframe. The **executed assertion count must equal the pin** (`EXPECTED_ASSERTIONS`), so a silently dropped case fails the gate.

**Harness limitation (HT-D47), stated rather than hidden:** `createImageBitmap` never settles under `--virtual-time-budget`. The harness therefore proves the **leash** and the fallback decoder, and cannot exercise the preferred decoder. `layout-gate.ps1` runs in real time and does.

**The vision contract is unruled (D1).** The capture-chain cases install a synthetic contract through `CT.setVisionContract`. They prove the chain, never a contract.

## `layout-gate.ps1` — the claims that only a viewport can settle (HT-D51)

**Renamed from the capture-outcome gate on 2026-09-13.** It had already outgrown that name — repointed for R1's identity draft, and now measuring R2b's comps scatter. One CDP harness, honestly named: a sibling would have duplicated ~150 lines of scaffolding, and the first fix landing in one copy and not the other is D3's family.

**Why the second claim exists.** R2b's comps row shipped as three inline spans with **no CSS at all** and reached a phone as one run of text — `"$52.46The Incredible Hulk #271 … 198217/08"`, the title's year merging into the date. **Every data-layer assertion was green while that shipped**, because `--dump-dom` sees markup and cannot see geometry. Emitting a class is not shipping a layout, and asserting the class exists is not asserting it separates anything.

**The comps claims**, measured at all four viewports: the price, date and title rectangles are **disjoint** (touching edges allowed, overlap is exactly what "ran together" looks like); the title's top sits **below both**; and the page does not overflow horizontally. The modal is dismissed first — `Measure-Pending` leaves it open over a hung fetch, and a rect is still computed for an element underneath it, so measuring without dismissing would report a correct layout while the user sees a covered one.

**Proven against its defect** (row 45): restoring the concatenation gives `NOT MEASURABLE -- a field is not its own element: price=false date=false title=false` and `LAYOUT GATE: FAIL`, exit 1.

"Exactly one outcome, in view" is likewise a **layout** claim. The gate drives the shipped capture path against the real `index.html`, with fetch stubbed, at 360×690, 390×745 and 1200×900, and asserts per state:

- **success**: the first result row and **both** footer actions are fully in view with the page unscrolled; actions ≥ 44 px;
- **success, long result**: the body scrolls and the footer **does not**;
- **failure**: the stated message plus *Try again* and *Paste the reply by hand*, in view;
- **pending**: the counted spinner and the cancel, in view;
- and in every state the capture surface carries none of it.

## `defect-pass.sh` — the gates, run against the defects they close (HT-D60)

```sh
bash tests/defect-pass.sh
```

**A new or changed gate is not evidence until it has been run against the defect it closes and seen to fail.** HealthTracker records that this rule is not machine-enforced there, and names the missing mechanism — *"a mutation pass: a runner that flips a known set of properties false and asserts that a named gate fails for each"*. This is that runner.

Each row plants one defect in the shipped file, runs the gate, and prints the verdict **and the first case that failed by name**. Expect every row to FAIL, each naming its own case. Two outputs mean trouble:

- **`(NOTHING NAMED MATCHED -- SUSPECT THE FIXTURE)`** — the gate failed but the case written for that defect never spoke. Clause 4's own diagnostic; it happened once here (see `../GATES.md`).
- **`!! MUTATION DID NOT APPLY`** — the code moved and the mutation no longer targets anything, so the row proves nothing.

Every mutated file (`app.js`, `index.html`, `CLAUDE.md`, `GATES.md`) is restored after each row and **verified against this run's pre-run copy**, with an exit trap so an interrupted run cannot leave a mutation behind. Verify a restore with `git status` / a comparison, never with the next run.

**Restore by COPY, never by `git checkout --`.** One row once restored `GATES.md` with git, which resets from **HEAD** — so it silently discarded edits made minutes earlier and not yet committed. A restore must return a file to **what it was**, not to what was last committed. The `mutate` helper compares each file against that same copy, so a mutation that fails to apply says so instead of producing a row that proves nothing.

**And the copy must be from THIS run — the rule above is not enough on its own.** It happened again, differently. A backgrounded pass was killed by the OS partway through, and a later step found the `.orig` files, compared `app.js` against one, saw a large difference, read it as mid-mutation corruption, and restored — **from a backup three hours old, belonging to a previous run**. Three hours of uncommitted work in four files were overwritten. The restore was by copy. It was verified by `cmp`. It returned the file to what it was *at some point*, and that was the whole defect.

So:

- **A backup must not outlive its run.** `defect-pass.sh` now deletes `tests/.tmp/*.orig` on a clean exit, which makes their **presence meaningful**: a leftover `.orig` means *a run is in progress or was killed*, never *a run finished*. A kill still leaves them, and that is precisely the point.
- **Use `bash tests/restore-backups.sh`, not `cp`.** The freshness rule is now code rather than a procedure — it refuses any backup that predates HEAD or exceeds an age limit, naming the file and the reason, and it is dry-run by default (`--apply` to act). It has been run against its own defect: a back-dated `app.js.orig` produces `FRESHNESS GATE: FAIL - app.js.orig is OLDER THAN HEAD`, exit 1, nothing written; fresh backups pass. Its limits are listed at the foot of the script and in `../GATES.md`.
- **Check the timestamp before trusting a backup**, and compare it against the work you are about to overwrite. The `.orig` files here were stamped ten minutes *before* the last commit; the file they clobbered was three hours *after* it. One `ls` would have caught it.
- **The gate is weakest where you need it most.** Its strongest signal is "newer than HEAD", so a repo committed once in six hours gives it almost nothing to work with. **Commit before running a pass**: it costs ten seconds and retires this entire failure class, because a committed file makes `git checkout HEAD -- <file>` a correct restore rather than a destructive one. The rule above — *restore by copy, never by `git checkout --`* — is a workaround for uncommitted work, not a principle.
- **`git status` is the cheap sanity check.** A file you have been editing all session that suddenly shows as *unmodified* has not been repaired — it has been reverted.
- **Recovery, when it happens:** the survivors are whatever is not in `MUTATED`. Here that was `DECISIONS.md` and everything under `tests/`, so the rulings, the cases and the pin all lived and only the implementation had to be rebuilt.

**NEVER RUN TWO PASSES AT ONCE — and the script now refuses to.** Both write the *same* `tests/.tmp/*.orig` backups, so whichever finishes first deletes them out from under the other, which is then left with a mutation applied and nothing to restore from. It happened: a backgrounded row-37 run was still in its cleanup when a rows-38-39 run started; the older run's trailing `rm -f *.orig` removed the newer run's backups mid-flight; all four files reported `RESTORE FAILED`, and two mutations were left live in `app.js`.

- **The lock.** `defect-pass.sh` writes its PID to `tests/.tmp/.pass.lock` at start, refuses to run if a live PID holds it, and clears it in the exit trap. A second pass now exits 2 instead of causing damage.
- **A process check is NOT a substitute, and trusting one is what caused this.** The running process is `bash`, so `ps | grep defect-pass` returns **nothing** while a pass is very much alive. It reports safe at exactly the moment it matters.
- **The reliable signal is the runner's own bookkeeping: a background job is running until its completion notification arrives.** Not until a process list looks quiet, not until the log stops growing.
- **Recovering with no backup at all:** every mutation has a known, greppable signature (`const warn = (role === 'prices')`, `), "comic"]`, `aspectFilter`, `_slab.concat(_raw)`, …). Sweep for all of them, reverse the ones found by hand — watching for incidental changes the mutation made, such as swapping `'` for `"` — and then **let the suite prove it**: a surviving mutation fails a gate by name, so a green run is the evidence that the reversal restored the original rather than something merely plausible.

### `ROWS=` must cover every way a row plants, not just `mutate()`

`ROWS=31-40 bash tests/defect-pass.sh` runs a subset, which is how the pass fits on a machine where each row costs ~250s. The filter hooks `mutate()` and `report()` — and **two rows do not plant through `mutate()` at all**: one appends `function phoneHome(u) { return fetch(u); }` to `app.js` with `>>` (to fail the egress census), another `mv`s the gate script aside (to fail the census). Both bypassed the range check, so **every subset run executed them whatever the range**.

That is invisible while the restore works, and it is not academic. When a concurrent pass destroyed the backups, the appended `phoneHome` survived into the working tree. The suite then failed on the egress census, and because a **mutation-signature sweep only knows about `mutate()`-based defects**, the diagnosis had to start from "`app.js` is 44 bytes larger than it should be" and work backwards. Both plants now carry `row_wanted &&`.

**The general form, and it is this repo's own rule turned on its own tooling:** a filter that covers *most* of the sites it should cover **looks exactly like one that covers all of them** — which is D5, verbatim, applied to a test harness instead of a query. When you add a filter, enumerate the sites it must cover and check each one, rather than the ones that came to mind. `grep -nE '^\s*(cat|echo|printf).*>>|^\s*mv ' tests/defect-pass.sh` is the enumeration for this file.

The fixture must be able to exhibit the failure (Clause 4). A gate that cannot fail on this machine says so in its own text and is paired with one that can (Clause 2): see `CL5 BEHAVIOURAL` and its structural twin. Defect runs are recorded in `../GATES.md`.

Re-pin `EXPECTED_ASSERTIONS` and the census manifest **deliberately, in the same commit** that changes them, and state the delta.

## Environment

- **Scope.** Browser profiles and defect-pass backups live under `tests/.tmp/` (gitignored), never `%TEMP%`. This repo's sessions stay inside their own directory.
- **Antivirus (inherited from HealthTracker's record, same machine).** CDP gates drive headless Chrome over a debugging port. Kaspersky has quarantined such scripts as `PDM:Trojan.Win32.Bazon.a` and denied execution. **The exclusion must be scoped to All components, not the default Selected components.** A quarantine and an execution denial are one event, triggered by the run. Verify a restore with `git hash-object`, not with the next run. If a gate goes missing, suspect the AV before the runner. The census and the verdict runner both fail loudly by name.
