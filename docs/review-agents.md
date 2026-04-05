# Review Agents

Claudin2 uses 4 specialized Claude reviewer archetypes that provide different perspectives during plan review and code review. Each archetype has a distinct focus area, ensuring comprehensive coverage across quality dimensions.

## The 4 Archetypes

### Generic Reviewer

**Focus**: Broad code quality coverage — bugs, logic, duplication, test coverage, backward compatibility, and style consistency.

**Checklist**:

- Logical flaws, incorrect conditions, wrong variable usage, broken control flow
- Code duplication — searches the codebase for existing implementations that overlap
- Missing or insufficient test coverage
- Breaking changes to existing callers, CLI commands, API contracts
- Style consistency with existing patterns and naming conventions

**Model**: Sonnet

### Correctness Reviewer

**Focus**: Deep correctness analysis — everything that could cause the code to produce wrong results.

**Specialized checks**:

- Logic errors (incorrect booleans, inverted checks, wrong operators)
- Off-by-one errors (loop bounds, slice indices, pagination limits)
- Null/nil/None handling (missing nil checks, zero-value assumptions)
- Type mismatches (wrong assertions, implicit conversions)
- Incorrect return values (swapped returns, missing early returns)
- Race conditions (shared state without synchronization, goroutine leaks)
- Exception/error paths (swallowed errors, panic recovery gaps)
- Math errors (integer overflow, division by zero, floating-point comparison)

**Model**: Sonnet

### Risk/Integration Reviewer

**Focus**: Breaking changes, side effects, and deployment risks — everything that could go wrong in production.

**Specialized checks**:

- Breaking changes to callers, API contracts, downstream consumers
- Cache invalidation issues
- Import side effects (init functions, global state, circular dependencies)
- Thread safety (concurrent map access, channel misuse)
- Deployment risks (schema migrations, config changes, incompatible wire formats)
- Regression risk to existing tests
- Module interaction (tracing callers of modified functions)
- CI constraints (test globs, workflow YAML syntax)

**Model**: Sonnet

### Architect Reviewer

**Focus**: Structural integrity — separation of concerns, contract boundaries, invariants, and semantic boundaries.

**Specialized checks**:

- **Separation of Concerns**: Single responsibility per module, business logic not mixed with I/O
- **Contract Boundaries**: Explicit cross-repo contracts, consistent types across layers, peer field consistency
- **Invariants**: Edge case validation at boundaries, loud failures over silent defaults, proper ordering of operations
- **Semantic Boundaries**: Domain logic in the right layer, correct import direction, explicit data shapes at system boundaries

**Model**: Opus

## Persistent Agents vs. Inline Templates

There are two related but distinct mechanisms for invoking these archetypes:

**Persistent agent definitions** (`.claude/agents/*.md`) — Standalone agent files with frontmatter specifying name, description, model, and allowed tools. These can be referenced by the Agent tool by name.

**Inline reviewer templates** (`.claude/skills/shared/reviewer-templates.md`) — Parameterized prompt templates that skills fill in with context-specific variables. Skills use these templates to spawn fresh Agent tool invocations with the full review prompt.

The persistent agents and inline templates are derived from the same source and kept in sync.

## Output Format

All 4 reviewer archetypes produce **dual-list output**:

1. **In-Scope Findings** — Issues that should be fixed in this PR, with specific file/line references and suggested fixes
2. **Out-of-Scope Observations** — Pre-existing issues or concerns beyond the PR's scope, surfaced for future attention

External reviewers (Codex, Cursor) produce single-list output — their entire output is treated as in-scope findings.

## Usage Across Skills

| Skill | Phase | Reviewers Used |
|---|---|---|
| `/design` | Plan review | All 4 Claude archetypes + Codex + Cursor (6 total) |
| `/review` | Code review | All 4 Claude archetypes + Codex + Cursor (6 total) |
| `/loop-review` | Slice review | All 4 Claude archetypes + Codex + Cursor (6 total) |
| `/implement` (quick mode) | Simplified review | All 4 Claude archetypes only (no external reviewers) |
