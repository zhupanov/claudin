# Progress Reporting Contract

Shared format rules for step progress output across all larch skills. Each skill keep own **Step Name Registry** (map step numbers to short names) and reference this contract for format.

## Breadcrumb Format

Every progress line follow:

```
{icon} {step_number}: {breadcrumb_path}[ — {payload}]
```

- **`{icon}`**: One of icons below, show line type.
- **`{step_number}`**: Full numeric step designation with any parent prefix (e.g., `1.2a.5` when `/design` step `2a.5` called from `/implement` step `1`).
- **`{breadcrumb_path}`**: Human-readable path root to current step, segments joined by ` | `. Built from `STEP_PATH_PREFIX | step_short_name` when nested, or just `step_short_name` when standalone.
- **`{payload}`**: Optional description, outcome, or reason — appended after ` — `.

## Icon Taxonomy

| Icon | Line type | When to use |
|------|-----------|-------------|
| `🔶` | Step start | Enter new step |
| `✅` | Completion | Step done with info payload |
| `⏩` | Sub-step skip | Optimization or workflow-conditional skip (quick mode, no changes, etc.) |
| `⏭️` | Precondition skip | Whole step skip due to missing precondition (repo unavailable, Slack not configured, merge not set) |
| `⚠` | Warning | Non-fatal issue in step |
| `🔃` | Rebase | Rebase op |
| `⏳` | Intermediate | Progress update in long-running step |
| `⚡` | Quick mode | Special quick-mode announcements |

**Semantic distinction**: `⏩` and `⏭️` separate on purpose. `⏩` mean light skip in normal flow; `⏭️` mean precondition fail that bypass whole major step.

## Step Start Formatting

Step start lines (`🔶`) get special visual treatment so easy to spot:

1. **Separator line**: Print line of 80 `━` chars right before every step start line.
2. **Bold text**: Render whole step start line bold using `**...**` markdown.
3. **Blockquote**: Wrap bold line in markdown blockquote (`>`) for color differ.

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
> **🔶 2: implementation**
```

Only `🔶` step start lines get separator, blockquote, bold. Completion (`✅`), skip (`⏩`/`⏭️`), warning (`⚠`), and other lines do NOT get separators, blockquotes, or bold.

## Elapsed Time

Every line that mark **end** of step or work item must include elapsed time — whether done ok, skipped, failed, or timed out. Apply to: `✅`, `⏩`, `⏭️`, and step-ending `⚠` lines.

**Step-ending `⚠`** mean any `⚠` with step-number prefix (e.g., `⚠ 7a: ...`, `⚠ 14: ...`). Unnumbered bail lines (e.g., `⚠ Rebase onto main failed. Bailing to cleanup.`) not need elapsed time.

### Step progress lines

Append elapsed time in parens at end of line, short form. Timer start when step logically begin (its `🔶` start line, or step entry if no `🔶` line).

```
✅ 2a.5: dialectic — 2 voted, 1 fallback (1m42s)
⏩ 6: checks (2) — skipped, no review changes (1s)
⏭️ 12: CI+merge loop — skipped (--merge not set) (0s)
⚠ 7a: code flow — generation failed, proceeding without diagram (12s)
```

### Compact status tables (`📊` lines)

For reviewer/agent status tables, include elapsed time right after each `✅` and `❌`. Timer for each entry start when that agent/reviewer launched.

Voting-Protocol skills (`/design`, `/review`, `/implement` Phase 3 conflict review) use 3-reviewer composition:

```
📊 Reviewers: | Code: ✅ 2m31s | Codex: ⏳ | Cursor: ✅ 4m12s |
```

Negotiation-Protocol skills `/loop-review` and `/research` both use 3-lane composition (per slice in `/loop-review`; per phase in `/research` — Phase 1 research, Phase 2 validation).

For review-shaped lanes (`/loop-review` Step 3c and `/research` Phase 2 validation), attribution is `Code` / `Codex` / `Cursor`:

```
📊 Reviewers: | Code: ✅ 2m31s | Codex: ⏳ | Cursor: ✅ 4m12s |
```

For `/research` Phase 1 (research not review), table labelled `Agents` and keep slot names:

```
📊 Agents: | Claude: ✅ 2m31s | Cursor: ⏳ | Codex: ✅ 3m5s |
```

When external unavailable in review-shaped panel, single Claude fallback lane appear in its slot (attributed `Code`). When external unavailable in `/research` Phase 1, Claude fallback keep slot name (entry stay labelled `Cursor` or `Codex` on status table because fallback agent is plain research subagent, not `code-reviewer` subagent — fill same research slot).

`⏳` (in-progress) and `⊘` (skipped/unavailable) not include timing.

### Time format

Use shortest form:
- Under 1 min: `45s`
- 1–59 min: `2m31s`
- 1+ hour: `1h3m` (seconds always dropped in hours tier)

Drop zero parts: use `2m` not `2m0s`, use `1h` not `1h0m`.

## `--step-prefix` Encoding

When parent skill invoke child skill (e.g., `/implement` → `/design`), it pass step context via `--step-prefix` using this encoding:

```
--step-prefix "NUM_PREFIX::TEXT_PATH"
```

- **`NUM_PREFIX`**: Numeric prefix to prepend to child step numbers (e.g., `"1."` mean child step `2a` become `1.2a`).
- **`TEXT_PATH`**: Human-readable breadcrumb segment(s) from parent (e.g., `"design plan"`).
- **Delimiter**: Split on first `::` to separate numeric from text parts.
- **Backward compat**: If `::` absent, treat whole value as numeric-only prefix. Text path default empty — breadcrumbs show only leaf step name.

### Parsing in child skills

Child skills parse `--step-prefix` into two mental vars:

- `STEP_NUM_PREFIX`: Everything before first `::` (or whole value if `::` absent).
- `STEP_PATH_PREFIX`: Everything after first `::` (or empty if `::` absent).

When output step:

- **Step number**: `{STEP_NUM_PREFIX}{local_step_number}` (e.g., `1.` + `2a.5` = `1.2a.5`)
- **Breadcrumb path**: If `STEP_PATH_PREFIX` non-empty: `{STEP_PATH_PREFIX} | {step_short_name}`. Else: just `{step_short_name}`.

### Examples

Standalone `/design` (no `--step-prefix`):
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
> **🔶 2a: sketches**
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
> **🔶 2a.5: dialectic**
✅ 2a.5: dialectic — 2 voted, 1 fallback (1m42s)
```

`/design` called from `/implement` with `--step-prefix "1.::design plan"`:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
> **🔶 1.2a: design plan | sketches**
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
> **🔶 1.2a.5: design plan | dialectic**
✅ 1.2a.5: design plan | dialectic — 2 voted, 1 fallback (1m42s)
```

`/review` called from `/implement` with `--step-prefix "5.::code review"`:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
> **🔶 5.2: code review | launch reviewers**
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
> **🔶 5.3: code review | review cycle**
```

## Section headers and structured output

Do NOT prefix section headers (e.g., `## Implementation Plan`), structured output headers, artifact labels, or compact reviewer status tables with breadcrumb format. Breadcrumbs apply only to progress status lines.
