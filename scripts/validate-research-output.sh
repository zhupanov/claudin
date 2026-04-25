#!/usr/bin/env bash
# validate-research-output.sh — Substantive-content validator for /research outputs.
#
# Reads a single file, applies a fixed set of substantive-content checks, and
# exits 0 if substantive or non-zero with a one-line diagnostic on stdout. The
# intended consumer is `scripts/collect-reviewer-results.sh --substantive-validation`,
# which translates a non-zero exit into a `STATUS=NOT_SUBSTANTIVE` entry with
# `HEALTHY=false`. Phase 3 of umbrella issue #413 (closes #416, #447).
#
# Substantive = ALL of:
#   1. Body word count >= --min-words (default 200), excluding fenced-code-block
#      interiors. The opening and closing fence lines are also excluded.
#   2. (when --require-citations is on, the default) at least one provenance
#      marker, where a marker is any of:
#        - file or file:line: regex match for an extension in the recognized
#          set (#447 broadened from the #416 set):
#          {c, cc, cfg, cjs, cpp, cs, css, csv, dart, env, go, gradle,
#           groovy, h, hpp, htm, html, java, js, json, jsx, kt, lock, lua,
#           m, md, mjs, mk, mm, php, pl, proto, py, r, rb, rs, sass, scala,
#           scss, sh, sql, swift, toml, ts, tsv, tsx, txt, vue, xml, yaml,
#           yml} — permits leading dot for hidden files with a basename
#          (e.g. `.pre-commit-config.yaml`); requires a trailing-token
#          boundary so the extension cannot bleed into adjacent path-token
#          characters (rejects fake citations like `file.mdjunk:42`,
#          `file.md:garbage`, `file.md/child`). Bare hidden-file forms
#          without a basename (e.g. `.env:7`, `.gitignore:5`) are NOT
#          matched and rely on probes 2-4 / contract. Boundary class
#          excludes alnum, `_`, `-`, `:`, `/`; `.` IS a valid boundary so
#          sentence-ending periods (`See foo.sh.`) and compound extensions
#          (`Cargo.lock.bak`) match.  Edit-in-sync: this list is duplicated
#          in `validate-research-output.md` intentionally so `--help`
#          (sed-extracted from this header) stays self-contained; both
#          must be updated together.
#        - extensionless filename: Makefile / Dockerfile / GNUmakefile,
#        - a fenced code block (``` ... ```) with at least one non-blank
#          content line,
#        - a URL (https?://...).
#
# Validation-mode preset (--validation-mode): for use with /research's Step
# 2.4 validation phase, where reviewer outputs are structurally different
# from research-phase prose (they contain the literal `NO_ISSUES_FOUND`
# token on the happy path, or short numbered findings with file:line
# citations). The preset:
#   - accepts a file whose entire trimmed content equals `NO_ISSUES_FOUND`
#     (case-sensitive) as substantive — exit 0 with no further checks,
#   - lowers the default --min-words floor to 30 (a single concise finding
#     comfortably exceeds this, but a junk one-liner does not),
#   - keeps the citation requirement unchanged (validation findings must
#     still cite file:line per the reviewer-template archetype).
# The preset is a defaults override: explicit `--min-words N` and
# `--no-require-citations` flags still take precedence.
#
# Known limitations (defense-in-depth, not authentication):
#   - Tilde-fence variants (~~~ ... ~~~) are NOT recognized; only triple-
#     backtick fences are.
#   - Length-mismatched fences (e.g. open with ```` close with ```) are
#     simplified to "any line beginning with optional whitespace + 3+
#     backticks toggles the fence state". Pathological inputs may exhibit
#     surprising body-word-count behavior.
#   - Adversarial padding: 200 words of repeated nonsense plus one fake
#     `path/file.md:42` will pass both gates. The validator is a deterministic
#     sanity gate, not a quality oracle.
#
# Usage:
#   validate-research-output.sh [--min-words N] [--require-citations|--no-require-citations] [--validation-mode] <file>
#
# Exit codes:
#   0 — substantive (no stdout output)
#   1 — usage error (missing/unknown flag, multiple file arguments)
#   2 — body too thin (word count below --min-words after stripping fenced code)
#   3 — no provenance marker found (only when --require-citations is on)
#   4 — file missing or not readable
#
# Diagnostic format:
#   Exit 2: `body too thin: <count>/<min> words after stripping fenced code`
#   Exit 3: `no provenance marker found`
#   Exit 4: `file missing or not readable: <path>`
#
# Portability: uses `awk` (POSIX) and `grep -E` (BSD + GNU). No `\d`, no
# lookarounds, no `\w` — all character classes are explicit `[...]`.

# No -e: exit codes are meaningful return values that distinguish failure
# modes for the test harness and the collector consumer. Bare `grep -Eq`
# returning 1 (no match) must NOT abort the script.
set -uo pipefail

MIN_WORDS=""
REQUIRE_CITATIONS=true
VALIDATION_MODE=false
INPUT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --min-words)
            MIN_WORDS="${2:?--min-words requires a value}"; shift 2 ;;
        --require-citations)
            REQUIRE_CITATIONS=true; shift ;;
        --no-require-citations)
            REQUIRE_CITATIONS=false; shift ;;
        --validation-mode)
            VALIDATION_MODE=true; shift ;;
        --help)
            sed -n '/^# /,/^[^#]/p' "$0" | head -n 60
            exit 0 ;;
        -*)
            echo "validate-research-output.sh: unknown option: $1" >&2
            exit 1 ;;
        *)
            if [[ -n "$INPUT" ]]; then
                echo "validate-research-output.sh: only one file argument allowed" >&2
                exit 1
            fi
            INPUT="$1"; shift ;;
    esac
