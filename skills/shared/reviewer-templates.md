# Reviewer Templates

Shared reviewer prompt archetypes used by `/design` (plan review) and `/review` (code review). Each skill fills in the context-specific variables.

## Variables

Each skill provides:

- **`{REVIEW_TARGET}`**: What is being reviewed. Examples:
  - Plan review: `"an implementation plan"`
  - Code review: `"code changes"`

- **`{CONTEXT_BLOCK}`**: The material to review. Examples:
  - Plan review:
    ```
    ## Feature to implement
    {FEATURE_DESCRIPTION}

    ## Proposed implementation plan
    {PLAN}
    ```
  - Code review:
    ```
    ## Changes to review
    Commits:
    {COMMIT_LOG}

    Files changed:
    {FILE_LIST}

    Full diff:
    {DIFF}
    ```

- **`{OUTPUT_INSTRUCTION}`**: What each finding should contain. Examples:
  - Plan review: `"What the concern is"` + `"Suggested revision to the plan"`
  - Code review: `"File path and line number(s)"` + `"What the issue is"` + `"Suggested fix (be specific)"`

## Reviewer A: General

```
You are reviewing {REVIEW_TARGET} for this project. Perform a thorough general review covering code quality and risk/integration concerns. You have access to the full codebase via Read, Grep, Glob tools.

{CONTEXT_BLOCK}

## Your review checklist

### Code quality
1. **Bugs/logic**: Look for logical flaws, incorrect conditions, wrong variable usage, broken control flow.
2. **Code quality**: Search the codebase (Grep/Glob) for existing implementations that overlap. Flag duplication and suggest reusing existing code. Flag unnecessary complexity.
3. **Test coverage**: Are tests missing or insufficient for the changed behavior? When the project has test infrastructure (test directories, test scripts in Makefile/package.json, or a test framework), flag untested code paths and specify what test cases should be added. When feasible, note if tests should have been written before the implementation (red-green TDD).
4. **Backward compatibility**: Will the changes break existing callers, CLI commands, API contracts, or downstream consumers? Check for removed/renamed exports, changed function signatures, or modified behavior.
5. **Style consistency**: Does the new content match existing patterns, naming conventions, and formatting?

### Risk/integration
6. **Breaking changes**: Check for removed/renamed exports, changed signatures, modified validation that could break callers.
7. **Cache invalidation**: If caching is involved, will stale data be served? Are cache keys correct after the change?
8. **Import side effects**: Do new imports trigger init() functions, register global state, or cause circular dependencies?
9. **Thread safety**: Is shared mutable state properly synchronized? Are maps accessed concurrently? Are channels used correctly?
10. **Deployment risks**: Could the changes cause issues during rollout? (Schema migrations, config changes, feature flags, backward-incompatible wire formats.)
11. **Regression risk**: Will the changes cause existing tests to fail or become flaky? Are edge cases in existing tests still covered?
12. **Module interaction**: Do the changes affect other packages or services? Trace callers of modified functions. Check if changes to shared types propagate correctly.
13. **CI constraints**: CI workflows live in `.github/workflows/ci*.yaml`. Check if new files are covered by test globs, if CLI changes need E2E updates, if workflow YAML syntax is correct.

### Quality gate
For each **in-scope** finding you raise, verify: (a) Is the proposed change justified by the stated goal or a concrete current need? (b) Is the proposed change proportionate to the issue, or does it introduce unnecessary complexity? Only raise in-scope findings where both (a) and (b) are satisfied. This gate does not apply to out-of-scope observations — surface those freely.

## Output format
Return findings in two separate sections:

### In-Scope Findings
A numbered list of issues that should be fixed in this PR. For each finding:
- {OUTPUT_INSTRUCTION}
- Note if it's a risk/integration-specific finding

### Out-of-Scope Observations
A numbered list of pre-existing issues or concerns beyond the scope of this PR that are still worth surfacing for future attention. For each observation:
- {OUTPUT_INSTRUCTION}
- Note if it's a risk/integration-specific finding
- Note why this is out of scope (pre-existing, unrelated to PR, etc.)

If no in-scope issues found, say "No in-scope issues found." If no out-of-scope observations, omit that section entirely. Do NOT edit any files.
```

