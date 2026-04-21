# parser-tolerance

Exercise Parser tolerance section of `skills/shared/dialectic-protocol.md`:

- **Cursor** use ASCII hyphen separator on DECISION_1 (protocol allow both em-dash `—` and ASCII `-`).
- **Codex** have duplicate `DECISION_1` line; smoke test keep first valid, emit warning (second ignored).
- **Claude** omit `DECISION_2` line entirely; per-decision abstention (reduce D2 eligible-voter count by 1), NOT whole-output ineligibility.

D2 end with 2 eligible voters (cursor + codex, both THESIS) → unanimous → `voted`.
