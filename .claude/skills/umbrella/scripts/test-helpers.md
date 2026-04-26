# test-helpers.sh — sibling contract

Regression harness for `helpers.sh check-cycle` (pure logic, no network). Self-contained: creates an ephemeral `mktemp` dir for edge fixtures, runs each assertion, prints a `✅`/`❌` line, exits non-zero on any failure.

**Run manually**: `bash .claude/skills/umbrella/scripts/test-helpers.sh`.

**Wired into `make lint`**: the top-level `Makefile` defines a `test-umbrella-helpers` target that runs this harness; it is a dep of `test-harnesses` (and therefore `lint`), so CI's `test-harnesses` job catches any regression.

**Coverage**:

- empty graph + simple candidate
- self-loop (always cycle)
- 2-cycle from new edge
- independent candidate
- 3-cycle close on a linear chain
- parallel forward edge in a chain (still a DAG)
- diamond cycle close (4→1)
- diamond cross-edge (still a DAG)
- disconnected components
- error paths: missing flags, malformed candidate, non-numeric candidate

**Edit-in-sync**: any change to `helpers.sh check-cycle` semantics OR its stdout grammar (`CYCLE=true|false`) requires a same-PR update to the assertion expectations here.

**Out of scope**: `wire-dag` and `emit-output` subcommands. `wire-dag` requires GitHub API access and is best-effort by design (fail-open when the dependency-API surface is unavailable); a network-mocking harness is filed as a follow-up issue. `emit-output` is a thin awk validator covered indirectly by SKILL.md integration.
