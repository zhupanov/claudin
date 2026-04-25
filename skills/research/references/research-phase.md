# Research Phase Reference

**Consumer**: `/research` Step 1 — loaded via the `MANDATORY — READ ENTIRE FILE` directive at Step 1 entry in SKILL.md.

**Contract**: scale-aware research-lane invariant. `RESEARCH_SCALE=standard` (default) keeps the 3-lane shape — Claude inline + Cursor + Codex, with Claude subagent fallbacks preserving the 3-lane count when an external tool is unavailable. `RESEARCH_SCALE=quick` runs 1 inline Claude lane only (single-lane confidence; no externals, no fallbacks). `RESEARCH_SCALE=deep` runs 5 lanes — Claude inline (baseline `RESEARCH_PROMPT`) plus 2 Cursor slots and 2 Codex slots carrying the four diversified angle prompts (`RESEARCH_PROMPT_ARCH`, `RESEARCH_PROMPT_EDGE`, `RESEARCH_PROMPT_EXT`, `RESEARCH_PROMPT_SEC`). Owns the spawn-order rule, the external-evidence trigger detector and the conditional `RESEARCH_PROMPT` literals, the four named angle-prompt literals, external launch bash blocks, per-slot fallback rules, the Claude-inline independence rule, Step 1.3 collection with zero-externals branch + runtime-timeout replacement, and Step 1.4 synthesis requirements.

**When to load**: once Step 1 is about to execute. Do NOT load during Step 0, Step 2, Step 3, or Step 4. SKILL.md emits the Step 1 entry breadcrumb and the Step 1 completion print; this file does NOT emit those — it owns body content only.

---

**IMPORTANT: The research phase runs the lane shape selected by `RESEARCH_SCALE`. When `RESEARCH_SCALE=standard` (default) or `deep`, the phase MUST run with the configured ≥3 agents (using Claude subagent fallbacks where an external tool is unavailable, preserving the configured lane count). When `RESEARCH_SCALE=quick`, the phase runs 1 inline Claude lane only — that is the designated minimum, and the synthesis must explicitly note "single-lane confidence". Never silently promote between scales: `quick` does not get auto-upgraded to `standard`, and `standard` is not auto-upgraded to `deep`.**

A diverge-then-converge phase where N agents independently explore the codebase before synthesizing findings. N is 1 for `quick`, 3 for `standard`, and 5 for `deep`. In standard mode, diversity comes from model-family heterogeneity (Claude + Cursor's backing model + Codex's backing model). In deep mode, diversity additionally comes from differentiated per-lane personalities (architecture / edge cases / external comparisons / security) carried by the four named angle prompts.

The research agents per scale:

- **`RESEARCH_SCALE=quick`** (1 lane):
  1. **Claude (inline)** — the orchestrating agent's own research, run with the shared `RESEARCH_PROMPT` below. No external launches, no fallbacks.

- **`RESEARCH_SCALE=standard`** (3 lanes — default):
  1. **Claude (inline)** — the orchestrating agent's own research, run with the shared `RESEARCH_PROMPT` below.
  2. **Cursor** (if available) — or a **Claude subagent** fallback via the Agent tool, running the same `RESEARCH_PROMPT`.
  3. **Codex** (if available) — or a **Claude subagent** fallback via the Agent tool, running the same `RESEARCH_PROMPT`.

- **`RESEARCH_SCALE=deep`** (5 lanes):
  1. **Claude (inline)** — orchestrator's own research, run with the baseline `RESEARCH_PROMPT` (general/synthesis-style, covers all angles broadly).
  2. **Cursor slot 1 — Architecture** — runs `RESEARCH_PROMPT_ARCH`. Claude subagent fallback if `cursor_available=false`.
  3. **Cursor slot 2 — Edge cases** — runs `RESEARCH_PROMPT_EDGE`. Claude subagent fallback if `cursor_available=false`.
  4. **Codex slot 1 — External comparisons** — runs `RESEARCH_PROMPT_EXT`. Claude subagent fallback if `codex_available=false`.
  5. **Codex slot 2 — Security** — runs `RESEARCH_PROMPT_SEC`. Claude subagent fallback if `codex_available=false`.

## 1.2 — Launch Research Perspectives in Parallel

**Critical sequencing**: You MUST launch all external research Bash tool calls (with `run_in_background: true`) AND any Claude subagent fallbacks BEFORE producing your own inline research. External reviewers take significantly longer than Claude — launching them first maximizes parallelism.

