# Domain-Specific Review Rules

**Consumer**: `/review` Step 3 entry (loaded unconditionally on every Step 3 entry; no branch-skip guard).

**Contract**: owns the repo-specific review rules layered on top of the generic reviewer templates — settings-ordering rules, scripts/skills-shared genericity rules, and any other domain-specific invariants applied during collect, dedup, voting, and fix application across all of Step 3.

**When to load**: at every Step 3 entry, before 3a collect/dedup runs, so the rules are visible throughout the step (including during the zero-findings short-circuit, where a missed ordering or genericity regression must still be caught). Do NOT load during Steps 0, 1, 2, 4, or 5.

**Binding convention**: single normative source for repo-specific review rules that supplement the generic reviewer templates. The orchestrating agent applies them when evaluating findings and reviewing the diff across all of Step 3 (collect, dedup, voting, fix application). Loaded at Step 3 entry — not at Step 3c — so the rules are visible during 3a's collect/dedup work and during the zero-findings short-circuit (where a missed `.claude/settings.json` ordering or `scripts/`/`skills/shared/` genericity regression must still be caught).

---

These rules supplement the generic reviewer templates. The orchestrating agent applies them when evaluating findings and reviewing the diff, especially during Step 3c (deduplication).

## Settings.json Permissions Ordering

When changes touch `.claude/settings.json`, verify that the `permissions.allow` array remains in **strict ASCII/Unicode code-point order** (equivalent to `LC_ALL=C sort`, Go's `sort.Strings`, or Python's `sorted()`). Entries must be sorted as raw strings without preprocessing or normalization. This means special characters sort by their code-point value (e.g., `$` < `.` < `/` < uppercase letters < `[` < lowercase letters < `~`).

## Skill and Script Genericity

When changes touch files under `scripts/` or `skills/shared/`, verify the changes do not introduce repo-specific content: no repo-specific paths (e.g., `server/`, `cli/`, `myservice`), cluster names (e.g., `prod-1`, `staging-2`), service-specific environment variable names, or hardcoded project references that would break when the file is used in a different repository.

- **Generic directories**: `scripts/`, `skills/shared/` — changes to files here must not introduce repo-specific references.
- **Repo-specific directories**: individual skill-specific script directories (e.g., `skills/implement/scripts/`), and the private `.claude/skills/relevant-checks/` skill — files here are repo-specific by design and exempt from this rule.
