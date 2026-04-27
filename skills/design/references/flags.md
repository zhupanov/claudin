# Flag Reference

**Consumer**: `/design` argument parsing (loaded before Step 0 via the MANDATORY directive adjacent to the compact flag table in SKILL.md).

**Contract**: single normative source for every `/design` flag — validation rules, default values, fallback behaviors, the `::` delimiter encoding spec for `--step-prefix`, the 4-key requirement for `--branch-info`, the `--auto` / `--quick` interaction rules, and all backward-compat notes. The literal string `All 4 keys are required` is byte-pinned by `scripts/test-design-structure.sh`.

**When to load**: once at the top of `/design` invocation, before Step 0 executes, via the MANDATORY directive adjacent to the compact flag table. Do NOT load mid-flow; flag parsing runs once and the decisions are sticky.

**Binding convention**: This file is the single normative source for `/design` flag semantics. SKILL.md's compact flag table is a non-normative index — when a caller needs the authoritative validation rule, fallback behavior, or encoding spec for any flag, read this file.

---

- `--auto`: Set a mental flag `auto_mode=true`. Default: `auto_mode=false`. When `auto_mode=true`, all interactive question checkpoints (Steps 1c, 1d, and 3.5) are skipped — the skill runs fully autonomously without user interaction. When `--quick` is set in the caller and `/design` is skipped entirely, `--auto` has no effect.
- `--debug`: Set a mental flag `debug_mode=true`. Controls output verbosity — see Verbosity Control in `${CLAUDE_PLUGIN_ROOT}/skills/design/SKILL.md`. Default: `debug_mode=false`.
- `--session-env <path>`: Set `SESSION_ENV_PATH` to the given path. This file contains already-discovered session values from a caller skill (e.g., `/implement`) and will be forwarded to `session-setup.sh` via `--caller-env`. If not provided, `SESSION_ENV_PATH` is empty (standalone invocation — full discovery).
- `--step-prefix <prefix>`: Encodes both numeric prefix and textual breadcrumb path using `::` delimiter — see `${CLAUDE_PLUGIN_ROOT}/skills/shared/progress-reporting.md` for the full encoding spec. Examples: `"1.::design plan"` (numeric `1.`, path `design plan`), `"1."` (numeric only, backward compat). Parse into `STEP_NUM_PREFIX` (before `::`) and `STEP_PATH_PREFIX` (after `::`, or empty if `::` absent). Default: empty (standalone numbering). This is an internal orchestration flag used when `/design` is invoked from `/implement`.
- `--branch-info <values>`: Set `branch_info_supplied=true` and parse `IS_MAIN`, `IS_USER_BRANCH`, `USER_PREFIX`, `CURRENT_BRANCH` from the space-separated `KEY=VALUE` pairs. All 4 keys are required. Values are safe for space-splitting (`USER_PREFIX` is sanitized by `create-branch.sh`'s `derive_user_prefix()`, `CURRENT_BRANCH` cannot contain spaces). **Validation**: If any of the 4 keys is missing, print `**⚠ --branch-info is incomplete. Falling back to create-branch.sh --check.**` and run the script as fallback. **Fallback**: When `--branch-info` is absent (standalone invocation), run `create-branch.sh --check` as usual. This is an internal orchestration flag used when `/design` is invoked from `/implement` to skip the redundant branch-state check.
