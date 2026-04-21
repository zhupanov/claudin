# Skill Design Principles

Canonical source for how larch skills designed and written. Cited by `skills/create-skill/SKILL.md` (body `## Principles` section and Step 3 `/im` feature-description handoff) and by `AGENTS.md` Canonical sources. Add new principle or revise existing one → update compact A/B/C excerpt in `skills/create-skill/SKILL.md` Step 3 in same PR only if Section III mechanical rule change — Sections I–II and IV–IX not mirrored elsewhere, evolve independently.

Provenance tags per section: **[larch]** = rule enforced in repo (harness or review); **[skill-judge]** = extrapolated from `skill-judge` plugin eval dimensions; **[skill-creator]** = extrapolated from Anthropic `skill-creator` plugin.

## Precedence

**Section III (Larch mechanical rules) overrides Section IV (Writing style)** when two conflict. Section IV draws on `skill-creator` "avoid rigid MUSTs, explain why" advice; Section III embodies larch harness-enforced invariants that MUST followed even when read rigid. Precedence rule exists because `skill-creator` targets standalone single-purpose skills, while larch skills compose within multi-skill harness where mechanical invariants load-bearing.

## Section I — Knowledge delta is the core value **[skill-judge]**

Skill value = gap between what teaches and what model already knows. Every paragraph must earn tokens.

- **Skip what Claude already knows.** No explain "what is PDF", "how write for-loop", standard library usage, generic best practices. Those paragraphs redundant compression.
- **Keep expert-only content.** Decision trees for non-obvious choices, trade-offs that take years learn, edge cases from real incidents, domain-specific sequences easy get wrong.
- **Before writing any section, ask: "Is this explaining TO Claude or FOR Claude?"** Explaining TO Claude = red flag — Claude know already.

43-line skill can outperform 500-line skill. Token waste in body displaces system prompts, conversation history, other skills user rely on in same window.

## Section II — Structure and progressive disclosure **[skill-judge, skill-creator]**

Skills load in three layers. Respect layering when decide where content lives.

- **Metadata (always in memory).** `name` + `description` only. ~100 tokens. Only layer harness sees before deciding whether trigger skill.
- **SKILL.md body (loaded after triggering).** Decision trees, invariants, wiring. Keep SKILL.md under 500 lines when possible — add `references/` layer when approaching limit.
- **Resources (loaded on demand).** `scripts/` for deterministic executable logic, `references/` for docs loaded via explicit `MANDATORY — READ ENTIRE FILE` triggers embedded in workflow steps, `assets/` for templates/fonts/icons.

Rules:

- **Emit explicit loading triggers** for every `references/` file. Dangling references that no step loads = dead weight.
- **Emit `Do NOT Load` guidance** where one branch of workflow should skip reference file. Loading too much bad as loading too little.
- **Split by domain when skill spans multiple variants.** E.g. `references/aws.md`, `references/gcp.md`, `references/azure.md` — caller reads only relevant one.

## Section III — Larch mechanical rules **[larch]**

Rules apply to every new skill scaffolded by `/create-skill` and every existing larch skill under edit. Guidance, not mechanically lint-enforced — but battle-tested, reviewed on every PR. Change to this section requires updating compact A/B/C excerpt in `skills/create-skill/SKILL.md` Step 3 in same PR.

- **A — Express content and logic as bash scripts.** Any non-trivial step belongs in `.sh` file: shared at `${CLAUDE_PLUGIN_ROOT}/scripts/` when two or more skills can reuse, or private at `${CLAUDE_PLUGIN_ROOT}/skills/<NAME>/scripts/` when skill-specific. Prefer reuse — grep existing `scripts/` before creating new one. See `AGENTS.md` Editing rules for canonical script-ownership bullets.
- **B — No direct command calls via the Bash tool.** Every shell command invoked from SKILL.md step must be call to `.sh` wrapper. Do NOT inline pipelines, loops, multi-line `bash -c` strings into SKILL.md. Wrappers keep SKILL.md scannable, centralize error handling and logging, make each step auditable without reading prompt prose.
- **C — No consecutive Bash tool calls.** When step needs two or more shell actions, combine into single coordinator `.sh` that invokes individual scripts internally (or calls via `source`). SKILL.md step should issue exactly one Bash tool call per logical unit of work. Rationale: each Bash tool call = separate inspectable artifact; stacking fragments audit trail, encourages copy-paste drift.

## Section IV — Writing style **[skill-creator]**

Prefer humane explanation over heavy-handed caps. Today models have good theory of mind; given *why*, they generalize beyond specific example.

