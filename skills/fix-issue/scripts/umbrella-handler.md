# skills/fix-issue/scripts/umbrella-handler.sh — contract

`skills/fix-issue/scripts/umbrella-handler.sh` is the umbrella-issue helper invoked by `skills/fix-issue/scripts/find-lock-issue.sh`'s explicit-issue path. It owns three orthogonal decisions: detection, child enumeration, and pick-next-eligible-child. Auto-pick mode in `find-lock-issue.sh` does NOT call this helper — umbrella handling is restricted to the explicit-issue path per the design dialectic's DECISION_1 (`/design` Step 2a.5 voted 2-1 ANTI_THESIS).

## Subcommands

- **`detect --issue N`** — emits `IS_UMBRELLA=true|false` plus `UMBRELLA_TITLE=<title>` and `DETECTION=body|title` when true.

  **Detection priority** (FINDING_13 from the plan-review panel):

  1. **Body-primary**: body contains the literal `Umbrella tracking issue.` anywhere in its text (case-sensitive). This is the canonical signal emitted by `/umbrella`'s `render-umbrella-body.sh` for every tool-created umbrella; matching it does not depend on title formatting and survives title edits.
  2. **Title-fallback**: title starts with the literal text `Umbrella:` followed by a space, or `Umbrella` followed by an em-dash and space (`Umbrella —`) — case-sensitive, anchored at start. This catches hand-authored umbrellas (e.g., #348) whose body does not include the body literal because they were created by hand or before `/umbrella` existed.

  Tool-created umbrellas always satisfy the body check; title prefix matches are a fallback. An issue that satisfies neither is NOT an umbrella.

- **`list-children --issue N`** — emits `CHILDREN=<space-separated #s>` in body-order first-occurrence dedup. Empty value if no children parse from the body.

  **Grammar** (DECISION_3 from the design dialectic — voted 3-0 task-list-only):

  ```
  ^[[:space:]]*- \[[ xX]\] .*#([0-9]+)
  ```

  Captures both /umbrella-rendered children (`- [ ] #N — title`) and hand-authored operator checklists (`- [ ] /fix-issue executes #N` as in #348). **Cross-repo references like `owner/repo#150` are NOT matched** — the parser strips any `<token>/<token>#<digits>` segment before extracting `#N`, so cross-repo `#N` forms never leak into the children list. **Self-references** (the umbrella's own number) are filtered out so an umbrella that mentions itself in its body cannot create a self-deadlock. Children are deduplicated, preserving first-occurrence body order.

- **`pick-child --issue N`** — emits ONE of three outcomes:
  - `CHILD_NUMBER=<C>` + `CHILD_TITLE=<T>` — the first eligible child in body order. Caller (`find-lock-issue.sh`) proceeds to lock with `issue-lifecycle.sh comment --lock-no-go --issue <C> --body "IN PROGRESS"`. **`pick-child` applies the native dependency-blockers filter (`child_native_blockers`) inside `child_eligible`** so it iterates past natively-blocked siblings to the next ready child. The full `all_open_blockers` (native + prose) pass is owned by `find-lock-issue.sh` and runs once on the chosen child before locking — defense in depth on top of the native-only filter inside `pick-child`.
  - `ALL_CLOSED=true` — every parsed child is verified `CLOSED` AND at least one child was parsed. Caller invokes `finalize-umbrella.sh finalize --issue N`. **FINDING_3**: this branch requires AT LEAST ONE parseable child. Zero parseable children is NOT treated as vacuous-truth `ALL_CLOSED`.
  - `NO_ELIGIBLE_CHILD=true` + `BLOCKING_REASON=<one-line>` — children exist but none are pickable in this run, OR zero parseable children were found in the body (FINDING_3). Caller surfaces the blocking reason via `find-lock-issue.sh`'s exit-5 path; `/fix-issue` prints a warning and skips to cleanup.

  **Per-child eligibility** (no GO required — children inherit approval from the umbrella's existence, per dialectic DECISION_1):
  - State is `OPEN`.
  - Title does not start with a managed lifecycle prefix (`[IN PROGRESS]` / `[DONE]` / `[STALLED]`).
  - Last comment is NOT exactly `IN PROGRESS` (not locked by a concurrent `/fix-issue` runner).
  - `child_native_blockers` returns empty — no open native GitHub dependency blockers (the native-only filter inside `child_eligible`, so `pick-child` iterates past natively-blocked siblings). Prose blockers are NOT checked here; the full `all_open_blockers` (native + prose) pass runs in `find-lock-issue.sh` once on the chosen child before locking.

  Children are walked in body order; the FIRST that passes eligibility wins. Deterministic try-one-then-fail — there is no fallback to a sibling on lock failure (the lock-failure path lives in `find-lock-issue.sh` and exits 3 with a clear umbrella-context error message).

## Stdout contract

KEY=value lines on stdout. Each subcommand emits its own keyset; auxiliary delegate output (e.g., `gh` JSON) is captured into local variables and never streamed.

| Subcommand | Success keys | Failure keys |
|------------|--------------|--------------|
| `detect` | `IS_UMBRELLA=true\|false`, `UMBRELLA_TITLE`, `DETECTION` (body or title) | `ERROR=<reason>` (exit 1) |
| `list-children` | `CHILDREN=<space-separated>` (may be empty value) | `ERROR=<reason>` (exit 1) |
| `pick-child` | one of: (`CHILD_NUMBER`+`CHILD_TITLE`) / `ALL_CLOSED=true` / (`NO_ELIGIBLE_CHILD=true`+`BLOCKING_REASON`) | `ERROR=<reason>` (exit 1) |

## Exit codes

| Exit | Meaning |
|------|---------|
| 0 | Success — see subcommand-specific stdout. |
| 1 | `gh` API failure or other internal error (`ERROR=` on stdout). |
| 2 | Usage error (unknown subcommand, missing `--issue`, etc.). |

## Edit-in-sync rules

- **Detection signals** (body literal, title prefix) are byte-pinned in `is_umbrella_body` / `is_umbrella_title`. If `/umbrella`'s `render-umbrella-body.sh` ever changes the body literal (`Umbrella tracking issue.`), update both files in the same PR AND update `test-umbrella-handler.sh`'s detect fixtures.
- **Child grammar** (`^[[:space:]]*- \[[ xX]\] .*#([0-9]+)`) is byte-pinned in `parse_children_from_body`. If the grammar widens (e.g., to support tables), update this contract, the harness, and `skills/fix-issue/SKILL.md` Known Limitations together.
- **Cross-repo strip**: the `[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[0-9]+` sed pattern enforces same-repo-only at the parser layer. Edits that loosen this open the cross-repo dispatch surface and require a security review.
- **`pick-child` eligibility checks** include the native-only blocker filter (`child_native_blockers` defined in `umbrella-handler.sh` and called from `child_eligible`); the full `all_open_blockers` (native + prose) pass remains in `find-lock-issue.sh` and runs once on the chosen child before locking. Editing this rule requires updating both files.

## Test harness

`skills/fix-issue/scripts/test-umbrella-handler.sh` is the offline regression harness. PATH-prepended `gh` stub (same pattern as `test-find-lock-issue.sh`). Fixtures cover detection priority (body-primary vs title-fallback), task-list grammar boundaries (cross-repo rejection, self-reference filter, mixed-text-only-no-task-list), pick-child eligibility branches (eligible / locked / managed-prefix / closed), the all-closed terminal state, and FINDING_3's zero-children-is-not-ALL_CLOSED invariant. Run manually via `bash skills/fix-issue/scripts/test-umbrella-handler.sh`. Wired into `make lint` via the `test-umbrella-handler` target under `test-harnesses`. Both `.sh` and `.md` are in `agent-lint.toml`'s exclude list per the Makefile-only-reference pattern.
