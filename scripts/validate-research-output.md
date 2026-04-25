# scripts/validate-research-output.sh — contract

`scripts/validate-research-output.sh` is the substantive-content validator invoked by `scripts/collect-reviewer-results.sh --substantive-validation` after the existing non-empty + retry path settles a successful output. Phase 3 of umbrella issue #413 (closes #416, #447). Promotes the documented "caller's responsibility" check (`skills/research/references/research-phase.md`) into a deterministic gate. Substantive = body word count >= `--min-words` (default 200, fenced-code-block interiors excluded) AND (when `--require-citations` is on, the default) at least one provenance marker (file or `file:line` with a recognized extension, including leading-dot hidden files with a basename; extensionless `Makefile`/`Dockerfile`/`GNUmakefile`; fenced code block with >= 1 non-blank content line; URL). Exit 0 on success; non-zero exits emit a single-line diagnostic on stdout — 2 (body thin), 3 (no marker), 4 (file missing). Tilde-fence variants (`~~~`), length-mismatched fences, and adversarial padding are documented limitations. `scripts/test-validate-research-output.sh` is its regression test, wired into `make lint` via the `test-validate-research-output` Makefile target. `scripts/collect-reviewer-results.sh` translates a non-zero exit into `STATUS=NOT_SUBSTANTIVE` with `HEALTHY=false` and the validator's diagnostic in `FAILURE_REASON` (sanitized at the collector boundary). Edit-in-sync rule: changes to the marker regex set, the fence-stripping word-count rule, or the exit-code numbering must update this contract, the script header (which feeds `--help`), and the regression test in lockstep.

## Probe 1 — recognized extensions and trailing-boundary rule (#447)

The recognized extension set (canonical; same list duplicated in the script header so `--help` stays self-contained):

`c`, `cc`, `cfg`, `cjs`, `cpp`, `cs`, `css`, `csv`, `dart`, `env`, `go`, `gradle`, `groovy`, `h`, `hpp`, `htm`, `html`, `java`, `js`, `json`, `jsx`, `kt`, `lock`, `lua`, `m`, `md`, `mjs`, `mk`, `mm`, `php`, `pl`, `proto`, `py`, `r`, `rb`, `rs`, `sass`, `scala`, `scss`, `sh`, `sql`, `swift`, `toml`, `ts`, `tsv`, `tsx`, `txt`, `vue`, `xml`, `yaml`, `yml`.

Inside the regex alternation these are ordered **longest-first within each prefix-conflict family** (`cc|cfg|cjs|cpp|css|csv|cs|c`, `html|htm|hpp|h`, `json|jsx|js`, `mjs|mk|mm|md|m`, `rb|rs|r`, `tsx|tsv|ts`) so `grep -E` on BSD/macOS does not need to backtrack through alternation to satisfy the trailing-boundary constraint. Non-conflicting families are ordered for readability rather than strict alphabetical sort — only within-family ordering (where one extension is a strict prefix of another) is correctness-relevant.

A matched extension token must be followed by one of:

1. End-of-line, OR
2. The line-reference suffix `:[0-9]+(-[0-9]+)?` followed by end-of-line OR a character outside `[A-Za-z0-9_:/-]`, OR
3. A character outside `[A-Za-z0-9_:/-]` (i.e., not alnum, underscore, dash, `:`, or `/`).

This rejects:
- Alphanumeric junk after the extension: `file.mdjunk:42` — `j` is alnum, fails the boundary. (Primary #447 bypass class.)
- Bare-`:`-then-non-digits bypass: `file.md:garbage` — the `:[0-9]+` group does not match (no digits), and bare `:` is excluded from the boundary alphabet, so the boundary check on `:` fails.
- Slash-suffix bypass: `file.md/child` — `/` is excluded from the boundary alphabet.

Boundary characters `.`, `,`, `(`, `)`, space, `;`, etc. are explicitly accepted, so common real-world citation forms continue to match: sentence-ending periods (`See foo.sh.`), comma-separated prose (`See foo.md, then ...`), and compound-extension files (`Cargo.lock.bak`, `bundle.js.map`) that match by substring evidence on the inner extension.

### Documented limitations of probe 1

- **Bare hidden-file forms without a basename** like `.env:7`, `.gitignore:5`, `.npmrc:3` are NOT matched — probe 1's path-stem regex requires `[A-Za-z_]` before the final `\.`. Citations of the form `app.env:5`, `Cargo.lock:7`, `package-lock.json:5` (where the `.env`/`.lock` is preceded by a basename) DO match. Operators citing bare hidden files should add prose context that satisfies probes 2-4, or open a follow-up issue to widen probe 1.
- **Underscore-glued prose** like `file.md_for_details` is NOT matched — `_` is in the boundary's excluded set per the #447 issue text. This is an unusual prose form (English does not glue identifiers with underscores to subsequent words); accepted as a known limitation.
- **Generic-English false positives for short extensions**: extensions like `lock`, `env`, `txt`, `r`, `m`, `c`, `h` may match prose tokens whose tail happens to coincide with an extension form (e.g., `the spin.lock primitive`). This is an inherent trade-off of a syntax-only sanity gate; reviewers should rely on probes 2-4 for stronger provenance evidence when prose is dense.
