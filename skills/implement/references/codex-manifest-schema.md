# Codex Implementer Manifest Schema

**Consumer**: `/implement` Step 2 — `skills/implement/scripts/step2-implement.sh` dispatcher (validation), `agents/codex-implementer.md` (production), and downstream Steps 4 / 8a / 9a / 9a.1 (consumption).

**Contract**: Single normative source for the JSON manifest Codex writes at `$IMPLEMENT_TMPDIR/manifest.json` after each implementation attempt. The dispatcher validates the manifest with `jq -e` per the rules below; downstream SKILL.md steps consume only the validated manifest — they never read Codex's transcript or run `git diff` to figure out what changed.

**When to load**: at Step 2 entry (via the MANDATORY directive at the top of Step 2 in SKILL.md) and whenever editing the dispatcher's validation logic, the Codex implementer prompt's manifest-writing instructions, or any of Steps 4 / 8a / 9a / 9a.1 manifest-consumption blocks.

---

## Schema

```json
{
  "schema_version": "1",
  "status": "complete|needs_qa|bailed",
  "files_touched": [
    {"path": "<repo-relative path>", "lines_added": <int>, "lines_removed": <int>}
  ],
  "tests_added_or_modified": ["<repo-relative path>", ...],
  "summary_bullets": ["<bullet 1>", "<bullet 2>", "<bullet 3>"],
  "commit_message": "<subject line>\n\n<optional body paragraphs>",
  "todos_left": ["<actionable todo>", ...],
  "oos_observations": [
    {"title": "<short title>", "description": "<full description>", "phase": "implement"}
  ],
  "bail_reason": "<token>",
  "needs_qa": {
    "questions": [{"id": "<stable id>", "text": "<full question text>"}, ...]
  }
}
```

## Required keys per status

| Field | `complete` | `needs_qa` | `bailed` |
|-------|------------|------------|----------|
| `schema_version` (string `"1"`) | required | required | required |
| `status` (enum) | required | required | required |
| `files_touched` (array of `{path, lines_added, lines_removed}`) | required, non-empty | optional | optional |
| `tests_added_or_modified` (array of strings) | required (may be empty) | optional | optional |
| `summary_bullets` (array of strings, length 1–5) | required | optional | optional |
| `commit_message` (string) | required, non-empty | optional | optional |
| `todos_left` (array of strings) | required (may be empty) | optional | optional |
| `oos_observations` (array of `{title, description, phase}`) | required (may be empty) | optional | optional |
| `bail_reason` (string) | absent or empty | absent or empty | required, non-empty |
| `needs_qa.questions` (non-empty array) | absent | required, non-empty | absent |

Optional fields MAY be present in the non-`complete` statuses but are not required and are not consumed by downstream SKILL.md steps.

## Validation rules (dispatcher applies via `jq -e`)

1. `schema_version == "1"`. Future schema bumps will add new accepted values.
2. `status` is one of the three enum literals above. No other value is accepted.
3. Per-status required keys per the table; the dispatcher rejects (`STATUS=bailed reason=manifest-schema-invalid`) any manifest that fails this check.
4. **Path normalization** (applied to every `path` in `files_touched` and every entry in `tests_added_or_modified`): the path MUST be repo-relative. Reject if it contains `..`, starts with `/`, contains a NUL byte, or, after resolving symlinks, leaves the repo root (`git rev-parse --show-toplevel`). Also reject any path equal to `.claude-plugin/plugin.json` (reserved for `/bump-version`) and any path under a submodule (per `git submodule status`).
5. **Path-set cross-check** (status=`complete` only): the union of `files_touched[].path` MUST equal `git diff --name-only $BASELINE..HEAD` exactly (set equality, not subset). Mismatch → `STATUS=bailed reason=manifest-diff-mismatch`. Baseline is the SHA recorded by the dispatcher in `$IMPLEMENT_TMPDIR/step2-baseline.txt` on first invocation.
6. **Sanitization** (applied AFTER schema validation, BEFORE the canonical manifest is written to `$IMPLEMENT_TMPDIR/manifest.json`): `summary_bullets[*]`, `commit_message`, `oos_observations[*].title`, `oos_observations[*].description`, and `todos_left[*]` are run through the standard redaction rules (secrets → `<REDACTED-TOKEN>`, internal hostnames/URLs → `<INTERNAL-URL>`, PII → `<REDACTED-PII>`). The shell-layer backstop is `scripts/redact-secrets.sh` for the secrets family; URL/PII patterns are applied compose-time inside the dispatcher.

