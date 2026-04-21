# scripts/dialectic-smoke-test.sh — contract

**Dialectic smoke test** — `scripts/dialectic-smoke-test.sh` is an offline fixture-driven regression guard for `/design` Step 2a.5. Fixtures live under `tests/fixtures/dialectic/` (a non-runtime path — everything outside the named runtime surface is supplementary). Run locally with `bash scripts/dialectic-smoke-test.sh` or via `make smoke-dialectic`; CI runs it in the `smoke-dialectic` job. When changing `skills/shared/dialectic-protocol.md` Parser tolerance or Threshold Rules sections, update the smoke test and/or fixtures in the same PR.