**Spawn order**: Cursor first (slowest), then Codex, then any Claude subagent fallbacks, then your own inline research (fastest). Issue all Bash and Agent tool calls in a single message.

**External-evidence trigger detection** (mental — performed before constructing `RESEARCH_PROMPT`): set the flag `external_evidence_mode` to `true` if `RESEARCH_QUESTION` contains any of the following case-insensitive substrings; otherwise leave it `false`. The list is intentionally narrow and biased toward obvious external-research signals — misrouting compounds errors, so prefer false negatives (an operator who wants external evidence can always restate the question). Extend the list when a clear pattern emerges:

- `external`
- `other repos`
- `github`
- `compare with`
- `contrast`
- `reputable sources`
- `karpathy`
- `anthropic`
- `open source`
- `oss`
- `large amount of stars`
- `high stars`
- `star count`

**Shared prompt** (used verbatim by all 3 lanes — Cursor, Codex, inline Claude, and any Claude fallbacks; identical across lanes — do NOT branch per-lane):

When `external_evidence_mode=false`:

`RESEARCH_PROMPT` = ``"You are researching a codebase to answer this question: <RESEARCH_QUESTION>. Consider alternative perspectives to the obvious interpretation. Actively scrutinize for edge cases, gaps, missing pieces, and assumption failures. Explore the codebase to ground your findings with verifiable provenance (see (4)). Write 2-3 paragraphs covering: (1) key findings and observations, including any that challenge the obvious reading, (2) relevant files/modules/areas and architectural patterns, (3) risks, constraints, feasibility concerns, edge cases, and gaps, (4) Every concrete claim must carry provenance: a `file:line` (or `file:line-range`) reference for repo-internal claims, a fenced command + 1–3 lines of its output for behavior claims, or a URL for external claims. Pure prose summaries without provenance are acceptable only for synthesis sentences that aggregate already-cited claims. Do NOT modify files."``

When `external_evidence_mode=true`, use the combined literal below — the external-evidence stanza is already inserted at the correct position (immediately after the question line and before "Consider alternative perspectives…"); do NOT prepend it again at runtime:

`RESEARCH_PROMPT` = ``"You are researching a codebase to answer this question: <RESEARCH_QUESTION>. This question demands external evidence (other repos, blog posts, official docs). Use WebSearch and WebFetch to gather sources from reputable origins (vendor docs like anthropic.com / openai.com, well-known engineer blogs, GitHub repos with notable star counts). Each external claim must cite a URL. The codebase remains the source of truth for any internal claim about this repo. Consider alternative perspectives to the obvious interpretation. Actively scrutinize for edge cases, gaps, missing pieces, and assumption failures. Explore the codebase to ground your findings with verifiable provenance (see (4)). Write 2-3 paragraphs covering: (1) key findings and observations, including any that challenge the obvious reading, (2) relevant files/modules/areas and architectural patterns, (3) risks, constraints, feasibility concerns, edge cases, and gaps, (4) Every concrete claim must carry provenance: a `file:line` (or `file:line-range`) reference for repo-internal claims, a fenced command + 1–3 lines of its output for behavior claims, or a URL for external claims. Pure prose summaries without provenance are acceptable only for synthesis sentences that aggregate already-cited claims. Do NOT modify files."``

The Phase 1 provenance clause (item 4 — URL for external claims) already accommodates URL citations; this branch widens only the *invitation* to use them.

**Named angle prompts** (`RESEARCH_SCALE=deep` only; ignored for `quick` and `standard`). The four diversified angle prompts assign each external slot in deep mode a focused investigative lens. Each prompt body retains the structure of `RESEARCH_PROMPT` (2-3 paragraphs covering the four numbered items including the provenance clause), narrowed by the angle's emphasis. The orchestrator substitutes `<RESEARCH_QUESTION>` literally at launch time, identical to the standard-mode `RESEARCH_PROMPT`.

`RESEARCH_PROMPT_ARCH` = ``"You are researching a codebase to answer this question: <RESEARCH_QUESTION>. Focus your investigation on the **architecture & data flow** angle — how the relevant components fit together, what abstractions and contracts they expose, where the boundaries are, and how data and control flow between them. Explore the codebase to ground your findings with verifiable provenance (see (4)). Write 2-3 paragraphs covering: (1) key architectural findings — modules, layering, contracts, boundaries, (2) relevant files/modules/areas and how data flows through them, (3) architectural risks, fragile boundaries, and structural feasibility concerns, (4) Every concrete claim must carry provenance: a `file:line` (or `file:line-range`) reference for repo-internal claims, a fenced command + 1–3 lines of its output for behavior claims, or a URL for external claims. Pure prose summaries without provenance are acceptable only for synthesis sentences that aggregate already-cited claims. Do NOT modify files."``

