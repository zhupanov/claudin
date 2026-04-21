# Plan Review Reference

**Consumer**: `/design` Step 3 — Voting Panel launch + Finalize + Track Rejected.

**Contract**: 3-voter panel (Claude Code Reviewer subagent + Codex + Cursor), YES/NO/EXONERATE ballot, 2+ YES threshold, proportionality rule. Claude subagent voter replacement when external tool unavailable so the panel always remains at 3.

---

## Competition notice

> **Competition notice**: Your findings will be voted on by a 3-agent panel (Claude Code Reviewer subagent, Codex, Cursor) using YES/NO/EXONERATE. Each finding that receives 2+ YES votes earns you +1 point. Findings with exactly 1 YES earn 0 points. Findings with 0 YES but at least 1 EXONERATE earn 0 points (the panel recognized your concern as legitimate). Findings with 0 YES and 0 EXONERATE cost you -1 point. Focus on high-quality, actionable findings. Concerns that are valid but not actionable in this PR may still be exonerated rather than penalized. Out-of-scope observations use **asymmetric scoring** — accepted OOS items (2+ YES) earn +1 point and are filed as GitHub issues; all other OOS outcomes (including unanimous rejection) score 0.

---

## Voter prompts

- **Voter 1**: **Claude Code Reviewer subagent** — fresh Agent tool invocation (subagent_type: `code-reviewer`) with the voting prompt. Instruct: `"You are a senior code reviewer on a voting panel. You will vote YES, NO, or EXONERATE on proposed modifications to an implementation plan. Be scrupulous — only vote YES for findings that are correct, important, and worth revising the plan for. Vote EXONERATE if the concern is legitimate but not worth implementing in this PR. When voting, also consider proportionality: vote EXONERATE (not YES) if the finding's concern is legitimate but the proposed change would introduce more complexity than the issue warrants."`
- **Voter 2**: Codex — via `run-external-reviewer.sh` with the ballot (use `--with-effort` and append "Work at maximum reasoning effort level." to the voter prompt). If `codex_available` is false, launch a Claude subagent voter instead per the Voting Protocol.
- **Voter 3**: Cursor — via `run-external-reviewer.sh` with the ballot (use `--with-effort` and append "Work at maximum reasoning effort level." to the voter prompt). If `cursor_available` is false, launch a Claude subagent voter instead per the Voting Protocol.

For Codex, Cursor, and their Claude replacement voters, instruct each: `"You are a senior engineer on a voting panel deciding which proposed plan modifications should be accepted. When voting, also consider proportionality: vote EXONERATE (not YES) if the finding's concern is legitimate but the proposed change would introduce more complexity than the issue warrants."`

---

## Ballot file handling

**Ballot file handling**: Use the Write tool (not `cat` with heredoc or Bash) to write the ballot to `$DESIGN_TMPDIR/ballot.txt`. For Codex and Cursor voter prompts, reference the ballot file path (e.g., "Read the ballot from $DESIGN_TMPDIR/ballot.txt") instead of inlining the ballot content. This avoids permission prompts from `cat > file << 'EOF'` or `BALLOT=$(cat file)` patterns.

---

## Finalize Plan Review — accepted FINDING_N template

```markdown
### FINDING_N: <title>
- **Concern**: <what was raised>
- **Resolution**: <how the plan was revised>
```

---

## Finalize Plan Review — accepted OOS format

```markdown
### OOS_N: <short title>
- **Description**: <full description of the observation>
- **Reviewer**: <attribution>
- **Vote tally**: <YES/NO/EXONERATE counts>
- **Phase**: design
```

---

## Track Rejected Plan Review Findings template

```markdown
### [Plan Review] <Reviewer Name>
**Finding**: <thorough description of the finding — include what aspect of the plan the reviewer questioned, the specific concern raised, and what revision they suggested. Must be detailed enough to serve as an actionable TODO item if later prioritized. Do NOT use a terse one-liner — a reader who has never seen the original review must be able to understand the concern and act on it.>
**Reason not implemented**: <complete justification for why this finding was not accepted — include the specific technical reasoning, any relevant context about project conventions or design decisions, and why the current plan is acceptable despite the finding. Do NOT abbreviate — preserve all important details from the evaluation.>
```
