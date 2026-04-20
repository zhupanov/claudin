# Skill Design Principles

Canonical source for how larch skills are designed and written. Cited by `skills/create-skill/SKILL.md` (both the body `## Principles` section and the Step 3 `/im` feature-description handoff) and by `AGENTS.md` Canonical sources. When you add a new principle or revise an existing one, update the compact A/B/C excerpt in `skills/create-skill/SKILL.md` Step 3 in the same PR only if a Section III mechanical rule changes — Sections I–II and IV–IX are not mirrored elsewhere and evolve independently.

Provenance tags on each section: **[larch]** = rule enforced in this repo (harness or review); **[skill-judge]** = extrapolated from the `skill-judge` plugin's evaluation dimensions; **[skill-creator]** = extrapolated from Anthropic's `skill-creator` plugin.

## Precedence

**Section III (Larch mechanical rules) overrides Section IV (Writing style)** whenever the two conflict. Section IV draws on `skill-creator`'s "avoid rigid MUSTs, explain the why" advice; Section III embodies larch's harness-enforced invariants that MUST be followed even when they read as rigid. The precedence rule exists because `skill-creator` targets standalone single-purpose skills, while larch skills compose within a multi-skill harness where mechanical invariants are load-bearing.

## Section I — Knowledge delta is the core value **[skill-judge]**

A skill's value is measured by the gap between what it teaches and what the model already knows. Every paragraph must earn its tokens.

- **Skip what Claude already knows.** Do not explain "what is PDF", "how to write a for-loop", standard library usage, or generic best practices. Those paragraphs are redundant compression.
- **Keep expert-only content.** Decision trees for non-obvious choices, trade-offs that take years to learn, edge cases from real incidents, domain-specific sequences that are easy to get wrong.
- **Before writing any section, ask: "Is this explaining TO Claude or FOR Claude?"** Explaining TO Claude is a red flag — Claude knows it already.

A 43-line skill can outperform a 500-line skill. Token waste in the skill body displaces system prompts, conversation history, and other skills the user is relying on in the same window.

## Section II — Structure and progressive disclosure **[skill-judge, skill-creator]**

Skills load in three layers. Respect the layering when you decide where content lives.

- **Metadata (always in memory).** `name` + `description` only. ~100 tokens. This is the only layer the harness sees before deciding whether to trigger the skill.
- **SKILL.md body (loaded after triggering).** Decision trees, invariants, and wiring. Keep SKILL.md under 500 lines when possible — add a `references/` layer when approaching the limit.
- **Resources (loaded on demand).** `scripts/` for deterministic executable logic, `references/` for docs loaded via explicit `MANDATORY — READ ENTIRE FILE` triggers embedded in workflow steps, `assets/` for templates/fonts/icons.

Rules:

- **Emit explicit loading triggers** for every `references/` file. Dangling references that no step loads are dead weight.
- **Emit `Do NOT Load` guidance** where one branch of the workflow should skip a reference file. Loading too much is as bad as loading too little.
- **Split by domain when a skill spans multiple variants.** E.g. `references/aws.md`, `references/gcp.md`, `references/azure.md` — the caller reads only the relevant one.

## Section III — Larch mechanical rules **[larch]**

These rules apply to every new skill scaffolded by `/create-skill` and to every existing larch skill under edit. They are guidance, not mechanically lint-enforced — but they are battle-tested and reviewed on every PR. A change to this section requires updating the compact A/B/C excerpt in `skills/create-skill/SKILL.md` Step 3 in the same PR.

- **A — Express content and logic as bash scripts.** Any non-trivial step belongs in a `.sh` file: shared at `${CLAUDE_PLUGIN_ROOT}/scripts/` when two or more skills can reuse it, or private at `${CLAUDE_PLUGIN_ROOT}/skills/<NAME>/scripts/` when it is skill-specific. Prefer reuse — grep existing `scripts/` before creating a new one. See `AGENTS.md` Editing rules for canonical script-ownership bullets.
- **B — No direct command calls via the Bash tool.** Every shell command invoked from a SKILL.md step must be a call to a `.sh` wrapper. Do NOT inline pipelines, loops, or multi-line `bash -c` strings into the SKILL.md. Wrappers keep the SKILL.md scannable, centralize error handling and logging, and make each step auditable without reading prompt prose.
- **C — No consecutive Bash tool calls.** When a step needs two or more shell actions, combine them into a single coordinator `.sh` that invokes the individual scripts internally (or calls them via `source`). The SKILL.md step should issue exactly one Bash tool call per logical unit of work. Rationale: each Bash tool call is a separate inspectable artifact; stacking them fragments the audit trail and encourages copy-paste drift.

## Section IV — Writing style **[skill-creator]**

Prefer humane explanation over heavy-handed caps. Today's models have good theory of mind; when given the *why*, they generalize beyond the specific example.