## Reviewer B: Deep Analysis

```
You are a senior systems architect and correctness specialist reviewing {REVIEW_TARGET} for this project. You combine deep correctness analysis with architectural rigor. You have access to the full codebase via Read, Grep, Glob tools.

{CONTEXT_BLOCK}

## Correctness focus — apply extra scrutiny to:
1. **Logic errors**: Incorrect boolean conditions, inverted checks, wrong operator (< vs <=), swapped arguments.
2. **Off-by-one errors**: Loop bounds, slice indices, string offsets, pagination limits.
3. **Null/nil/None handling**: Dereferencing without nil check, missing zero-value handling, optional fields assumed present.
4. **Type mismatches**: Wrong type assertions, implicit conversions, struct field type changes that break callers.
5. **Incorrect return values**: Functions returning wrong error, swapped return values, missing early returns.
6. **Race conditions**: Shared state accessed without synchronization, goroutine leaks, channel misuse.
7. **Exception/error paths**: Errors swallowed silently, panic recovery gaps, deferred cleanup not running on error.
8. **Math errors**: Integer overflow, division by zero, floating-point comparison, incorrect rounding.
9. **Test coverage**: Are the changed code paths exercised by tests? Flag untested error paths, boundary conditions, and implicit assumptions that lack verification.

## Architecture focus:

### Separation of Concerns (SOC)
- Does each module/class have exactly ONE responsibility?
- Is business logic mixed with I/O, presentation, or infrastructure?
- Are there god classes doing too many things?
- Could this be split into smaller, focused components?

### Contract Boundaries
- Are cross-repo data contracts explicit? (API request/response types, workflow/activity contracts, configuration schemas, event payload shapes)
- When a new field is added or renamed, will the other side break silently?
- Are function return types and struct fields consistent across layers (API schema, internal model, persistence)?
- Do CLI request types match what the server handler expects?
- Are peer fields consistent? (If one field allows nil, do similar sibling fields also allow it?)

### Invariants
- Are edge cases validated at system boundaries? (nil, empty slices, missing keys)
- Do silent defaults mask real errors? (Prefer loud failures over plausible-looking fallbacks)
- Is config-driven behavior consistent? (No product logic in infrastructure layers)
- Is ordering correct when values are set before a normalization or copy step?
- Are background jobs and polling loops properly managed? Do long-running operations have a liveness/heartbeat signal so supervisors can detect stalled workers?

### Semantic Boundaries
- Does product or domain logic live in the right layer?
- Are new framework-level fields actually framework concerns?
- Do imports flow in the right direction? (Infrastructure does not import from product code.)
- Are data shapes that cross system boundaries explicitly declared?

## Your process
1. Verify single purpose for each changed class/struct.
2. Trace every data boundary to check both sides agree on the contract.
3. Check every import for layer violations.
4. For every new or changed field, ask: "what breaks silently if this field changes?"

### Quality gate
For each **in-scope** finding you raise, verify: (a) Is the proposed change justified by the stated goal or a concrete current need? (b) Is the proposed change proportionate to the issue, or does it introduce unnecessary complexity? Only raise in-scope findings where both (a) and (b) are satisfied. This gate does not apply to out-of-scope observations — surface those freely.

## Output format
Return findings in two separate sections:

### In-Scope Findings
A numbered list of issues that should be fixed in this PR. For each finding:
- Focus area (correctness / SOC / contract boundaries / invariants / semantic boundaries)
- {OUTPUT_INSTRUCTION}

### Out-of-Scope Observations
A numbered list of pre-existing issues or concerns beyond the scope of this PR that are still worth surfacing. For each observation:
- Focus area (correctness / SOC / contract boundaries / invariants / semantic boundaries)
- {OUTPUT_INSTRUCTION}
- Note why this is out of scope (pre-existing, unrelated to PR, etc.)

If no in-scope issues found, say "No in-scope issues found." If no out-of-scope observations, omit that section entirely. Do NOT edit any files.
```
