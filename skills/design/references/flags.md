# Flag Reference

**Consumer**: `/design` argument parsing (loaded before Step 0 via MANDATORY directive adjacent to compact flag table in SKILL.md).

**Binding convention**: This file single normative source for `/design` flag semantics. SKILL.md compact flag table non-normative index — when caller need authoritative validation rule, fallback behavior, or encoding spec for any flag, read this file.

---

- `--auto`: Set mental flag `auto_mode=true`. Default: `auto_mode=false`. When `auto_mode=true`, all interactive question checkpoints (Steps 1c, 1d, 3.5, 3a) skipped — skill run fully autonomous, no user interaction. When `--quick` set in caller and `/design` skipped entirely, `--auto` no effect.
- `--debug`: Set mental flag `debug_mode=true`. Control output verbosity — see Verbosity Control below. Default: `debug_mode=false`.
- `--session-env <path>`: Set `SESSION_ENV_PATH` to given path. File contain already-discovered session values from caller skill (e.g., `/implement`), forwarded to `session-setup.sh` via `--caller-env`. If not provided, `SESSION_ENV_PATH` empty (standalone invocation — full discovery).
- `--step-prefix <prefix>`: Encode both numeric prefix and textual breadcrumb path using `::` delimiter — see `${CLAUDE_PLUGIN_ROOT}/skills/shared/progress-reporting.md` for full encoding spec. Examples: `"1.::design plan"` (numeric `1.`, path `design plan`), `"1."` (numeric only, backward compat). Parse into `STEP_NUM_PREFIX` (before `::`) and `STEP_PATH_PREFIX` (after `::`, or empty if `::` absent). Default: empty (standalone numbering). Internal orchestration flag used when `/design` invoked from `/implement`.
- `--branch-info <values>`: Set `branch_info_supplied=true` and parse `IS_MAIN`, `IS_USER_BRANCH`, `USER_PREFIX`, `CURRENT_BRANCH` from space-separated `KEY=VALUE` pairs. All 4 keys required. Values safe for space-splitting (`USER_PREFIX` sanitized by `create-branch.sh`'s `derive_user_prefix()`, `CURRENT_BRANCH` cannot contain spaces). **Validation**: If any of 4 keys missing, print `**⚠ --branch-info is incomplete. Falling back to create-branch.sh --check.**` and run script as fallback. **Fallback**: When `--branch-info` absent (standalone invocation), run `create-branch.sh --check` as usual. Internal orchestration flag used when `/design` invoked from `/implement` to skip redundant branch-state check.
