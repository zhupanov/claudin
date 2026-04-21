# scripts/redact-secrets.sh — contract

`scripts/redact-secrets.sh` is the outbound secret-scrubbing filter invoked by `skills/issue/scripts/create-one.sh` before `gh issue create`. `scripts/test-redact-secrets.sh` is its regression test, wired into `make lint` via the `test-redact` target. Edit patterns only after reading `SECURITY.md`'s outbound-redaction subsection.
