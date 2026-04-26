# test-classify-research-scale.sh — Contract

**Purpose**: offline regression harness for `classify-research-scale.sh`. Feeds canned question texts to the classifier and asserts exit code + `SCALE=` / `REASON=` lines match the contract in `classify-research-scale.md`.

**Consumed by**: `make lint` via the `test-classify-research-scale` Makefile target. Also runs in CI via the same Makefile target (CI invokes `make test-harnesses` which depends on `test-classify-research-scale`).

**Why a separate harness**: every `skills/<name>/scripts/` script that ships a contract requires a colocated regression harness per `AGENTS.md` "Per-script contracts live beside the script" rule. This harness is the canonical guard against rule-set regressions in the classifier — any future edit to `classify-research-scale.sh`'s thresholds, keyword lists, or stage ordering must update fixtures here in the same PR.

## Invocation

```bash
bash skills/research/scripts/test-classify-research-scale.sh
```

No flags or arguments. The harness creates a fresh tmpdir under `mktemp -d`, writes one fixture file per case, invokes the classifier, asserts on stdout + exit code, and cleans up via a `trap rm -rf` on EXIT.

## Output

- **stdout** on success: `All <N> test cases passed.` exit 0.
- **stderr** on failure: per-case `FAIL [<case-name>]: ...` line(s), then a summary `Result: <P> passed, <F> failed` line. Exit 1.

## Fixture coverage

The harness covers each rule branch defined in `classify-research-scale.md`:

### Stage 1 (deep) coverage

- `length_deep_just_over_threshold` — question > 600 bytes → `SCALE=deep` + `REASON=length_deep` (implicit via SCALE assertion alone — REASON is asserted in adjacent cases).
- `keyword_deep_compare_architecture` — 2+ deep keywords → `SCALE=deep`.
- `keyword_deep_reason_token` — same input as above, asserts `REASON=keyword_deep`.
- `multi_part_deep` / `multi_part_deep_reason` — 2+ `?` characters → `SCALE=deep` + `REASON=multi_part_deep`.
- `single_deep_keyword_falls_through_to_standard_or_quick` — single deep keyword does NOT fire deep (Stage 1b requires ≥2).
- `deep_security_review_threat_model` — multi-word deep keyphrases counted correctly.
- `two_questions_short_still_deep` — Stage 1 priority over Stage 2 (multi-`?` wins even when Stage 2 would otherwise fire).

### Stage 2 (quick) coverage

- `lookup_quick_what_is` / `lookup_quick_reason` — short + lookup + single `?` → `SCALE=quick` + `REASON=lookup_quick`.
- `lookup_quick_where_is`, `lookup_quick_how_many` — coverage for additional lookup-set entries.
- `long_lookup_falls_to_standard` — length ≥ 80 disqualifies Stage 2 even when lookup keyword present.
- `short_no_lookup_keyword_standard` — short single-`?` without lookup keyword → standard (Stage 2c fails).
- `short_lookup_with_deep_keyword_standard` — lookup keyword + deep keyword → standard (Stage 2d fails; Stage 1 doesn't fire because only one deep keyword).
- `yes_no_question_falls_to_standard` — `does` deliberately excluded from lookup set (would false-positive on "how does"), so a yes/no question without other lookup signals falls through to standard.

### Stage 3 (default) coverage

- `mid_length_explanatory_standard` / `mid_length_explanatory_reason` — mid-length explanatory question → `SCALE=standard` + `REASON=default_standard`.

### Failure-mode coverage

- `empty_input` — zero-byte file → `REASON=empty_input` + exit 1.
- `whitespace_only_empty_input` — file containing only spaces/tabs/newlines → `REASON=empty_input` + exit 1.
- `missing_question_arg` — invocation with no args → `REASON=missing_arg` + exit 2.
- `unknown_arg` — invocation with an unknown flag → `REASON=missing_arg` + exit 2.
- `bad_path_nonexistent` — `--question` path does not exist → `REASON=bad_path` + exit 2.
- `bad_path_directory` — `--question` path points at a directory → `REASON=bad_path` + exit 2.

### Asymmetric-conservatism coverage

- `borderline_short_single_q_no_lookup_standard` — short single-`?` without lookup-keyword stays in standard (no auto-quick on doubt).
- `borderline_lookup_too_long_standard` — lookup keyword present but length disqualifies → standard.

## Edit-in-sync rules

- **Adding a new rule branch in `classify-research-scale.sh`**: add a fixture case here covering both the positive trigger and at least one negative case (similar input that does NOT trigger).
- **Changing thresholds or keyword sets in `classify-research-scale.sh`**: update fixture inputs to reflect the new boundaries; the harness deliberately keeps fixtures close to the threshold so off-by-one regressions are caught.
- **Changing stdout schema (`SCALE=` / `REASON=`)**: update assertions here AND `classify-research-scale.md` AND any orchestrator parsing in `skills/research/SKILL.md` Step 0.5 / `skills/research/references/research-phase.md`.
- **Changing exit code semantics**: update the harness's `expected_exit` values + the contract in `classify-research-scale.md` + the orchestrator's exit-code branch in SKILL.md.

## bash 3.2 compatibility

The harness uses the `${args[@]+"${args[@]}"}` idiom for the trailing-array expansion on `run_case_invocation` to avoid `unbound variable` errors on macOS-default bash 3.2 under `set -u`. Do NOT replace with `${args[@]}` (errors on empty arrays) or `${args[@]:-}` (works on bash 4+ but is brittle on 3.2 with arrays).