`RESEARCH_PROMPT_EDGE` = ``"You are researching a codebase to answer this question: <RESEARCH_QUESTION>. Focus your investigation on the **edge cases & failure modes** angle — boundary conditions, error paths, failure recovery, race conditions, silent data corruption, and what can go wrong. Explore the codebase to ground your findings with verifiable provenance (see (4)). Write 2-3 paragraphs covering: (1) key edge-case and failure-mode findings, (2) relevant files/modules/areas where defensive logic lives or is conspicuously absent, (3) failure-mode risks, error-handling gaps, and reliability/feasibility concerns, (4) Every concrete claim must carry provenance: a `file:line` (or `file:line-range`) reference for repo-internal claims, a fenced command + 1–3 lines of its output for behavior claims, or a URL for external claims. Pure prose summaries without provenance are acceptable only for synthesis sentences that aggregate already-cited claims. Do NOT modify files."``

`RESEARCH_PROMPT_EXT` = ``"You are researching a codebase to answer this question: <RESEARCH_QUESTION>. Focus your investigation on the **external comparisons** angle — how this question is approached in other repositories, libraries, or established prior art. Use WebSearch / WebFetch when available to gather sources from reputable origins (vendor docs, well-known engineering blogs, GitHub repos with notable star counts) and surface concrete alternative approaches worth considering. Each external claim must cite a URL. The codebase remains the source of truth for any internal claim about this repo. Write 2-3 paragraphs covering: (1) key external comparisons and prior-art findings, (2) which files/modules/areas in this repo correspond to the externally-observed patterns, (3) tradeoffs surfaced by the comparison and feasibility implications, (4) Every concrete claim must carry provenance: a `file:line` (or `file:line-range`) reference for repo-internal claims, a fenced command + 1–3 lines of its output for behavior claims, or a URL for external claims. Pure prose summaries without provenance are acceptable only for synthesis sentences that aggregate already-cited claims. Do NOT modify files."``

`RESEARCH_PROMPT_SEC` = ``"You are researching a codebase to answer this question: <RESEARCH_QUESTION>. Focus your investigation on the **security & threat surface** angle — injection vectors, authn/authz gaps, secret handling, crypto choices, deserialization risks, SSRF, path traversal, dependency CVEs, and any other security-relevant exposure. Explore the codebase to ground your findings with verifiable provenance (see (4)). Write 2-3 paragraphs covering: (1) key security findings — concrete threat surfaces and exposures, (2) relevant files/modules/areas (including dependency manifests and trust boundaries), (3) security risks, attacker scenarios, and mitigation feasibility, (4) Every concrete claim must carry provenance: a `file:line` (or `file:line-range`) reference for repo-internal claims, a fenced command + 1–3 lines of its output for behavior claims, or a URL for external claims. Pure prose summaries without provenance are acceptable only for synthesis sentences that aggregate already-cited claims. Do NOT modify files."``

**Cursor web-tool asymmetry**: Cursor's `cursor agent` runtime does not expose `WebSearch` / `WebFetch` as named tools the way Claude does. When `external_evidence_mode=true`, the prompt invitation is honored directly by the Codex and Claude lanes (which carry web tools); the Cursor lane falls back to whatever web access its underlying model provides via the prompt — typically none in `--full-auto` mode. The 3-lane invariant (in standard mode) holds at the prompt-text level (all three lanes receive the identical stanza), but external-evidence yield is realized primarily through Codex + Claude-inline. Step 1.4 synthesis should treat a Cursor lane that returned no URL citations under `external_evidence_mode=true` as an expected limitation of that lane (not as substantive disagreement with the other two), so the agree/diverge analysis does not over-weight an empty Cursor external thread.

Branch the launch blocks below on `RESEARCH_SCALE`. The `### Standard` subsection is the default-mode behavior and is byte-stable for backward compatibility; `### Quick` and `### Deep` are additive branches.

### Standard (RESEARCH_SCALE=standard, default)

