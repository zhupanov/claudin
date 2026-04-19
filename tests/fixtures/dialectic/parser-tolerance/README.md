# parser-tolerance

Exercises the Parser tolerance section of `skills/shared/dialectic-protocol.md`:

- **Cursor** uses ASCII hyphen separator on DECISION_1 (protocol allows both em-dash `—` and ASCII `-`).
- **Codex** has a duplicate `DECISION_1` line; the smoke test must keep the first valid and emit a warning (second ignored).
- **Claude** omits the `DECISION_2` line entirely; this is a per-decision abstention (reduces D2's eligible-voter count by 1), NOT a whole-output ineligibility.

D2 ends up with 2 eligible voters (cursor + codex, both THESIS) → unanimous → `voted`.
