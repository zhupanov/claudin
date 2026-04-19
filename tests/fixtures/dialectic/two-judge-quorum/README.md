# two-judge-quorum

Codex judge output has `STATUS=ERROR` as its first meaningful line, rendering the whole output ineligible per the protocol (`dialectic-protocol.md` "Eligible" note under Threshold Rules). That leaves cursor + claude as the eligible judges. DECISION_1 exercises the 2-voter unanimous row; DECISION_2 exercises the 2-voter 1-1 tie row (→ `fallback-to-synthesis` with reason `1-1 tie with 2 voters`).
