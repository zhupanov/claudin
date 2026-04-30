# Sketch Launch Choreography

**Consumer**: `/design` Step 2a.2 — external sketch launches (Cursor/Codex) and per-slot Claude fallbacks.

**Contract**: byte-preserved launch shell blocks for the external slots — 8 in regular mode (4 Cursor + 4 Codex, one per personality per tool) or 2 in quick mode (1 Cursor-Generic + 1 Codex-Generic) — the spawn-order rule (externals before Claude General), the `run_in_background: true` + `timeout: 1260000` requirements, the per-slot Claude fallback rules, and the Claude General sketch independence rule. Token bodies (`<ARCH_PROMPT>` etc.) are resolved from the companion `references/sketch-prompts.md`, not here. Sketch-phase collection (`collect-agent-results.sh` for Step 2a.3) is NOT defined here — that invocation stays single-source in SKILL.md.

**When to load**: at Step 2a.2 entry, AFTER `references/sketch-prompts.md` has been loaded (so the placeholder tokens are resolvable). Do NOT load during Steps 0, 1, 2a.3, 2a.4, 2a.5, 2b, 3, 3.5, 3b, 4, or 5.

**Binding convention**: single normative source for the external-slot launch shell blocks (8 regular + 2 quick), the spawn-order rule, the per-slot `run_in_background: true` / `timeout: 1260000` requirements, the per-slot Claude fallback notes, and the Claude General sketch independence rule. Token substitution placeholders (`<ARCH_PROMPT>`, `<EDGE_PROMPT>`, `<INNOVATION_PROMPT>`, `<PRAGMATIC_PROMPT>`, `<GENERIC_PROMPT>`) are resolved from `references/sketch-prompts.md`, which the caller loads first. Sketch-phase collection is NOT defined here — the `collect-agent-results.sh` invocation for Step 2a.3 remains single-source in SKILL.md.

---

**Critical sequencing**: You MUST launch all external sketch Bash tool calls (with `run_in_background: true`) AND any Claude subagent fallback sketches BEFORE producing your own inline sketch. External reviewers take significantly longer than Claude — launching them first maximizes parallelism.

**Personality prompts**: the four personality prompts and the generic prompt are shared across external slots (Cursor/Codex) and Claude fallbacks (Agent tool). Token bodies are defined in `references/sketch-prompts.md` (loaded separately via the companion MANDATORY directive at Step 2a.2). For Claude fallback Agent-tool invocations, drop the "Work at your maximum reasoning effort level" trailing suffix — Claude uses session-default effort.

## Regular Mode (`quick_mode=false`)

**Spawn order**: all 4 Cursor slots first (slowest), then all 4 Codex slots, then any Claude subagent fallbacks, then your own inline sketch (fastest). Issue all Bash and Agent tool calls in a single message.

**Cursor — Architecture/Standards** (if `cursor_available`):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/run-external-agent.sh --tool cursor --output "$DESIGN_TMPDIR/cursor-sketch-arch-output.txt" --timeout 1200 --capture-stdout -- \
  cursor agent -p --force --trust $("${CLAUDE_PLUGIN_ROOT}/scripts/agent-model-args.sh" --tool cursor --with-effort) --workspace "$PWD" \
    "$("${CLAUDE_PLUGIN_ROOT}/scripts/cursor-wrap-prompt.sh" "<ARCH_PROMPT>")"
```

Use `run_in_background: true` and `timeout: 1260000` on the Bash tool call.

**Cursor — Architecture/Standards fallback** (if `cursor_available` is false): Launch a Claude subagent via the Agent tool with `<ARCH_PROMPT>` (drop the "Work at your maximum reasoning effort level" suffix — Claude uses session-default effort).

**Cursor — Edge-cases/Failure-modes** (if `cursor_available`):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/run-external-agent.sh --tool cursor --output "$DESIGN_TMPDIR/cursor-sketch-edge-output.txt" --timeout 1200 --capture-stdout -- \
  cursor agent -p --force --trust $("${CLAUDE_PLUGIN_ROOT}/scripts/agent-model-args.sh" --tool cursor --with-effort) --workspace "$PWD" \
    "$("${CLAUDE_PLUGIN_ROOT}/scripts/cursor-wrap-prompt.sh" "<EDGE_PROMPT>")"
```

Use `run_in_background: true` and `timeout: 1260000` on the Bash tool call.

**Cursor — Edge-cases/Failure-modes fallback** (if `cursor_available` is false): Claude subagent with `<EDGE_PROMPT>` (effort suffix dropped).

**Cursor — Innovation/Exploration** (if `cursor_available`):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/run-external-agent.sh --tool cursor --output "$DESIGN_TMPDIR/cursor-sketch-innovation-output.txt" --timeout 1200 --capture-stdout -- \
  cursor agent -p --force --trust $("${CLAUDE_PLUGIN_ROOT}/scripts/agent-model-args.sh" --tool cursor --with-effort) --workspace "$PWD" \
    "$("${CLAUDE_PLUGIN_ROOT}/scripts/cursor-wrap-prompt.sh" "<INNOVATION_PROMPT>")"
```

Use `run_in_background: true` and `timeout: 1260000` on the Bash tool call.

**Cursor — Innovation/Exploration fallback** (if `cursor_available` is false): Claude subagent with `<INNOVATION_PROMPT>` (effort suffix dropped).

**Cursor — Pragmatism/Safety** (if `cursor_available`):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/run-external-agent.sh --tool cursor --output "$DESIGN_TMPDIR/cursor-sketch-pragmatic-output.txt" --timeout 1200 --capture-stdout -- \
  cursor agent -p --force --trust $("${CLAUDE_PLUGIN_ROOT}/scripts/agent-model-args.sh" --tool cursor --with-effort) --workspace "$PWD" \
    "$("${CLAUDE_PLUGIN_ROOT}/scripts/cursor-wrap-prompt.sh" "<PRAGMATIC_PROMPT>")"
```

