# Code review brief

Review the change under "Scope" below — only the recent changes, not the whole
repository and not pre-existing code the change merely touches. Read the diff
and the surrounding code before judging anything; a review that restates the
diff is worthless.

## Look for, in priority order

1. **Correctness** — wrong logic, bad edge/null handling, swallowed errors,
   unhandled failure paths, races, leaks, broken callers or contracts.
2. **Security** — untrusted input reaching a sink (injection, path traversal,
   unsafe deserialization), missing authn/authz, leaked secrets, weak crypto,
   over-broad permissions, unpinned dependencies.
3. **Data safety** — destructive or irreversible operations without a guard,
   migrations that lose data or can't roll back.
4. **Implementation quality** — duplicating what already exists, wrong level of
   abstraction, dead code, structure that fights the surrounding conventions.
5. **Tests and observability** — is the risky part covered, and are failures
   diagnosable?

Match the codebase's existing style; personal preference is not a finding.

## Fix as you go

Verify each finding before acting — re-read the code and confirm the failure is
real. "No issues found" is a valid outcome, and a wrong finding costs more than
it saves, so argue against one you can't stand behind instead of "fixing" it.

Apply the fix for every finding you confirm, minimal and targeted. Refactor only
where the code genuinely needs it: behaviour-preserving, inside the reviewed
change, never style churn. Stop and describe instead when a fix would be large,
risky, or would change intended behaviour.

## Report

- **Fixed** — file:line, the defect in one sentence, the concrete failure
  scenario, and what the fix does. Most severe first.
- **Refactored** — behaviour-preserving cleanups and why they were worth it.
- **Not fixed** — what you left alone and why.

Re-run `infra-llm --verify` afterwards. Never commit or push as part of a
review — fixes stay in the working tree.
