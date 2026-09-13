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

## `run-data-layer.sh` — the harness, plus the static checks that guard it

In order, each failing the whole gate:

1. **Gate-script census** (HT-D53): the `*-gate.ps1` set must equal a pinned manifest. A quarantined gate does not run and does not say so; naming it ends the hunt.
2. **Port residue** (D1): no `healthtracker-` storage key, no HT console seam, no meal-domain identifiers in `app.js` / `index.html`. The match is on code shapes, with a planted control.
3. **Egress census** (`check-egress.sh`, D1): every network primitive in the shell is enumerated and mapped to its enclosing function. **Exactly one site, inside `egress()`.** Planted control first.
4. **Cross-reference census** (`check-refs.sh`, D3): every `Dnn`, `HT-Dnn`, `HT-Rnn`, `Rn` and `rule(s) N` cited in `CLAUDE.md` / `DECISIONS.md` / `GATES.md` must resolve to a heading or rule that exists, and the brief's rule list must be 1..N with no duplicates or gaps. Planted control first. **It catches unresolvable citations and an inconsistent list — not a citation that resolves to the wrong thing.**
5. **`data-layer.test.html`** in headless Chrome: the real `app.js`, plus the real `index.html` in an iframe. The **executed assertion count must equal the pin** (`EXPECTED_ASSERTIONS`), so a silently dropped case fails the gate.

**Harness limitation (HT-D47), stated rather than hidden:** `createImageBitmap` never settles under `--virtual-time-budget`. The harness therefore proves the **leash** and the fallback decoder, and cannot exercise the preferred decoder. `capture-outcome-gate.ps1` runs in real time and does.

**The vision contract is unruled (D1).** The capture-chain cases install a synthetic contract through `CT.setVisionContract`. They prove the chain, never a contract.

## `capture-outcome-gate.ps1` — one outcome, in view without scrolling (HT-D51)

"Exactly one outcome, in view" is a **layout** claim, so it is measured in a viewport. The gate drives the shipped capture path against the real `index.html`, with fetch stubbed, at 360×690, 390×745 and 1200×900, and asserts per state:

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

Every mutated file (`app.js`, `index.html`, `CLAUDE.md`, `GATES.md`) is restored after each row and **verified against its own pre-run copy**, with an exit trap so an interrupted run cannot leave a mutation behind. Verify a restore with `git status` / a comparison, never with the next run.

**Restore by COPY, never by `git checkout --`.** One row once restored `GATES.md` with git, which resets from **HEAD** — so it silently discarded edits made minutes earlier and not yet committed. A restore must return a file to **what it was**, not to what was last committed. The `mutate` helper compares each file against that same copy, so a mutation that fails to apply says so instead of producing a row that proves nothing.

The fixture must be able to exhibit the failure (Clause 4). A gate that cannot fail on this machine says so in its own text and is paired with one that can (Clause 2): see `CL5 BEHAVIOURAL` and its structural twin. Defect runs are recorded in `../GATES.md`.

Re-pin `EXPECTED_ASSERTIONS` and the census manifest **deliberately, in the same commit** that changes them, and state the delta.

## Environment

- **Scope.** Browser profiles and defect-pass backups live under `tests/.tmp/` (gitignored), never `%TEMP%`. This repo's sessions stay inside their own directory.
- **Antivirus (inherited from HealthTracker's record, same machine).** CDP gates drive headless Chrome over a debugging port. Kaspersky has quarantined such scripts as `PDM:Trojan.Win32.Bazon.a` and denied execution. **The exclusion must be scoped to All components, not the default Selected components.** A quarantine and an execution denial are one event, triggered by the run. Verify a restore with `git hash-object`, not with the next run. If a gate goes missing, suspect the AV before the runner. The census and the verdict runner both fail loudly by name.
