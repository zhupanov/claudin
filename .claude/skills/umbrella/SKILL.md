---
name: umbrella
description: "Use when planning or breaking up a task or plan into GitHub issues — auto-classifies one-shot vs multi-piece work, delegates to /issue (batch mode plus an umbrella tracking issue), wires hard GitHub native block dependencies into an execution DAG, and back-links each child issue to the umbrella."
argument-hint: "[--label L]... [--title-prefix P] [--repo OWNER/REPO] [--closed-window-days N] [--dry-run] [--go] [--debug] <task description or empty to deduce from context>"
allowed-tools: Bash, Read, Skill
---

# umbrella

Plan-to-issues orchestrator. Takes a task description (or deduces it from session context), classifies it as one-shot or multi-piece, and delegates GitHub issue creation to `/issue` — adding native blocked-by dependencies to form an execution DAG and back-linking children to the umbrella when multi-piece.

> **Before editing**, read `${CLAUDE_PLUGIN_ROOT}/skills/shared/skill-design-principles.md` (full file). Section III mechanical rules A/B/C override general writing-style guidance on conflict.

## Anti-patterns (with WHY)

- **NEVER** call `gh api` directly with hard-coded REST paths inside this `SKILL.md`. **Why**: GitHub's issue-dependency / sub-issue API surface has shifted multiple times (REST `/dependencies/blocked_by`, the sub-issues endpoint, the GraphQL `addSubIssue` mutation). Wrap every dependency-related GitHub call in `scripts/wire-dag.sh` so the surface can be swapped without rewriting prompt prose.
- **NEVER** add a blocking edge before verifying it does not create a cycle. **Why**: a cycle in the blocked-by graph deadlocks `/fix-issue` and any other automation that respects dependencies — and deadlocked queues fail silently. `wire-dag.sh` runs `check-cycle.sh` against the proposed edge plus all existing edges before posting.
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
| `--dry-run` | Forwarded to `/issue`. Multi-piece path also skips DAG wiring + back-links. |
| `--go` | Forwarded to `/issue` for child batch AND umbrella single. Posts `GO` on every successfully-created issue (children + umbrella). Duplicates / failed creates / dry-runs never get a GO comment (per `/issue` Step 6 contract). |
| `--debug` | Verbose mode for this skill's own helpers. |

## Step 0 — Setup

```bash
$PWD/.claude/skills/umbrella/scripts/parse-args.sh "$ARGUMENTS"
```

Parse stdout for: `LABELS_COUNT` (integer ≥ 0), then `LABEL_1` through `LABEL_<LABELS_COUNT>` (one indexed key per `--label` value; empty when `LABELS_COUNT=0`), `TITLE_PREFIX`, `REPO`, `CLOSED_WINDOW_DAYS`, `DRY_RUN` (`true|false`), `GO` (`true|false`), `DEBUG` (`true|false`), `TASK` (everything after the last flag — may be empty; preserves embedded whitespace AND any quote/escape characters verbatim), `UMBRELLA_TMPDIR` (mktemp dir created by the parser; cleaned at Step 5). When parsing each KV line, split on the FIRST `=` only — values may contain literal `=` characters (e.g., `LABEL_1=priority=high`).

When forwarding labels to `/issue` in Steps 3A, 3B.2, and 3B.3 below, reconstruct the repeated `--label` flags by emitting one `--label <value>` for each `LABEL_1` through `LABEL_<LABELS_COUNT>`.

On non-zero exit, print the `ERROR=` line and abort.

## Step 1 — Resolve Task Description

If `TASK` is non-empty, use it verbatim.

If `TASK` is empty, deduce the task from session context — the most recent unambiguous user request (e.g., a feature spec discussed in the prior turns, a research finding, a /research output the user just acted on). Surface the deduced task to the user as a single quoted line prefixed by `Deduced task:` so they can interrupt if you got it wrong. If the context is genuinely ambiguous (multiple plausible tasks, or none), abort with the error message: `/umbrella requires a task description and could not deduce one from context. Re-invoke with the description as a positional argument.`