**Cursor research** (if `cursor_available`):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/run-external-reviewer.sh --tool cursor --output "$RESEARCH_TMPDIR/cursor-research-output.txt" --timeout 1800 --capture-stdout -- \
  cursor agent -p --force --trust $("${CLAUDE_PLUGIN_ROOT}/scripts/reviewer-model-args.sh" --tool cursor) --workspace "$PWD" \
    "$("${CLAUDE_PLUGIN_ROOT}/scripts/cursor-wrap-prompt.sh" "<RESEARCH_PROMPT>")"
```

Use `run_in_background: true` and `timeout: 1860000` on the Bash tool call.

**Cursor fallback** (if `cursor_available` is false): Launch a Claude subagent via the Agent tool carrying `RESEARCH_PROMPT` verbatim. **Do NOT use `subagent_type: code-reviewer`** — the code-reviewer archetype mandates a dual-list findings output that conflicts with the 2-3 prose paragraph shape this phase requires.

**Codex research** (if `codex_available`):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/run-external-reviewer.sh --tool codex --output "$RESEARCH_TMPDIR/codex-research-output.txt" --timeout 1800 -- \
  codex exec --full-auto -C "$PWD" $("${CLAUDE_PLUGIN_ROOT}/scripts/reviewer-model-args.sh" --tool codex) \
    --output-last-message "$RESEARCH_TMPDIR/codex-research-output.txt" \
    "<RESEARCH_PROMPT>"
```

Use `run_in_background: true` and `timeout: 1860000` on the Bash tool call.

**Codex fallback** (if `codex_available` is false): Launch a Claude subagent via the Agent tool carrying `RESEARCH_PROMPT` verbatim. Same rule as the Cursor fallback above — **do NOT use `subagent_type: code-reviewer`**.

**Claude research (inline)**: Only after all external and fallback launches are issued, produce your own 2-3 paragraph research inline using `RESEARCH_PROMPT` as your brief. Print it under a `### Claude Research (inline)` header. Write this **before** reading any external or subagent outputs to preserve independence.

### Quick (RESEARCH_SCALE=quick)

Skip all external launches and all Claude subagent fallbacks — there are none in quick mode. Produce a single inline Claude research paragraph (2-3 paragraphs) using `RESEARCH_PROMPT` as the brief and print it under a `### Claude Research (inline)` header. The single-lane outcome is by design; the synthesis at Step 1.4 must label the result with explicit "single-lane confidence" framing so the operator does not mistake it for a multi-perspective synthesis.

### Deep (RESEARCH_SCALE=deep)

Launch 5 lanes — 4 external slots in parallel plus the Claude inline lane. Spawn order: both Cursor slots first (slowest), then both Codex slots, then any per-slot Claude fallbacks, then the Claude inline lane (fastest). Issue all Bash and Agent tool calls in a single message.

**Cursor slot 1 — Architecture** (if `cursor_available`):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/run-external-reviewer.sh --tool cursor --output "$RESEARCH_TMPDIR/cursor-research-arch-output.txt" --timeout 1800 --capture-stdout -- \
  cursor agent -p --force --trust $("${CLAUDE_PLUGIN_ROOT}/scripts/reviewer-model-args.sh" --tool cursor) --workspace "$PWD" \
    "$("${CLAUDE_PLUGIN_ROOT}/scripts/cursor-wrap-prompt.sh" "<RESEARCH_PROMPT_ARCH>")"
```

Use `run_in_background: true` and `timeout: 1860000` on the Bash tool call.

**Cursor slot 1 fallback** (if `cursor_available` is false): launch a Claude subagent via the Agent tool carrying `RESEARCH_PROMPT_ARCH` verbatim. Same rule as standard-mode Cursor fallback — **do NOT use `subagent_type: code-reviewer`**.

**Cursor slot 2 — Edge cases** (if `cursor_available`):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/run-external-reviewer.sh --tool cursor --output "$RESEARCH_TMPDIR/cursor-research-edge-output.txt" --timeout 1800 --capture-stdout -- \
  cursor agent -p --force --trust $("${CLAUDE_PLUGIN_ROOT}/scripts/reviewer-model-args.sh" --tool cursor) --workspace "$PWD" \
    "$("${CLAUDE_PLUGIN_ROOT}/scripts/cursor-wrap-prompt.sh" "<RESEARCH_PROMPT_EDGE>")"
```

Use `run_in_background: true` and `timeout: 1860000`.

