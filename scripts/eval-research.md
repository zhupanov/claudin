# eval-research.sh — contract

## Purpose

`scripts/eval-research.sh` is the offline evaluation harness for the `/research` skill. It reads `skills/research/references/eval-set.md`, runs each entry through `/research` as a fresh `claude -p` subprocess, scores the output along deterministic + LLM-as-judge axes, and emits either a markdown summary table (default) or a populated `eval-baseline.json`-shaped file (with `--write-baseline`). It is opt-in operator instrumentation; it is NOT a CI gate, NOT wired into `make lint`, and NOT a `test-harnesses` prerequisite.

Closes issue #419 under umbrella #413 (evidence-grounded research synthesis for `/research`). Source: Anthropic's *How we built our multi-agent research system* and *Building Effective Agents* describe small-sample (~20-case) rubric-based LLM-as-judge evaluation as the substrate for prompt-side iteration; this harness is the local instantiation.

## Invocation

Direct invocation is the documented operator path:

```bash
bash scripts/eval-research.sh [flags]
```

The Makefile `eval-research` target exists for occasional pass-through via `ARGS=`:

```bash
make eval-research ARGS="--id eval-1 --timeout 4200"
```

`make` cannot forward arbitrary `--flag value` arguments to a recipe directly; the `ARGS=` variable pattern is the standard workaround in this repo.

## Flags