## Step 2 — Classify One-Shot vs Multi-Piece

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

Parse `/issue`'s stdout for `ISSUES_CREATED`, `ISSUES_DEDUPLICATED`, `ISSUES_FAILED`, `ISSUE_1_NUMBER`, `ISSUE_1_URL`, `ISSUE_1_TITLE`, `ISSUE_1_DUPLICATE_OF_NUMBER` / `ISSUE_1_DUPLICATE_OF_URL` (when deduplicated), `ISSUE_1_DRY_RUN` (when dry-run). Capture into the `CHILD_*` fields per Step 4 (the one-shot child is `CHILD_1`).

Continue at Step 4. (No umbrella issue, no DAG, no back-links — there is only one child.)

## Step 3B — Multi-Piece Path

Four sub-steps run in order. Each is exactly one Bash tool call (Section III rule C). The LLM owns the decomposition; the scripts own the I/O and GitHub mechanics.

### 3B.1 — Decompose and write batch-input file

Decompose `TASK` into N concrete work-pieces (`N >= 2`). Each piece must be small enough to land as one PR but substantial enough to merit its own issue — bias toward pieces that are independently testable. Compose, in your reasoning, an ordered list of `(title, body, depends-on)` tuples:

- `title` — one line, ≤ 80 chars, imperative ("Add X", "Fix Y", "Refactor Z").
- `body` — markdown, the implementation contract for that piece (problem, suggested approach, acceptance criteria).
- `depends-on` — comma-separated 1-based indices of earlier pieces this one depends on (empty if none).

If decomposition produces fewer than 2 pieces, fall back to one-shot: print three strict KV lines — `UMBRELLA_VERDICT=one-shot` (preserving the Step 2 `UMBRELLA_VERDICT=<one-shot|multi-piece>` token grammar), `UMBRELLA_DOWNGRADE=decomposition-lt-2` (shell-safe machine token capturing the downgrade trigger on a separate KV line), and `UMBRELLA_RATIONALE=Downgraded from multi-piece — fewer than two decomposed pieces` (preserving the Step 2 verdict + rationale shape required by the "NEVER skip the user-visible classification verdict" anti-pattern) — and execute Step 3A with the original `TASK`. Carry `UMBRELLA_DOWNGRADE=decomposition-lt-2` through to Step 4's `output.kv` (see the optional schema entry).

Render the batch-input markdown file:

```bash
$PWD/.claude/skills/umbrella/scripts/render-batch-input.sh --tmpdir "$UMBRELLA_TMPDIR" --pieces-file "$UMBRELLA_TMPDIR/pieces.json"
```

Write `$UMBRELLA_TMPDIR/pieces.json` (a JSON array of `{title, body, depends_on: [int,...]}` objects in pieces order) BEFORE invoking the renderer using the Write tool. The renderer emits `BATCH_INPUT_FILE=<path>`, `PIECES_TOTAL=<N>`, plus per-piece `PIECE_<i>_TITLE` and `PIECE_<i>_DEPENDS_ON` lines. On non-zero exit, print `ERROR=` and abort.

### 3B.2 — Batch-create children via /issue

Invoke the Skill tool:

- Try skill `"issue"` first. Fall back to `"larch:issue"`.
- args: `--input-file <BATCH_INPUT_FILE> [--label L]... [--title-prefix P] [--repo R] [--closed-window-days N] [--dry-run] [--go]` — flags forwarded verbatim. Reconstruct `[--label L]...` by emitting one `--label <value>` for each `LABEL_1` through `LABEL_<LABELS_COUNT>` parsed in Step 0. Do NOT pass `<TASK>` (batch mode rejects a trailing description).

