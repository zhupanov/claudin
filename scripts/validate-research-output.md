# scripts/validate-research-output.sh — contract

`scripts/validate-research-output.sh` is the substantive-content validator invoked by `scripts/collect-agent-results.sh --substantive-validation` after the existing non-empty + retry path settles a successful output. Phase 3 of umbrella issue #413 (closes #416, #447, #473). Promotes the documented "caller's responsibility" check (`skills/research/references/research-phase.md`) into a deterministic gate. Substantive = body word count >= `--min-words` (default 200, fenced-code-block interiors excluded) AND (when `--require-citations` is on, the default) at least one provenance marker (file or `file:line` with a recognized extension, including leading-dot hidden files with a basename; extensionless `Makefile`/`Dockerfile`/`GNUmakefile`; fenced code block with >= 1 non-blank content line; URL). Probe 1 is split into two extension tiers per #473 (long-tier: relaxed rule; short-tier: strict path-likeness rule — see "Probe 1 short-extension strict-mode rule (#473)" below). Exit 0 on success; non-zero exits emit a single-line diagnostic on stdout — 2 (body thin), 3 (no marker), 4 (file missing or not readable). Tilde-fence variants (`~~~`), length-mismatched fences, and adversarial padding are documented limitations. `scripts/test-validate-research-output.sh` is its regression test, wired into `make lint` via the `test-validate-research-output` Makefile target. `scripts/collect-agent-results.sh` translates a non-zero exit into `STATUS=NOT_SUBSTANTIVE` with `HEALTHY=false` and the validator's diagnostic in `FAILURE_REASON` (sanitized at the collector boundary). Edit-in-sync rule: changes to the marker regex set (long/short tier membership), the fence-stripping word-count rule, or the exit-code numbering must update this contract, the script header (which feeds `--help`), and the regression test in lockstep.

## Probe 1 — recognized extensions and trailing-boundary rule (#447)