**Cursor slot 2 fallback** (if `cursor_available` is false): Claude subagent with `RESEARCH_PROMPT_EDGE` verbatim.

**Codex slot 1 — External comparisons** (if `codex_available`):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/run-external-reviewer.sh --tool codex --output "$RESEARCH_TMPDIR/codex-research-ext-output.txt" --timeout 1800 -- \
  codex exec --full-auto -C "$PWD" $("${CLAUDE_PLUGIN_ROOT}/scripts/reviewer-model-args.sh" --tool codex) \
    --output-last-message "$RESEARCH_TMPDIR/codex-research-ext-output.txt" \
    "<RESEARCH_PROMPT_EXT>"
```

Use `run_in_background: true` and `timeout: 1860000`.

**Codex slot 1 fallback** (if `codex_available` is false): Claude subagent with `RESEARCH_PROMPT_EXT` verbatim.

**Codex slot 2 — Security** (if `codex_available`):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/run-external-reviewer.sh --tool codex --output "$RESEARCH_TMPDIR/codex-research-sec-output.txt" --timeout 1800 -- \
  codex exec --full-auto -C "$PWD" $("${CLAUDE_PLUGIN_ROOT}/scripts/reviewer-model-args.sh" --tool codex) \
    --output-last-message "$RESEARCH_TMPDIR/codex-research-sec-output.txt" \
    "<RESEARCH_PROMPT_SEC>"
```

Use `run_in_background: true` and `timeout: 1860000`.

**Codex slot 2 fallback** (if `codex_available` is false): Claude subagent with `RESEARCH_PROMPT_SEC` verbatim.

**Claude research (inline)**: only after all external and per-slot fallback launches are issued, produce your own 2-3 paragraph inline research using the baseline `RESEARCH_PROMPT` as your brief (NOT one of the diversified angle prompts — Claude inline plays the general/synthesis-style role in deep mode). Print it under a `### Claude Research (inline)` header. Write this **before** reading any external or subagent outputs to preserve independence.

**Per-tool availability coupling note**: a runtime timeout in any one Cursor lane flips the session-wide `cursor_available` flag (per `external-reviewers.md` Runtime Timeout Fallback) and takes out the surviving Cursor lane too. Same coupling applies to Codex. This matches existing `/design` 5-sketch behavior; per-slot availability tracking is out of scope for v1.

## 1.3 — Wait and Validate Research Outputs

Collection logic branches on `RESEARCH_SCALE`. The Standard subsection is byte-stable for backward compatibility.

### Standard (RESEARCH_SCALE=standard, default)

Collect and validate external research outputs using the shared collection script. Build the argument list from only the externals that were actually launched (not Claude fallbacks — those return via Agent tool):

```
COLLECT_ARGS=()
[[ "$cursor_available" == true ]] && COLLECT_ARGS+=("$RESEARCH_TMPDIR/cursor-research-output.txt")
[[ "$codex_available" == true ]] && COLLECT_ARGS+=("$RESEARCH_TMPDIR/codex-research-output.txt")
```

**Zero-externals branch**: If BOTH Cursor and Codex are unavailable (`COLLECT_ARGS` is empty), **skip `collect-reviewer-results.sh` entirely** — the script exits non-zero when called with an empty path list. Proceed directly to Step 1.4 with the 3 Claude outputs (inline + 2 fallback subagents).

