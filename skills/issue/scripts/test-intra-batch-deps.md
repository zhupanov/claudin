# test-intra-batch-deps.sh — sibling contract

**Purpose**: structural regression harness pinning the intra-batch dependency decoupling from external CANDIDATES in `/issue` SKILL.md. Asserts that Step 4E redirects to Step 5 when `N_NON_MALFORMED >= 2`, Step 5's gate admits the intra-batch-only path, fetch is conditionally skipped, empty-CANDIDATES verdict guidance exists, and the old unconditional short-circuit clause is absent.

**Makefile wiring**: `make test-intra-batch-deps` (listed in both `.PHONY` and `test-harnesses`).

**Assertions**:
1. Step 4E contains "If \`N_NON_MALFORMED >= 2\`, proceed to Step 5" — pins the redirect.
2. SKILL.md contains "N_NON_MALFORMED >= 2" — pins the gate condition.
3. Step 5 contains "skip \`fetch-issue-details.sh\` entirely" — pins the conditional fetch skip.
4. Step 5 contains "Empty-CANDIDATES + multi-item path" — pins the verdict guidance.
5. Step 4E does NOT contain "short-circuits cleanly via its existing" — asserts removal of old clause (assert_absent).

**Edit-in-sync rules**: if the asserted strings in SKILL.md change (e.g., rewording the Step 4E redirect or Step 5 gate), update this harness's `assert_present`/`assert_absent` needles in the same PR.
