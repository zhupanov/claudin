# loop-halt-rate fixture

Throwaway fixture skill used by `scripts/test-loop-improve-skill-halt-rate.sh` (closes #278).

Harness copy `SKILL.md` into per-run scratch git repo at `skills/loop-halt-rate/SKILL.md`, then invoke `/larch:loop-improve-skill loop-halt-rate` headless via `claude -p` under bare-origin provisioned repo with PATH-shimmed `gh`. Fixture skeletal on purpose so `/skill-judge` grade below A — force `/loop-improve-skill` iterate, exercise Step-3.j halt surface harness measure.

Do NOT expand fixture into "good" skill. Harness need deficiency. See `scripts/test-loop-improve-skill-halt-rate.sh` and `scripts/lib-loop-improve-halt-ledger.sh` (`clause_for_last_completed()`) for halt-location taxonomy.