Otherwise, invoke the script with only the launched paths:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/collect-reviewer-results.sh --timeout 1860 "${COLLECT_ARGS[@]}"
```

Use `timeout: 1860000` on the Bash tool call. **Do NOT** set `run_in_background: true` — this call must block.

Parse the structured output for each reviewer's `STATUS` and `REVIEWER_FILE`. For research outputs, additionally check that valid output contains at least one paragraph of substantive prose (the script validates non-empty; content validation is the caller's responsibility).

**Runtime-timeout replacement**: For any reviewer with `STATUS` not `OK`, follow the **Runtime Timeout Fallback** procedure in `${CLAUDE_PLUGIN_ROOT}/skills/shared/external-reviewers.md` to flip the corresponding availability flag, then **immediately launch a Claude subagent fallback via the Agent tool** (no `subagent_type`, carrying `RESEARCH_PROMPT` verbatim — same as the pre-launch fallback in Step 1.2) and wait for it before synthesis. This preserves the 3-lane invariant at synthesis time; without it, a mid-run external timeout silently reduces the synthesis input from 3 perspectives to 2.

### Quick (RESEARCH_SCALE=quick)

There are no external launches and no fallbacks in quick mode — the Step 1.2 Quick subsection produced exactly one Claude inline output. **Skip `collect-reviewer-results.sh` entirely** (this reuses the same zero-externals discipline as standard mode's `COLLECT_ARGS=()` branch — `collect-reviewer-results.sh` exits non-zero when called with an empty path list). Proceed directly to Step 1.4.

### Deep (RESEARCH_SCALE=deep)

Build `COLLECT_ARGS` from the four diversified output paths actually launched:

```
COLLECT_ARGS=()
[[ "$cursor_available" == true ]] && COLLECT_ARGS+=("$RESEARCH_TMPDIR/cursor-research-arch-output.txt" "$RESEARCH_TMPDIR/cursor-research-edge-output.txt")
[[ "$codex_available" == true ]] && COLLECT_ARGS+=("$RESEARCH_TMPDIR/codex-research-ext-output.txt" "$RESEARCH_TMPDIR/codex-research-sec-output.txt")
```

Same zero-externals behavior as standard: if both `cursor_available` and `codex_available` are false (`COLLECT_ARGS` is empty), skip `collect-reviewer-results.sh` entirely and proceed to Step 1.4 with the 5 Claude outputs (inline + 4 fallback subagents).

Otherwise, invoke `collect-reviewer-results.sh` with the launched paths:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/collect-reviewer-results.sh --timeout 1860 "${COLLECT_ARGS[@]}"
```

`collect-reviewer-results.sh` derives the tool from each output filename's basename (`*cursor*` / `*codex*`); the chosen filenames satisfy that heuristic unambiguously. **Runtime-timeout replacement** is per-tool, not per-slot — if any one Cursor or Codex lane reports `STATUS != OK`, flip the corresponding session-wide flag (per `external-reviewers.md`) and launch matching Claude subagent fallback(s) for ALL of that tool's slots that did not already produce `OK` output. The 5-lane invariant holds at synthesis time.

### Update lane-status.txt (RESEARCH_* slice only)

`RESEARCH_SCALE=quick` skips this update entirely — quick mode has no external lanes to attribute. SKILL.md Step 0b initialized `lane-status.txt` only when `RESEARCH_SCALE != quick`; if quick mode entered, the file does not exist and Step 3 emits a literal "1 agent (Claude inline only — single-lane confidence)" header without consulting it.

For `RESEARCH_SCALE=standard` and `RESEARCH_SCALE=deep`: after Runtime Timeout Fallback determinations are made, surgically update only the `RESEARCH_*` slice of `$RESEARCH_TMPDIR/lane-status.txt`. The `VALIDATION_*` keys must be preserved verbatim — Step 0b initialized them and Step 2 (validation-phase.md) owns subsequent updates. Do NOT rewrite the full file. In deep mode, `RESEARCH_CURSOR_*` reflects the per-tool aggregate across both Cursor slots (any one Cursor slot with `STATUS != OK` flips the session-wide flag and is reflected here as `fallback_runtime_*`); same for `RESEARCH_CODEX_*` across both Codex slots.

For each Cursor/Codex lane with `STATUS != OK`, derive the new token + reason:
- `STATUS=TIMED_OUT` or `SENTINEL_TIMEOUT` → token `fallback_runtime_timeout`, reason empty
- `STATUS=FAILED` or `EMPTY_OUTPUT` → token `fallback_runtime_failed`, reason = sanitized `FAILURE_REASON` (strip `=` and `|`, collapse whitespace, trim, truncate to 80 chars)

If both Cursor and Codex lanes returned `STATUS=OK` (or were never launched because pre-launch fallback already applied), no update is needed — the `RESEARCH_*` keys from Step 0b remain correct.

Otherwise, perform a read-filter-rewrite via temp + atomic `mv`. All four `RESEARCH_*` keys must be emitted on every rewrite (lanes that returned `OK`, or were never launched, keep the pre-launch token from Step 0b — `ok` / `fallback_binary_missing` / `fallback_probe_failed`).

The append uses a **quoted heredoc** (`<<'EOF'`) so residual shell metacharacters in a substituted reason value are preserved literally rather than expanded — same shell-injection defense as Step 0b. The orchestrator literally substitutes the resolved per-lane status and sanitized reason text into the placeholders below.