Parse the per-item `ISSUE_<i>_NUMBER`, `ISSUE_<i>_URL`, `ISSUE_<i>_TITLE`, `ISSUE_<i>_DUPLICATE_OF_NUMBER`, `ISSUE_<i>_DUPLICATE_OF_URL`, `ISSUE_<i>_DRY_RUN`, `ISSUE_<i>_FAILED`, plus aggregate `ISSUES_CREATED`, `ISSUES_DEDUPLICATED`, `ISSUES_FAILED`.

**Abort condition**: if `ISSUES_FAILED >= 1`, do NOT proceed to umbrella creation. Capture the children-batch-failure as session state (preserve `ISSUES_FAILED` and the count of successfully-resolved children for Step 4's summary), populate the `CHILD_*` output fields with whatever did succeed (for partial-failure auditability), and jump to Step 4 with `UMBRELLA_NUMBER` and `UMBRELLA_URL` **omitted** from `output.kv` entirely — do NOT write them with blank values. The canonical Step 4 grammar marks these keys present only on multi-piece success, so consumers distinguish success from failure by key presence/absence; writing blank values would validate but break that contract. Skip 3B.3 and 3B.4. Do NOT print a warning here — Step 4 is the single emission point for the human summary line and will render the multi-piece children-batch-failed shape on this path.

For each successfully-resolved item (created OR deduplicated to an existing issue), record `(piece_index, issue_number, issue_url, title)` — this is the canonical child set for umbrella body, DAG wiring, and back-links. Items resolved as `ISSUE_<i>_DRY_RUN=true` count as children for output purposes but skip wiring + back-links (handled in 3B.3 / 3B.4).

### 3B.3 — Compose umbrella body and create umbrella

Compose a one-paragraph summary of the overall task (≤ 4 sentences, plain prose) — distinct from any individual piece body. Render the umbrella issue body:

```bash
$PWD/.claude/skills/umbrella/scripts/render-umbrella-body.sh --tmpdir "$UMBRELLA_TMPDIR" --summary-file "$UMBRELLA_TMPDIR/summary.txt" --children-file "$UMBRELLA_TMPDIR/children.tsv"
```

Write `$UMBRELLA_TMPDIR/summary.txt` (the summary paragraph) and `$UMBRELLA_TMPDIR/children.tsv` (one row per child: `<number>\t<title>\t<url>`, in pieces order) BEFORE invoking the renderer. The renderer emits `UMBRELLA_BODY_FILE=<path>` and `UMBRELLA_TITLE_HINT=<derived umbrella title from the first sentence of the summary>`.

Then forward to `/issue` (single mode) for the umbrella itself:

- Try skill `"issue"` first; fall back to `"larch:issue"`.
- args: `--body-file <UMBRELLA_BODY_FILE> [--label L]... [--title-prefix P] [--repo R] [--closed-window-days N] [--dry-run] [--go] <UMBRELLA_TITLE_HINT>` — title is the trailing description (`/issue` derives the title from the first non-empty line, which is `UMBRELLA_TITLE_HINT`). Reconstruct `[--label L]...` by emitting one `--label <value>` for each `LABEL_1` through `LABEL_<LABELS_COUNT>` parsed in Step 0.

Parse `ISSUE_1_NUMBER` (capture as `UMBRELLA_NUMBER`), `ISSUE_1_URL` (capture as `UMBRELLA_URL`), `ISSUE_1_TITLE` (capture as `UMBRELLA_TITLE`). On `ISSUE_1_FAILED=true` or empty `ISSUE_1_NUMBER`, capture the umbrella-creation failure: derive a sanitized one-line `UMBRELLA_FAILURE_REASON` value from `/issue`'s available failure signals. `ISSUE_1_FAILED=true` is a boolean — for an umbrella-create failure (the typical case here, since 3B.3 invokes `/issue` in single mode for the umbrella) `/issue` Step 6 emits the explanatory detail on **stderr** as `**⚠ /issue: create failed for item 1: <msg>**` (not on stdout); `ISSUE_1_ERROR=<msg>` appears on stdout only for dep-link / transitive-failure paths. Compose `UMBRELLA_FAILURE_REASON` from, in priority order: (a) the redacted stderr `**⚠ /issue: create failed …**` line when present, (b) `ISSUE_1_ERROR=<msg>` from stdout when present (dep-link / transitive paths), (c) as a constrained stdout fallback, ONLY lines matching `^ISSUE_1_` (umbrella-create-related) and `^ISSUES_FAILED=` — never an unconstrained tail of the full stream (the batch child KV lines that precede umbrella creation must not bleed into this value). Sanitize the value: strip control characters, replace newlines and tabs with single spaces, collapse internal whitespace runs to one space, strip markdown metacharacters (`*`, `_`, `` ` ``, `[`, `]`, `(`, `)`) so the value cannot break the surrounding `**…**` formatting in Step 4's partial breadcrumb, redact secrets / API keys / OAuth / JWT / passwords / certificates → `<REDACTED-TOKEN>`, internal hostnames / URLs / private IPs → `<INTERNAL-URL>`, PII (emails, account IDs tied to a real user) → `<REDACTED-PII>` (mirroring the `skills/implement/SKILL.md` Execution-Issues-Tracking compose-time redaction tokens), and trim to ~200 characters. Then jump to Step 4 with `UMBRELLA_NUMBER` and `UMBRELLA_URL` **omitted** from `output.kv` entirely — do NOT write them with blank values. The canonical Step 4 grammar marks these keys present only on multi-piece success, so consumers distinguish success from failure by key presence/absence; writing blank values would validate but break that contract. Carry `UMBRELLA_FAILURE_REASON` through to Step 4's `output.kv` as the optional KV line (see the optional schema entry); when no failure signal can be extracted, omit `UMBRELLA_FAILURE_REASON` rather than writing a blank value. Skip 3B.4. Do NOT print a warning here — Step 4 is the single emission point for the human summary line and will render the multi-piece partial shape on this path.

### 3B.4 — Wire DAG dependencies and post back-links

Skip this entire sub-step when `DRY_RUN=true` (no children actually exist on GitHub). Print `⏭️ /umbrella: dependency wiring + back-links skipped (--dry-run)` and jump to Step 4.

Compose the proposed edge list from the `depends-on` field of each piece: for piece index `i` with `depends_on=[j, k, ...]`, propose edges `child[j] blocks child[i]`, `child[k] blocks child[i]`, etc. (using the resolved issue numbers from 3B.2). Write the proposed edges to `$UMBRELLA_TMPDIR/proposed-edges.tsv` (one row per edge: `<blocker-number>\t<blocked-number>`) using the Write tool.

Then run the wiring + back-links coordinator:

```bash
$PWD/.claude/skills/umbrella/scripts/helpers.sh wire-dag --tmpdir "$UMBRELLA_TMPDIR" --umbrella "$UMBRELLA_NUMBER" --umbrella-title "$UMBRELLA_TITLE" --children-file "$UMBRELLA_TMPDIR/children.tsv" --edges-file "$UMBRELLA_TMPDIR/proposed-edges.tsv" --repo "$REPO"
```

`wire-dag.sh` is a coordinator that, internally, (a) probes existing blocked-by edges per child via the GitHub dependency-API adapter, (b) runs `check-cycle.sh` on the union of existing + proposed edges to refuse any edge that would create a cycle, (c) adds each surviving new edge via the same adapter, and (d) posts a back-link comment (`Part of umbrella #M — <umbrella-title>`) on each child unless the GitHub-native umbrella relationship is detected as already rendering on the child page.

Parse stdout for `EDGES_ADDED`, per-edge `EDGE_<j>_BLOCKER`, `EDGE_<j>_BLOCKED`, `EDGES_REJECTED_CYCLE` (count of rejected proposed edges), `EDGES_SKIPPED_EXISTING` (count of skipped already-present edges), `EDGES_SKIPPED_API_UNAVAILABLE` (count of edges skipped because the GitHub dependency API surface is not available on this repo — fail-open, do not abort), `BACKLINKS_POSTED`, `BACKLINKS_SKIPPED_NATIVE` (count of children whose native umbrella relationship was already detected). On non-zero exit, log the `ERROR=` line and continue to Step 4 — partial wiring is acceptable.

## Step 4 — Emit Output

```bash
$PWD/.claude/skills/umbrella/scripts/helpers.sh emit-output --kv-file "$UMBRELLA_TMPDIR/output.kv"
```

Write `$UMBRELLA_TMPDIR/output.kv` (one `KEY=VALUE` line per fact) BEFORE invoking the emitter, using the Write tool. The orchestrator owns completeness (it authored `output.kv`); the emitter validates the KV grammar (well-formed `KEY=VALUE` lines, no embedded newlines, no duplicate keys) and prints to stdout in the canonical order:

```
UMBRELLA_VERDICT=<one-shot|multi-piece>
UMBRELLA_RATIONALE=<one-line>
UMBRELLA_DOWNGRADE=<token>   (only when Step 3B.1 downgraded multi-piece → one-shot; e.g., `decomposition-lt-2`)
CHILDREN_CREATED=<N>
CHILDREN_DEDUPLICATED=<N>
CHILDREN_FAILED=<N>
CHILD_<i>_NUMBER=<N>
CHILD_<i>_URL=<url>
CHILD_<i>_TITLE=<title>
UMBRELLA_NUMBER=<N>          (only on multi-piece + success)
UMBRELLA_URL=<url>           (only on multi-piece + success)
UMBRELLA_FAILURE_REASON=<text>   (only on multi-piece partial — children created, umbrella creation failed; sanitized one-line value, ≤200 chars; omitted when no failure signal could be extracted)
EDGES_ADDED=<N>              (only on multi-piece, non-dry-run, success)
EDGE_<j>_BLOCKER=<N>
EDGE_<j>_BLOCKED=<M>
BACKLINKS_POSTED=<N>         (only on multi-piece, non-dry-run, success)
```

After `emit-output` returns, the orchestrator (the LLM running this skill) MUST print exactly one human summary breadcrumb of the form below. Step 4 is the single emission point for this summary — Step 3B.3's umbrella-creation-failure path defers to Step 4 instead of printing inline. The orchestrator composes each shape using both `output.kv` values AND any session state captured from earlier sub-steps (e.g., `/issue`'s stdout for the one-shot dedup'd / failed cases — `ISSUE_1_DUPLICATE_OF_NUMBER`/`ISSUE_1_DUPLICATE_OF_URL` and the `/issue` failure context). The multi-piece partial shape interpolates the optional `UMBRELLA_FAILURE_REASON` field documented in the canonical grammar above; the remaining shapes (one-shot, multi-piece success, multi-piece dry-run) compose from `output.kv` values and earlier-step session state without additional canonical fields:

- one-shot: `✅ /umbrella: filed #<N> — <url>` (or `ℹ /umbrella: dedup'd to #<N> — <url>` / `**⚠ /umbrella: failed — <error>**` etc.).
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
- `scripts/helpers.sh` — Steps 3B.4 / 4 consolidated helpers exposing `check-cycle`, `wire-dag`, and `emit-output` subcommands; contract `scripts/helpers.md`.
- `scripts/test-helpers.sh` — regression harness for `helpers.sh check-cycle`; contract `scripts/test-helpers.md`. Run manually via `bash scripts/test-helpers.sh`; wire into `make lint` as a follow-up issue.
- `scripts/test-umbrella-parse-args.sh` — regression harness for `parse-args.sh`; contract `scripts/test-umbrella-parse-args.md`. Wired into `make lint` via the `test-umbrella-parse-args` Makefile target alongside `test-umbrella-helpers`.
