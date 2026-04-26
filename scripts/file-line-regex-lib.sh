#!/usr/bin/env bash
# shellcheck shell=bash disable=SC2034,SC2016
# file-line-regex-lib.sh — Shared file:line provenance regex library.
#
# Source-safe library: no `set` modifiers, no `exit` calls, no global
# state mutation outside the `__filelinelib_*` namespace. Two consumers
# today (validate-research-output.sh provenance probe; validate-citations.sh
# file:line claim extraction) both need the same regex tier rules. Inlining
# them in two places drifted under #473's tier split — extracting them
# here makes the contract single-sourced.
#
# Source ONLY — never run directly. The script does nothing on its own.
# Consumers source it after their own flag parsing and before they need
# the patterns.
#
# Exposed names (all `__filelinelib_*` prefixed):
#   __filelinelib_long_exts        long-tier extension alternation (relaxed rule)
#   __filelinelib_short_exts       short-tier extension alternation (strict rule)
#   __filelinelib_long_re          long-tier full match regex
#   __filelinelib_short_path_re    short-tier match w/ path-likeness signal
#   __filelinelib_short_line_re    short-tier match w/ trailing :line-ref
#   __filelinelib_extensionless_re Makefile / Dockerfile / GNUmakefile match
#
# Tier rules (mirrored from validate-research-output.sh header for
# documentation continuity):
#
#   LONG tier (relaxed): {cc, cfg, cjs, cpp, cs, css, csv, dart, go, gradle,
#     groovy, hpp, htm, html, java, js, json, jsx, kt, lua, md, mjs, mk,
#     mm, php, pl, proto, py, rb, rs, sass, scala, scss, sh, sql, swift,
#     toml, ts, tsv, tsx, vue, xml, yaml, yml}
#     — bare `foo.go` matches without a path-likeness signal.
#
#   SHORT tier (strict, #473): {c, env, h, lock, m, r, txt}
#     — short extensions overlap with English words / short identifiers
#       (`spin.lock`, `point.r`, `notes.txt`), so the basename MUST carry
#       at least one path-likeness signal: `/`, `_`, `-` somewhere in the
#       stem, OR a trailing `:[0-9]+(-[0-9]+)?` line reference.
#
# Boundary rules: leading `(^|[^A-Za-z0-9])` so the citation cannot fuse
# with adjacent identifier characters; trailing `($|[^A-Za-z0-9_:/-])` so
# `file.mdjunk:42`, `file.md:garbage`, and `file.md/child` are rejected.
# `.` IS a valid trailing boundary so sentence-ending periods (`See foo.sh.`)
# match. Compound extensions: `bundle.js.map` matches via the inner `.js`
# (long tier); `Cargo.lock.bak` does NOT match because the inner `.lock` is
# short-tier and `Cargo` lacks a path-likeness signal.
#
# Hidden files: leading `\.?` allows `.pre-commit-config.yaml`-style basenames.
# Bare hidden-file forms without a basename (`.env:7`, `.gitignore:5`) are
# NOT matched; the pattern requires `[A-Za-z_]` as the first stem character
# AFTER the optional leading dot.
#
# Portability: extended-regex (`grep -E`, `[[ =~ ]]`) compatible. No PCRE,
# no lookarounds, no `\d` / `\w`. Tested under BSD grep (macOS default) and
# GNU grep (Ubuntu CI).

__filelinelib_long_exts='cc|cfg|cjs|cpp|css|csv|cs|dart|gradle|groovy|go|html|htm|hpp|java|json|jsx|js|kt|lua|mjs|mk|mm|md|php|pl|proto|py|rb|rs|sass|scala|scss|sh|sql|swift|toml|tsx|tsv|ts|vue|xml|yaml|yml'
__filelinelib_short_exts='lock|env|txt|c|h|m|r'

__filelinelib_long_re='(^|[^A-Za-z0-9])\.?[A-Za-z_][A-Za-z0-9_./-]*\.('"$__filelinelib_long_exts"')(:[0-9]+(-[0-9]+)?)?($|[^A-Za-z0-9_:/-])'
__filelinelib_short_path_re='(^|[^A-Za-z0-9])\.?[A-Za-z_][A-Za-z0-9_./-]*[/_-][A-Za-z0-9_./-]*\.('"$__filelinelib_short_exts"')(:[0-9]+(-[0-9]+)?)?($|[^A-Za-z0-9_:/-])'
__filelinelib_short_line_re='(^|[^A-Za-z0-9])\.?[A-Za-z_][A-Za-z0-9_./-]*\.('"$__filelinelib_short_exts"'):[0-9]+(-[0-9]+)?($|[^A-Za-z0-9_:/-])'

__filelinelib_extensionless_re='(^|[^A-Za-z0-9_])(Makefile|Dockerfile|GNUmakefile)(:[0-9]+(-[0-9]+)?)?'

# Convenience: combined "any provenance" regex used by validate-research-output.sh
# Probe 1 (long-or-short-path-or-short-line). Equivalent to the explicit
# alternation `<long_re>|<short_path_re>|<short_line_re>` — kept under one name
# so consumers can use a single grep -E without composing locally.
__filelinelib_any_re="$__filelinelib_long_re|$__filelinelib_short_path_re|$__filelinelib_short_line_re"
