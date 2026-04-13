# Progress Reporting Contract

Shared formatting rules for step progress output across all larch skills. Each skill maintains its own **Step Name Registry** (mapping step numbers to short names) and references this contract for formatting.

## Breadcrumb Format

Every progress line follows:

```
{icon} {step_number}: {breadcrumb_path}[ — {payload}]
```

- **`{icon}`**: One of the icons below, indicating the line type.
- **`{step_number}`**: The full numeric step designation including any parent prefix (e.g., `1.2a.5` when `/design` step `2a.5` is called from `/implement` step `1`).
- **`{breadcrumb_path}`**: Human-readable path from root to current step, segments joined by ` | `. Built from `STEP_PATH_PREFIX | step_short_name` when nested, or just `step_short_name` when standalone.
- **`{payload}`**: Optional description, outcome, or reason — appended after ` — `.

## Icon Taxonomy

| Icon | Line type | When to use |
|------|-----------|-------------|
| `▸` | Step start | Entering a new step |
| `✅` | Completion | Step completed with informational payload |
| `⏩` | Sub-step skip | Optimization or workflow-conditional skip (quick mode, no changes, etc.) |
| `⏭️` | Precondition skip | Entire step skipped due to missing precondition (repo unavailable, Slack not configured, merge not set) |
| `⚠` | Warning | Non-fatal issue within a step |
| `🔃` | Rebase | Rebase-related operation |
| `⏳` | Intermediate | Progress update within a long-running step |
| `⚡` | Quick mode | Special quick-mode announcements |

**Semantic distinction**: `⏩` and `⏭️` are intentionally separate. `⏩` indicates a lightweight skip within the normal flow; `⏭️` indicates a precondition failure that causes an entire major step to be bypassed.

## `--step-prefix` Encoding

When a parent skill invokes a child skill (e.g., `/implement` → `/design`), it passes step context via `--step-prefix` using this encoding:

```
--step-prefix "NUM_PREFIX::TEXT_PATH"
```

- **`NUM_PREFIX`**: The numeric prefix to prepend to the child's step numbers (e.g., `"1."` means child step `2a` becomes `1.2a`).
- **`TEXT_PATH`**: The human-readable breadcrumb segment(s) from the parent (e.g., `"design plan"`).
- **Delimiter**: Split on the first `::` to separate numeric from textual parts.
- **Backward compatibility**: If `::` is absent, treat the entire value as a numeric-only prefix. The text path defaults to empty — breadcrumbs show only the leaf step name.

### Parsing in child skills

Child skills parse `--step-prefix` into two mental variables:

- `STEP_NUM_PREFIX`: Everything before the first `::` (or the entire value if `::` absent).
- `STEP_PATH_PREFIX`: Everything after the first `::` (or empty if `::` absent).

When outputting a step:

- **Step number**: `{STEP_NUM_PREFIX}{local_step_number}` (e.g., `1.` + `2a.5` = `1.2a.5`)
- **Breadcrumb path**: If `STEP_PATH_PREFIX` is non-empty: `{STEP_PATH_PREFIX} | {step_short_name}`. Otherwise: just `{step_short_name}`.

### Examples

Standalone `/design` (no `--step-prefix`):
```
▸ 2a: sketches
▸ 2a.5: dialectic
✅ 2a.5: dialectic — 3 decisions resolved
```

`/design` called from `/implement` with `--step-prefix "1.::design plan"`:
```
▸ 1.2a: design plan | sketches
▸ 1.2a.5: design plan | dialectic
✅ 1.2a.5: design plan | dialectic — 3 decisions resolved
```

`/review` called from `/implement` with `--step-prefix "5.::code review"`:
```
▸ 5.2: code review | launch reviewers
▸ 5.3: code review | review cycle
```

## Section headers and structured output

Do NOT prefix section headers (e.g., `## Implementation Plan`), structured output headers, artifact labels, or compact reviewer status tables with breadcrumb formatting. Breadcrumbs apply only to progress status lines.
