# Voting Panel (round 1 only)

**Consumer**: `/review` Step 3c.1, round-1 branch.

**Contract**: owns the round-1 voting-panel body — three-voter setup with proportionality guidance, ballot file handling, parallel launch ordering, threshold + competition scoring rules, the zero-accepted-findings short-circuit, the OOS artifact write rule, the save-not-accepted-IDs rule, and the rounds-2+ skip-voting rule. The `### 3c.1` heading and the round-1 / rounds-2+ branch selector remain inline in SKILL.md; this file owns the round-1 body content only.

**When to load**: on Step 3c.1's round-1 branch only. Do NOT load on rounds 2+ (Step 3c.1's rounds-2+ branch explicitly skips voting) or on the zero-findings short-circuit (Step 3b's skip-to-Step-4 path).

**Binding convention**: single normative source for the round-1 voting panel mechanics — three-voter setup with proportionality guidance, ballot file handling rule, parallel launch ordering, threshold + competition scoring rules, the zero-accepted-findings short-circuit, the OOS artifact write rule, the save-not-accepted-IDs rule, and the rounds 2+ skip-voting rule. The `### 3c.1` heading and the "round 1" / "rounds 2+" branch selector remain inline in `SKILL.md`; this file owns the body content the round-1 branch executes. Do NOT load on rounds 2+ (Step 3c.1 explicitly skips voting in those rounds) or on the zero-findings short-circuit (Step 3b skip-to-Step-4 path).

---

**In round 1**: Submit both in-scope findings and out-of-scope observations to a 3-agent voting panel per the **Voting Protocol** in `${CLAUDE_PLUGIN_ROOT}/skills/shared/voting-protocol.md`. Include OOS items on the ballot with `[OUT_OF_SCOPE]` prefix per the protocol's OOS section. For code review:

- **Voter 1**: **Claude Code Reviewer subagent** — fresh Agent tool invocation (subagent_type: `code-reviewer`) with the voting prompt. Instruct: `"You are a very scrupulous senior code reviewer on a voting panel. You will vote YES, NO, or EXONERATE on proposed code changes. Be extremely rigorous — only vote YES for findings that identify genuine bugs, logic errors, security issues, or clearly important improvements. Vote EXONERATE if the concern is legitimate but not worth implementing in this PR. Vote NO for trivial style nits, subjective preferences, or speculative concerns. When voting, also consider proportionality: vote EXONERATE (not YES) if the finding's concern is legitimate but the proposed change would introduce more complexity than the issue warrants."`
- **Voter 2**: Codex — via `run-external-reviewer.sh` with the ballot (use `--with-effort` and append "Work at maximum reasoning effort level." to the voter prompt). If `codex_available` is false, launch a Claude subagent voter instead per the Voting Protocol. Instruct similarly as a "very scrupulous senior code reviewer," including the proportionality guidance.
- **Voter 3**: Cursor — via `run-external-reviewer.sh` with the ballot (use `--with-effort` and append "Work at maximum reasoning effort level." to the voter prompt). If `cursor_available` is false, launch a Claude subagent voter instead per the Voting Protocol. Instruct similarly, including the proportionality guidance.

**Ballot file handling**: Use the Write tool (not `cat` with heredoc or Bash) to write the ballot to `$REVIEW_TMPDIR/ballot.txt`. For Codex and Cursor voter prompts, reference the ballot file path (e.g., "Read the ballot from $REVIEW_TMPDIR/ballot.txt") instead of inlining the ballot content. This avoids permission prompts from `cat > file << 'EOF'` or `BALLOT=$(cat file)` patterns.

Launch all available voters **in parallel** (Cursor first, then Codex, then Claude subagent). Wait for external voter sentinels using `wait-for-reviewers.sh` per the Voting Protocol, then parse voter outputs.

**Tally votes**: Apply the threshold rules from the Voting Protocol based on eligible voters per finding (2+ YES with 3 voters, unanimous 2/2 with 2 voters, skip if <2 eligible). Print vote breakdown per finding.

**Competition scoring**: Compute and print the **Reviewer Competition Scoreboard** per the Voting Protocol. Note in the scoreboard that scores apply to round 1 only — round 2+ findings are auto-accepted and do not contribute to scores.

**Zero accepted in-scope findings**: If voting rejects all in-scope findings, print `**ℹ Voting panel rejected all in-scope findings. No changes to implement.**` (OOS items accepted for issue filing are processed separately by `/implement`.) and skip to **Step 4**.

**OOS items accepted by vote** (2+ YES in round 1): These are accepted for GitHub issue filing, NOT for code implementation. **Only when `SESSION_ENV_PATH` is non-empty**: write accepted OOS items to `$(dirname "$SESSION_ENV_PATH")/oos-accepted-review.md` using the format:
```markdown
### OOS_N: <short title>
- **Description**: <full description of the observation>
- **Reviewer**: <attribution>
- **Vote tally**: <YES/NO/EXONERATE counts>
- **Phase**: review
```
When `SESSION_ENV_PATH` is empty (standalone invocation), skip the OOS artifact write.

**Save not-accepted finding IDs**: Record the IDs of findings not accepted by vote in round 1 (whether rejected or exonerated). In rounds 2+, if a Claude-only reviewer re-raises a finding that was not accepted by the round-1 voting panel (same file, same issue), suppress it — do not re-accept a finding the panel already voted down or exonerated. The rounds-2+ skip-voting rule itself lives in `SKILL.md` at the Step 3c.1 branch selector (the file you are reading is loaded only on the round-1 branch, so duplicating that rule here would be dead content and a split-source maintenance risk).
