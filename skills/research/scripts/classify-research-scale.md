# classify-research-scale.sh — Contract

**Purpose**: deterministic shell classifier that resolves `RESEARCH_SCALE` for `/research` from `RESEARCH_QUESTION` text alone, without any LLM call. Replaces the prior manual-only `--scale=quick|standard|deep` selector as the default; manual `--scale=` is preserved as an explicit override.

**Consumed by**: `/research` Step 0.5 (Adaptive Scale Classification). The orchestrator writes `RESEARCH_QUESTION` to `$RESEARCH_TMPDIR/classifier-question.txt`, invokes this script with `--question <path>`, parses stdout, and sets `RESEARCH_SCALE` + `SCALE_SOURCE` accordingly. On any non-zero exit, the orchestrator falls back to `RESEARCH_SCALE=standard` with `SCALE_SOURCE=fallback` and a visible warning.

**Why a separate script**: the rule set is deterministic text processing, ideal for offline regression testing. Keeping rules in shell rather than embedding them in SKILL.md prose enables `make lint` to pin behavior against fixtures (see `test-classify-research-scale.sh`). This separation matches the repo pattern: orchestrator-side prompt-shaped sequencing stays in `skills/research/SKILL.md` and `references/research-phase.md`; mechanical text processing stays in colocated `skills/<name>/scripts/`.

**Why no LLM**: per the design dialectic on issue #513 (DECISION_1, voted 2-1 ANTI_THESIS), the orchestrator panel concluded that a tiny LLM classifier's marginal routing-finesse advantage is absorbed by the same `standard`-fallback safety floor that a deterministic heuristic also relies on, while every classifier call would compete under the documented `--token-budget` model. Deterministic shell rules are diffable, regression-testable, and reproducible across CI and laptops.

## Invocation

```bash
${CLAUDE_PLUGIN_ROOT}/skills/research/scripts/classify-research-scale.sh \
  --question "$RESEARCH_TMPDIR/classifier-question.txt"
```

The `--question` flag is required. The path must point at a regular, readable, non-empty file containing the research question text. The orchestrator owns `$RESEARCH_TMPDIR` creation in Step 0.

## Contract

### Stdout (machine output only)

- **On success** (exit 0):
  ```
  SCALE=<bucket>
  REASON=<token>
  ```
  where `<bucket>` is one of `quick`, `standard`, `deep`, and `<token>` documents which rule fired (see token vocabulary below). The orchestrator parses both lines via prefix-strip (e.g., `${line#SCALE=}`), matching the existing `KEY=value` discipline used by `collect-reviewer-results.sh`, `render-lane-status.sh`, and `run-research-planner.sh`.

- **On failure** (exit non-zero):
  ```
  REASON=<token>
  ```
  Tokens (canonical, pinned by `test-classify-research-scale.sh`):
  - `empty_input` — `--question` file missing-content (zero-byte) or whitespace-only (exit 1).
  - `bad_path` — `--question` path does not exist, is not a regular file, or is not readable (exit 2).
  - `missing_arg` — `--question` not provided, or unknown argument (exit 2).

No other lines appear on stdout.

### Stderr (human diagnostics)

One short diagnostic line per anomaly observed during validation. Stderr is intended for the orchestrator's runtime log; the orchestrator does NOT parse stderr. Human-readable text is acceptable; do not promise a stable schema.

### Exit code

- `0` on success.
- `1` on empty input (zero-byte or whitespace-only `--question` file).
- `2` on argument error or bad path (operator/orchestrator bug — distinct from a question-content failure).

## Rule set

Applied in order; the first matching stage wins.

### Stage 0 — Validation gate

1. `--question` flag present (else `REASON=missing_arg`, exit 2).
2. Path exists, is a regular file (or symlink to one), and is readable (else `REASON=bad_path`, exit 2).
3. File is non-zero bytes AND not whitespace-only (else `REASON=empty_input`, exit 1).

### Stage 1 — strong-`deep` signals (any one fires → `SCALE=deep`)

1a. **Length signal**: byte length (`wc -c`) > 600. `REASON=length_deep`.
1b. **Keyword signal**: ≥2 matches across the case-insensitive deep keyword set. `REASON=keyword_deep`.
1c. **Multi-part signal**: ≥2 `?` characters in the question text. `REASON=multi_part_deep`.

**Deep keyword set** (substring match, case-insensitive — no word-boundary anchoring; `vulnerab` matches both "vulnerable" and "vulnerability"):

