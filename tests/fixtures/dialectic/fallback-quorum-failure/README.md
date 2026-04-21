# fallback-quorum-failure

`debate-2-thesis.txt` skip `<evidence>` tag on purpose — document eligibility-gate fail path. Orchestrator mark D2 `Disposition: fallback-to-synthesis` with `Why fallback: missing_tag`, kick from ballot, no judge vote for D2. Fixture use `skip_debater_validation=true` so smoke test structural check no flag intentional break.
