# test-render-specialist-prompt.sh

**Purpose**: Test harness for `scripts/render-specialist-prompt.sh`. Validates that all specialist agent files exist, have valid frontmatter, and render correctly in both diff and description modes. Also validates error handling for invalid inputs.

**Test groups**:
1. Specialist agent file existence (5 files)
2. YAML frontmatter validation (2 fences, non-empty body)
3. Diff mode rendering (preamble, trust boundary, focus-area tagging, NO_ISSUES_FOUND, do-not-modify)
4. Description mode rendering (description preamble, canonical file list, OOS anchor)
5. Competition notice flag (absent without flag, present with flag)
6. Error cases (missing args, invalid mode, nonexistent file, incomplete description args)
7. Security focus-area presence in all specialist outputs

**Makefile wiring**: `make test-harnesses` target.

**Edit-in-sync**: Update this harness when `scripts/render-specialist-prompt.sh` or any `agents/reviewer-*.md` file changes behavior.
