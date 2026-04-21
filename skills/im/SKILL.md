---
name: im
description: "Use when implementing a feature with auto-merge. Shortcut for /implement --merge."
argument-hint: "<arguments>"
allowed-tools: Skill
---

Auto-gen alias. larch /alias make. Call /implement with preset flags.

## Usage

/im <arguments> same as /implement --merge <arguments>

## Behavior

Call Skill tool:
- Try skill: "implement" first (bare name). No match → try skill: "larch:implement" (full plugin name).
- args: --merge $ARGUMENTS

Made by larch /alias v2.1.3
