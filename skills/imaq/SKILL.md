---
name: imaq
description: "Use when implementing a feature quickly and autonomously with auto-merge. Shortcut for /implement --merge --auto --quick."
argument-hint: "<arguments>"
allowed-tools: Skill
---

Auto-gen alias from larch /alias. Invoke /implement with preset flags.

## Usage

/imaq <arguments> same as /implement --merge --auto --quick <arguments>

## Behavior

Invoke Skill tool:
- Try skill: "implement" first (bare name). No match, try skill: "larch:implement" (full plugin name).
- args: --merge --auto --quick $ARGUMENTS

Made by larch /alias v2.1.3