| Flag | Default | Effect |
|------|---------|--------|
| `--id <id>` | empty | Run only the entry with this `id` from `eval-set.md` (debugging single-question iterations). |
| `--scale <s>` | `standard` | Forward-compat metadata recorded in `eval-baseline.json`. `/research` does NOT yet accept `--scale` (issue #418 is open). When #418 lands, edit the `build_research_prompt` function so the literal CLAUDE_SCALE_PASSTHROUGH branch is used. |
| `--baseline <ref>` | empty | Pre-fetches the baseline JSON at the given git ref (sha, tag, or branch) into `$WORK_DIR/baseline-rows.json` for manual diffing. **Inline delta columns are NOT yet wired** in this PR — a stdout `PREVIEW MODE` banner makes the partial implementation visible alongside the summary table. The ref is regex-validated against `^[0-9A-Za-z._/-]+$` before any shell interpolation. **Exits 2 if the ref cannot be resolved** (the bad-ref branch used to silently disable with a stderr-only warning; that produced misleading green-looking runs and is fixed in issue #441). |
| `--work-dir <dir>` | `$(mktemp -d)` | Per-run scratch base. Each entry runs in a unique subdirectory underneath. Override only when resuming a prior run for forensics. |
| `--write-baseline <file>` | unset | Write run results in `eval-baseline.json` shape to this file path. Used to populate the committed baseline after a clean end-to-end run. |
| `--timeout <sec>` | `4200` | Per-question timeout for the `/research` subprocess. Default is above `/research`'s composite budget (Step 1 1860s + Step 2 1860s = 3720s) so healthy runs never misclassify as harness timeouts. |
| `--judge-timeout <sec>` | `600` | Per-question timeout for the LLM-as-judge call. |
| `--smoke-test` | off | Parse and schema-validate `eval-set.md` and `eval-baseline.json`, then exit 0 without invoking `claude -p`. No API cost. Used by `scripts/test-eval-set-structure.sh`. |
| `--help` | — | Print the script's usage block and exit 0. |

## Operational definitions

These are the contract-level definitions of every metric the harness emits. Mechanical regressions to these definitions break baseline comparisons silently and need an intentional baseline regeneration to recover.

### Provenance

The harness emits three orthogonal counters, each as the count of unique matches across the research output:

- **`prov_fl`** (file-with-line): regex `[A-Za-z0-9_/.-]+:[0-9]+` filtered to drop `https?:` URLs and pure-numeric `<n>:<m>` line-range tokens. Matches anchored citations like `scripts/foo.sh:42`, `skills/x/SKILL.md:100`, mixed-case extensions like `INSTALL.MD:5`, and extensionless basenames like `Makefile:9` or `Dockerfile:10`. The strongest provenance form.
- **`prov_path`** (repo path): regex `(scripts|skills|hooks|docs|tests|agents)/[A-Za-z0-9_/.-]+`. Matches plain repo-path mentions without a line anchor — the form `/research`'s "Key Files and Areas" section emits today.
- **`prov_url`**: regex `https?://[A-Za-z0-9._/?#&=%-]+`. Matches absolute URLs.

Each counter applies independently; a single citation that matches both `prov_fl` and `prov_path` regexes counts toward both. `expected_provenance_count` in `eval-set.md` is the sum-floor heuristic used by humans when grading; the harness reports the three components separately so regressions are localized.

### Keyword coverage

The harness lowercases the entire research output and the `expected_keywords` list, then computes:

```
kw% = matched_kw / total_kw * 100
```

A keyword is "matched" if it appears as a case-insensitive substring anywhere in the lowercased output. Whole-word boundaries are NOT enforced (substring on lowercased text is more tolerant of compound tokens like `--skip-if-pushed` that would fall through whole-word matchers). Empty keyword strings are ignored. Order does not matter.

### Length

Output line count via `wc -l`. Reported but not weighted in the rubric.

### Judge score

Five dimensions (factual_accuracy, citation_accuracy, completeness, source_quality, tool_efficiency), each 0-20, total 0-100. The judge prompt is a literal heredoc in the harness body — see the `JUDGE_RUBRIC` variable in `eval-research.sh` for the canonical text. The parser is fail-closed: any malformed judge output (missing `JUDGE_SCORE_TOTAL`, out-of-range total, empty file) yields `JUDGE_STATUS=parse_failed` with `JUDGE_TOTAL=null`. There is no default mid-range score.

### URL reputability

For external-comparison entries only, the harness classifies each unique URL into:

- `URL_HIGH`: `anthropic.com`, `openai.com`, `*.gov`, `*.edu`, `deepmind.com`, `microsoft.com/research`, `arxiv.org`, `nature.com`.
- `URL_LOW`: `medium.com`, `dev.to`, `*.blog`, `substack.com`, `hashnode.dev`.
- `URL_UNKNOWN`: everything else.

A run where `URL_LOW > URL_HIGH` for an external-comparison entry signals SEO content-farm bias per Anthropic's blog warning.

## Output schema

When `--write-baseline <file>` is set, the harness writes JSON of this shape:

```json
{
  "version": 1,
  "harness_commit": "<sha or null>",
  "model_id": null,
  "scale": "standard",
  "generated_at": "<UTC ISO-8601>",
  "entries": [
    {
      "id": "eval-1",
      "category": "lookup",
      "provenance": { "file_line": 0, "repo_path": 0, "url": 0 },
      "keyword_coverage_pct": 0,
      "length_lines": 0,
      "judge_total": null,
      "judge_status": "ok|parse_failed|judge_call_failed|skipped_no_research",
      "wall_clock_seconds": 0,
      "research_status": "ok|timeout|research_failed"
    }
  ]
}
```

`model_id` is reserved for a future amendment that captures the active Claude model identifier; today it is always `null` because the harness has no robust way to query Claude's model id from the subprocess output without parsing free-text. Operators recording a baseline should manually set `model_id` post-write if it is needed for reproducibility.

## Authoring `eval-set.md`

Authors editing `skills/research/references/eval-set.md` MUST follow:

- The global reference rules enforced by `scripts/test-references-headers.sh` and documented in `scripts/test-references-headers.md`. The `**Consumer**:` / `**Contract**:` / `**When to load**:` triplet must appear at line-start. The `**Contract**:` paragraph must be a single paragraph (terminated by a blank line) and must NOT contain `L<digits>-<digits>` line-range citations.
- The entry schema. Each entry begins with `### eval-N: <id>` and has six bulleted fields in order: `question`, `category`, `expected_provenance_count`, `expected_keywords`, `notes`. Fields use the format `- **<name>**: <value>`.
- The id rule. Each `<id>` must match `^[a-z0-9-]+$` (lowercase letters, digits, and hyphens only) and must be unique across the eval set — `validate_eval_set()` rejects duplicates and path-like ids under `--smoke-test` because `run_one_research()` later uses the raw `id` as `$WORK_DIR/$id`. The same rule is enforced at lint time by `scripts/test-eval-set-structure.sh` Check 5b.
- The structural invariants enforced by `scripts/test-eval-set-structure.sh`: at least 20 entries, all five categories present, two entries flagged `ADVERSARIAL` in `notes`, and the harness file containing the Anthropic-blog citation literal.

## Edit-in-sync

| File | Relationship |
|------|-------------|
| `skills/research/references/eval-set.md` | Source data; harness's primary input. Schema defined here, validated mechanically by `--smoke-test` and `test-eval-set-structure.sh`. |
| `skills/research/references/eval-baseline.json` | Schema-only stub today (`entries: []`). Operator runs `bash scripts/eval-research.sh --write-baseline <file>` to populate. |
| `scripts/test-eval-set-structure.sh` | Offline structural regression. Asserts entry count, category coverage, schema validity, and invokes `--smoke-test` for round-trip verification. |
| `scripts/test-eval-set-structure.md` | Sibling contract for the test harness. |
| `Makefile` | Adds `eval-research` and `test-eval-set-structure` standalone targets. NEITHER is a `test-harnesses` prerequisite. |
| `agent-lint.toml` | Excludes both `scripts/eval-research.sh` and `scripts/test-eval-set-structure.sh` from dead-script checks (Makefile-only references). |
| `docs/linting.md` | Documents `eval-research` as opt-in operator-run instrumentation. |
| `skills/improve-skill/scripts/iteration.sh` | Source of the `claude -p` subprocess pattern (stdin file + stderr sidecar + poll loop). The harness reuses the pattern but decouples numeric timeouts. |
| `scripts/parse-skill-judge-grade.sh` | Source of the fail-closed structured-output parsing discipline. The harness's judge-output parser mirrors the exit-zero-with-status-on-stdout shape. |
| `scripts/test-loop-improve-skill-halt-rate.sh` | Source of the opt-in operator-run pattern (Makefile-only, agent-lint excluded, documented in `docs/linting.md`). |

## Exit codes

- `0` — harness ran. Per-entry timeouts and parse failures are reported in the `status` column / `research_status` JSON field, not the exit code.
- `1` — schema validation of `eval-set.md` or `eval-baseline.json` failed.
- `2` — argument parse error or invalid argument value (bad timeout integer, regex-invalid baseline ref, or baseline ref that cannot be resolved via `git show`).
- `3` — required tooling missing (`claude`, `jq`, or `awk`).

## Security

The `--baseline <ref>` flag accepts only `^[0-9A-Za-z._/-]+$`. Anything else is rejected with exit 2 before any shell interpolation, so `git show <ref>:...` cannot be smuggled with arbitrary text. This is the implementation of `OOS_1` from the plan-review panel for issue #419. `model_id` is never derived from untrusted output; a future amendment that wires a real value in must apply the same input-validation discipline.
