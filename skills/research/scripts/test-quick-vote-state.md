# test-quick-vote-state.sh — regression harness

**Consumer**: `make test-quick-vote-state` (wired into `test-harnesses` aggregate). Issue #520.

**Contract**: validate `quick-vote-state.sh` round-trip + edge cases:
- Round-trip for each valid `--succeeded` value `{0,1,2,3}`.
- Missing file → defensive default `LANES_SUCCEEDED=0`.
- Out-of-range / garbage / empty content → defensive default `LANES_SUCCEEDED=0`.
- Bad `--succeeded` value → exit non-zero.
- Missing `--dir` → exit non-zero.
- Unknown subcommand → exit non-zero.
- Atomic write leaves no `.tmp` files behind.

**Edit-in-sync**: any change to `quick-vote-state.sh`'s defensive-default semantics, error-exit codes, or atomic-write behavior MUST update the assertions here. Conversely, any test added here that asserts a contract not documented in `quick-vote-state.md` is a contract-doc gap.

**Wiring**: `Makefile` declares `test-quick-vote-state: bash skills/research/scripts/test-quick-vote-state.sh` and includes it in the `test-harnesses` target so `make lint` runs it.
