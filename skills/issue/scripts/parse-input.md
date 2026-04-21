# skills/issue/scripts/parse-input.sh — contract

`skills/issue/scripts/parse-input.sh` parses `/issue` batch-mode input. `skills/issue/scripts/test-parse-input.sh` is its regression harness, wired into `make lint` via the `test-parse-input` target so parser regressions cannot ship undetected.
