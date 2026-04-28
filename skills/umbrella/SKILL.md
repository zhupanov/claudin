---
name: umbrella
description: "Use when planning or breaking up a task or plan into GitHub issues — auto-classifies one-shot vs multi-piece, delegates to /issue (batch mode plus umbrella tracking issue), and wires native blocked-by edges plus child→umbrella back-links."
argument-hint: "[--label L]... [--title-prefix P] [--repo OWNER/REPO] [--closed-window-days N] [--dry-run] [--go] [--debug] [--pieces-json PATH] <task description or empty to deduce from context>"
allowed-tools: Bash, Read, Skill
---

# umbrella

Plan-to-issues orchestrator. Takes a task description (or deduces it from session context), classifies it as one-shot or multi-piece, and delegates GitHub issue creation to `/issue` — adding native blocked-by dependencies to form an execution DAG and back-linking children to the umbrella when multi-piece.

> **Before editing**, read `${CLAUDE_PLUGIN_ROOT}/skills/shared/skill-design-principles.md` (full file). Section III mechanical rules A/B/C override general writing-style guidance on conflict.

## Anti-patterns (with WHY)

- **NEVER** call `gh api` directly with hard-coded REST paths inside this `SKILL.md`. **Why**: GitHub's issue-dependency / sub-issue API surface has shifted multiple times (REST `/dependencies/blocked_by`, the sub-issues endpoint, the GraphQL `addSubIssue` mutation). Wrap every dependency-related GitHub call in `scripts/helpers.sh wire-dag` so the surface can be swapped without rewriting prompt prose.
- **NEVER** add a blocking edge before verifying it does not create a cycle. **Why**: a cycle in the blocked-by graph deadlocks `/fix-issue` and any other automation that respects dependencies — and deadlocked queues fail silently. `helpers.sh wire-dag` runs `helpers.sh check-cycle` against the proposed edge plus all existing edges before posting.
- **NEVER** create the umbrella issue before the children. **Why**: the umbrella body lists child numbers as a checklist (`- [ ] #N — <title>`); those numbers are unknown until `/issue --input-file` returns. A placeholder umbrella with `#TBD` references rots fast and breaks GitHub's auto-rendering of the checklist.
- **NEVER** skip the user-visible classification verdict. **Why**: the LLM's one-shot vs multi-piece judgment is the most error-prone step in the pipeline and the cheapest to correct — silent multi-piece on a small ask spams the issue tracker; silent one-shot on a sprawling ask defeats the purpose of `/umbrella`. Always print the verdict + one-line rationale before proceeding.
- **NEVER** bypass `/issue` with a direct `gh issue create`. **Why**: `/issue` carries semantic dedup (Phase 1 + Phase 2), OOS-template support, outbound secret redaction, and sentinel writing that must apply uniformly across the larch toolchain. A direct create diverges `/umbrella`'s outputs from the rest of the pipeline.

## Flags

Parse flags from the start of `$ARGUMENTS`. Flags may appear in any order; stop at the first non-flag token. The remainder is the task description (may be empty — see Step 1).

| Flag | Meaning |
|------|---------|
| `--label LABEL` | Repeatable. Forwarded to `/issue` for every child create AND the umbrella create. |
| `--title-prefix PREFIX` | Prepended by `/issue` to every child title AND the umbrella title. |
| `--repo OWNER/REPO` | Forwarded to `/issue`. Defaults to the inferred current repo. |
| `--closed-window-days N` | Forwarded to `/issue` (closed-issue dedup window). Default 90. |
| `--dry-run` | Forwarded to `/issue`. Multi-piece path skips umbrella body composition + umbrella issue creation (Step 3B.3) and DAG wiring + back-links (Step 3B.4). |
| `--go` | Forwarded to `/issue` for child batch AND umbrella single. Posts `GO` on every successfully-created issue (children + umbrella). Duplicates / failed creates / dry-runs never get a GO comment (per `/issue` Step 6 contract). |
| `--debug` | Verbose mode for this skill's own helpers. |
| `--input-file PATH` | Activates pre-decomposed-input mode. Bypasses Step 1 (task resolve) and Step 3B.1 (LLM decomposition). The file MUST be a pre-built `/issue --input-file` batch markdown. Required to be paired with `--umbrella-summary-file`. Mutually exclusive with positional TASK. |
| `--umbrella-summary-file PATH` | Caller-composed 1-2 sentence summary paragraph for the umbrella issue body's lead in Step 3B.3 (replaces the LLM-composed summary). Required to be paired with `--input-file`. |
| `--pieces-json PATH` | Optional. Caller-supplied inter-piece dependency edges for pre-decomposed-input mode. JSON array of `{title, body, depends_on: [int,...]}` objects matching the `/issue --input-file` batch items by index. Required to be paired with `--input-file` (asymmetric: `--input-file` does NOT require `--pieces-json`). When supplied, Step 3B.4 reads `depends_on` fields to compose inter-child edges (resolving piece indices to issue numbers via `/issue` batch return). Validated by `validate-pieces-json.sh` before Step 3B.2. |

## Step 0 — Setup

```bash
${CLAUDE_PLUGIN_ROOT}/skills/umbrella/scripts/parse-args.sh "$ARGUMENTS"
```

Parse stdout for: `LABELS_COUNT` (integer ≥ 0), then `LABEL_1` through `LABEL_<LABELS_COUNT>` (one indexed key per `--label` value; empty when `LABELS_COUNT=0`), `TITLE_PREFIX`, `REPO`, `CLOSED_WINDOW_DAYS`, `DRY_RUN` (`true|false`), `GO` (`true|false`), `DEBUG` (`true|false`), `INPUT_FILE` (path — empty if `--input-file` not specified), `UMBRELLA_SUMMARY_FILE` (path — empty if `--umbrella-summary-file` not specified), `PIECES_JSON` (path — empty if `--pieces-json` not specified), `TASK` (everything after the last flag — may be empty; preserves embedded whitespace AND any quote/escape characters verbatim), `UMBRELLA_TMPDIR` (mktemp dir created by the parser; cleaned at Step 5). When parsing each KV line, split on the FIRST `=` only — values may contain literal `=` characters (e.g., `LABEL_1=priority=high`).

**Pre-decomposed-input mode**: when `INPUT_FILE` is non-empty (and `UMBRELLA_SUMMARY_FILE` is also non-empty by paired-flag validation in `parse-args.sh`), skip Step 1 (task resolve) and Step 3B.1 (LLM decomposition); Step 2 classification is replaced by post-3B.2 distinct-resolved-child-count rule (see Step 2 below). Mutual exclusion with positional `TASK` is enforced at the parser layer.

When forwarding labels to `/issue` in Steps 3A, 3B.2, and 3B.3 below, reconstruct the repeated `--label` flags by emitting one `--label <value>` for each `LABEL_1` through `LABEL_<LABELS_COUNT>`.

On non-zero exit, print the `ERROR=` line and abort.

## Step 1 — Resolve Task Description

**Skip Step 1 entirely when `INPUT_FILE` is non-empty** (pre-decomposed-input mode). The caller has already produced a `/issue --input-file` batch markdown directly, so there is no `TASK` to resolve and no LLM decomposition needed downstream. Proceed directly to Step 2.

If `TASK` is non-empty, use it verbatim.

