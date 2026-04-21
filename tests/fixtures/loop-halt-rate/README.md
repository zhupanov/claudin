# loop-halt-rate fixture

Throwaway fixture skill consumed by `scripts/test-loop-improve-skill-halt-rate.sh` (closes #278).

The harness copies `SKILL.md` into a per-run scratch git repo at `skills/loop-halt-rate/SKILL.md`, then invokes `/larch:loop-improve-skill loop-halt-rate` headlessly via `claude -p` under a bare-origin provisioned repo with a PATH-shimmed `gh`. The fixture is deliberately skeletal so `/skill-judge` consistently grades it below A — forcing `/loop-improve-skill` to iterate and exercising the Step-3.j halt surface the harness is measuring.

Do NOT expand this fixture into a "good" skill. The harness depends on its deficiency. See `scripts/test-loop-improve-skill-halt-rate.sh` and `skills/loop-improve-skill/SKILL.md` §#247 for the halt-location taxonomy.