- **Explain the *why*.** Every instruction benefits from one sentence of rationale. When you catch yourself writing `ALWAYS` or `NEVER` in all caps, pause and try to reframe as "do X because [specific consequence]" — except for Section III mechanical rules, where the precedence layer applies.
- **Use the imperative form.** "Read the ballot", not "The reader should read the ballot" or "You may want to read the ballot".
- **Keep the prompt lean.** Remove sections that are not pulling their weight. If a paragraph is only there "in case the model needs it," delete it.
- **Generalize from examples.** The test set you iterate against is narrower than the production distribution. Write rules that work for cases you have not seen.
- **Avoid overly-rigid structures for creative or judgment work.** Rigid steps are correct for fragile tasks (see Section VII); they suppress quality in creative work.

## Section V — Description as activation gate **[skill-judge, skill-creator]**

The `description` frontmatter field is the only signal the harness sees before deciding whether to load the skill. A skill with perfect body content but a vague description never runs.

Every description must answer three questions:

- **WHAT** does this skill do? Functionality in concrete terms.
- **WHEN** should it trigger? Explicit use-case scenarios with keywords a user might type (`"Use when X"`, `"When user asks for Y"`).
- **KEYWORDS** a search would match: file extensions, domain terms, action verbs, tool names.

Anti-patterns to avoid:

- **"A helpful skill for various tasks."** Useless — the harness has no idea when to activate it.
- **"Helps with document processing."** Too vague. What documents? What processing? When?
- **"When to use this skill" section buried in the SKILL.md body.** The body is loaded only AFTER triggering. Move all triggering information to `description`.

Under-triggering is the common failure mode. If the skill should fire on multiple phrasings, include them in the description — even at the cost of verbose prose.

## Section VI — Anti-patterns with WHY **[skill-judge]**

Half of expert knowledge is knowing what NOT to do. Models do not have this intuition; make the "absolutely don'ts" explicit with reasons.

- **Include an explicit NEVER list** where the skill touches fragile or commonly-mistaken patterns.
- **Always state the reason.** `"NEVER use purple gradient on white background — it is the signature of AI-generated content"` is useful. `"NEVER use bad colors"` is not.
- **Weak anti-patterns:** "Avoid errors", "be careful with edge cases", "write clean code" — these are generic filler Claude already knows.
- **Strong anti-patterns** read like incident reports: `"NEVER skip the --continue path of rebase-push.sh when handling a conflict — this leaves the rebase in progress and the next invocation fails with a cryptic error"`.

When you find yourself writing a vague anti-pattern, either sharpen it with a specific WHY or delete it.

## Section VII — Freedom calibration **[skill-judge]**

Match the level of specificity to the task's fragility. "If the agent makes a mistake here, what is the consequence?" High-consequence tasks get low freedom; low-consequence tasks get high freedom.

| Task type | Freedom | Form |
|---|---|---|
| Fragile operations (file formats, migrations, mechanical invariants) | Low | Exact scripts, explicit parameter lists, no improvisation |
| Code review, judgment-heavy process | Medium | Priorities + principles, but room to judge |
| Creative / design work | High | Principles and aesthetic direction, no prescribed steps |

Rigid scripts for creative tasks suppress quality; vague prose for fragile operations produces broken files. Section III mechanical rules are low-freedom by design — they enforce larch-harness invariants where the blast radius of a mistake is large.

## Section VIII — Pattern recognition **[skill-judge]**

Official skills tend to follow one of five patterns. Pick the pattern that matches your task shape before writing.

| Pattern | Lines | When to use |
|---|---|---|
| **Mindset** | ~50 | Creative tasks requiring taste (frontend-design) |
| **Navigation** | ~30 | Multiple distinct scenarios, routes to sub-files |
| **Philosophy** | ~150 | Art/creation requiring originality |
| **Process** | ~200 | Complex multi-step projects |
| **Tool** | ~300 | Precise operations on specific formats |

Most larch skills follow the Process pattern (phased workflow, checkpoints, medium freedom) or a hybrid of Process + Tool. `/design`, `/implement`, `/review`, `/fix-issue` are Process-pattern with heavy `references/` layering.

## Section IX — Verifiable quality criteria **[larch, skill-judge]**

A well-formed larch skill satisfies every bullet below. Use this list during skill review.

- **Valid YAML frontmatter** — `name` matches `^[a-z][a-z0-9-]*$`, ≤64 characters; `description` answers WHAT/WHEN/KEYWORDS (Section V) and is ≤1024 characters.
- **No tutorial prose** — no "what is X" explanations of concepts Claude already knows; knowledge-delta ratio of the body is high (Section I).
- **SKILL.md body under 500 lines** — if longer, heavy content lives in `references/` with explicit loading triggers (Section II).
- **Explicit anti-pattern list with WHY** for any fragile or commonly-mistaken surface (Section VI).
- **Pattern match** — the skill structure matches exactly one of the five patterns in Section VIII; structure feels coherent end-to-end.
- **Section III compliance** — all non-trivial shell logic lives in `.sh` wrappers; no direct command calls or consecutive Bash tool calls in the body.
- **Description triggers reliably** — under the intended use cases (e.g., "the user says 'review my PR'") the description's keywords match; under adjacent use cases that should NOT trigger, they do not.
- **No orphan references** — every `references/*.md` file is loaded by at least one workflow step via a `MANDATORY — READ ENTIRE FILE` trigger; unused references are deleted.