```
compare, tradeoff, trade-off, audit, architecture, migration, vulnerab,
security review, threat model, refactor, design decision, end-to-end,
end to end, comprehensive
```

### Stage 2 — strong-`quick` signals (ALL fire AND no Stage 1 hit → `SCALE=quick`)

2a. **Length**: byte length < 80.
2b. **Single sentence**: exactly one `?` character in the question text.
2c. **Lookup keyword**: at least one match in the case-insensitive lookup keyword set.
2d. **No deep keywords**: zero deep keywords present (defensive — Stage 1 already excluded ≥2; Stage 2 requires ZERO).

If all four fire: `SCALE=quick`, `REASON=lookup_quick`.

**Lookup keyword set** (substring match, case-insensitive):

```
"what is", "where is", "who owns", "which file", "value of", "how many"
```

Note: `does` was deliberately excluded from this set even with a trailing-space anchor (the literal pattern `does` followed by a space), because it would false-positive on questions like "how does X work" that are not narrow factual lookups. Yes/no questions land in `standard`, which is the conservative direction.

### Stage 3 — Default

If neither Stage 1 nor Stage 2 fired: `SCALE=standard`, `REASON=default_standard`.

## Asymmetric conservatism

The rule set is biased away from `quick` and toward `standard`. `quick` requires the conjunction of multiple positive signals AND the absence of any `deep` trigger; `deep` fires on any single trigger; ambiguity → `standard`. This posture is deliberate (per dialectic resolution on issue #513 DECISION_1) so that auto-classification never silently downgrades a broad question to a single-lane run. The `--scale=` operator override remains the explicit escape hatch for cases the heuristic mis-classifies.

## Fallback semantics

The orchestrator at Step 0.5 treats ANY non-zero exit (any `REASON=*` value) as a signal to fall back to `RESEARCH_SCALE=standard` with `SCALE_SOURCE=fallback`. The orchestrator parses `REASON=<token>` from stdout via prefix-strip and substitutes the token into a visible warning line:

```
**⚠ 0.5: classify-scale — fallback to standard (<token>).**
```

Successful classification prints the resolved bucket and reason:

```
✅ 0.5: classify-scale — auto-classified as <bucket> (reason: <token>)
```

Manual override (operator passed `--scale=`) skips the script entirely; the orchestrator emits:

```
⏩ 0.5: classify-scale — manual override --scale=<value>
```

## Security

`--question` MUST be a path under `$RESEARCH_TMPDIR` (which lives under canonical `/tmp` per the `/research` skill-scoped `deny-edit-write.sh` hook). The script does not enforce this constraint mechanically — caller-side discipline relies on the existing PreToolUse hook on `/research`'s `Edit | Write | NotebookEdit` surface. **Path-traversal residual risk**: if a future caller passes a path outside `/tmp`, the script would read there. The hook covers `Write` from Claude's tool surface but NOT this Bash subprocess; operator-side `Bash(...)` permission narrowing is the relevant defense (see SECURITY.md).

The classifier reads only — it never writes. There is no prompt-injection surface (no LLM in the loop). Adversarial question content can still steer the bucket choice via keyword stuffing, but this is bounded: the worst case is `deep` (over-provisioning, not silent under-provisioning), and operators can always pass `--scale=quick` to override.

## Test harness

`skills/research/scripts/test-classify-research-scale.sh` — offline regression harness; runs against canned `--question` inputs covering the boundaries (lookup-quick; compare-deep; multi-?-deep; security-keyword-deep; mid-length-standard; long-length-deep; empty input; whitespace-only input; missing `--question`; non-existent path; non-regular path). Wired into `make lint` via the `test-classify-research-scale` target.

## Edit-in-sync rules

- **Rule changes** (length thresholds, keyword sets, structural cues, asymmetric-conservatism posture): update this contract AND `test-classify-research-scale.sh` AND the corresponding orchestrator prose in `skills/research/SKILL.md` (the "Adaptive scale classification" section and the Step 0.5 body in `skills/research/references/research-phase.md`).
- **Stdout schema changes** (`SCALE=` / `REASON=`): update this contract, the test harness, AND the orchestrator's stdout-parsing instruction in SKILL.md Step 0.5.
- **`REASON` token vocabulary changes**: update this contract, the test harness, AND any prose in SKILL.md or research-phase.md that references the tokens by name.
