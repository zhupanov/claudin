# skills/issue/scripts/allocate-candidates.sh — contract

`skills/issue/scripts/allocate-candidates.sh` applies a deterministic two-pass selection to /issue Phase 1 Tier-1 candidate flags: per-item floor reservation followed by confidence-ranked spillover, under a hard 30-cap on the final CANDIDATES list. Resolves issue #554 (per-item floor for Phase 1 candidate cap).

## Invocation

```
allocate-candidates.sh --total-items N
  (reads CAND rows from stdin)
```

`--total-items N` is the count of **non-malformed** items in the /issue batch — NOT `ITEMS_TOTAL`. Malformed items (per `parse-input.sh`'s `ITEM_<i>_MALFORMED=true` flag) are excluded from Phase 1/2 and so contribute zero CAND rows; their inclusion in the denominator would understate the per-item floor (e.g. 10 non-malformed + 5 malformed → floor(30/15)=2 instead of the correct floor=3).

## Stdin format

One row per line:

```
CAND <item-i> <issue-N> <kind:dup|dep|both> <confidence:high|medium|low>
```

Field validation (defensive — drop with stderr warning, do NOT abort):

- `item-i`: numeric, 1 ≤ i ≤ N. Out-of-range or non-numeric → drop row.
- `issue-N`: positive integer. Non-numeric or zero → drop row.
- `kind`: `dup`, `dep`, or `both` (first-class). Anything else → defaults to `dup`.
- `confidence`: `high`, `medium`, or `low`. Missing or unknown → defaults to `low`.

Blank lines and lines not starting with the literal `CAND` token followed by whitespace are silently ignored.

## Stdout contract

On exit 0, **exactly one line** on stdout:

```
CANDIDATES=<comma-separated issue numbers, ascending>
```

Empty selection (N=0, empty stdin, all rows dropped, or no candidates after both passes) emits `CANDIDATES=` and exits 0. The empty case is normal — `/issue` SKILL Step 5's gate allows this when `N_NON_MALFORMED >= 2` (intra-batch-only path) or short-circuits to Step 6 when `N_NON_MALFORMED < 2`.

ALL diagnostics (warnings, dropped-row notices, the N>30 banner) go to **stderr only**. Any accidental stdout pollution would break the calling SKILL prompt's parse of `CANDIDATES=`.

## Algorithm (single normative source)

Let `N` = `--total-items` value, `CAP` = 30 (hard cap on final union size).

1. Compute per-item floor `F`:
   - If `N > CAP` → `F = 0` (degenerate case; emit stderr warning).
   - Else if `N == 0` → emit `CANDIDATES=` and exit 0.
   - Else → `F = min(3, floor(CAP / N))`.

2. Read stdin; validate each CAND row per the field rules above. Drop invalid rows with stderr warnings. Deduplicate `(item, issue)` pairs — for each pair, keep the highest-confidence row.

3. **Pass A — floor reservation.** Iterate items in **ascending item index** (1, 2, …, N). For each item:
   - Sort the item's valid rows by **confidence-desc, issue-asc**.
   - For each row: if the candidate issue is already in the union, **increment `floor_credits[item]` without growing the union** (union-credit semantics: a candidate already added covers every item that nominated it). Else, if `floor_credits[item] < F` AND `|union| < CAP`, add the candidate to the union and increment `floor_credits` for **every** item that nominated this issue at any confidence (not just the current item).
   - Stop processing this item once `floor_credits[item] >= F`.

4. **Pass B — spillover.** Collect leftover rows whose issue is not yet in the union. Sort by **confidence-desc → issue-asc → item-asc**. Add issues one at a time until `|union| == CAP` or the leftover list is exhausted.

5. Emit `CANDIDATES=<comma-separated, ascending>` on stdout.

## Exit codes

- `0` — success (any successful run, including empty output).
- `1` — usage error only (missing or invalid `--total-items`).

The script does NOT exit 1 on malformed input rows — those are dropped with stderr warnings and processing continues. The calling SKILL is responsible for branching on a non-zero exit (which only happens for `usage error`) and treating it as fail-open per /issue's `LIST_STATUS=failed` posture.

## kind=both first-class

`kind=both` is a valid token, NOT an "unknown → dup" fallback. A `both` row counts as a single candidate (one union slot, one floor credit per nominator); the category metadata is preserved for trace inspection but does not multiply the slot cost. Consumers downstream (Step 5's `fetch-issue-details.sh`) see only the issue number — kind is Phase-1-internal.

## Bash 3.2 portability

Implemented in Bash 3.2-safe style — no `declare -A` (associative arrays), no `mapfile`, no `${var,,}` lowercasing. macOS `/bin/bash` is 3.2 by default, and other scripts in `skills/issue/scripts/*` follow the same constraint. Uses parallel arrays + `awk` + `sort` for non-trivial state. The regression harness `test-allocate-candidates.sh` includes a `grep -nE 'declare -A|mapfile|\$\{[A-Z_]+,,\}'` check that fails the harness if Bash-4-only constructs creep in.

## Regression coverage

`skills/issue/scripts/test-allocate-candidates.sh` is the regression harness, wired into `make lint` via the `test-allocate-candidates` target. It pins:

- Floor formula at boundary (N=10/11/15/16/30/31).
- Partial-floor + Pass B spillover interaction.
- Tie-breaks (confidence band → issue-asc → item-asc).
- Union-credit semantics (a candidate in the union covers every nominator's floor).
- `kind=both` first-class behavior.
- Defensive-default drops (non-numeric item, out-of-range item, non-numeric issue).
- N>30 stderr warning.
- Empty stdin and N=0 paths.
- Stdout-shape invariant (exactly one `CANDIDATES=` line).
- Bash 3.2 portability guard.

## Edit-in-sync rule

Any change to:
- the CAND row schema (field names, field count, kind/confidence enums),
- the algorithm (F formula, Pass A/B iteration order, union-credit semantics, tie-breaks),
- the defensive-default rules (which malformed rows are dropped vs normalized),
- the stdout contract (`CANDIDATES=` line shape, single-line invariant),
- the exit-code semantics

requires updating, in the same PR:

1. This script (`allocate-candidates.sh`) and this contract file (`allocate-candidates.md`).
2. `skills/issue/SKILL.md` Step 4 prose (worked examples, syntax line, fail-open branch, `--total-items` flag binding to `N_NON_MALFORMED`).
3. `skills/issue/scripts/test-allocate-candidates.sh` (golden-test outputs).

The harness is the mechanical guard against drift; the prose cross-references in SKILL.md and the sibling .md are the operator-facing documentation surface.
