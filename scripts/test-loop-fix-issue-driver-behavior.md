# test-loop-fix-issue-driver-behavior.sh contract

**Purpose**: Tier-2 NDJSON behavior fixture for `skills/loop-fix-issue/scripts/driver.sh`. Companion to `test-loop-fix-issue-driver.sh` (Tier-1 structural) and `test-loop-fix-issue-skill-md.sh` (SKILL.md structural).

**Wired into**: `make lint` (via the `test-harnesses` aggregate) and the explicit `test-loop-fix-issue-driver-behavior` Makefile target.

**Tier-1 vs Tier-2**: structural assertions (Tier-1) cannot catch a regression where the new `--output-format stream-json --verbose` flags are typed correctly but the driver's grep semantics break against the captured NDJSON. This Tier-2 fixture exercises the live driver against canned NDJSON via `LARCH_LOOP_FIX_ISSUE_CLAUDE_OVERRIDE` and asserts that the success-path sentinel match, the Step 0 exit-1 sub-sentinel match, and the defensive-fallback path all behave correctly on actual NDJSON.

## Scenarios

| ID | FIXTURE_SCENARIO | NDJSON shape | Expected driver behavior |
|----|-------------------|--------------|--------------------------|
| 1 | `success` | iter 1 emits `> **🔶 0: find & lock — found and locked #1: stub-test-issue**` inside `assistant`-typed JSON; iter 2 emits `0: find & lock — no approved issues found` | Detects sentinel on iter 1 (continues), then clean-exits on iter 2 with reason `no eligible issues (clean exhaustion)` |
| 2 | `no-eligible` | iter 1 emits `0: find & lock — no approved issues found` immediately | Clean-exits on iter 1 with same reason |
| 3 | `no-sentinel` | iter 1 emits NDJSON with no Step 0 literal | Halts via the defensive-fallback path with reason `Step 0 unknown short-circuit (sentinel mismatch)`; LOOP_TMPDIR retained for inspection |

## Mocking strategy

- **claude**: `LARCH_LOOP_FIX_ISSUE_CLAUDE_OVERRIDE` redirects the driver's `claude -p` invocations at a stub script (`$TEST_TMPDIR/claude-stub.sh`). The stub uses an iteration counter file at `$TEST_TMPDIR/counter-<scenario>` to vary output across iterations within one driver run. The stub drains stdin (the `/fix-issue` prompt) without acting on it, then emits canned NDJSON via `printf` and exits 0.
- **gh**: a stub `gh` shim is placed in `$TEST_TMPDIR/bin` and prepended to `PATH` for the test invocation. The driver's preflight calls `command -v gh` and `gh auth status`; the stub returns success for both. No GitHub auth is required to run the fixture, so `make lint` works in CI environments without a `gh` token.

## Stub argv compatibility

The stub claude script honors the production argv shape that the driver passes (`-p --plugin-dir <path> --output-format stream-json --verbose < <prompt-file> > <out-file> 2> <err-file>`) by accepting and ignoring all arguments. If the driver argv shape regresses to a form the stub cannot tolerate, the test will fail with stub-side behavior visible in the captured driver output — surfacing the mismatch.

## Performance

Each driver iteration completes within ~10s due to the polling kill-loop in `invoke_claude_p_skill` (the watcher polls every 10s; the stub exits in <50ms but the watcher's first `kill -0` check happens after `pid=$!` is set, and the loop sleeps 10s before re-checking). Total fixture wall-clock time is bounded by:
- Scenario 1: 2 iterations × ~10s = ~20s
- Scenario 2: 1 iteration × ~10s = ~10s
- Scenario 3: 1 iteration × ~10s = ~10s

Total: ~40s for the full fixture. Acceptable for `make lint`; not run in inner-loop development.

## Edit-in-sync rules

- **NDJSON shape**: the stub's `emit_text` uses `python3 json.dumps(..., ensure_ascii=False)` to JSON-escape arbitrary text into a `"text":"..."` field. **`ensure_ascii=False` is load-bearing**: it mirrors Anthropic's actual stream-json encoder, which preserves em-dash, ampersand, and other UTF-8 content verbatim in JSON string fields (NOT escaped to `—` / `&`). The driver's literal-substring grep depends on this. Defaulting to `ensure_ascii=True` (Python's default) would produce `find & lock — found and locked` in the JSON line and break the test against the live driver — which would correctly indicate that the *test is non-representative*, NOT that production is broken (since Anthropic's encoder doesn't escape these characters). If a future Anthropic CLI version starts escaping em-dash or ampersand, the production driver would also break; that case must be caught by either updating both the stub AND the driver (e.g., adding decoded-text grep) OR by pinning the Anthropic CLI minimum version. Don't silently flip to `ensure_ascii=True` to "make the test match Python's default" — that would mask the production failure mode rather than catch it.
- **Sentinel literals**: the canned `> **🔶 0: find & lock — found and locked #1: stub-test-issue**` line in scenario 1 must contain the substring `find & lock — found and locked` byte-identical to `driver.sh:SETUP_SENTINEL`. The exit-1 sub-sentinel in scenarios 1 (iter 2) and 2 must contain `0: find & lock — no approved issues found`. Both pin to the same contracts as `test-loop-fix-issue-driver.sh` Assertions H + I.
- **Stub argv compatibility**: when adding new flags to the production `claude -p` invocation in driver.sh's `invoke_claude_p_skill`, verify the stub still ignores them gracefully (it should — bash scripts that don't reference `$@` accept any argv). If a future flag must be acted on by the stub (e.g., switching to a different output format), update the stub in the same PR.
- **`gh` mock surface**: the stub `gh` accepts `auth status` and any other invocation, all returning 0. If the driver ever calls `gh` for non-preflight purposes (it currently does not in the iteration body), expand the stub to handle the new commands.
- **`python3` requirement**: the stub uses `python3` for JSON-escape. `make lint` environments must have `python3` on PATH. Removing this dependency would require either embedding pre-escaped JSON literals (less readable) or a `printf`-based escape that handles all special chars — the python3 path is simpler and reliable.
