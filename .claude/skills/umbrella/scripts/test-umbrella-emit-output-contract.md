# test-umbrella-emit-output-contract.sh — sibling contract

Structural regression harness for `/umbrella` SKILL.md Step 2 (input-file dry-run-safe distinct-count rule — added in #724), Step 3B.2 (created-eq-1 bypass branch — added in #717), Step 3B.3 (dry-run skip directive — added in #719), Step 3B.4 (dry-run skip directive — pre-existing, pinned as the matched pair with 3B.3), Step 4 (Emit Output) prose including the dry-run child shape contract (added in #726), and the `emit-output` subcommand subsection of `helpers.md`. Closes #602 — out-of-scope observation surfaced during /implement for #571 (which fixed the original SKILL.md/helpers.md drift). Extended for #719 to pin the new Step 3B.3 dry-run guard (`d1`–`d3`) and the matched-pair Step 3B.4 guard (`e1`–`e2`) so the two parallel dry-run gates cannot drift apart silently. Extended for #724 to pin the Step 2 dry-run-safe distinct-count rule (`f1`–`f4`) as authoritative for any caller of `/umbrella --input-file`. Extended for #717 to pin the new Step 3B.2 created-eq-1 bypass branch (`g1`–`g4`) and the new Step 4 bypass breadcrumb (`c8`) plus the broadened UMBRELLA_DOWNGRADE schema parenthetical (`a3`/`a3b`/`a3c`). Extended for #726 to pin the Step 4 dry-run child shape contract (`h1`–`h4`): `CHILD_<i>_DRY_RUN=true` line literal + per-key omission annotations on `CHILD_<i>_NUMBER` and `CHILD_<i>_URL`, with the `h3`/`h4` split anchoring each annotation to its specific key line so asymmetric drift cannot pass. The intent is a cheap CI guard against regression of the same drift; `test-helpers.sh` explicitly leaves `emit-output` out of scope.

This is a *structural* test (literal-substring assertions on `awk`-extracted blocks), not a runtime conformance test of `helpers.sh emit-output` (which remains exercised indirectly via SKILL.md integration). Pattern matches `skills/fix-issue/scripts/test-fix-issue-bail-detection.sh`.

**Run manually**: `bash .claude/skills/umbrella/scripts/test-umbrella-emit-output-contract.sh`.

**Wired into `make lint`**: the top-level `Makefile` defines a `test-umbrella-emit-output-contract` target that runs this harness; it is a dep of `test-harnesses` (and therefore `lint`), so CI's `test-harnesses` job catches any regression.

## Coverage

Thirty-four assertions, fail-fast on first miss.

### Step 2 block (extracted from SKILL.md) — added in #724

The Step 2 dry-run-safe distinct-count rule is the umbrella-layer authority for `/issue --input-file --dry-run` interactions regardless of caller (`/review --create-issues` today, future CI drivers exercising `/umbrella --input-file --dry-run` tomorrow). The four `f*` assertions pin its load-bearing literals so any future edit that removes or rewords them breaks CI.

- (f1) Step 2 dry-run-safe rule heading: ``Distinct-resolved-child-count rule** (dry-run-safe)``
- (f2) Step 2 `ISSUE_<i>_DRY_RUN=true` count-as-1 sentence: ``If `ISSUE_<i>_DRY_RUN=true`: count this item as 1 prospective distinct child``
- (f3) Step 2 distinct-count formula: `len(set_of_numbers) + count_of_dry_run_items`
- (f4) Step 2 caller-agnostic authoritativeness note: `` authoritative for any caller of `/umbrella --input-file` ``

### Step 3B.2 block (extracted from SKILL.md) — added in #717

Pin the load-bearing literals of the new `created-eq-1` bypass branch (closes #717). The bypass triggers when `INPUT_FILE` is empty AND `DRY_RUN=false` AND `ISSUES_FAILED=0` AND `ISSUES_CREATED=1`; it skips Steps 3B.3 and 3B.4 entirely and emits one-shot-shaped output with `UMBRELLA_DOWNGRADE=created-eq-1`. The four `g*` assertions guard against silent regression of the predicate, the precedence note, the bypass-condition heading, and the explicit "do NOT execute Step 3A" guardrail.

- (g1) Step 3B.2 bypass-condition heading: `` `created-eq-1` bypass condition ``
- (g2) Step 3B.2 full-conjunction predicate: `` `INPUT_FILE` is empty AND `DRY_RUN=false` AND `ISSUES_FAILED=0` AND `ISSUES_CREATED=1` ``
- (g3) Step 3B.2 precedence note: `failed batch (ISSUES_FAILED>=1) > created-eq-1 (normal mode, non-dry-run) > existing 3B.3 dispatch`
- (g4) Step 3B.2 "do NOT execute Step 3A" guardrail: ``Do NOT execute Step 3A on this path — children were already created in Step 3B.2; re-invoking `/issue` would double-create``

### Step 3B.3 block (extracted from SKILL.md) — added in #719

- (d1) 3B.3 contains the shared dry-run skip directive prefix ``Skip this entire sub-step when `DRY_RUN=true` ``. Matched-pair invariant with `e1` below — both must mirror the same literal so the two parallel dry-run gates cannot drift.
- (d2) 3B.3 contains the folded skip-line breadcrumb `⏭️ /umbrella: umbrella body + umbrella create + dependency wiring + back-links skipped (--dry-run)` (subsumes 3B.4's skip-line on the dry-run path because the orchestrator never enters 3B.4 there).
- (d3) 3B.3 documents the `output.kv` contract — ``UMBRELLA_NUMBER`` and ``UMBRELLA_URL`` are **omitted** from `output.kv` — which routes the dry-run path through the canonical "only on multi-piece + success" key-presence convention shared with the children-batch-failure and umbrella-creation-failure paths.

### Step 3B.4 block (extracted from SKILL.md) — added in #719 as matched pair with 3B.3

- (e1) 3B.4 contains the shared dry-run skip directive prefix ``Skip this entire sub-step when `DRY_RUN=true` ``. Matched pair with `d1`. Pinning both at the same literal is the load-bearing drift guard that prevents one gate from being reworded while the other stays.
- (e2) 3B.4 contains its existing pre-#719 skip-line breadcrumb `⏭️ /umbrella: dependency wiring + back-links skipped (--dry-run)`. Pinning this protects against silent removal — even though it is unreachable on the dry-run path post-#719, it remains in place as defense in depth for any path that might still flow through 3B.4.

### Step 4 block (extracted from SKILL.md)

- (a1) Orchestrator-attribution: the human summary breadcrumb is printed by the orchestrator (the LLM running this skill), not by the `emit-output` helper.
- (a2) Single-emission-point invariant: Step 4 is the only place in SKILL.md that emits the breadcrumb (Step 3B.3's umbrella-creation-failure path defers to Step 4).
- (a3 / a3b / a3c) UMBRELLA_DOWNGRADE schema parenthetical lists all 3 emission sites (`decomposition-lt-2`, `input-file-distinct-lt-2`, `created-eq-1`) — added in #717. Pinned because the previous wording mentioned only Step 3B.1, which became stale once `input-file-distinct-lt-2` (Step 2) and `created-eq-1` (Step 3B.2) were added.
- (c1)–(c8) plus (c6b) — the nine concrete breadcrumb shape literals on disk:
  - (c1) one-shot filed: `✅ /umbrella: filed #<N> — <url>`
  - (c2) one-shot dedup'd: `ℹ /umbrella: dedup'd to #<N> — <url>`
  - (c3) one-shot failed: `**⚠ /umbrella: failed — <error>**`
  - (c4) multi-piece success: `✅ /umbrella: filed umbrella #<M> with <N> children, <E> dependency edge(s), <B> back-link(s) — <umbrella-url>`
  - (c5) multi-piece dry-run: `ℹ /umbrella: dry-run — would file umbrella with <N> children`
  - (c6) multi-piece partial — fallback (no `UMBRELLA_FAILURE_REASON`): `**⚠ /umbrella: <N> children created but umbrella creation failed. Children remain unlinked.**`
  - (c6b) multi-piece partial — with `UMBRELLA_FAILURE_REASON` parenthetical: `**⚠ /umbrella: <N> children created but umbrella creation failed (<UMBRELLA_FAILURE_REASON>). Children remain unlinked.**`
  - (c7) multi-piece children-batch-failed (umbrella never attempted): `**⚠ /umbrella: /issue batch reported <F> failure(s); refusing to create a half-populated umbrella. <N> children remain unlinked.**`
  - (c8) created-eq-1 bypass — multi-piece downgraded one-shot (added in #717): `✅ /umbrella: filed #<N> — <url> (multi-piece downgraded — created-eq-1, <D> sibling(s) deduplicated to existing issues, no umbrella issue created)`

  Issue #602 specifies "the four canonical shape templates" but explicitly includes "dry-run and partial-failure variants of multi-piece as documented in Step 4". On disk, Step 4 now contains nine concrete breadcrumb literals — the multi-piece partial case has dual shapes (with-reason / fallback) that #644 surfaced as both load-bearing, the children-batch-failed variant was added after #602 was filed, and the created-eq-1 bypass shape was added in #717. The harness pins each concrete literal to guard against silent shape deletion — pinning fewer would let one variant disappear unnoticed.

### Step 4 block — dry-run child shape (added in #726)

The Step 4 grammar block now documents two child variants: resolved/non-dry-run children carry `CHILD_<i>_NUMBER` + `CHILD_<i>_URL` + `CHILD_<i>_TITLE`; dry-run children carry `CHILD_<i>_TITLE` + `CHILD_<i>_DRY_RUN=true` only (NUMBER and URL are omitted). The `h*` family pins this contract. (The `g*` letter was already taken by #717's Step 3B.2 bypass-branch coverage above; `h*` is the next free letter.)

- (h1) Step 4 grammar contains the `CHILD_<i>_DRY_RUN=true` key declaration line for the dry-run child variant.
- (h2) Step 4 grammar contains the omission-semantics annotation tail: ``only on dry-run children — when emitted, `CHILD_<i>_NUMBER` and `CHILD_<i>_URL` are omitted``. This pins the explanatory phrasing that links the new `DRY_RUN` key to the omission of NUMBER / URL.
- (h3) Step 4 grammar contains the per-key omission annotation on `CHILD_<i>_NUMBER`: ``CHILD_<i>_NUMBER=<N>         (only on resolved/non-dry-run children)``. Anchored to the key line specifically (the literal includes the key name) so an asymmetric drift on the URL line cannot pass.
- (h4) Step 4 grammar contains the per-key omission annotation on `CHILD_<i>_URL`: ``CHILD_<i>_URL=<url>          (only on resolved/non-dry-run children)``. The `h3`/`h4` split is load-bearing — a single shared-substring assertion would pass even if one of the two annotations was reworded or dropped, because `grep -qF` is order-agnostic. Splitting per key closes that gap.

### emit-output subsection (extracted from helpers.md)

- (b1) `stderr` is reserved for parse/validation/usage errors only.
- (b2) The human breadcrumb is emitted by the orchestrator at SKILL.md Step 4, **not** by this script.
- (b3) The wire-dag stderr-warning carve-out: `` `wire-dag` ``'s documented stderr behavior is unaffected by the emit-output-specific scoping. Pinning this carve-out guards against accidental over-broad scoping (e.g., a future PR removing the carve-out and inadvertently constraining wire-dag's stderr).

## Extraction boundaries

| Block | Start regex | End regex |
|-------|-------------|-----------|
| SKILL.md Step 2 | `^## Step 2 — Classify One-Shot vs Multi-Piece` (full heading) | `^## Step 3A` (prefix only) |
| SKILL.md Step 3B.2 | `^### 3B\.2` plus space (subheading prefix) | `^### 3B\.3` plus space (next subheading prefix) |
| SKILL.md Step 3B.3 | `^### 3B\.3` plus space (subheading prefix) | `^### 3B\.4` plus space (next subheading prefix) |
| SKILL.md Step 3B.4 | `^### 3B\.4` plus space (subheading prefix) | `^## Step 4 — Emit Output` (full heading) |
| SKILL.md Step 4 | `^## Step 4 — Emit Output` (full heading) | `^## Step 5` (prefix only) |
| helpers.md emit-output | `^## .emit-output` | `^###` followed by a space (first triple-hash) |

The Step 5 end regex is deliberately a prefix match (not the full heading): it tolerates Step 5 subtitle changes while still bounding the block. The end pattern for helpers.md (`^###` followed by a space) matches the first triple-hash heading after the `## emit-output` heading — today, `### Edit-in-sync rules`. Empty extraction is treated as a hard failure with both boundary regexes printed to stderr.

**Known limitation**: if a future PR adds a `###` subheading inside the emit-output section above `### Edit-in-sync rules`, the helpers.md extractor will truncate the block early and (b1)/(b2)/(b3) may false-fail. The current placement of `### Edit-in-sync rules` is the de facto end boundary; an editor adding intermediate `###` headings should also update the end pattern in this harness. (Considered and exonerated during plan review — voted 1 YES + 2 EXONERATE.)

## Edit-in-sync rules

- Any change to SKILL.md Step 4 prose (orchestrator-attribution sentence, single-emission-point invariant, or any of the eight concrete literals — c1–c7 plus c6b) requires a same-PR update to the corresponding assertion literal in this harness.
- Any change to helpers.md `emit-output` subsection (stderr discipline sentence, the orchestrator-emits-breadcrumb sentence, or the wire-dag carve-out) requires the same.
- Renaming or renumbering Step 2, Step 3B.2, Step 3B.3, Step 3B.4, or Step 4 in SKILL.md, or renaming the `emit-output` subcommand in helpers.md, requires updating the boundary regexes here AND in the table above.
- Any change to SKILL.md Step 3B.2's `created-eq-1` bypass branch (predicate, precedence note, "do NOT execute Step 3A" guardrail, condition heading) requires a same-PR update to the corresponding `(g1)`–`(g4)` assertion literal here.
- Any change to SKILL.md Step 4's UMBRELLA_DOWNGRADE schema parenthetical (the enumeration of emission sites) requires preserving all 3 downgrade tokens (`decomposition-lt-2`, `input-file-distinct-lt-2`, `created-eq-1`); pinned by `(a3)`, `(a3b)`, `(a3c)`.
- Adding a new canonical breadcrumb shape to SKILL.md Step 4: add a corresponding `(c<N>)` assertion here.
- Reword to either dry-run skip directive (Step 3B.3 or Step 3B.4): the matched-pair invariant requires both `d1` and `e1` to share the same literal — update both assertion literals in lockstep, otherwise CI catches the drift.
- Reword to either skip-line breadcrumb literal (3B.3's `d2` folded form, or 3B.4's `e2` wiring/back-links form): update the assertion literal here in the same PR.
- Any change to SKILL.md Step 2's dry-run-safe distinct-count rule (heading suffix `(dry-run-safe)`, the `ISSUE_<i>_DRY_RUN=true` count-as-1 sentence, the `count_of_dry_run_items` formula, or the caller-agnostic authoritativeness note) requires a same-PR update to the corresponding `(f1)`–`(f4)` assertion literal here.
- Any change to SKILL.md Step 4's dry-run child shape grammar (the `CHILD_<i>_DRY_RUN=true` line, its omission-semantics annotation, or the per-key `(only on resolved/non-dry-run children)` annotations on `CHILD_<i>_NUMBER` and `CHILD_<i>_URL`) requires a same-PR update to the corresponding `(h1)`–`(h4)` assertion literal here. The `h3`/`h4` per-key split is load-bearing — do NOT collapse them back into a single shared-substring assertion, because `grep -qF` is order-agnostic and an asymmetric drift would pass.

## Out of scope

Runtime conformance of `helpers.sh emit-output` (KV grammar validation, duplicate-key rejection, embedded-newline rejection) — `helpers.sh emit-output` is a thin awk validator covered indirectly by SKILL.md integration. `test-helpers.sh` covers both `helpers.sh check-cycle` (pure logic) and `helpers.sh wire-dag` (PATH-stub `gh` for the per-edge POST classifier and counter categorization, including `EDGES_FAILED` per issue #720).

## Pattern reference

Mirrors `skills/fix-issue/scripts/test-fix-issue-bail-detection.sh` (awk range extraction + literal-substring assertions + fail-fast). Path discovery uses umbrella-local style (`HERE=$(cd "$(dirname "$0")" && pwd)`) parallel to `test-umbrella-parse-args.sh`, not the `REPO_ROOT/../../..` math from `test-fix-issue-bail-detection.sh` (whose three-`..` segments do not reach the repo root from `.claude/skills/umbrella/scripts/`).
