# test-umbrella-emit-output-contract.sh — sibling contract

Structural regression harness for `/umbrella` SKILL.md Step 4 (Emit Output) and the `emit-output` subcommand subsection of `helpers.md`. Closes #602 — out-of-scope observation surfaced during /implement for #571 (which fixed the original SKILL.md/helpers.md drift). The intent is a cheap CI guard against regression of the same drift; `test-helpers.sh` explicitly leaves `emit-output` out of scope.

This is a *structural* test (literal-substring assertions on `awk`-extracted blocks), not a runtime conformance test of `helpers.sh emit-output` (which remains exercised indirectly via SKILL.md integration). Pattern matches `skills/fix-issue/scripts/test-fix-issue-bail-detection.sh`.

**Run manually**: `bash .claude/skills/umbrella/scripts/test-umbrella-emit-output-contract.sh`.

**Wired into `make lint`**: the top-level `Makefile` defines a `test-umbrella-emit-output-contract` target that runs this harness; it is a dep of `test-harnesses` (and therefore `lint`), so CI's `test-harnesses` job catches any regression.

## Coverage

Thirteen assertions, fail-fast on first miss.

### Step 4 block (extracted from SKILL.md)

- (a1) Orchestrator-attribution: the human summary breadcrumb is printed by the orchestrator (the LLM running this skill), not by the `emit-output` helper.
- (a2) Single-emission-point invariant: Step 4 is the only place in SKILL.md that emits the breadcrumb (Step 3B.3's umbrella-creation-failure path defers to Step 4).
- (c1)–(c7) plus (c6b) — the eight concrete breadcrumb shape literals on disk:
  - (c1) one-shot filed: `✅ /umbrella: filed #<N> — <url>`
  - (c2) one-shot dedup'd: `ℹ /umbrella: dedup'd to #<N> — <url>`
  - (c3) one-shot failed: `**⚠ /umbrella: failed — <error>**`
  - (c4) multi-piece success: `✅ /umbrella: filed umbrella #<M> with <N> children, <E> dependency edge(s), <B> back-link(s) — <umbrella-url>`
  - (c5) multi-piece dry-run: `ℹ /umbrella: dry-run — would file umbrella with <N> children`
  - (c6) multi-piece partial — fallback (no `UMBRELLA_FAILURE_REASON`): `**⚠ /umbrella: <N> children created but umbrella creation failed. Children remain unlinked.**`
  - (c6b) multi-piece partial — with `UMBRELLA_FAILURE_REASON` parenthetical: `**⚠ /umbrella: <N> children created but umbrella creation failed (<UMBRELLA_FAILURE_REASON>). Children remain unlinked.**`
  - (c7) multi-piece children-batch-failed (umbrella never attempted): `**⚠ /umbrella: /issue batch reported <F> failure(s); refusing to create a half-populated umbrella. <N> children remain unlinked.**`

  Issue #602 specifies "the four canonical shape templates" but explicitly includes "dry-run and partial-failure variants of multi-piece as documented in Step 4". On disk, Step 4 contains eight concrete breadcrumb literals — the multi-piece partial case has dual shapes (with-reason / fallback) that #644 surfaced as both load-bearing, and the children-batch-failed variant was added after #602 was filed. The harness pins each concrete literal to guard against silent shape deletion — pinning fewer would let one variant disappear unnoticed.

### emit-output subsection (extracted from helpers.md)

- (b1) `stderr` is reserved for parse/validation/usage errors only.
- (b2) The human breadcrumb is emitted by the orchestrator at SKILL.md Step 4, **not** by this script.
- (b3) The wire-dag stderr-warning carve-out: `` `wire-dag` ``'s documented stderr behavior is unaffected by the emit-output-specific scoping. Pinning this carve-out guards against accidental over-broad scoping (e.g., a future PR removing the carve-out and inadvertently constraining wire-dag's stderr).

## Extraction boundaries

| Block | Start regex | End regex |
|-------|-------------|-----------|
| SKILL.md Step 4 | `^## Step 4 — Emit Output` (full heading) | `^## Step 5` (prefix only) |
| helpers.md emit-output | `^## .emit-output` | `^###` followed by a space (first triple-hash) |

The Step 5 end regex is deliberately a prefix match (not the full heading): it tolerates Step 5 subtitle changes while still bounding the block. The end pattern for helpers.md (`^###` followed by a space) matches the first triple-hash heading after the `## emit-output` heading — today, `### Edit-in-sync rules`. Empty extraction is treated as a hard failure with both boundary regexes printed to stderr.

**Known limitation**: if a future PR adds a `###` subheading inside the emit-output section above `### Edit-in-sync rules`, the helpers.md extractor will truncate the block early and (b1)/(b2)/(b3) may false-fail. The current placement of `### Edit-in-sync rules` is the de facto end boundary; an editor adding intermediate `###` headings should also update the end pattern in this harness. (Considered and exonerated during plan review — voted 1 YES + 2 EXONERATE.)

## Edit-in-sync rules

- Any change to SKILL.md Step 4 prose (orchestrator-attribution sentence, single-emission-point invariant, or any of the seven canonical breadcrumb shape literals) requires a same-PR update to the corresponding assertion literal in this harness.
- Any change to helpers.md `emit-output` subsection (stderr discipline sentence, the orchestrator-emits-breadcrumb sentence, or the wire-dag carve-out) requires the same.
- Renaming or renumbering Step 4 in SKILL.md, or renaming the `emit-output` subcommand in helpers.md, requires updating the boundary regexes here AND in the table above.
- Adding a new canonical breadcrumb shape to SKILL.md Step 4: add a corresponding `(c<N>)` assertion here.

## Out of scope

Runtime conformance of `helpers.sh emit-output` (KV grammar validation, duplicate-key rejection, embedded-newline rejection) — `helpers.sh emit-output` is a thin awk validator covered indirectly by SKILL.md integration. `test-helpers.sh` covers `helpers.sh check-cycle` only; `wire-dag` has a follow-up issue for network-mocking coverage.

## Pattern reference

Mirrors `skills/fix-issue/scripts/test-fix-issue-bail-detection.sh` (awk range extraction + literal-substring assertions + fail-fast). Path discovery uses umbrella-local style (`HERE=$(cd "$(dirname "$0")" && pwd)`) parallel to `test-umbrella-parse-args.sh`, not the `REPO_ROOT/../../..` math from `test-fix-issue-bail-detection.sh` (whose three-`..` segments do not reach the repo root from `.claude/skills/umbrella/scripts/`).
