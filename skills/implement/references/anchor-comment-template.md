# Anchor Comment Template

**Consumer**: `/implement` Phase 3 (umbrella #348) — the canonical anchor-comment markdown template written via `scripts/tracking-issue-write.sh upsert-anchor` and parsed from issue comments by future consumers. Phase 1 ships this reference file with no consumer wiring; the first consumer lands in Phase 3.

**Contract**: single normative source for (1) the eight canonical section markers, (2) the first-line HTML anchor marker literal, (3) the Voting Tally extraction guidance, (4) the Step 9a.1 OOS pipeline procedure adapted to anchor-comment context, (5) the Quick-mode anchor guidance, and (6) the three load-bearing string literals that Phase 3's test-harness migration will pin (`Accepted OOS (GitHub issues filed)`, `| OOS issues filed |`, `<details><summary>Execution Issues</summary>`). Section headers and HTML comment markers must NOT drift — `scripts/tracking-issue-write.sh`'s `SECTION_MARKERS` array and the body-level collapse priority rely on the exact slug set listed here, and future `test-implement-structure.sh` assertions will pin these literals.

**When to load**: by Phase 3 consumers when they begin composing anchor-comment bodies via `tracking-issue-write.sh upsert-anchor`, and by the `test-implement-structure.sh` assertion (future) that pins the load-bearing literals here. Do NOT load in Phase 1 — there are no consumers yet.

---

## Anchor first-line marker

Every anchor comment begins with exactly this line (`<N>` is the tracking issue number):

```
<!-- larch:implement-anchor v1 issue=<N> -->
```

Rationale: the HTML-comment prefix renders invisibly in GitHub's comment UI but is machine-greppable by `tracking-issue-write.sh upsert-anchor`'s marker-search fallback when no explicit `--anchor-id` is passed. The `v1` version is strict: the write script matches only `<!-- larch:implement-anchor v1`-prefixed comments, and `tracking-issue-read.sh`'s anchor-marker filter uses the same strict prefix. Future anchor versions (v2, …) introduce a new marker handled by a new tool version.

Mixed-version state on a single issue (a legacy `<!-- larch:implement-anchor v1` comment alongside a hypothetical future `<!-- larch:implement-anchor v2`) fails closed: Phase 1's `upsert-anchor` exits 2 with `FAILED=true ERROR=multiple anchor comments found (ids: <list>)` any time it finds more than one v1-prefixed comment.

## Canonical template

```markdown
<!-- larch:implement-anchor v1 issue=<N> -->

<!-- section:plan-goals-test -->
## Goal

<goal paragraph from /design output>

## Test plan

<test plan from /design output>

<!-- section-end:plan-goals-test -->

<!-- section:plan-review-tally -->
## Plan Review Voting Tally

<per-finding YES/NO/EXONERATE counts and reviewer scoreboard from /design Step 3>

<!-- section-end:plan-review-tally -->

<!-- section:code-review-tally -->
## Code Review Voting Tally (Round 1)

<per-finding YES/NO/EXONERATE counts and reviewer scoreboard from /review>

<!-- section-end:code-review-tally -->

<!-- section:diagrams -->
## Architecture Diagram

```mermaid
<architecture diagram>
```

## Code Flow Diagram

```mermaid
<code flow diagram>
```

<!-- section-end:diagrams -->

<!-- section:version-bump-reasoning -->
## Version Bump Reasoning

<classification and justification from /bump-version>

<!-- section-end:version-bump-reasoning -->

<!-- section:oos-issues -->
## Accepted OOS (GitHub issues filed)

<one bullet per accepted OOS item: `- <short title> — #<issue-number>`>

## Rejected / Out-of-Scope Observations (not filed)

<one bullet per non-accepted OOS observation>

<!-- section-end:oos-issues -->

<!-- section:execution-issues -->
<details><summary>Execution Issues</summary>

<verbatim contents of $IMPLEMENT_TMPDIR/execution-issues.md — categorized entries: Pre-existing Code Issues, Tool Failures, Permission Prompts, External Reviewer Issues, CI Issues, Warnings>

</details>

<!-- section-end:execution-issues -->

<!-- section:run-statistics -->
## Run Statistics

| Metric | Value |
|---|---|
| OOS issues filed | <N> |
| Findings accepted | <N> |
| Findings rejected | <N> |
| CI wait duration | <mm:ss> |
| Rebase count | <N> |

<!-- section-end:run-statistics -->
```

## Section markers — exact slug list

The `SECTION_MARKERS` array in `scripts/tracking-issue-write.sh` must list these exact eight slugs in this order (truncation algorithm walks sections in this order for pass 1):

1. `plan-goals-test`
2. `plan-review-tally`
3. `code-review-tally`
4. `diagrams`
5. `version-bump-reasoning`
6. `oos-issues`
7. `execution-issues`
8. `run-statistics`

Every section is wrapped as `<!-- section:<slug> -->` ... `<!-- section-end:<slug> -->`. Both markers must appear on their own line; no other content may share a marker's line.

## Body-level collapse priority

When the composed anchor-comment body exceeds the 60000-char body-level cap (after per-section 8000-char caps have been applied), sections collapse to a single-line `[section '<slug>' truncated — see execution-issues.md locally]` placeholder in this priority order:

1. `execution-issues` (most ephemeral — reproducible from local `$IMPLEMENT_TMPDIR` tmpdir)
2. `plan-review-tally`
3. `code-review-tally`
4. `oos-issues`
5. `run-statistics`
6. `version-bump-reasoning`
7. `diagrams`
8. `plan-goals-test` (highest user-value — goal + test plan must survive)

Collapse stops as soon as the body fits the cap. Section markers themselves are preserved even when interiors collapse; Phase 3 consumers parse by these markers.

## Voting Tally extraction guidance

The `plan-review-tally` and `code-review-tally` sections contain per-finding vote counts and per-reviewer competition scoreboards. For Phase 3+:

- The tally table format matches the scoreboard format in `skills/shared/voting-protocol.md`.
- Future consumers extracting tallies from an existing anchor comment should use the section-open / section-end markers as the extraction boundary (not prose heuristics).
- If a tally section is present but its interior is collapsed to the `[section '...' truncated — see execution-issues.md locally]` placeholder, treat the tally as unavailable and degrade gracefully — do NOT fabricate counts.

## Step 9a.1 OOS pipeline procedure (canonical, anchor-comment context)

The canonical Step 9a.1 procedure lives here (Phase 3+). The anchor comment is the single source of truth for report content — the PR body is a slim projection (see `skills/implement/references/pr-body-template.md` for the slim-PR scaffold).

Step 9a.1's sequence in anchor context:

1. Read `$IMPLEMENT_TMPDIR/oos-accepted-*.md` artifact files (one per phase: `oos-accepted-design.md`, `oos-accepted-review-r<N>.md`, `oos-accepted-main-agent.md`).
2. If all artifacts are empty, emit `Accepted OOS (GitHub issues filed)` as an empty bulleted list.
3. Idempotency guard: if `$IMPLEMENT_TMPDIR/oos-issues-created.md` sentinel exists, recover prior URLs from it and skip the `/issue` invocation (deterministic byte-exact guard). Do NOT double-file.
4. Invoke `/issue --input-file` batch mode with the accepted OOS entries. Parse stdout for `ISSUES_CREATED`, `ISSUES_FAILED`, `ISSUES_DEDUPLICATED`, per-issue `ISSUE_<i>_NUMBER=`, `ISSUE_<i>_URL=`.
5. Write the sentinel `$IMPLEMENT_TMPDIR/oos-issues-created.md` with the per-issue URLs for rerun idempotency.
6. Replace the `oos-issues` section's `Accepted OOS (GitHub issues filed)` placeholder with one bullet per created issue (`- <short title> — #<number>`) plus any `— filed as #<N>` annotations linking prior rejected findings to newly-filed follow-ups.
7. Update the `run-statistics` section's `| OOS issues filed |` row with the count of newly-created issues (recovered-from-sentinel count is NOT included — sentinel recovery means "previously filed this session, not filed again this step").

## Quick-mode anchor guidance

Quick mode (`/implement --quick`) skips `/design` and `/review`, so the `plan-review-tally` and `code-review-tally` sections have no standard content. Quick-mode consumers should:

- Leave the `plan-review-tally` and `code-review-tally` sections present (with section markers preserved) but populate the interior with `(plan review skipped — quick mode)` / `(single-reviewer loop — no voting panel)` as appropriate.
- Populate `diagrams` with only the Architecture Diagram (Code Flow Diagram is skipped in quick mode per SKILL.md Step 7a).
- All other sections are populated normally.

This keeps the anchor-comment shape stable across mode-selection so a Phase 3+ consumer can parse by section marker regardless of mode.

## Compose-time sanitization rule

Every fragment composed into the anchor-comment body must apply prompt-level sanitization at compose time, parallel to the rule stated in `skills/implement/SKILL.md` "Execution Issues Tracking" section:

- Redact secrets / API keys / OAuth / JWT / passwords / certificates → `<REDACTED-TOKEN>`.
- Internal hostnames / URLs / private IPs → `<INTERNAL-URL>`.
- PII (emails, names, account IDs linked to a real user) → `<REDACTED-PII>`.

This is a defense-in-depth layer above `scripts/redact-secrets.sh`'s outbound scrubber: the scrubber catches covered token families mechanically, but internal URLs and PII are out of its coverage and MUST be sanitized at compose time. `tracking-issue-write.sh`'s structural choke point (compose → redact → truncate) ensures no bypass path exists, but it does NOT invent redactions the helper does not cover — compose-time prompt-level sanitization is the first and primary defense for those classes.

## Edit-in-sync pointers

| File | Relationship |
|---|---|
| `scripts/tracking-issue-write.sh` | `SECTION_MARKERS` and `COLLAPSE_PRIORITY` arrays must match the slug list here. |
| `scripts/tracking-issue-read.sh` | Anchor-marker filter uses the same strict `<!-- larch:implement-anchor v1` prefix. |
| `skills/implement/references/pr-body-template.md` | Sibling slim-projection template for the PR body (Summary + Diagrams + Test plan + `Closes #<N>` + footer only); Phase 3+ the anchor comment is canonical for rich content. |
| `scripts/test-implement-structure.sh` | Phase 3 test-harness assertion (9a) pins the three load-bearing literals here (`Accepted OOS (GitHub issues filed)`, `| OOS issues filed |`, `<details><summary>Execution Issues</summary>`); assertion (9b) pins a ≥3 reference floor for `anchor-comment-template.md` in SKILL.md. |