If `TASK` is empty, deduce the task from session context — the most recent unambiguous user request (e.g., a feature spec discussed in the prior turns, a research finding, a /research output the user just acted on). Surface the deduced task to the user as a single quoted line prefixed by `Deduced task:` so they can interrupt if you got it wrong. If the context is genuinely ambiguous (multiple plausible tasks, or none), abort with the error message: `/umbrella requires a task description and could not deduce one from context. Re-invoke with the description as a positional argument.`

## Step 2 — Classify One-Shot vs Multi-Piece

### Pre-decomposed-input mode (when `INPUT_FILE` is non-empty)

Skip LLM classification entirely. Instead, classification is **deterministic post-3B.2**: jump directly to Step 3B.2 (batch /issue create), then count distinct resolved child issue numbers per the rule below. The verdict + rationale are emitted *after* 3B.2 returns.

**Distinct-resolved-child-count rule** (dry-run-safe):
- For each `ISSUE_<i>_*` group emitted by `/issue` (batch-mode stdout):
  - If `ISSUE_<i>_DRY_RUN=true`: count this item as 1 prospective distinct child (dry-run children have no real number; treat each independently).
  - Else if `ISSUE_<i>_DUPLICATE_OF_NUMBER=<N>` is non-empty: contribute `<N>` to the set of distinct numbers (deduplicates collapse to the existing target).
  - Else if `ISSUE_<i>_NUMBER=<N>` is non-empty (newly-created child): contribute `<N>` to the set.
  - Else (failed item — `ISSUE_<i>_FAILED=true`): exclude from the count.
- The distinct count is `len(set_of_numbers) + count_of_dry_run_items`.

This rule is authoritative for any caller of `/umbrella --input-file` — it applies uniformly regardless of whether `/issue --input-file --dry-run` is invoked through `/review --create-issues`, a future CI driver exercising `/umbrella --input-file --dry-run`, or any other caller. The three load-bearing literals (`Distinct-resolved-child-count rule** (dry-run-safe)`, the `ISSUE_<i>_DRY_RUN=true` count-as-1 sentence, and the `len(set_of_numbers) + count_of_dry_run_items` formula) plus this caller-agnostic note are pinned by `scripts/test-umbrella-emit-output-contract.sh` to guard against silent drift.

