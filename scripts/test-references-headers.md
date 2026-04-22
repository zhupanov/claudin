# scripts/test-references-headers.sh — contract

`scripts/test-references-headers.sh` is the cross-skill structural regression guard for the progressive-disclosure **reference header triplet** (closes #308). It scans every `skills/*/references/*.md` via flat glob and asserts each file contains the three anchored headers `**Consumer**:`, `**Contract**:`, `**When to load**:` at line start.

**Scope and scan rule**. The glob is flat: `skills/*/references/*.md`. Nested paths such as `skills/<skill>/references/<subdir>/*.md` are NOT scanned. If a future skill introduces a `references/` subtree, the harness will not see those files; a follow-up PR must either flatten the layout or widen the glob (e.g., `globstar` / `find`) and document the change here.

**Header match is anchored**. Each header is matched via `grep -E` against `^\*\*Consumer\*\*:`, `^\*\*Contract\*\*:`, `^\*\*When to load\*\*:`. Anchoring at line-start avoids false-positives when a body paragraph or a code-fenced example mentions one of the triplet tokens without actually declaring it as a section header. This is a deliberate tightening compared to the legacy `grep -Fq` whole-file substring check in the retired `scripts/test-implement-structure.sh` assertion (8).

**Fail-closed on empty glob**. If no `skills/*/references/*.md` files are found, the harness fails rather than silently passing. The guard protects against a layout refactor that renames or moves `references/` directories without updating this harness's scope.

**Ownership split with sibling harnesses**:
- `scripts/test-implement-structure.sh` owns `/implement`-specific topology (top-level headings, MANDATORY ↔ reference binding, CI-parity focus-area enum, the `see Step N below|above` ban). As of #308, it no longer owns the Consumer/Contract/When-to-load triplet; that invariant moved here.
- `scripts/test-research-structure.sh` retains a stricter `/research`-local check that the triplet appears **in the first 20 lines** (opens-with), layered on top of the global presence check this harness enforces. Do not remove the `/research` first-20-lines check in favor of the global presence check — it is a tightening, not a duplicate.

**Wiring**:
- Invoked via `make test-references-headers` target in the root `Makefile`; included in the `test-harnesses` aggregate so `make lint` and CI's `agent-sync`/`test-harnesses` jobs pick it up transitively.
- Added to `agent-lint.toml`'s exclude list (same Makefile-only-reference pattern as other `test-*.sh` harnesses): agent-lint's dead-script rule does not follow Makefile-only references.

**Edit synchronization**:
- Any edit to `skills/*/references/*.md` that would remove or rename one of the three anchored headers must also update that file's header block so the harness continues to pass.
- Adding a new `references/` directory under a new skill (e.g., `skills/<new>/references/foo.md`) requires the triplet headers on all included `.md` files from day one.
- Moving to a nested layout (`references/<subdir>/*.md`) requires widening this harness's scan rule (glob or `find`-based) and updating this contract section.
