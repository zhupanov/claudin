# Voting Panel (round 1 only)

**Consumer**: `/review` Step 3c.1, round-1 branch.

**Contract**: owns the round-1 voting-panel body — three-voter setup with proportionality guidance, ballot file handling, parallel launch ordering, threshold + competition scoring rules, the zero-accepted-findings short-circuit, the OOS artifact write rule, the save-not-accepted-IDs rule, and the rounds-2+ skip-voting rule. The `### 3c.1` heading and the round-1 / rounds-2+ branch selector remain inline in SKILL.md; this file owns the round-1 body content only.

**When to load**: on Step 3c.1's round-1 branch only. Do NOT load on rounds 2+ (Step 3c.1's rounds-2+ branch explicitly skips voting) or on the zero-findings short-circuit (Step 3b's skip-to-Step-4 path).

**Binding convention**: single normative source for the round-1 voting panel mechanics — three-voter setup with proportionality guidance, ballot file handling rule, parallel launch ordering, threshold + competition scoring rules, the zero-accepted-findings short-circuit, the OOS artifact write rule, the save-not-accepted-IDs rule, and the rounds 2+ skip-voting rule. The `### 3c.1` heading and the "round 1" / "rounds 2+" branch selector remain inline in `SKILL.md`; this file owns the body content the round-1 branch executes. Do NOT load on rounds 2+ (Step 3c.1 explicitly skips voting in those rounds) or on the zero-findings short-circuit (Step 3b skip-to-Step-4 path).

---

**In round 1**: Submit both in-scope findings and out-of-scope observations to a 3-agent voting panel per the **Voting Protocol** in `${CLAUDE_PLUGIN_ROOT}/skills/shared/voting-protocol.md`. Include OOS items on the ballot with `[OUT_OF_SCOPE]` prefix per the protocol's OOS section. For code review:

- **Voter 1**: **Claude Code Reviewer subagent** — fresh Agent tool invocation (subagent_type: `larch:code-reviewer`) with the voting prompt. Instruct: `"You are a very scrupulous senior code reviewer on a voting panel. You will vote YES, NO, or EXONERATE on proposed code changes. Be extremely rigorous — only vote YES for findings that identify genuine bugs, logic errors, security issues, or clearly important improvements. Vote EXONERATE if the concern is legitimate but not worth implementing in this PR. Vote NO for trivial style nits, subjective preferences, or speculative concerns. When voting, also consider proportionality: vote EXONERATE (not YES) if the finding's concern is legitimate but the proposed change would introduce more complexity than the issue warrants."`
- **Voter 2**: Codex — via `run-external-reviewer.sh` with the ballot (use `--with-effort` and append "Work at maximum reasoning effort level." to the voter prompt). If `codex_available` is false, launch a Claude subagent voter instead per the Voting Protocol. Instruct similarly as a "very scrupulous senior code reviewer," including the proportionality guidance.
- **Voter 3**: Cursor — via `run-external-reviewer.sh` with the ballot (use `--with-effort` and append "Work at maximum reasoning effort level." to the voter prompt). If `cursor_available` is false, launch a Claude subagent voter instead per the Voting Protocol. Instruct similarly, including the proportionality guidance.

**Ballot file handling**: Use the Write tool (not `cat` with heredoc or Bash) to write the ballot to `$REVIEW_TMPDIR/ballot.txt`. For Codex and Cursor voter prompts, reference the ballot file path (e.g., "Read the ballot from $REVIEW_TMPDIR/ballot.txt") instead of inlining the ballot content. This avoids permission prompts from `cat > file << 'EOF'` or `BALLOT=$(cat file)` patterns.

Launch all available voters **in parallel** (Cursor first, then Codex, then Claude subagent). Wait for external voter sentinels using `wait-for-reviewers.sh` per the Voting Protocol, then parse voter outputs.

**Tally votes**: Apply the threshold rules from the Voting Protocol based on eligible voters per finding (2+ YES with 3 voters, unanimous 2/2 with 2 voters, skip if <2 eligible). Print vote breakdown per finding.

**Competition scoring**: Compute and print the **Reviewer Competition Scoreboard** per the Voting Protocol. Note in the scoreboard that scores apply to round 1 only — round 2+ findings are auto-accepted and do not contribute to scores.

**Zero accepted in-scope findings**: If voting rejects all in-scope findings, print `**ℹ Voting panel rejected all in-scope findings. No changes to implement.**` (In diff mode driven by `/implement`, OOS items accepted for issue filing are processed by `/implement` Step 9a.1; in slice mode with `--create-issues`, `/review` Step 4b files them via `/umbrella` (which delegates batch creation to `/issue` and adds an umbrella tracking issue when ≥2 distinct issues are filed) — see the **Diff mode** / **Slice mode** bullets below.) and skip to **Step 4**.

**OOS items accepted by vote** (2+ YES in round 1): These are accepted for GitHub issue filing, NOT for code implementation.

- **Diff mode** (slice mode NOT active per `SKILL.md` Mutual exclusion + slice-mode activation section — i.e., none of `--slice`, `--slice-file`, or trailing positional text after `--create-issues`): **Only when `SESSION_ENV_PATH` is non-empty**, write accepted OOS items to `$(dirname "$SESSION_ENV_PATH")/oos-accepted-review.md` using the format below. When `SESSION_ENV_PATH` is empty (standalone invocation), skip the OOS artifact write — `/implement` is the only consumer.
- **Slice mode** (slice mode active per `SKILL.md` Mutual exclusion + slice-mode activation section — i.e., any of `--slice`, `--slice-file`, or trailing positional text after `--create-issues`, plus `--create-issues`): **Bypass** the `oos-accepted-review.md` staging artifact entirely. `/review` Step 4b composes a findings batch (in-scope-accepted + OOS-accepted, excluding security-tagged) and invokes `/umbrella --input-file` (which delegates batch creation to `/issue` and adds an umbrella tracking issue when ≥2 distinct issues are filed). The `oos-accepted-review.md` artifact is `/implement`-specific (consumed by Step 9a.1's sentinel-driven OOS pipeline); slice mode runs from `/loop-review`'s driver, which has no equivalent consumer and instead relies on `/review`'s inline `/umbrella` call. **OOS classification anchor in slice mode**: a finding is OOS iff it concerns a file NOT in `$REVIEW_TMPDIR/slice-files.txt` (the canonical file list resolved by /review Step 1 from the verbal slice description). Reviewers may explore via Glob/Grep/Read for context but must anchor in/OOS classification to that list. Both in-scope-accepted AND OOS-accepted findings (2+ YES) are filed via /umbrella when `--create-issues` is set; security-tagged findings (focus-area=security) are routed to `--security-output` instead and NEVER fed to /issue (per SECURITY.md hold-local policy).

In both modes, accepted OOS items use this format:

```markdown
### OOS_N: <short title>
- **Description**: <full description of the observation>
- **Reviewer**: <attribution>
- **Vote tally**: <YES/NO/EXONERATE counts>
- **Phase**: review
```

**Save not-accepted finding IDs**: Record the IDs of findings not accepted by vote in round 1 (whether rejected or exonerated). In rounds 2+, if a Claude-only reviewer re-raises a finding that was not accepted by the round-1 voting panel (same file, same issue), suppress it — do not re-accept a finding the panel already voted down or exonerated. The rounds-2+ skip-voting rule itself lives in `SKILL.md` at the Step 3c.1 branch selector (the file you are reading is loaded only on the round-1 branch, so duplicating that rule here would be dead content and a split-source maintenance risk).