```bash
LANE_STATUS_FILE="$RESEARCH_TMPDIR/lane-status.txt"
LANE_STATUS_TMP="$(mktemp "${LANE_STATUS_FILE}.XXXXXX")"
# Preserve VALIDATION_* keys verbatim.
grep -v '^RESEARCH_' "$LANE_STATUS_FILE" > "$LANE_STATUS_TMP"
# Append fresh RESEARCH_* keys with literal substitutions.
cat >> "$LANE_STATUS_TMP" <<'EOF'
RESEARCH_CURSOR_STATUS=<cursor token>
RESEARCH_CURSOR_REASON=<cursor sanitized reason or empty>
RESEARCH_CODEX_STATUS=<codex token>
RESEARCH_CODEX_REASON=<codex sanitized reason or empty>
EOF
mv "$LANE_STATUS_TMP" "$LANE_STATUS_FILE"
```

Token vocabulary is documented in `${CLAUDE_PLUGIN_ROOT}/scripts/render-lane-status.md`.

## 1.4 — Synthesis

Synthesis branches by `RESEARCH_SCALE`. The `### Standard` body is byte-stable for backward compatibility. All three branches MUST write `$RESEARCH_TMPDIR/research-report.txt` so Step 2 (when not skipped) and Step 3 can consume it — quick mode is no exception to this contract.

### Standard (RESEARCH_SCALE=standard, default)

Read all 3 research outputs (Claude inline + Cursor or its fallback + Codex or its fallback). Produce a synthesis that:

1. Identifies where the perspectives **agree** on key findings
2. Identifies where they **diverge** and makes a reasoned assessment on each contested point
3. Notes which insights from each perspective are most significant
4. Highlights **architectural patterns** observed in the codebase (each lane's prompt requires coverage of this dimension)
5. Highlights **risks, constraints, and feasibility** concerns (each lane's prompt requires coverage of this dimension)

Print the synthesis under a `## Research Synthesis` header. Write the synthesis to `$RESEARCH_TMPDIR/research-report.txt` via Bash so it can be used by Step 2. The file should contain:
- The original research question
- The branch and commit being researched
- The synthesized findings

### Quick (RESEARCH_SCALE=quick)

Read the single Claude inline research output. Produce a single-lane synthesis under a `## Research Synthesis` header that explicitly opens with a "**Single-lane confidence — no validation pass.**" disclaimer (one short sentence noting that the result reflects one perspective and was not cross-checked by a multi-lane synthesis or a validation panel). Then summarize the inline findings: key observations, relevant files/modules/areas and architectural patterns, and risks / constraints / feasibility concerns.

Write `$RESEARCH_TMPDIR/research-report.txt` with the same content (research question, branch + commit, single-lane synthesis with disclaimer). The Step 1.4 contract is preserved — the report file MUST exist so Step 3 can render it, even though Step 2 is skipped.

### Deep (RESEARCH_SCALE=deep)

Read all 5 research outputs (Claude inline running baseline `RESEARCH_PROMPT` + 4 angle lanes — `Cursor-Arch` running `RESEARCH_PROMPT_ARCH`, `Cursor-Edge` running `RESEARCH_PROMPT_EDGE`, `Codex-Ext` running `RESEARCH_PROMPT_EXT`, `Codex-Sec` running `RESEARCH_PROMPT_SEC`, or their respective Claude subagent fallbacks). Produce a synthesis under a `## Research Synthesis` header that:

1. Explicitly **names each of the four diversified angles by name** ("architecture & data flow", "edge cases & failure modes", "external comparisons", "security & threat surface") in the synthesis prose, summarizing the most significant finding from each angle so the operator can see the angles were genuinely covered.
2. Identifies where the 5 perspectives **agree** on key findings (treat the four angle lanes as complementary, not redundant — convergence across angle boundaries is the strongest signal).
3. Identifies where they **diverge** and makes a reasoned assessment on each contested point — note when divergence is angle-driven (a security finding flagged only by `Codex-Sec` is expected, not contested) vs. genuinely contested.
4. Notes which insights from each perspective are most significant.
5. Highlights **architectural patterns** observed in the codebase (`Cursor-Arch` is the primary source but Claude inline and other angles may contribute).
6. Highlights **risks, constraints, and feasibility** concerns (`Cursor-Edge` and `Codex-Sec` are the primary sources for failure-mode and security risks, respectively).

Write `$RESEARCH_TMPDIR/research-report.txt` with the synthesis (research question, branch + commit, 5-lane synthesis naming the four diversified angles).