## Atomic write rule

Codex MUST write `manifest.json` and `qa-pending.json` atomically: write to `<path>.tmp`, then `mv <path>.tmp <path>`. The dispatcher reads `manifest.json` only — never `manifest.json.tmp`. A crashed Codex that left only `manifest.json.tmp` looks identical to "no manifest written" and trips the `STATUS=bailed reason=manifest-missing` path.

## Bail-reason tokens

When `status=bailed`, `bail_reason` MUST be one of these stable tokens (downstream tooling pattern-matches on them):

- `resume-incompatible` — Codex inspected branch state on resume and could not reconcile prior partial work with the new operator answers. The branch is left as-is for operator inspection.
- `qa-loop-exceeded` — dispatcher's resume cap (5) tripped on the 6th invocation. Set by the dispatcher, not by Codex itself.
- `manifest-schema-invalid` — manifest failed JSON or schema validation. Set by the dispatcher.
- `manifest-diff-mismatch` — `files_touched` set ≠ baseline-rooted diff set. Set by the dispatcher.
- `protected-path-modified` — Codex's diff touched `.claude-plugin/plugin.json` or a submodule. Set by the dispatcher.
- `submodule-dirty` — `git submodule status --recursive` reported any non-clean entry. Set by the dispatcher.
- `branch-changed` — current branch differs from spawn-time branch. Set by the dispatcher.
- `dirty-tree-after-codex` — `git status --porcelain` non-empty after Codex returned status=complete (Codex was supposed to commit cleanly). Set by the dispatcher.
- `dirty-state-after-timeout` — Codex timed out and the dispatcher refused to retry because the working tree / index was dirty. Set by the dispatcher.
- `availability-flip-mid-codex-run` — `CODEX_HEALTHY` flipped to `false` after at least one Codex spawn this session; dispatcher refuses to silently hand the Codex-modified branch to Claude.
- `codex-runtime-failure` — launcher returned non-zero exit code or no manifest written, and the bounded retry also failed.
- Free-form Codex-authored token — Codex MAY emit any string; the dispatcher passes it through verbatim. Use this for genuine fatal errors Codex itself diagnoses (e.g., `unable-to-resolve-import-cycle`, `external-api-down`).

## Example: `complete` manifest

```json
{
  "schema_version": "1",
  "status": "complete",
  "files_touched": [
    {"path": "skills/foo/SKILL.md", "lines_added": 14, "lines_removed": 3},
    {"path": "scripts/foo-helper.sh", "lines_added": 42, "lines_removed": 0}
  ],
  "tests_added_or_modified": ["scripts/test-foo-helper.sh"],
  "summary_bullets": [
    "Add foo-helper.sh with deterministic stdout contract",
    "Wire helper into skills/foo/SKILL.md Step 3",
    "Cover helper with offline harness"
  ],
  "commit_message": "Add foo-helper.sh and wire it into /foo Step 3\n\nReplaces the inline awk block previously inlined in SKILL.md.",
  "todos_left": [],
  "oos_observations": [],
  "bail_reason": "",
  "needs_qa": {"questions": []}
}
```

## Example: `needs_qa` manifest

```json
{
  "schema_version": "1",
  "status": "needs_qa",
  "files_touched": [],
  "tests_added_or_modified": [],
  "summary_bullets": [],
  "commit_message": "",
  "todos_left": [],
  "oos_observations": [],
  "bail_reason": "",
  "needs_qa": {
    "questions": [
      {"id": "q1", "text": "Should the helper use jq -e or jq --exit-status (older jq versions)?"}
    ]
  }
}
```

The `qa-pending.json` companion file (also atomic-written) carries the same `questions` array in a flat shape:

```json
{"questions": [{"id": "q1", "text": "..."}]}
```

`qa-pending.json` is what the orchestrator reads to drive `AskUserQuestion`; the manifest's `needs_qa.questions` is informational redundancy for tooling that prefers a single file.

## Edit-in-sync

Any change to this schema MUST be paired with edits in:

- `skills/implement/scripts/step2-implement.sh` — dispatcher validation (`jq -e` filters).
- `agents/codex-implementer.md` — Codex prompt's manifest-writing instructions.
- `skills/implement/SKILL.md` — Step 4 (commit verification), Step 8a (CHANGELOG), Step 9a (PR `## Summary`), Step 9a.1 (OOS pipeline) consumption blocks.
- `skills/implement/scripts/test-step2-dispatch.sh` — golden manifest fixtures.
