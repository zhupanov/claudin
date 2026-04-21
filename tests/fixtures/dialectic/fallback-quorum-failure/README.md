# fallback-quorum-failure

`debate-2-thesis.txt` deliberately omits the `<evidence>` tag to document the eligibility-gate failure path. The orchestrator would classify D2 as `Disposition: fallback-to-synthesis` with `Why fallback: missing_tag`, exclude it from the ballot, and no judge votes exist for D2. The fixture uses `skip_debater_validation=true` so the smoke test's structural check does not flag the intentional breakage.
