# Review Agents

Larch uses a single unified Claude reviewer archetype — **Code Reviewer** — that provides combined coverage during plan review and code review. The archetype walks four explicit focus areas (code quality, risk/integration, correctness, architecture) and tags each finding with its focus area, so comprehensive coverage is preserved in one prompt.

## The Code Reviewer Archetype

**Focus**: Unified coverage across code quality, risk/integration, correctness, and architecture.

**Checklist**:

### 1. Code Quality
- Logical flaws, incorrect conditions, wrong variable usage, broken control flow
- Code duplication — searches the codebase for existing implementations that overlap
- Missing or insufficient test coverage — flags untested code paths and notes when TDD should have been used
- Breaking changes to existing callers, CLI commands, API contracts
- Style consistency with existing patterns and naming conventions

### 2. Risk / Integration
- Breaking changes to callers, API contracts, downstream consumers
- Cache invalidation issues
- Import side effects (init functions, global state, circular dependencies)
- Thread safety (concurrent map access, channel misuse)
- Deployment risks (schema migrations, config changes, incompatible wire formats)
- Regression risk to existing tests
- Module interaction (tracing callers of modified functions)
- CI constraints (test globs, workflow YAML syntax)

### 3. Correctness
- Logic errors (incorrect booleans, inverted checks, wrong operators)
- Off-by-one errors (loop bounds, slice indices, pagination limits)
- Null/nil/None handling (missing nil checks, zero-value assumptions)
- Type mismatches (wrong assertions, implicit conversions)
- Incorrect return values (swapped returns, missing early returns)
- Race conditions (shared state without synchronization, goroutine leaks)
- Exception/error paths (swallowed errors, panic recovery gaps)
- Math errors (integer overflow, division by zero, floating-point comparison)

### 4. Architecture
- **Separation of Concerns**: Single responsibility per module, business logic not mixed with I/O
- **Contract Boundaries**: Explicit cross-repo contracts, consistent types across layers, peer field consistency
- **Invariants**: Edge case validation at boundaries, loud failures over silent defaults, proper ordering of operations
- **Semantic Boundaries**: Domain logic in the right layer, correct import direction, explicit data shapes at system boundaries

**Finding tagging**: Every finding must be tagged with its focus area (`code-quality` / `risk-integration` / `correctness` / `architecture`) so downstream readers can identify the lens each issue came from.

**Quality gate**: For each in-scope finding, verify: (a) Is the proposed change justified by a concrete need? (b) Is it proportionate to the issue? Out-of-scope observations are exempt.

**Model**: Sonnet (default); effort inherits from session. The Claude subagent is deliberately not bumped to opus/max; max reasoning effort is applied only to the external Codex reviewer via `codex_effort` plugin userConfig / `LARCH_CODEX_EFFORT` env var (default `high`).

## Persistent Agent vs. Inline Template

There are two related but distinct mechanisms for invoking this archetype:

**Persistent agent definition** (`agents/code-reviewer.md`) — Standalone agent file with frontmatter specifying name, description, model, and allowed tools. Invoked via the Agent tool with `subagent_type: code-reviewer`.

**Inline reviewer template** (`skills/shared/reviewer-templates.md`) — Parameterized prompt template that skills fill in with context-specific variables (`{REVIEW_TARGET}`, `{CONTEXT_BLOCK}`, `{OUTPUT_INSTRUCTION}`). In the Voting-Protocol skills (`/design`, `/review`, `/implement` Phase 3 conflict review), external reviewers (Codex, Cursor) receive an inline rendering of the unified four-focus-area checklist with mandatory focus-area tagging. In the Negotiation-Protocol skills (`/loop-review`, `/research`), external reviewer prompts retain their pre-existing "4 review perspectives" wording and do not currently enforce focus-area tagging — those prompts are out of scope for the unified consolidation.

The persistent agent and inline template are derived from the same source and kept in sync (per the `AGENTS.md` contract — both must change together).

## Output Format

The Code Reviewer archetype produces **dual-list output**:

1. **In-Scope Findings** — Issues that should be fixed in this PR, with specific file/line references, focus-area tag, and suggested fixes
2. **Out-of-Scope Observations** — Pre-existing issues or concerns beyond the PR's scope, surfaced for future attention

External reviewers (Codex, Cursor) produce single-list output — their entire output is treated as in-scope findings.

## Usage Across Skills

| Skill | Phase | Reviewers Used |
|---|---|---|
| `/design` | Plan review | 1 Claude Code Reviewer subagent + 1 Codex + 1 Cursor (3 total, Voting Protocol) |
| `/review` | Code review | 1 Claude Code Reviewer subagent + 1 Codex + 1 Cursor (3 total, Voting Protocol) |
| `/implement` | Phase 3 conflict review | 1 Claude Code Reviewer subagent + 1 Codex + 1 Cursor (3 total) |
| `/implement` (quick mode) | Simplified review | 1 Claude Code Reviewer subagent (no external reviewers, no voting) |
| `/loop-review` | Slice review | 2 Claude Code Reviewer subagent lanes (broad + deep perspectives) + 2 Codex (broad + deep) + Cursor (5 total, Negotiation Protocol) |
| `/research` | Validation | 2 Claude Code Reviewer subagent lanes (broad + deep perspectives) + 2 Codex (broad + deep) + Cursor (5 total, Negotiation Protocol) |

**Note A**: `/loop-review` and `/research` retain 5-lane compositions because they use the Negotiation Protocol (per-reviewer independent negotiation), not the Voting Protocol (quorum-based). The two Claude lanes invoke the same unified archetype with per-lane emphasis on code quality/risk-integration (broad) vs correctness/architecture (deep), preserving distinct finding streams under Negotiation semantics.

**Claude fallback for externals**: When Cursor or Codex is unavailable in the 3-reviewer skills, a Claude Code Reviewer subagent is launched in its place so the total reviewer count remains 3.