If distinct count is **<2** → emit a 3-line bundle (parallel to 3B.1's existing `decomposition-lt-2` downgrade convention; preserves the "NEVER skip the user-visible classification verdict" anti-pattern):
```
UMBRELLA_VERDICT=one-shot
UMBRELLA_DOWNGRADE=input-file-distinct-lt-2
UMBRELLA_RATIONALE=Downgraded from input-file mode — fewer than two distinct resolved child issue numbers after /issue dedup
```
Then **skip Step 3B.3 and Step 3B.4 entirely** and continue at Step 4. **CRITICAL**: do NOT execute Step 3A on the downgrade path — children were already created in Step 3B.2; re-invoking `/issue` would double-create. Step 4's `output.kv` for `CHILDREN_CREATED`, `CHILDREN_DEDUPLICATED`, `CHILDREN_FAILED` reflects the Step 3B.2 batch results directly. `UMBRELLA_NUMBER` and `UMBRELLA_URL` are omitted.

If distinct count is **≥2** → emit `UMBRELLA_VERDICT=multi-piece` + `UMBRELLA_RATIONALE=<one short sentence — under 120 chars — explaining the call>` and proceed to Step 3B.3 (umbrella body composition + creation), then Step 3B.4 (DAG-empty wire-dag with back-links).

### Normal mode (when `INPUT_FILE` is empty)

Decide one of two verdicts based on the task description:

- **`one-shot`** (default — bias here): a single bug fix, doc tweak, refactor confined to one component, single skill scaffold, single CI fix, single test addition. Anything that one PR can plausibly land.
- **`multi-piece`**: spec-style descriptions naming distinct phases, sub-systems, or independent work units (e.g., "Phase 1: do X. Phase 2: do Y. Phase 3: do Z."); multi-component refactors with discrete steps that can land in separate PRs; an umbrella tracking issue that consolidates ≥2 cleanly partitionable units.

Print exactly one line in this shape (machine-grep-friendly + human-readable):

```
UMBRELLA_VERDICT=<one-shot|multi-piece>
UMBRELLA_RATIONALE=<one short sentence — under 120 chars — explaining the call>
```

Then branch: `one-shot` → Step 3A; `multi-piece` → Step 3B.

## Step 3A — One-Shot Path

Forward the entire `TASK` to `/issue` (single mode). Do NOT add or strip any flag the user did not pass.

Invoke the Skill tool:

- Try skill `"issue"` first (bare name). If no skill matches, try `"larch:issue"`.
- args: `[--label L]... [--title-prefix P] [--repo R] [--closed-window-days N] [--dry-run] [--go] <TASK>` — pass each captured flag verbatim; omit the flag if its parsed value is the default. Reconstruct `[--label L]...` by emitting one `--label <value>` for each `LABEL_1` through `LABEL_<LABELS_COUNT>` parsed in Step 0.

Parse `/issue`'s stdout for `ISSUES_CREATED`, `ISSUES_DEDUPLICATED`, `ISSUES_FAILED`, `ISSUE_1_NUMBER`, `ISSUE_1_URL`, `ISSUE_1_TITLE`, `ISSUE_1_DUPLICATE_OF_NUMBER` / `ISSUE_1_DUPLICATE_OF_URL` (when deduplicated), `ISSUE_1_DRY_RUN` (when dry-run). Capture into the `CHILD_*` fields per Step 4 (the one-shot child is `CHILD_1`). When `ISSUE_1_DRY_RUN=true`, capture the one-shot child per the dry-run child shape in Step 4.

Continue at Step 4. (No umbrella issue, no DAG, no back-links — there is only one child.)

## Step 3B — Multi-Piece Path

Four sub-steps run in order. Each is exactly one Bash tool call (Section III rule C). The LLM owns the decomposition; the scripts own the I/O and GitHub mechanics. On the multi-piece dry-run path (`DRY_RUN=true`), 3B.2's children-batch-failure abort or 3B.3's dry-run guard may short-circuit to Step 4, skipping the remaining sub-steps; this is the canonical exit shape, not an exception.

### 3B.1 — Decompose and write batch-input file

**Skip Step 3B.1 entirely when `INPUT_FILE` is non-empty** (pre-decomposed-input mode). The caller-supplied `INPUT_FILE` is already a `/issue --input-file` batch markdown — no decomposition or rendering needed. `BATCH_INPUT_FILE` is set to `INPUT_FILE` directly. Proceed to Step 3B.2.

Decompose `TASK` into N concrete work-pieces (`N >= 2`). Each piece must be small enough to land as one PR but substantial enough to merit its own issue — bias toward pieces that are independently testable. Compose, in your reasoning, an ordered list of `(title, body, depends-on)` tuples:

- `title` — one line, ≤ 80 chars, imperative ("Add X", "Fix Y", "Refactor Z").
- `body` — markdown, the implementation contract for that piece (problem, suggested approach, acceptance criteria). **Do NOT use `###` sub-headers anywhere inside any piece body, including inside fenced code blocks** — `/issue`'s `parse-input.sh` is line-based and treats any `^### <title>` line as a new-item boundary in generic mode (Path 3: flush current item + start new), which would silently split the piece into multiple parsed items with wrong titles and broken `depends_on` index alignment. Use `**bold**` headings or `####` level-4 for any internal structure. (The bundling carve-out below restates this restriction in the bundled-checklist context for self-containment; both bullets are subject to the same root rule.)
- `depends-on` — comma-separated 1-based indices of earlier pieces this one depends on (empty if none).

**Bundle very small work items into fewer pieces** (token-cost optimization for downstream `/implement`). When two or more candidate pieces are each "very small" — expected to be under ~10 lines of change, especially when touching only 1-3 files — bias toward merging them into a single composed `(title, body, depends-on)` tuple rather than filing each as its own issue. **Security / permissions carve-out (never bundle these)**: a 6-line auth, permissions, or security-critical change is small but NOT bundle-safe; keep such items as separate pieces so review and rollback granularity remain crisp.

Bundling criteria (all required):

- **Same area**: bundled items touch the same component, the same skill, or the same script-and-its-test pair.
- **Pairwise incomparable in the dependency graph**: for every pair of bundled items, no directed path exists between them in either direction in the combined `depends_on` graph. Direct-edge absence alone is not sufficient — in chain `1 → 2 → 3`, items `1` and `3` are transitively comparable via `2`, so bundling them while leaving `2` separate breaks ordering.
- **Merged `depends_on` = sorted unique union of all bundled items' predecessors**, mapped to new 1-based indices after the array is compacted. Forbid self-references and out-of-range refs.
- **Body shape**: enumerate sub-tasks as a markdown checklist using `- [ ]` bullets only. **Do NOT use `###` sub-headers anywhere inside the bundled body, including inside fenced code blocks** — `/issue`'s `parse-input.sh` is line-based and treats any `^### <title>` line as a new-item boundary in generic mode (Path 3: flush current item + start new), which would silently undo the bundle. Use `**bold**` headings or `####` level-4 for any internal structure.

Bundling must keep at least 2 final pieces. If every candidate item is genuinely tiny enough that even two thematic groups feel artificial, fall through to the existing `decomposition-lt-2` one-shot path below — filing the original `TASK` as a single issue is consistent with the "fewer issues" goal.

If decomposition produces fewer than 2 pieces, fall back to one-shot: print three strict KV lines — `UMBRELLA_VERDICT=one-shot` (preserving the Step 2 `UMBRELLA_VERDICT=<one-shot|multi-piece>` token grammar), `UMBRELLA_DOWNGRADE=decomposition-lt-2` (shell-safe machine token capturing the downgrade trigger on a separate KV line), and `UMBRELLA_RATIONALE=Downgraded from multi-piece — fewer than two decomposed pieces` (preserving the Step 2 verdict + rationale shape required by the "NEVER skip the user-visible classification verdict" anti-pattern) — and execute Step 3A with the original `TASK`. Carry `UMBRELLA_DOWNGRADE=decomposition-lt-2` through to Step 4's `output.kv` (see the optional schema entry).

Render the batch-input markdown file:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/umbrella/scripts/render-batch-input.sh --tmpdir "$UMBRELLA_TMPDIR" --pieces-file "$UMBRELLA_TMPDIR/pieces.json"
```

Write `$UMBRELLA_TMPDIR/pieces.json` (a JSON array of `{title, body, depends_on: [int,...]}` objects in pieces order) BEFORE invoking the renderer using the Write tool. The renderer emits `BATCH_INPUT_FILE=<path>`, `PIECES_TOTAL=<N>`, plus per-piece `PIECE_<i>_TITLE` and `PIECE_<i>_DEPENDS_ON` lines. On non-zero exit, print `ERROR=` and abort.

### 3B.1.5 — Validate caller-supplied pieces.json (pre-decomposed-input mode only)

**Skip this sub-step when `PIECES_JSON` is empty.** When `PIECES_JSON` is non-empty, count the items in `INPUT_FILE` (the number of `### <title>` headings in the batch markdown — this is `ITEMS_TOTAL` from `/issue`'s `parse-input.sh` contract) and validate:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/umbrella/scripts/validate-pieces-json.sh --pieces-file "$PIECES_JSON" --count $ITEMS_TOTAL
```

On non-zero exit, print the `ERROR=` line and abort. This is fail-closed: a malformed `pieces.json` must not silently produce an empty DAG. The validation runs before Step 3B.2 so that no children are created from a batch whose dependency metadata is invalid.

`ITEMS_TOTAL` derivation: use `grep -c '^### ' "$INPUT_FILE"` to count level-3 headings. This is the same heading-count convention `parse-input.sh` uses in Path 3 (generic `--input-file` mode) to determine batch length; the count must align with `parse-input.sh`'s emitted `ITEMS_TOTAL` when both operate on the same file. If the heading count is 0 (file has no level-3 headings), treat as a validation error — a `pieces.json` paired with an empty or non-batch input file is structurally invalid.

### 3B.2 — Batch-create children via /issue

Invoke the Skill tool:

- Try skill `"issue"` first. Fall back to `"larch:issue"`.
- args: `--input-file <BATCH_INPUT_FILE> [--intra-batch-deps-file <INTRA_BATCH_DEPS_FILE>] [--label L]... [--title-prefix P] [--repo R] [--closed-window-days N] [--dry-run] [--go]` — flags forwarded verbatim. Reconstruct `[--label L]...` by emitting one `--label <value>` for each `LABEL_1` through `LABEL_<LABELS_COUNT>` parsed in Step 0. Do NOT pass `<TASK>` (batch mode rejects a trailing description). When `PIECES_JSON` is non-empty, generate `INTRA_BATCH_DEPS_FILE` by writing a TSV file at `$UMBRELLA_TMPDIR/intra-batch-deps.tsv` (one row per edge: `<blocker-1based>\t<blocked-1based>`, derived from `pieces.json`'s `depends_on` arrays — for piece `i` with `depends_on=[j,...]`, emit row `<j>\t<i+1>` for each `j`), and include `--intra-batch-deps-file $UMBRELLA_TMPDIR/intra-batch-deps.tsv` in the `/issue` invocation. When `PIECES_JSON` is empty, omit `--intra-batch-deps-file`.

Parse the per-item `ISSUE_<i>_NUMBER`, `ISSUE_<i>_URL`, `ISSUE_<i>_TITLE`, `ISSUE_<i>_DUPLICATE_OF_NUMBER`, `ISSUE_<i>_DUPLICATE_OF_URL`, `ISSUE_<i>_DRY_RUN`, `ISSUE_<i>_FAILED`, plus aggregate `ISSUES_CREATED`, `ISSUES_DEDUPLICATED`, `ISSUES_FAILED`.

**Abort condition**: if `ISSUES_FAILED >= 1`, do NOT proceed to umbrella creation. Capture the children-batch-failure as session state (preserve `ISSUES_FAILED` and the count of successfully-resolved children for Step 4's summary), populate the `CHILD_*` output fields with whatever did succeed (for partial-failure auditability), and jump to Step 4 with `UMBRELLA_NUMBER` and `UMBRELLA_URL` **omitted** from `output.kv` entirely — do NOT write them with blank values. The canonical Step 4 grammar marks these keys present only on multi-piece success, so consumers distinguish success from failure by key presence/absence; writing blank values would validate but break that contract. Skip 3B.3 and 3B.4. Do NOT print a warning here — Step 4 is the single emission point for the human summary line and will render the multi-piece children-batch-failed shape on this path.

**`created-eq-1` bypass condition** (normal mode only — closes #717): when the children-batch-failed abort above does NOT fire (i.e., the batch succeeded with `ISSUES_FAILED=0`), apply this second post-3B.2 gate before falling through to Step 3B.3. When **`INPUT_FILE` is empty AND `DRY_RUN=false` AND `ISSUES_FAILED=0` AND `ISSUES_CREATED=1`**, emit a downgrade KV bundle (parallel to Step 3B.1's `decomposition-lt-2` and Step 2's `input-file-distinct-lt-2` conventions) and skip Steps 3B.3 and 3B.4 entirely. Precedence: `failed batch (ISSUES_FAILED>=1) > created-eq-1 (normal mode, non-dry-run) > existing 3B.3 dispatch`. The bypass exists because if `/issue --input-file` deduplicated `N-1` of `N` pieces to existing tickets and created only 1 new issue, the natural shape is one-shot — creating a brand-new umbrella tracking that single child plus `N-1` duplicates is wrong. Do NOT execute Step 3A on this path — children were already created in Step 3B.2; re-invoking `/issue` would double-create.

The bypass procedure:

1. **Identify the single new child's piece-index `c`**: the unique `i` where `ISSUE_<i>_NUMBER` is non-empty AND `ISSUE_<i>_DUPLICATE_OF_NUMBER` is empty AND `ISSUE_<i>_FAILED` is not `true` AND `ISSUE_<i>_DRY_RUN` is not `true`. Set `CHILD_NEW_NUMBER = ISSUE_<c>_NUMBER`, `CHILD_NEW_URL = ISSUE_<c>_URL`, `CHILD_NEW_TITLE = ISSUE_<c>_TITLE`.

2. **Build a thin bidirectional edge set incident to `c`** (using `pieces.json`'s `depends_on` info — captured in the session-state `PIECE_<i>_DEPENDS_ON` lines from Step 3B.1). Scan ALL pieces (not just `c`) and keep every edge incident to `c` in EITHER direction:
   - For each `j` in `pieces.json[c].depends_on` (i.e., piece `c` depends on piece `j`): if `j` resolves to a real issue number (via `ISSUE_<j>_NUMBER` if newly created OR `ISSUE_<j>_DUPLICATE_OF_NUMBER` if dedup'd), emit edge `<resolved-j> → <c-number>` (j blocks c).
   - For each piece `i ≠ c`: if `pieces.json[i].depends_on` contains `c` (i.e., piece `i` depends on piece `c`), and `i` resolves, emit edge `<c-number> → <resolved-i>` (c blocks i).
   - Skip edges where the other endpoint is a failed sibling (no resolved number); log to stderr if any are skipped.

3. **Build `proposed-edges.tsv` and `children.tsv`**: Use the Write tool (per Step 3B.4's existing pattern) to write `$UMBRELLA_TMPDIR/proposed-edges.tsv` with one row per resolved edge (`<blocker>\t<blocked>`), and `$UMBRELLA_TMPDIR/children.tsv` containing **ALL resolved children** — the newly-created child as the FIRST row (so it remains `wire-dag --no-backlinks`'s API-availability probe target) followed by every successfully-resolved deduplicated sibling (`<resolved-number>\t<title>\t<url>` per row, where `<resolved-number>` is `ISSUE_<i>_DUPLICATE_OF_NUMBER` for dedup'd pieces). Including dedup'd siblings is essential for `wire-dag`'s cycle-check completeness: `helpers.sh wire-dag` enumerates existing GitHub `blocked_by` edges only for issues listed in `children.tsv`, so a single-row `children.tsv` would miss reverse paths that traverse dedup'd siblings and could let a real cycle pass the gate. Skip pieces that failed (no resolved number).

4. **Invoke `helpers.sh wire-dag --no-backlinks`** (one Bash tool call):

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/skills/umbrella/scripts/helpers.sh wire-dag --no-backlinks --tmpdir "$UMBRELLA_TMPDIR" --umbrella '' --children-file "$UMBRELLA_TMPDIR/children.tsv" --edges-file "$UMBRELLA_TMPDIR/proposed-edges.tsv" --repo "$REPO"
   ```

   `--no-backlinks` instructs `wire-dag` to (a) probe the first child in `children.tsv` for API availability instead of the (empty) umbrella; (b) skip the entire back-link emission loop — no native-relationship `gh api` calls and no `gh issue comment` posts. Edge wiring + cycle-check + idempotency + per-edge counters are unchanged. `wire-dag` still emits `EDGES_*` and `BACKLINKS_*` counters on stdout, but per the schema rule below the orchestrator does NOT propagate them to `output.kv` on this path. On non-zero exit, log `ERROR=` and continue — partial wiring is acceptable.

5. **Compose `output.kv`**: write the 3-line downgrade bundle:
   ```
   UMBRELLA_VERDICT=one-shot
   UMBRELLA_DOWNGRADE=created-eq-1
   UMBRELLA_RATIONALE=Downgraded — ISSUES_CREATED=1; <D> sibling pieces deduplicated to existing issues
   ```
   Where `<D> = ISSUES_DEDUPLICATED`. Then emit aggregate counts (`CHILDREN_CREATED=1`, `CHILDREN_DEDUPLICATED=<D>`, `CHILDREN_FAILED=0`) and the **renormalized `CHILD_*` set**: `CHILD_1` is always the newly-created child (piece `c`) — set `CHILD_1_NUMBER=$CHILD_NEW_NUMBER`, `CHILD_1_URL=$CHILD_NEW_URL`, `CHILD_1_TITLE=$CHILD_NEW_TITLE`. Then append deduplicated siblings as `CHILD_2_*`, `CHILD_3_*`, ... in pieces order (using `ISSUE_<i>_DUPLICATE_OF_NUMBER` / `ISSUE_<i>_DUPLICATE_OF_URL` / `ISSUE_<i>_TITLE` for each dedup'd piece `i ≠ c`). This preserves the documented `CHILD_1_URL` consumer contract for one-shot consumers (e.g., `/skill-evolver`). Do NOT emit `UMBRELLA_NUMBER`, `UMBRELLA_URL`, `EDGES_ADDED`, per-edge `EDGE_<j>_*`, or `BACKLINKS_*` keys — they are reserved for the multi-piece-success path; the bypass output is one-shot-shaped.

6. **Skip Steps 3B.3 and 3B.4 entirely** and continue at Step 4.

For each successfully-resolved item (created OR deduplicated to an existing issue), record `(piece_index, issue_number, issue_url, title)` — this is the canonical child set for umbrella body, DAG wiring, and back-links. Items resolved as `ISSUE_<i>_DRY_RUN=true` count as children for output purposes; on the multi-piece dry-run path, 3B.3's dry-run guard skips umbrella body composition + umbrella creation AND 3B.4's wiring + back-links entirely. When `ISSUE_<i>_DRY_RUN=true`, record the child per the dry-run child shape in Step 4.

### 3B.3 — Compose umbrella body and create umbrella

Skip this entire sub-step when `DRY_RUN=true` (no real children exist on GitHub — `/issue --dry-run` does not emit issue numbers, so `children.tsv`'s numeric-first-column invariant cannot hold and `render-umbrella-body.sh`'s validator at lines 38–42 would hard-fail; the renderer is left strict by design). Print `⏭️ /umbrella: umbrella body + umbrella create + dependency wiring + back-links skipped (--dry-run)` and jump to Step 4 with `UMBRELLA_NUMBER` and `UMBRELLA_URL` **omitted** from `output.kv` entirely (consistent with the canonical "only on multi-piece + success" contract documented in Step 4). The folded skip-line subsumes 3B.4's existing skip breadcrumb on this path because the orchestrator never enters 3B.4. Step 4's emit-output then renders the canonical multi-piece dry-run breadcrumb (`ℹ /umbrella: dry-run — would file umbrella with <N> children`) using `<N> = CHILDREN_CREATED` from session state authored in Step 3B.2 — not dependent on this skipped sub-step's outputs.

**Pre-decomposed-input mode**: when `INPUT_FILE` is non-empty (so `UMBRELLA_SUMMARY_FILE` is also non-empty by paired-flag validation), the summary is caller-supplied at `UMBRELLA_SUMMARY_FILE`; do NOT compose one. Skip the LLM-summary step. Pass the caller's summary path as `--summary-file` to the renderer (the caller is expected to have applied compose-time sanitization — strip control chars, redact secrets/internal URLs/PII). Continue with the renderer invocation below using `--summary-file "$UMBRELLA_SUMMARY_FILE"`.

**Normal mode**: compose a one-paragraph summary of the overall task (≤ 4 sentences, plain prose) — distinct from any individual piece body. Write to `$UMBRELLA_TMPDIR/summary.txt` and use that path as `--summary-file`.

Render the umbrella issue body:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/umbrella/scripts/render-umbrella-body.sh --tmpdir "$UMBRELLA_TMPDIR" --summary-file "<summary-path>" --children-file "$UMBRELLA_TMPDIR/children.tsv"
```

Where `<summary-path>` is `$UMBRELLA_SUMMARY_FILE` in pre-decomposed-input mode and `$UMBRELLA_TMPDIR/summary.txt` in normal mode. Write `$UMBRELLA_TMPDIR/children.tsv` (one row per child: `<number>\t<title>\t<url>`, in pieces order) BEFORE invoking the renderer. The renderer emits `UMBRELLA_BODY_FILE=<path>` and `UMBRELLA_TITLE_HINT=<derived umbrella title from the first sentence of the summary>`.

Then forward to `/issue` (single mode) for the umbrella itself:

- Try skill `"issue"` first; fall back to `"larch:issue"`.
- args: `--body-file <UMBRELLA_BODY_FILE> [--label L]... [--title-prefix P] [--repo R] [--closed-window-days N] [--dry-run] [--go] <UMBRELLA_TITLE_HINT>` — trailing arg is the explicit title (`/issue` uses it directly as the issue title when combined with `--body-file`). Reconstruct `[--label L]...` by emitting one `--label <value>` for each `LABEL_1` through `LABEL_<LABELS_COUNT>` parsed in Step 0.

Parse `ISSUE_1_NUMBER` (capture as `UMBRELLA_NUMBER`), `ISSUE_1_URL` (capture as `UMBRELLA_URL`), `ISSUE_1_TITLE` (capture as `UMBRELLA_TITLE`). On `ISSUE_1_FAILED=true` or empty `ISSUE_1_NUMBER`, capture the umbrella-creation failure: derive a sanitized one-line `UMBRELLA_FAILURE_REASON` value from `/issue`'s available failure signals. `ISSUE_1_FAILED=true` is a boolean — for an umbrella-create failure (the typical case here, since 3B.3 invokes `/issue` in single mode for the umbrella) `/issue` Step 6 emits the explanatory detail on **stderr** as `**⚠ /issue: create failed for item 1: <msg>**` (not on stdout); `ISSUE_1_ERROR=<msg>` appears on stdout only for dep-link / transitive-failure paths. Compose `UMBRELLA_FAILURE_REASON` from, in priority order: (a) the redacted stderr `**⚠ /issue: create failed …**` line when present, (b) `ISSUE_1_ERROR=<msg>` from stdout when present (dep-link / transitive paths), (c) as a constrained stdout fallback, ONLY lines matching `^ISSUE_1_` (umbrella-create-related) and `^ISSUES_FAILED=` — never an unconstrained tail of the full stream (the batch child KV lines that precede umbrella creation must not bleed into this value). Sanitize the value: strip control characters, replace newlines and tabs with single spaces, collapse internal whitespace runs to one space, strip markdown metacharacters (`*`, `_`, `` ` ``, `[`, `]`, `(`, `)`) so the value cannot break the surrounding `**…**` formatting in Step 4's partial breadcrumb, redact secrets / API keys / OAuth / JWT / passwords / certificates → `<REDACTED-TOKEN>`, internal hostnames / URLs / private IPs → `<INTERNAL-URL>`, PII (emails, account IDs tied to a real user) → `<REDACTED-PII>` (mirroring the `skills/implement/SKILL.md` Execution-Issues-Tracking compose-time redaction tokens), and trim to ~200 characters. Then jump to Step 4 with `UMBRELLA_NUMBER` and `UMBRELLA_URL` **omitted** from `output.kv` entirely — do NOT write them with blank values. The canonical Step 4 grammar marks these keys present only on multi-piece success, so consumers distinguish success from failure by key presence/absence; writing blank values would validate but break that contract. Carry `UMBRELLA_FAILURE_REASON` through to Step 4's `output.kv` as the optional KV line (see the optional schema entry); when no failure signal can be extracted, omit `UMBRELLA_FAILURE_REASON` rather than writing a blank value. Skip 3B.4. Do NOT print a warning here — Step 4 is the single emission point for the human summary line and will render the multi-piece partial shape on this path.

### 3B.4 — Wire DAG dependencies and post back-links

Skip this entire sub-step when `DRY_RUN=true` (no children actually exist on GitHub). Print `⏭️ /umbrella: dependency wiring + back-links skipped (--dry-run)` and jump to Step 4.

**Pre-decomposed-input mode**: when `INPUT_FILE` is non-empty, Step 3B.1 was skipped. Two sub-cases:

- **When `PIECES_JSON` is non-empty**: the caller supplied inter-piece dependency edges. Read the validated `PIECES_JSON` (validated at Step 3B.1.5) and compose inter-child edges: for each piece index `i` (0-based in JSON, 1-based as batch item `i+1`) with `depends_on=[j, k, ...]`, resolve piece indices to issue numbers via the `/issue` batch return (`ISSUE_<j>_NUMBER` if newly created, or `ISSUE_<j>_DUPLICATE_OF_NUMBER` if dedup'd; skip if `ISSUE_<j>_FAILED=true`) and propose edges `<resolved-j>\t<resolved-i+1-number>`, `<resolved-k>\t<resolved-i+1-number>`, etc. Then append the **child→umbrella edges**: for each resolved child `c`, append `<c>\t<UMBRELLA_NUMBER>`. Write all rows to `$UMBRELLA_TMPDIR/proposed-edges.tsv` via the Write tool.
- **When `PIECES_JSON` is empty**: the caller's pre-built batch input has no inter-piece dependency information, so the inter-child edges are empty by construction — but the **child→umbrella edges** are still deterministic (each child blocks the umbrella, gating its completion on the children's). Compose one row per resolved child of the form `<child-number>\t<UMBRELLA_NUMBER>`, writing the result to `$UMBRELLA_TMPDIR/proposed-edges.tsv` via the Write tool.

In both sub-cases, the "resolved children" set is the rows of `$UMBRELLA_TMPDIR/children.tsv` (which Step 3B.3 wrote before this sub-step). The back-link comment fallback (`Part of umbrella #M — <umbrella-title>` comments on each child) and the back-link comment-existence idempotency check remain active.

**Normal mode**: compose the proposed edge list in two parts. First, the inter-child edges: from the `depends-on` field of each piece — for piece index `i` with `depends_on=[j, k, ...]`, propose edges `child[j] blocks child[i]`, `child[k] blocks child[i]`, etc. (using the resolved issue numbers from 3B.2). Then, **child→umbrella edges**: for each successfully-resolved child issue number `c` from 3B.2 (newly-created via `ISSUE_<i>_NUMBER` OR deduplicated via `ISSUE_<i>_DUPLICATE_OF_NUMBER`, excluding `ISSUE_<i>_FAILED=true` items), append the row `<c>\t<UMBRELLA_NUMBER>` so the umbrella is gated on its children's completion. Write all rows to `$UMBRELLA_TMPDIR/proposed-edges.tsv` (one row per edge: `<blocker-number>\t<blocked-number>`) using the Write tool. The umbrella-blocker row set deliberately covers every resolved child — a partial set would leave the umbrella's blocked-by graph incomplete and downstream DAG-aware automation would see only some children as gating the umbrella.

Then run the wiring + back-links coordinator:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/umbrella/scripts/helpers.sh wire-dag --tmpdir "$UMBRELLA_TMPDIR" --umbrella "$UMBRELLA_NUMBER" --umbrella-title "$UMBRELLA_TITLE" --children-file "$UMBRELLA_TMPDIR/children.tsv" --edges-file "$UMBRELLA_TMPDIR/proposed-edges.tsv" --repo "$REPO"
```

`helpers.sh wire-dag` is a coordinator that, internally, (a) builds the existing-edges TSV from the **full reachable `blocked_by` subgraph** (transitive closure from children + both endpoints of every proposed edge — issue #718; pre-#718 the TSV was seeded only from each child's `blocked_by`, missing cycles closing through non-child intermediaries), bounded by `WIRE_DAG_TRAVERSAL_NODE_CAP` (default 200), (b) runs `helpers.sh check-cycle` on the union of existing + proposed edges to refuse any edge that would create a cycle, (c) adds each surviving new edge via the GitHub dependency-API adapter, and (d) posts a back-link comment (`Part of umbrella #M — <umbrella-title>`) on each child unless an existing back-link comment matching the literal prefix <code>Part of umbrella #${UMBRELLA} — </code> is already present in the child's comments (issue #716 — the prior `blocked_by` native-detection probe was unreachable because no path created the matching native edge in the direction that probe tested, so re-runs accumulated duplicate comments). The comment-existence idempotency check runs unconditionally on the back-link loop, independent of `api_available` — the comments API is a separate GitHub surface from the dependencies API; on transient `gh api` failure the check fails open (post the comment).

Parse stdout for `EDGES_ADDED`, per-edge `EDGE_<j>_BLOCKER`, `EDGE_<j>_BLOCKED`, `EDGES_REJECTED_CYCLE` (count of rejected proposed edges), `EDGES_SKIPPED_EXISTING` (count of skipped already-present edges, including idempotent 422 already-exists responses per `add-blocked-by.sh:193-196`), `EDGES_SKIPPED_API_UNAVAILABLE` (count of edges skipped because the GitHub dependency API surface was not usable for this run — either confirmed feature-missing OR transient probe failure; fail-open, do not abort. Issue #728's fix split the disambiguating cause into the new `PROBE_FAILED` parse-only counter — `EDGES_SKIPPED_API_UNAVAILABLE` semantics are intentionally preserved as broad "repo-wide skip"; cause is read from `PROBE_FAILED`), `EDGES_FAILED` (count covering two categories: (a) per-edge **operational** failures where the POST returned a non-success status that did NOT match the feature-missing fingerprint — rate-limit, permission denied, ambiguous 404, other 4xx, 5xx, request-shape mismatches, blocker-id lookup failure, network (issue #720); (b) per-edge **policy-driven** failures of type `bound-exhausted` — set when the transitive `blocked_by` traversal hit `WIRE_DAG_TRAVERSAL_NODE_CAP` and the resulting `CYCLE=false` answer cannot be trusted on a known-incomplete TSV (issue #718 fail-closed posture). Stderr emits one redacted single-line warning per `EDGES_FAILED` event of the form `**⚠ /umbrella: wire-dag edge BLOCKER->BLOCKED failed (HTTP STATUS): REASON**` for both categories — `STATUS` carries the HTTP code for operational failures or the literal `bound-exhausted` for policy-driven failures. A separate one-time-per-run stderr warning fires when the traversal cap is hit; a one-time-per-failed-node warning fires for transient `blocked_by` lookup failures (these do NOT increment `EDGES_FAILED` — fail-open, residual posture). The `EDGES_FAILED` posture is split per category: the `wire-dag` run never aborts on `EDGES_FAILED` (orchestration-level fail-open, parity with operational failures); but for the `bound-exhausted` category specifically, the per-edge POST is **skipped** for that candidate (per-edge fail-CLOSED — the `CYCLE=false` answer cannot be trusted on a known-incomplete TSV). For operational `EDGES_FAILED` causes (HTTP 4xx/5xx, id-lookup, network), the POST was attempted and rejected by the server. Both categories share the same counter, the same warning prefix, and the same orchestration-continues posture; they differ only in whether a POST was attempted), `PROBE_FAILED` (parse-only, 0 or 1, issue #728): per-run flag distinguishing the two repo-wide-skip causes — `0` = confirmed feature-missing (probe got a fingerprinted 404) OR no probe attempted (e.g., empty `probe_target` on the `--no-backlinks` first-child path); `1` = transient/operational probe failure (5xx + retry also failed, or HTTP response other than 2xx/fingerprinted-404). The probe path issues at most two `gh api -i` calls — one initial attempt plus one retry on 5xx or empty-status only; 429, other 4xx, and 2xx/fingerprinted-404 are single-attempt. When `PROBE_FAILED=1`, a dedicated stderr warning `**⚠ /umbrella: wire-dag probe failed (HTTP STATUS): REASON**` fires once and the legacy "API not available" warning is suppressed to avoid double-warning. `BACKLINKS_POSTED`, `BACKLINKS_SKIPPED_EXISTING` (count of children whose existing back-link comment matching <code>Part of umbrella #${UMBRELLA} — </code> was already detected; renamed from `BACKLINKS_SKIPPED_NATIVE` per #716 — the prior counter name referred to a "native umbrella relationship" probe that was unreachable in practice). On non-zero exit, log the `ERROR=` line and continue — partial wiring is acceptable; the title-prefix step below still runs (its concern is independent of dependency wiring).

Then prepend the umbrella's issue-number marker — the literal text <code>(Umbrella: &lt;N&gt;) </code> with `<N>` substituted with `$UMBRELLA_NUMBER` (note the trailing space, load-bearing; the HTML `<code>` block instead of a Markdown backtick span avoids `MD038/no-space-in-code` flags on the trailing space, and `&lt;N&gt;` rather than `$UMBRELLA_NUMBER` inside the block avoids `MD049/emphasis-style` flags on the underscores) — to the title of every **newly-created** child issue. Build `$UMBRELLA_TMPDIR/newly-created-children.tsv` (same `<number>\t<title>\t<url>` shape as `children.tsv`) using the Write tool, including only children where `ISSUE_<i>_NUMBER` is non-empty AND `ISSUE_<i>_DUPLICATE_OF_NUMBER` is empty AND `ISSUE_<i>_FAILED` is not `true` AND `ISSUE_<i>_DRY_RUN` is not `true`. Use the title currently on the GitHub issue, taken from `ISSUE_<i>_TITLE` in `/issue`'s stdout. That field is `/issue`'s post-creation snapshot — it already incorporates any `--title-prefix` `/umbrella` forwarded — so it matches the live title at the time `prefix-titles` runs, which is the exact byte sequence the helper's idempotency check compares against. (Equivalent on the normal-mode path: the `pieces.json` title plus any `--title-prefix`. Pre-decomposed-input mode has no `pieces.json` but emits `ISSUE_<i>_TITLE` regardless.) Pre-decomposed-input mode: same filter; the `pieces.json` filter clause is irrelevant because there is no `pieces.json`, but the per-piece `ISSUE_<i>_*` keys are emitted by `/issue` regardless. Skip writing the file (and the invocation below) when no pieces match the filter — the helper would emit zeros, but the invocation is wasted.
The filter intentionally excludes dedup'd children: a dedup'd child is owned by whichever umbrella created it (or by no umbrella), and re-prefixing it would stomp on the prior owner's title. Failed children do not exist on GitHub; dry-run children only exist in `/issue`'s local tally. The umbrella issue itself is not renamed — it is the umbrella, it does not need to reference itself.

```bash
${CLAUDE_PLUGIN_ROOT}/skills/umbrella/scripts/helpers.sh prefix-titles --umbrella "$UMBRELLA_NUMBER" --children-file "$UMBRELLA_TMPDIR/newly-created-children.tsv" --repo "$REPO"
```

Parse stdout for `TITLES_RENAMED`, `TITLES_SKIPPED_EXISTING`, `TITLES_FAILED`. These are parse-only — they are NOT propagated through `output.kv` (parallel to `wire-dag`'s `EDGES_REJECTED_CYCLE` / `EDGES_SKIPPED_*` / `BACKLINKS_SKIPPED_EXISTING` precedent). Idempotency: `prefix-titles` skips a child whose title already starts with the exact same <code>(Umbrella: &lt;N&gt;) </code> marker as the current run (`<N>` = `$UMBRELLA_NUMBER`; same-umbrella resume case — the trailing space is part of the literal). On per-row `gh issue edit` failure, the helper emits a redacted stderr warning of the form `**⚠ /umbrella: prefix-titles edit #N failed (CODE): REASON**` and continues to the next row. On non-zero exit (caller-side input validation failure — bad flag or missing file), log the `ERROR=` line and continue — title prefixing is best-effort, on par with DAG wiring.

**Operator observability**: parse-only stdout counters mean automated `output.kv` consumers cannot distinguish a fully-successful prefix-titles pass from a partial-failure pass. Operators monitoring umbrella runs for title-prefix correctness should scan stderr for the `**⚠ /umbrella: prefix-titles edit #N failed (CODE): REASON**` warnings emitted per failed row — the count of those lines equals `TITLES_FAILED` and identifies which children's titles were not rewritten.

**Path coverage**: title prefixing runs only when Step 3B.4 itself runs — i.e., on the multi-piece-with-real-umbrella path. The Step 3B.2 `created-eq-1` bypass (where `N-1` of `N` decomposed pieces deduplicated and only one new child was created) explicitly skips Steps 3B.3 and 3B.4 *as a unit*: no umbrella is created, so no `$UMBRELLA_NUMBER` exists, and the title-prefix marker is undefined on that path. This is intentional, not an orchestrator bug — operators inspecting a `created-eq-1` downgrade run should not expect the new child's title to carry an <code>(Umbrella: &lt;N&gt;) </code> marker. Likewise: one-shot path (Step 3A), multi-piece children-batch-failure (3B.2 abort), multi-piece umbrella-creation-failure (3B.3 fault), and the `--dry-run` early-exit at the top of 3B.4 all skip the prefix pass for the same reason — the umbrella that would own the marker does not exist.

## Step 4 — Emit Output

```bash
${CLAUDE_PLUGIN_ROOT}/skills/umbrella/scripts/helpers.sh emit-output --kv-file "$UMBRELLA_TMPDIR/output.kv"
```

Write `$UMBRELLA_TMPDIR/output.kv` (one `KEY=VALUE` line per fact) BEFORE invoking the emitter, using the Write tool. The orchestrator owns completeness (it authored `output.kv`); the emitter validates the KV grammar (well-formed `KEY=VALUE` lines, no embedded newlines, no duplicate keys) and streams to stdout in file order. The canonical order shown below is author guidance for composing `output.kv`, not a guarantee from `emit-output`:

```
UMBRELLA_VERDICT=<one-shot|multi-piece>
UMBRELLA_RATIONALE=<one-line>
UMBRELLA_DOWNGRADE=<token>   (emitted on any bypass path — `decomposition-lt-2` (Step 3B.1 fallback), `input-file-distinct-lt-2` (Step 2 pre-decomposed-input mode), `created-eq-1` (Step 3B.2 normal-mode bypass))
CHILDREN_CREATED=<N>
CHILDREN_DEDUPLICATED=<N>
CHILDREN_FAILED=<N>
CHILD_<i>_NUMBER=<N>         (only on resolved/non-dry-run children)
CHILD_<i>_URL=<url>          (only on resolved/non-dry-run children)
CHILD_<i>_TITLE=<title>
CHILD_<i>_DRY_RUN=true       (only on dry-run children — when emitted, `CHILD_<i>_NUMBER` and `CHILD_<i>_URL` are omitted; `CHILD_<i>_TITLE` remains)
UMBRELLA_NUMBER=<N>          (only on multi-piece + success)
UMBRELLA_URL=<url>           (only on multi-piece + success)
UMBRELLA_FAILURE_REASON=<text>   (only on multi-piece partial — children created, umbrella creation failed; sanitized one-line value, ≤200 chars; omitted when no failure signal could be extracted)
EDGES_ADDED=<N>              (only on multi-piece, non-dry-run, success)
EDGE_<j>_BLOCKER=<N>
EDGE_<j>_BLOCKED=<M>
BACKLINKS_POSTED=<N>         (only on multi-piece, non-dry-run, success)
```

Global dry-run ⇒ every resolved-non-failed child uses the dry-run child shape; mixed-mode runs are not currently produced by `/umbrella`. The dry-run child shape mirrors `/issue --dry-run`'s upstream `ISSUE_<i>_DRY_RUN=true` grammar (per `skills/issue/SKILL.md` Step 6 dry-run branch), keeping `output.kv`'s child grammar a clean projection of `/issue`'s rather than a second invent-your-own-numbers layer.

After `emit-output` returns, the orchestrator (the LLM running this skill) MUST print exactly one human summary breadcrumb of the form below. Step 4 is the single emission point for this summary — Step 3B.3's umbrella-creation-failure path defers to Step 4 instead of printing inline. The orchestrator composes each shape using both `output.kv` values AND any session state captured from earlier sub-steps (e.g., `/issue`'s stdout for the one-shot dedup'd / failed cases — `ISSUE_1_DUPLICATE_OF_NUMBER`/`ISSUE_1_DUPLICATE_OF_URL` and the `/issue` failure context). The multi-piece partial shape interpolates the optional `UMBRELLA_FAILURE_REASON` field documented in the canonical grammar above; the remaining shapes (one-shot, multi-piece success, multi-piece dry-run) compose from `output.kv` values and earlier-step session state without additional canonical fields:

- one-shot: `✅ /umbrella: filed #<N> — <url>` (or `ℹ /umbrella: dedup'd to #<N> — <url>` / `**⚠ /umbrella: failed — <error>**` etc.).
- created-eq-1 bypass (Step 3B.2 normal-mode `ISSUES_CREATED==1` downgrade): `✅ /umbrella: filed #<N> — <url> (multi-piece downgraded — created-eq-1, <D> sibling(s) deduplicated to existing issues, no umbrella issue created)` where `<N>` / `<url>` are `CHILD_1_NUMBER` / `CHILD_1_URL` and `<D>` is `CHILDREN_DEDUPLICATED` from `output.kv`.
- multi-piece success: `✅ /umbrella: filed umbrella #<M> with <N> children, <E> dependency edge(s), <B> back-link(s) — <umbrella-url>`.
- multi-piece dry-run: `ℹ /umbrella: dry-run — would file umbrella with <N> children`.
- multi-piece partial (children created, umbrella failed): when `UMBRELLA_FAILURE_REASON` is present in `output.kv`, render `**⚠ /umbrella: <N> children created but umbrella creation failed (<UMBRELLA_FAILURE_REASON>). Children remain unlinked.**`; when omitted (no failure signal could be extracted), fall back to `**⚠ /umbrella: <N> children created but umbrella creation failed. Children remain unlinked.**`.
- multi-piece children-batch-failed (some children failed during batch creation, umbrella never attempted): `**⚠ /umbrella: /issue batch reported <F> failure(s); refusing to create a half-populated umbrella. <N> children remain unlinked.**`.

## Step 5 — Cleanup

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/cleanup-tmpdir.sh --dir "$UMBRELLA_TMPDIR"
```

## Sub-skill Invocation

This skill invokes `/issue` via the Skill tool (Step 3A and Steps 3B.2 / 3B.3). See `${CLAUDE_PLUGIN_ROOT}/skills/shared/subskill-invocation.md` for the canonical conventions. This skill is a pure delegator over `/issue` for the issue-creation half of the work — the machine contract consumed in post-Skill-call steps is the **stdout** grammar (deterministic mechanical verification per the conventions checklist). One narrow exception: Step 3B.3's umbrella-creation-failure path additionally consumes the operator-facing `**⚠ /issue: create failed for item 1: <msg>**` line on **stderr** to compose `UMBRELLA_FAILURE_REASON` per the priority-list and sanitization rules in 3B.3 — stderr is not part of the deterministic stdout grammar, so the priority list there encodes the merge order. The sub-skill calls happen at known checkpoints, not buried in conditionals.

## Script contracts

Each script under `scripts/` has a sibling contract `.md` documenting CLI surface, stdout grammar, exit codes, and edit-in-sync rules (per `AGENTS.md` "Per-script contracts live beside the script"):

- `scripts/parse-args.sh` — Step 0 flag parser; contract `scripts/parse-args.md`.
- `scripts/render-batch-input.sh` — Step 3B.1 batch-input renderer (`pieces.json` → `/issue --input-file` markdown); contract `scripts/render-batch-input.md`.
- `scripts/render-umbrella-body.sh` — Step 3B.3 umbrella-body composer (summary + children TSV → markdown body with GitHub-native checklist); contract `scripts/render-umbrella-body.md`.
- `scripts/validate-pieces-json.sh` — Step 3B.1.5 caller-supplied `pieces.json` dep-edge validator; contract `scripts/validate-pieces-json.md`.
- `scripts/test-validate-pieces-json.sh` — regression harness for `validate-pieces-json.sh`; contract `scripts/test-validate-pieces-json.md`. Wired into `make lint` via the `test-validate-pieces-json` Makefile target.
- `scripts/helpers.sh` — Steps 3B.4 / 4 consolidated helpers exposing `check-cycle`, `wire-dag`, `prefix-titles`, and `emit-output` subcommands; contract `scripts/helpers.md`. `prefix-titles` is the Step 3B.4 child-title rename pass — prepends the literal <code>(Umbrella: &lt;N&gt;) </code> marker on newly-created children only.
- `scripts/test-helpers.sh` — regression harness for `helpers.sh check-cycle` (pure logic), `helpers.sh wire-dag` (PATH-stub `gh` for the per-edge POST classifier and counter categorization, including `EDGES_FAILED`), and `helpers.sh prefix-titles` (PATH-stub `gh` for the title-rename loop, idempotency guards, and per-row failure handling); contract `scripts/test-helpers.md`. Wired into `make lint` via the `test-umbrella-helpers` Makefile target.
- `scripts/test-umbrella-parse-args.sh` — regression harness for `parse-args.sh`; contract `scripts/test-umbrella-parse-args.md`. Wired into `make lint` via the `test-umbrella-parse-args` Makefile target alongside `test-umbrella-helpers`.
- `scripts/test-umbrella-emit-output-contract.sh` — structural harness pinning Step 2's input-file dry-run-safe distinct-count rule, Step 3B.3 / 3B.4's matched-pair dry-run skip directives, Step 4 prose attribution and the canonical breadcrumb shape templates in `SKILL.md`, plus the `emit-output` stderr-discipline literals in `helpers.md`, plus the Step 4 dry-run child shape contract (`CHILD_<i>_DRY_RUN=true` and per-key omission annotations on `CHILD_<i>_NUMBER` / `CHILD_<i>_URL` — added in #726); contract `scripts/test-umbrella-emit-output-contract.md`. Wired into `make lint` via the `test-umbrella-emit-output-contract` Makefile target.
- `scripts/test-render-batch-input.sh` — regression harness pinning the malformed-`pieces.json` gatekeeper contract of `render-batch-input.sh` (parse failure OR valid-JSON-with-non-array-top-level → stable `ERROR=invalid pieces.json: <reason>` stderr line + exit 1, not raw `jq:` output); contract `scripts/test-render-batch-input.md`. Wired into `make lint` via the `test-umbrella-render-batch-input` Makefile target.
- `scripts/test-render-umbrella-body.sh` — runtime conformance harness for `render-umbrella-body.sh`; pins the `--tmpdir` writability preflight, the checked-write + atomic-rename success / failure paths, and the existing children-TSV malformed-input path; contract `scripts/test-render-umbrella-body.md`. Wired into `make lint` via the `test-render-umbrella-body` Makefile target alongside `test-umbrella-emit-output-contract`.