> **Forward-compat behavioral change (#473)**: probe 1 is split into a long-tier (relaxed rule, current behavior unchanged) and a short-tier (strict path-likeness rule). Bare short-extension citations like standalone `Cargo.lock`, `main.c`, `app.env`, `foo.h`, `notes.txt` in prose — without `/`, `_`, `-` in the basename and without a `:line-ref` — are NO LONGER markers. Operators citing short-extension files in research outputs MUST add a line ref (e.g., `Cargo.lock:7`) or path segment (e.g., `kernel/spin.lock`, `parser_state.h`, `kernel-mod.h`). See "Probe 1 short-extension strict-mode rule (#473)" subsection below.

The recognized extension set (canonical; same list duplicated in the script header so `--help` stays self-contained), partitioned into LONG and SHORT tiers per #473:

**Long-tier** (relaxed rule — current #447 behavior unchanged): `cc`, `cfg`, `cjs`, `cpp`, `cs`, `css`, `csv`, `dart`, `go`, `gradle`, `groovy`, `hpp`, `htm`, `html`, `java`, `js`, `json`, `jsx`, `kt`, `lua`, `md`, `mjs`, `mk`, `mm`, `php`, `pl`, `proto`, `py`, `rb`, `rs`, `sass`, `scala`, `scss`, `sh`, `sql`, `swift`, `toml`, `ts`, `tsv`, `tsx`, `vue`, `xml`, `yaml`, `yml`.

**Short-tier** (strict path-likeness rule — #473): `c`, `env`, `h`, `lock`, `m`, `r`, `txt`. These extensions overlap with English words / short identifiers (the verified `spin.lock` repro from issue #473), so they require a path-likeness signal — see the dedicated subsection below.

Inside each tier's regex alternation, extensions are ordered **longest-first within each prefix-conflict family** (`cc|cfg|cjs|cpp|css|csv|cs` in long-tier, `html|htm|hpp` in long-tier, `json|jsx|js` in long-tier, `mjs|mk|mm|md` in long-tier, `rb|rs` in long-tier, `tsx|tsv|ts` in long-tier; short-tier has no prefix conflicts since single-char extensions and `lock`/`env`/`txt` share no proper-prefix relationship) so `grep -E` on BSD/macOS does not need to backtrack through alternation to satisfy the trailing-boundary constraint. Non-conflicting families are ordered for readability rather than strict alphabetical sort — only within-family ordering (where one extension is a strict prefix of another) is correctness-relevant.

A matched extension token must be followed by one of:

1. End-of-line, OR
2. The line-reference suffix `:[0-9]+(-[0-9]+)?` followed by end-of-line OR a character outside `[A-Za-z0-9_:/-]`, OR
3. A character outside `[A-Za-z0-9_:/-]` (i.e., not alnum, underscore, dash, `:`, or `/`).

This rejects:
- Alphanumeric junk after the extension: `file.mdjunk:42` — `j` is alnum, fails the boundary. (Primary #447 bypass class.)
- Bare-`:`-then-non-digits bypass: `file.md:garbage` — the `:[0-9]+` group does not match (no digits), and bare `:` is excluded from the boundary alphabet, so the boundary check on `:` fails.
- Slash-suffix bypass: `file.md/child` — `/` is excluded from the boundary alphabet.

Boundary characters `.`, `,`, `(`, `)`, space, `;`, etc. are explicitly accepted, so common real-world citation forms continue to match: sentence-ending periods (`See foo.sh.`), comma-separated prose (`See foo.md, then ...`), and long-tier compound-extension files (`bundle.js.map`) that match by substring evidence on the inner long-tier extension. **Note (#473)**: short-tier compound-extension forms like `Cargo.lock.bak` no longer match probe 1 — the inner `.lock` is short-tier, and `Cargo` lacks any path-likeness signal (`/`, `_`, `-`, or `:line-ref`); the trailing-boundary rule itself is unchanged, so the rejection is caused by the short-tier strict rule, not by the boundary class.

### Documented limitations of probe 1

- **Bare hidden-file forms without a basename** like `.env:7`, `.gitignore:5`, `.npmrc:3` are NOT matched — probe 1's path-stem regex requires `[A-Za-z_]` before the final `\.`. Citations of the form `app.env:5`, `Cargo.lock:7`, `package-lock.json:5` (where the `.env`/`.lock` is preceded by a basename) DO match (the first two via the short-tier strict rule's `:line-ref` qualifier, the third via long-tier since `.json` is long-tier). Operators citing bare hidden files should add prose context that satisfies probes 2-4, or open a follow-up issue to widen probe 1.
- **Underscore-glued prose** like `file.md_for_details` is NOT matched — `_` is in the trailing boundary's excluded set per the #447 issue text. This is an unusual prose form (English does not glue identifiers with underscores to subsequent words); accepted as a known limitation. (Note: `_` IS used in the short-tier strict rule (#473) as a path-likeness signal *inside the stem* — these are two distinct uses of `_` and do not conflict.)
- **Bare short-extension filename mentions in prose** (#473): with the short-tier strict rule in effect, mentions like a sentence containing standalone `Cargo.lock`, `main.c`, `app.env`, `foo.h`, or `notes.txt` (no `/`, `_`, `-` in the stem and no `:line-ref`) are no longer matched. This is the deliberate forward-compat behavioral change of #473 — reviewers should add a line-ref (`Cargo.lock:7`) or path segment (`kernel/spin.lock`, `parser_state.h`, `kernel-mod.h`) when citing short-extension files. Probes 2-4 (Makefile/Dockerfile, fenced code blocks, URLs) provide complementary evidence.
- **Hyphenated or underscored programming-term + short-ext compounds** (e.g., `spin-lock.h`, `spin_lock.h`, `app-config.env`): these match probe 1 via the `-` or `_` path-likeness signal, even when the prose meaning is a programming concept rather than a file path. Accepted as a residual limitation — this prose form is rarer than the bare-token false-positive class that #473 fixes.

## Probe 1 short-extension strict-mode rule (#473)

Probe 1's path-stem regex `[A-Za-z_][A-Za-z0-9_./-]*` is permissive enough that short or generic-English-overlapping extensions (`c`, `h`, `m`, `r`, `env`, `txt`, `lock`) match prose tokens that happen to coincide with file-extension shape. The verified repro from issue #473: 200+ words of prose containing `the spin.lock primitive` passes probe 1 because path-stem `spin` matches, `\.lock` matches, and the trailing space satisfies the boundary rule — even though `spin.lock` is a programming-concept word, not a file path. The same risk applies to `env` (`my.env switch`), `txt` (`raw.txt format`), `m` (`big.m optimization`), and `r`/`c`/`h` in technical prose with abbreviations.

The fix is a tiered probe 1: long-tier extensions retain the original relaxed rule; short-tier extensions require an explicit **path-likeness signal** in addition to the trailing-boundary rule. The trailing-boundary semantics from #447 (alnum/underscore/dash/colon/slash excluded; `.` accepted) are unchanged — the short-tier strict rule is what causes bare prose tokens like `spin.lock` to fail probe 1, not a change in boundary semantics.

### Short-tier set

`c`, `env`, `h`, `lock`, `m`, `r`, `txt`. These are all 1-, 3-, or 4-character extensions that overlap with English words or short identifiers. Long-tier extensions are everything else (`go`, `py`, `md`, `json`, `yaml`, `tsx`, `vue`, etc.) and retain the original #447 relaxed behavior.

### Path-likeness signals

A short-tier citation matches probe 1 when the path-stem satisfies at least one of:

1. Contains `/` somewhere (e.g., `kernel/spin.lock`, `src/main.c`).
2. Contains `_` somewhere (e.g., `parser_state.h`, `foo_bar.c`).
3. Contains `-` somewhere (e.g., `kernel-mod.h`, `notes-2024.txt`).
4. Is followed by a `:line-ref` (`:[0-9]+(-[0-9]+)?`), e.g., `Cargo.lock:7`, `app.env:5`, `foo.m:42`, `bar.h:9-15`.

The first stem character `[A-Za-z_]` may itself be `_`, but the strict-mode `[/_-]` requires a path-likeness signal AFTER the start char (i.e., somewhere mid-stem), so a single underscore as the start char alone does not satisfy the rule.

### Examples

| Citation form | Tier | Verdict | Why |
|---|---|---|---|
| `Cargo.lock:7` | short | ✅ accept | `:line-ref` qualifier |
| `app.env:5` | short | ✅ accept | `:line-ref` qualifier |
| `foo.m:42` | short | ✅ accept | `:line-ref` qualifier |
| `kernel/spin.lock` | short | ✅ accept | `/` in stem |
| `kernel-mod.h` | short | ✅ accept | `-` in stem |
| `parser_state.h` | short | ✅ accept | `_` in stem |
| `package-lock.json:5` | long | ✅ accept | `.json` is long-tier (relaxed rule) |
| `notes.md:42` | long | ✅ accept | `.md` is long-tier (relaxed rule) |
| `Cargo.lock` (bare in prose) | short | ❌ reject | no signal — operator must add line-ref or path |
| `Cargo.lock.bak` (bare in prose) | short | ❌ reject | no signal on inner `.lock` short-ext |
| `main.c` (bare in prose) | short | ❌ reject | no signal — operator must add line-ref or path |
| `the spin.lock primitive` (prose) | short | ❌ reject | no signal — verified false positive now fixed |
| `my.env switch` (prose) | short | ❌ reject | no signal |
| `the big.m optimization` (prose) | short | ❌ reject | no signal |
