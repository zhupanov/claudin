# Research Adjudication Fixtures

Placeholder directory for `/research --adjudicate` ballot-builder fixtures.

The current offline harness `scripts/test-research-adjudication.sh` generates all its fixture inputs inline via heredocs — no static fixture files live here yet. This directory exists to give the harness a stable home for future static fixtures if the inline set grows beyond what is comfortable to maintain inside the test script.

If a future PR migrates inline fixtures to static files, the convention should mirror `tests/fixtures/dialectic/` (one subdirectory per fixture, `expected.txt` manifest declaring assertions).

See `scripts/test-research-adjudication.md` for the full harness contract and edit-in-sync invariants.