Use `run_in_background: true` and `timeout: 1260000` on the Bash tool call.

**Cursor — Pragmatism/Safety fallback** (if `cursor_available` is false): Claude subagent with `<PRAGMATIC_PROMPT>` (effort suffix dropped).

**Codex — Architecture/Standards** (if `codex_available`):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/run-external-agent.sh --tool codex --output "$DESIGN_TMPDIR/codex-sketch-arch-output.txt" --timeout 1200 -- \
  codex exec --full-auto -C "$PWD" $("${CLAUDE_PLUGIN_ROOT}/scripts/agent-model-args.sh" --tool codex --with-effort) \
    --output-last-message "$DESIGN_TMPDIR/codex-sketch-arch-output.txt" \
    "<ARCH_PROMPT>"
```

Use `run_in_background: true` and `timeout: 1260000` on the Bash tool call.

**Codex — Architecture/Standards fallback** (if `codex_available` is false): Claude subagent with `<ARCH_PROMPT>` (effort suffix dropped).

**Codex — Edge-cases/Failure-modes** (if `codex_available`):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/run-external-agent.sh --tool codex --output "$DESIGN_TMPDIR/codex-sketch-edge-output.txt" --timeout 1200 -- \
  codex exec --full-auto -C "$PWD" $("${CLAUDE_PLUGIN_ROOT}/scripts/agent-model-args.sh" --tool codex --with-effort) \
    --output-last-message "$DESIGN_TMPDIR/codex-sketch-edge-output.txt" \
    "<EDGE_PROMPT>"
```

Use `run_in_background: true` and `timeout: 1260000` on the Bash tool call.

**Codex — Edge-cases/Failure-modes fallback** (if `codex_available` is false): Claude subagent with `<EDGE_PROMPT>` (effort suffix dropped).

**Codex — Innovation/Exploration** (if `codex_available`):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/run-external-agent.sh --tool codex --output "$DESIGN_TMPDIR/codex-sketch-innovation-output.txt" --timeout 1200 -- \
  codex exec --full-auto -C "$PWD" $("${CLAUDE_PLUGIN_ROOT}/scripts/agent-model-args.sh" --tool codex --with-effort) \
    --output-last-message "$DESIGN_TMPDIR/codex-sketch-innovation-output.txt" \
    "<INNOVATION_PROMPT>"
```

Use `run_in_background: true` and `timeout: 1260000` on the Bash tool call.

**Codex — Innovation/Exploration fallback** (if `codex_available` is false): Claude subagent with `<INNOVATION_PROMPT>` (effort suffix dropped).

**Codex — Pragmatism/Safety** (if `codex_available`):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/run-external-agent.sh --tool codex --output "$DESIGN_TMPDIR/codex-sketch-pragmatic-output.txt" --timeout 1200 -- \
  codex exec --full-auto -C "$PWD" $("${CLAUDE_PLUGIN_ROOT}/scripts/agent-model-args.sh" --tool codex --with-effort) \
    --output-last-message "$DESIGN_TMPDIR/codex-sketch-pragmatic-output.txt" \
    "<PRAGMATIC_PROMPT>"
```

Use `run_in_background: true` and `timeout: 1260000` on the Bash tool call.

**Codex — Pragmatism/Safety fallback** (if `codex_available` is false): Claude subagent with `<PRAGMATIC_PROMPT>` (effort suffix dropped).

## Quick Mode (`quick_mode=true`)

**Spawn order**: Cursor-Generic first (slowest), then Codex-Generic, then any Claude subagent fallbacks, then your own inline sketch (fastest). Issue all Bash and Agent tool calls in a single message.

**Cursor — Generic** (if `cursor_available`):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/run-external-agent.sh --tool cursor --output "$DESIGN_TMPDIR/cursor-sketch-generic-output.txt" --timeout 1200 --capture-stdout -- \
  cursor agent -p --force --trust $("${CLAUDE_PLUGIN_ROOT}/scripts/agent-model-args.sh" --tool cursor --with-effort) --workspace "$PWD" \
    "$("${CLAUDE_PLUGIN_ROOT}/scripts/cursor-wrap-prompt.sh" "<GENERIC_PROMPT>")"
```

Use `run_in_background: true` and `timeout: 1260000` on the Bash tool call.

**Cursor — Generic fallback** (if `cursor_available` is false): Claude subagent with `<GENERIC_PROMPT>` (effort suffix dropped).

**Codex — Generic** (if `codex_available`):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/run-external-agent.sh --tool codex --output "$DESIGN_TMPDIR/codex-sketch-generic-output.txt" --timeout 1200 -- \
  codex exec --full-auto -C "$PWD" $("${CLAUDE_PLUGIN_ROOT}/scripts/agent-model-args.sh" --tool codex --with-effort) \
    --output-last-message "$DESIGN_TMPDIR/codex-sketch-generic-output.txt" \
    "<GENERIC_PROMPT>"
```

Use `run_in_background: true` and `timeout: 1260000` on the Bash tool call.

**Codex — Generic fallback** (if `codex_available` is false): Claude subagent with `<GENERIC_PROMPT>` (effort suffix dropped).

## Claude Sketch (General) — Both Modes

Only after all external and fallback launches are issued, produce your own 2-3 paragraph inline sketch covering: (1) key architectural decisions, (2) files/modules to modify, (3) main tradeoffs. Print it under a `### Claude Sketch` header. Write this **before** reading any external or fallback outputs to preserve independence.