done

# Apply --validation-mode defaults: lower min-words floor to 30 (a single
# concise finding suffices) when not explicitly overridden. Citation
# requirement is unchanged by the preset — explicit --no-require-citations
# still wins.
if [[ -z "$MIN_WORDS" ]]; then
    if [[ "$VALIDATION_MODE" == "true" ]]; then
        MIN_WORDS=30
    else
        MIN_WORDS=200
    fi
fi

if [[ -z "$INPUT" ]]; then
    echo "validate-research-output.sh: file argument is required" >&2
    exit 1
fi

if [[ ! -r "$INPUT" ]]; then
    echo "file missing or not readable: $INPUT"
    exit 4
fi

# --- 0. Validation-mode short-circuit: accept the literal NO_ISSUES_FOUND
# token (the explicit "no findings" signal emitted by /research's Step 2.4
# validators per scripts/render-reviewer-prompt.sh) as substantive without
# applying word-count or citation checks. The token must be the entire
# trimmed file content (whitespace-only lines removed top + bottom; tabs and
# trailing whitespace stripped) — partial matches inside larger prose do NOT
# trigger the short-circuit, since a finding that mentions "NO_ISSUES_FOUND"
# in commentary should still be subject to word-count + citation checks.
if [[ "$VALIDATION_MODE" == "true" ]]; then
    # Concatenate non-blank lines after stripping per-line leading and trailing
    # whitespace. If the result equals exactly `NO_ISSUES_FOUND`, the file is
    # the literal token (possibly surrounded by blank lines) and is accepted.
    TRIMMED=$(awk 'NF { gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print }' "$INPUT")
    if [[ "$TRIMMED" == "NO_ISSUES_FOUND" ]]; then
        exit 0
    fi
fi

# --- 1. Body word count, excluding fenced-code-block interiors ---
# awk state machine: every line beginning with optional whitespace + 3+
# backticks toggles `in_fence`; lines inside the fence (and the fence lines
# themselves) are skipped via `next`. NF is summed across body lines.
WORD_COUNT=$(awk '
    /^[[:space:]]*```/ { in_fence = !in_fence; next }
    in_fence { next }
    { words += NF }
    END { print words + 0 }
' "$INPUT")

if [[ "$WORD_COUNT" -lt "$MIN_WORDS" ]]; then
    echo "body too thin: $WORD_COUNT/$MIN_WORDS words after stripping fenced code"
    exit 2
fi

# --- 2. Provenance markers (when --require-citations) ---
if [[ "$REQUIRE_CITATIONS" == "true" ]]; then
    # Probe 1: file path with a known extension (#416 origin, #447 broadened
    # extension set + trailing-boundary rule, longest-first ordering inside
    # prefix-conflict families to avoid backtracking-through-alternation
    # dependence on BSD/macOS grep -E). Boundary `(^|[^A-Za-z0-9])` ensures
    # the match starts at a non-alnum boundary so partial matches mid-word
    # are rejected. Trailing `($|[^A-Za-z0-9_:/-])` requires the extension
    # token to end at end-of-line OR at a character outside the path-token
    # alphabet — alnum/underscore/dash plus `:` and `/`. Excluded `:`
    # forces the `:line[-end]` form to use the explicit `(:[0-9]+(-[0-9]+)?)?`
    # group (which requires digits after `:`) — bare `:garbage` does NOT
    # qualify as a boundary. Excluded `/` rejects `file.md/child`-style
    # bypass attempts. `.` IS a valid trailing boundary so sentence-ending
    # periods (e.g., `See foo.sh.`) and compound-extension forms (e.g.,
    # `file.md.bak`) match — these are real-world citation forms.
    if grep -Eq '(^|[^A-Za-z0-9])\.?[A-Za-z_][A-Za-z0-9_./-]*\.(cc|cfg|cjs|cpp|css|csv|cs|c|dart|env|gradle|groovy|go|html|htm|hpp|h|java|json|jsx|js|kt|lock|lua|mjs|mk|mm|md|m|php|pl|proto|py|rb|rs|r|sass|scala|scss|sh|sql|swift|toml|tsx|tsv|ts|txt|vue|xml|yaml|yml)(:[0-9]+(-[0-9]+)?)?($|[^A-Za-z0-9_:/-])' "$INPUT"; then
        exit 0
    fi

    # Probe 2: extensionless capitalized filenames (Makefile, Dockerfile,
    # GNUmakefile) — common /research provenance citations not covered by
    # probe 1.
    if grep -Eq '(^|[^A-Za-z0-9_])(Makefile|Dockerfile|GNUmakefile)(:[0-9]+(-[0-9]+)?)?' "$INPUT"; then
        exit 0
    fi

    # Probe 3: fenced code block with >= 1 non-blank content line. A fence-
    # only block (``` ... ``` with empty interior) does NOT count.
    HAS_CODE_FENCE=$(awk '
        /^[[:space:]]*```/ { in_fence = !in_fence; next }
        in_fence && NF > 0 { content++ }
        END { print (content > 0) ? 1 : 0 }
    ' "$INPUT")
    if [[ "$HAS_CODE_FENCE" == "1" ]]; then
        exit 0
    fi

    # Probe 4: URL.
    if grep -Eq 'https?://' "$INPUT"; then
        exit 0
    fi

    echo "no provenance marker found"
    exit 3
fi

exit 0
