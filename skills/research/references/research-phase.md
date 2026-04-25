# Research Phase Reference

**Consumer**: `/research` Step 1 — loaded via the `MANDATORY — READ ENTIRE FILE` directive at Step 1 entry in SKILL.md.

**Contract**: 3-lane research invariant (Claude inline + Cursor + Codex, with Claude subagent fallbacks preserving the 3-lane count when an external tool is unavailable). Owns the spawn-order rule, the external-evidence trigger detector and the conditional `RESEARCH_PROMPT` literals (one per `external_evidence_mode` value; identical across the 3 lanes within a run), external launch bash blocks, per-slot fallback rules, the Claude-inline independence rule, Step 1.3 collection with zero-externals branch + runtime-timeout replacement, and Step 1.4 synthesis requirements.

**When to load**: once Step 1 is about to execute. Do NOT load during Step 0, Step 2, Step 3, or Step 4. SKILL.md emits the Step 1 entry breadcrumb and the Step 1 completion print; this file does NOT emit those — it owns body content only.

---

**IMPORTANT: The collaborative research phase MUST ALWAYS run with 3 agents (using Claude subagent fallbacks when an external tool is unavailable). Never skip or abbreviate this phase regardless of how simple the research question appears. Multiple independent perspectives surface insights that a single agent would miss.**

A diverge-then-converge phase where 3 agents independently explore the codebase under a single uniform brief before synthesizing findings. Diversity comes from model-family heterogeneity (Claude + Cursor's backing model + Codex's backing model), not from differentiated per-lane personalities.

The 3 research agents:

1. **Claude (inline)** — the orchestrating agent's own research, run with the shared `RESEARCH_PROMPT` below.
2. **Cursor** (if available) — or a **Claude subagent** fallback via the Agent tool, running the same `RESEARCH_PROMPT`.
3. **Codex** (if available) — or a **Claude subagent** fallback via the Agent tool, running the same `RESEARCH_PROMPT`.

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

**Cursor web-tool asymmetry**: Cursor's `cursor agent` runtime does not expose `WebSearch` / `WebFetch` as named tools the way Claude does. When `external_evidence_mode=true`, the prompt invitation is honored directly by the Codex and Claude lanes (which carry web tools); the Cursor lane falls back to whatever web access its underlying model provides via the prompt — typically none in `--full-auto` mode. The 3-lane invariant holds at the prompt-text level (all three lanes receive the identical stanza), but external-evidence yield is realized primarily through Codex + Claude-inline. Step 1.4 synthesis should treat a Cursor lane that returned no URL citations under `external_evidence_mode=true` as an expected limitation of that lane (not as substantive disagreement with the other two), so the agree/diverge analysis does not over-weight an empty Cursor external thread.

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

## 1.3 — Wait and Validate Research Outputs

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

### Update lane-status.txt (RESEARCH_* slice only)

After Runtime Timeout Fallback determinations are made, surgically update only the `RESEARCH_*` slice of `$RESEARCH_TMPDIR/lane-status.txt`. The `VALIDATION_*` keys must be preserved verbatim — Step 0b initialized them and Step 2 (validation-phase.md) owns subsequent updates. Do NOT rewrite the full file.

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
