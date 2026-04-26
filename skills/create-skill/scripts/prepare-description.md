# prepare-description.sh contract

`skills/create-skill/scripts/prepare-description.sh` is the coordinator script for the Step 1.5 / Step 1.6 description synthesis flow in `skills/create-skill/SKILL.md`. It invokes `validate-args.sh` (sibling), classifies the result, and emits a small `MODE=…` signal that drives the orchestrator's branching. The authoritative developer-facing specification is the in-file header (lines 1–32 of the script) — edits that change the flag list, the stdout `KEY=VALUE` grammar, the synthesis-trigger error literals, or the F9 pre-synthesis scan rule MUST update both the in-file header and this sibling in the same PR per `AGENTS.md § Editing rules`.

## Inputs

- `--name <name>` (required) — forwarded verbatim to `validate-args.sh`.
- `--description-file <path>` OR `--description <text>` — exactly one is required (mutually exclusive).
  - `--description-file` is the multi-line-safe form used by SKILL.md Step 1.5's initial probe; the script reads the file via `cat "$path"` to preserve embedded newlines verbatim.
  - `--description` is the single-line shell-arg form used by SKILL.md Step 1.6's re-validate call against an LLM-synthesized one-liner.
- `--plugin` (optional) — forwarded to `validate-args.sh` when SKILL.md is in plugin-dev mode.

## Stdout grammar (success — exit 0)

The script emits ONLY short `KEY=VALUE` lines. **It NEVER emits the description text itself** — the orchestrator already holds it (in the tmpfile path or its own LLM-side memory). This is required because `KEY=VALUE` stdout cannot carry multi-line content safely, and the synthesis trigger class includes precisely multi-line input.

- `MODE=verbatim` — description passed `validate-args.sh` as-is. Orchestrator uses the original description for both the frontmatter `description:` field and the `/im` feature brief.
- `MODE=needs-synthesis` + `REASON=newlines-or-control-chars | length-exceeds-cap` — description failed on a synthesis-eligible trigger class (per DECISION_1 narrow gating + Round 2 length extension). Orchestrator distills a one-line `Use when…` frontmatter, applies a name-echo guard, and re-invokes the script via Step 1.6 with the synthesized line.
- `MODE=abort` + `ERROR=<message>` — description failed for any other reason, OR the F9 pre-synthesis security scan caught a banned token alongside the synthesis-trigger class. Orchestrator prints `ERROR` and aborts.

## Synthesis-trigger error literals (load-bearing cross-file dependency)

The script classifies as `MODE=needs-synthesis` when `validate-args.sh`'s `ERROR=` line contains either of these literal substrings:

- `Description contains newlines or control characters`
- `Description length (` (matches the start of validate-args.sh's `Description length (N) exceeds 1024 characters.` error)

If `validate-args.sh` ever rephrases either error literal, this script's classifier MUST update in the same PR — otherwise the synthesis path silently disables. The two regression harnesses (`scripts/test-prepare-description.sh` and `scripts/test-parse-args.sh`) do not couple these literals across files; the dependency is documented and editorial.

## F9 pre-synthesis security scan

BEFORE classifying as `MODE=needs-synthesis`, the script scans the raw description for banned-token classes:

- XML tag pattern `<…>` (any non-empty content between brackets)
- backtick `` ` ``
- command-substitution literal `$(`
- standalone heredoc / frontmatter token `EOF`, `HEREDOC`, or `---` (as a complete word — start of string, end of string, or surrounded by spaces)

If any banned token is present alongside the synthesis-trigger class (newline or length>1024), the script emits `MODE=abort` with a synthetic `ERROR=` mentioning the detected class. This closes the FEATURE_SPEC forward-leak that motivated narrow gating — without this scan, a description with `line1\n<xml>` would route to `MODE=needs-synthesis`, the synthesized one-liner would re-validate cleanly, but the original `<xml>`-bearing spec would still flow as `FEATURE_SPEC` to `/im`'s feature-brief block.

Newlines are NOT a banned-token class for this scan — they are the synthesis trigger themselves.

## set -e capture pattern

`validate-args.sh` exits with code 1 on `VALID=false`. Under `set -euo pipefail`, capturing its output via `$( … )` would normally abort the calling script. `prepare-description.sh` deliberately uses `set +e` / capture / `set -e` around the validator invocation, then parses `VALID=` and `ERROR=` lines from the captured output. This pattern is load-bearing — removing it would mask the validator's intentional non-zero exit signal as a script crash.

## Internal-error path (exit 1)

The script exits 1 (with `ERROR=<diagnostic>` on stdout) when:

- `--name` is missing.
- Both `--description-file` and `--description` are passed (ambiguous).
- Neither `--description-file` nor `--description` is passed.
- `--description-file <path>` does not exist.
- `validate-args.sh` is missing or not executable next to this script.

Classified failure modes (validator returns `VALID=false` for any reason) all exit 0 with `MODE=abort` — they are not internal errors, they are normal classification outcomes.

## Test coverage

`scripts/test-prepare-description.sh` is the regression harness; it is wired into `make lint` via the explicit `test-harnesses` target and is excluded from `agent-lint.toml`'s dead-script check (matches the `scripts/test-parse-args.sh` pattern). The harness covers all three `MODE` values, the verbatim path via both `--description` and `--description-file` input shapes, all anti-pattern abort cases, the F9 mixed-input scan, and the four internal-error exits. Add new test cases there whenever the stdout grammar, synthesis-trigger error literals, or F9 banned-token-class list changes.
