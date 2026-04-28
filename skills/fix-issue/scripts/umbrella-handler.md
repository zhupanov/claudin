# skills/fix-issue/scripts/umbrella-handler.sh — contract

`skills/fix-issue/scripts/umbrella-handler.sh` is the umbrella-issue helper invoked by `skills/fix-issue/scripts/find-lock-issue.sh`'s explicit-issue path. It owns three orthogonal decisions: detection, child enumeration, and pick-next-eligible-child. Auto-pick mode in `find-lock-issue.sh` does NOT call this helper — umbrella handling is restricted to the explicit-issue path per the design dialectic's DECISION_1 (`/design` Step 2a.5 voted 2-1 ANTI_THESIS).

## Subcommands

- **`detect --issue N`** — emits `IS_UMBRELLA=true|false` plus `UMBRELLA_TITLE=<title>` when true.

  **Detection** (title-only, post-#846 — body is no longer consulted):

  Title where, after stripping zero or more leading bracket-blocks of the form `[...]` and/or `(...)` (each with optional surrounding whitespace), the remainder starts with <code>Umbrella: </code> or <code>Umbrella — </code> (Umbrella + space + em-dash + space) — case-sensitive. Matches both `/umbrella`-created umbrellas (the orchestrator-composed summary conventionally starts with `Umbrella:`, though this is NOT code-enforced in `render-umbrella-body.sh` — existing umbrellas #774, #773, #770, #784 demonstrate the convention) and hand-authored umbrellas (e.g. #348). An umbrella whose title does not begin with the marker after the bracket peel will not be detected, regardless of body content; operators may need to rename non-marker umbrella titles to restore detection. Per #819 the grammar accepts an arbitrary sequence of `[...]` and `(...)` prefix blocks before the marker (peeled left-to-right, bounded by an iteration cap of 16 as a defensive guard against pathological titles), so titles like `[IN PROGRESS] Umbrella: foo`, `(urgent) Umbrella: foo`, and `[IN PROGRESS] (urgent) Umbrella: foo` are detected. Negative examples (all NOT umbrellas): `[IN PROGRESS] Do something umbrella related` (Umbrella mid-title after the prefix strip), `/umbrella should do X Y Z` (lowercase `umbrella` and command-syntax leader), `Some random title` whose body merely *quotes* the marker `Umbrella tracking issue.` in code or prose — body content is no longer consulted (this was the #753 false-positive class that motivated the #846 removal of body-based detection).

  **Title-grammar limitations (intentional)**:
  - **Non-nesting**: bracket blocks are peeled by finding the FIRST `]` or `)` after the opening delimiter. A block whose content itself contains a closing delimiter — e.g., `[outer [inner] outer]` — is not parsed as a single block; the peel stops at the first `]`, leaving `outer] Umbrella: foo` as the residual which fails the marker match. Acceptable false-negative; nested-bracket titles are not used in practice.
  - **Iteration cap = 16**: titles with more than 16 leading bracket blocks are NOT detected. Defensive guard against pathological input; titles in practice carry at most a few prefix tags.
  - **Fail-closed on unbalanced/unclosed leading bracket**: a title like `[unclosed Umbrella: foo` or `(unclosed Umbrella: foo` returns `IS_UMBRELLA=false` (the peel cannot find a matching closing delimiter). This is **silently indistinguishable** from "not an umbrella" on the `detect` subcommand's stdout — no `ERROR=` line is emitted on the malformed-bracket fail-closed path. Operationally fine: callers (find-lock-issue.sh) treat any non-true `IS_UMBRELLA` as "not an umbrella" without needing to disambiguate the cause.

  An issue whose title does not satisfy this grammar is NOT an umbrella, regardless of body content.

- **`list-children --issue N`** — emits `CHILDREN=<space-separated #s>` in body-order first-occurrence dedup. Empty value if no children parse from the body.

  **Grammar** (DECISION_3 from the design dialectic — voted 3-0 task-list-only):

  ```
  ^[[:space:]]*- \[[ xX]\] .*#([0-9]+)
  ```

  Captures both /umbrella-rendered children (`- [ ] #N — title`) and hand-authored operator checklists (`- [ ] /fix-issue executes #N` as in #348). **Cross-repo references like `owner/repo#150` are NOT matched** — the parser strips any `<token>/<token>#<digits>` segment before extracting `#N`, so cross-repo `#N` forms never leak into the children list. **Self-references** (the umbrella's own number) are filtered out so an umbrella that mentions itself in its body cannot create a self-deadlock. Children are deduplicated, preserving first-occurrence body order.

- **`pick-child --issue N`** — emits ONE of three outcomes:
  - `CHILD_NUMBER=<C>` + `CHILD_TITLE=<T>` — the first eligible child in body order. Caller (`find-lock-issue.sh`) proceeds to lock with `issue-lifecycle.sh comment --lock-no-go --issue <C> --body "IN PROGRESS"`. **`pick-child` applies the full native+prose blocker check (`all_open_blockers` from `blocker-helpers.sh`) inside `child_eligible`** so it iterates past both natively-blocked AND prose-blocked siblings to the next ready child (issue #768; superseded the prior native-only filter from FINDING_5 of the umbrella-PR plan-review panel). The same `all_open_blockers` runs once on the chosen child in `find-lock-issue.sh` before locking — that call is now defense in depth, no longer load-bearing for sibling iteration.
  - `ALL_CLOSED=true` — every parsed child is verified `CLOSED` AND at least one child was parsed. Caller invokes `finalize-umbrella.sh finalize --issue N`. **FINDING_3**: this branch requires AT LEAST ONE parseable child. Zero parseable children is NOT treated as vacuous-truth `ALL_CLOSED`.
  - `NO_ELIGIBLE_CHILD=true` + `BLOCKING_REASON=<one-line>` — children exist but none are pickable in this run, OR zero parseable children were found in the body (FINDING_3). Caller surfaces the blocking reason via `find-lock-issue.sh`'s exit-5 path; `/fix-issue` prints a warning and skips to cleanup.

  **Per-child eligibility** (no GO required — children inherit approval from the umbrella's existence, per dialectic DECISION_1):
  - State is `OPEN`.
  - Title does not start with a managed lifecycle prefix (`[IN PROGRESS]` / `[DONE]` / `[STALLED]`).
  - Last comment is NOT exactly `IN PROGRESS` (not locked by a concurrent `/fix-issue` runner).
  - `all_open_blockers` returns empty — no open native or prose blockers (native-first short-circuit applies, so prose pagination only fires when native is empty). Prose blockers ARE checked here, fixing issue #768's stall-on-prose-blocked-first-child.

  Children are walked in body order; the FIRST that passes eligibility wins. Deterministic try-one-then-fail — there is no fallback to a sibling on lock failure (the lock-failure path lives in `find-lock-issue.sh` and exits 3 with a clear umbrella-context error message).

## Stdout contract

KEY=value lines on stdout. Each subcommand emits its own keyset; auxiliary delegate output (e.g., `gh` JSON) is captured into local variables and never streamed.

| Subcommand | Success keys | Failure keys |
|------------|--------------|--------------|
| `detect` | `IS_UMBRELLA=true\|false`, `UMBRELLA_TITLE` | `ERROR=<reason>` (exit 1) |
| `list-children` | `CHILDREN=<space-separated>` (may be empty value) | `ERROR=<reason>` (exit 1) |
| `pick-child` | one of: (`CHILD_NUMBER`+`CHILD_TITLE`) / `ALL_CLOSED=true` / (`NO_ELIGIBLE_CHILD=true`+`BLOCKING_REASON`) | `ERROR=<reason>` (exit 1) |

## Exit codes

| Exit | Meaning |
|------|---------|
| 0 | Success — see subcommand-specific stdout. |
| 1 | `gh` API failure or other internal error (`ERROR=` on stdout). |
| 2 | Usage error (unknown subcommand, missing `--issue`, etc.). |

## Edit-in-sync rules

- **Title detection grammar** is byte-pinned in `is_umbrella_title` (the peel-prefix grammar per #819 — leading `[...]` and `(...)` blocks, iteration cap 16, fail-closed on unbalanced brackets, marker <code>Umbrella: </code> or <code>Umbrella — </code>). It is pinned by `test-umbrella-handler.sh` fixtures 14-20 plus the title-only fixtures 1-3; widening or narrowing the grammar requires updating the function, this contract paragraph, the test fixtures, and `skills/fix-issue/SKILL.md` Step 0 / Known Limitations together. Body content is NOT consulted by `detect` (post-#846 — the prior body-literal substring match produced false positives like #753).
- **Child grammar** (`^[[:space:]]*- \[[ xX]\] .*#([0-9]+)`) is byte-pinned in `parse_children_from_body`. If the grammar widens (e.g., to support tables), update this contract, the harness, and `skills/fix-issue/SKILL.md` Known Limitations together.
- **Cross-repo strip**: the `[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[0-9]+` sed pattern enforces same-repo-only at the parser layer. Edits that loosen this open the cross-repo dispatch surface and require a security review.
- **`pick-child` eligibility checks** invoke the full native+prose blocker check (`all_open_blockers` from `blocker-helpers.sh`, sourced near the top of `umbrella-handler.sh`) inside `child_eligible`; this fixed issue #768's stall-on-prose-blocked-first-child by making `pick-child` iterate past prose-blocked siblings. The same `all_open_blockers` is also invoked once on the chosen child in `find-lock-issue.sh handle_umbrella` as defense in depth. Editing the eligibility rule requires updating `umbrella-handler.sh`, this contract, `blocker-helpers.{sh,md}` (where the canonical `all_open_blockers` lives), and the test fixtures in `test-umbrella-handler.sh` together.

## Test harness

`skills/fix-issue/scripts/test-umbrella-handler.sh` is the offline regression harness. PATH-prepended `gh` stub (same pattern as `test-find-lock-issue.sh`). Fixtures cover title-only detection (marker positive, plain non-marker, the #753 body-literal-but-plain-title regression that motivated #846), task-list grammar boundaries (cross-repo rejection, self-reference filter, mixed-text-only-no-task-list), pick-child eligibility branches (eligible / locked / managed-prefix / closed), the all-closed terminal state, and FINDING_3's zero-children-is-not-ALL_CLOSED invariant. Run manually via `bash skills/fix-issue/scripts/test-umbrella-handler.sh`. Wired into `make lint` via the `test-umbrella-handler` target under `test-harnesses`. Both `.sh` and `.md` are in `agent-lint.toml`'s exclude list per the Makefile-only-reference pattern.