- **Explain the *why*.** Every instruction benefits from one sentence rationale. Catch self writing `ALWAYS` or `NEVER` in all caps → pause, try reframe as "do X because [specific consequence]" — except Section III mechanical rules, where precedence layer applies.
- **Use the imperative form.** "Read the ballot", not "The reader should read the ballot" or "You may want to read the ballot".
- **Keep the prompt lean.** Remove sections not pulling weight. Paragraph only there "in case model needs it" → delete.
- **Generalize from examples.** Test set you iterate against narrower than production distribution. Write rules that work for cases not seen.
- **Avoid overly-rigid structures for creative or judgment work.** Rigid steps correct for fragile tasks (see Section VII); they suppress quality in creative work.

## Section V — Description as activation gate **[skill-judge, skill-creator]**

`description` frontmatter = only signal harness sees before deciding whether load skill. Skill with perfect body but vague description never runs.

Every description must answer three questions:

- **WHAT** does skill do? Functionality in concrete terms.
- **WHEN** should trigger? Explicit use-case scenarios with keywords user might type (`"Use when X"`, `"When user asks for Y"`).
- **KEYWORDS** search would match: file extensions, domain terms, action verbs, tool names.

Anti-patterns avoid:

- **"A helpful skill for various tasks."** Useless — harness no idea when activate.
- **"Helps with document processing."** Too vague. What documents? What processing? When?
- **"When to use this skill" section buried in SKILL.md body.** Body loaded only AFTER triggering. Move all triggering info to `description`.

Under-triggering = common failure mode. If skill should fire on multiple phrasings, include in description — even at cost of verbose prose.

## Section VI — Anti-patterns with WHY **[skill-judge]**

Half of expert knowledge = knowing what NOT do. Models no have this intuition; make "absolutely don'ts" explicit with reasons.

- **Include explicit NEVER list** where skill touches fragile or commonly-mistaken patterns.
- **Always state the reason.** `"NEVER use purple gradient on white background — it is the signature of AI-generated content"` useful. `"NEVER use bad colors"` not.
- **Weak anti-patterns:** "Avoid errors", "be careful with edge cases", "write clean code" — generic filler Claude already knows.
- **Strong anti-patterns** read like incident reports: `"NEVER skip the --continue path of rebase-push.sh when handling a conflict — this leaves the rebase in progress and the next invocation fails with a cryptic error"`.

Find self writing vague anti-pattern → either sharpen with specific WHY or delete.

## Section VII — Freedom calibration **[skill-judge]**

Match specificity level to task fragility. "If agent makes mistake here, what consequence?" High-consequence tasks get low freedom; low-consequence tasks get high freedom.

| Task type | Freedom | Form |
|---|---|---|
| Fragile operations (file formats, migrations, mechanical invariants) | Low | Exact scripts, explicit parameter lists, no improvisation |
| Code review, judgment-heavy process | Medium | Priorities + principles, but room to judge |
| Creative / design work | High | Principles and aesthetic direction, no prescribed steps |

Rigid scripts for creative tasks suppress quality; vague prose for fragile operations produces broken files. Section III mechanical rules low-freedom by design — enforce larch-harness invariants where blast radius of mistake large.

## Section VIII — Pattern recognition **[skill-judge]**

Official skills tend follow one of five patterns. Pick pattern matching task shape before writing.

| Pattern | Lines | When to use |
|---|---|---|
| **Mindset** | ~50 | Creative tasks requiring taste (frontend-design) |
| **Navigation** | ~30 | Multiple distinct scenarios, routes to sub-files |
| **Philosophy** | ~150 | Art/creation requiring originality |
| **Process** | ~200 | Complex multi-step projects |
| **Tool** | ~300 | Precise operations on specific formats |

Most larch skills follow Process pattern (phased workflow, checkpoints, medium freedom) or hybrid Process + Tool. `/design`, `/implement`, `/review`, `/fix-issue` = Process-pattern with heavy `references/` layering.

## Section IX — Verifiable quality criteria **[larch, skill-judge]**

Well-formed larch skill satisfies every bullet below. Use list during skill review.

- **Valid YAML frontmatter** — `name` matches `^[a-z][a-z0-9-]*$`, ≤64 characters; `description` answers WHAT/WHEN/KEYWORDS (Section V) and ≤1024 characters.
- **No tutorial prose** — no "what is X" explanations of concepts Claude already knows; knowledge-delta ratio of body high (Section I).
- **SKILL.md body under 500 lines** — if longer, heavy content lives in `references/` with explicit loading triggers (Section II).
- **Explicit anti-pattern list with WHY** for any fragile or commonly-mistaken surface (Section VI).
- **Pattern match** — skill structure has clear primary pattern from Section VIII (named hybrids like "Process + Tool" acceptable when documented); structure feels coherent end-to-end.
- **Section III compliance** — all non-trivial shell logic lives in `.sh` wrappers; no direct command calls or consecutive Bash tool calls in body.
- **Description triggers reliably** — under intended use cases (e.g., "the user says 'review my PR'") description keywords match; under adjacent use cases that should NOT trigger, they do not.
- **No orphan references** — every `references/*.md` file loaded by at least one workflow step via `MANDATORY — READ ENTIRE FILE` trigger; unused references deleted.
