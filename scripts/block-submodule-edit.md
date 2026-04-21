# scripts/block-submodule-edit.sh — contract

`scripts/block-submodule-edit.sh` is the PreToolUse hook that denies edits to files inside submodules. `scripts/test-block-submodule-edit.sh` is its regression harness, wired into `make lint` via the `test-block-submodule` target; edits to the hook must stay in sync with the harness.
