# Code review brief

Review the change under "Scope" below — only the recent changes, not the whole
repository and not pre-existing code the change merely touches. Read the diff and
the surrounding code before judging anything; a review that restates the diff is
worthless.

Look for, in priority order: **correctness** (wrong logic, bad edge/null
handling, swallowed errors, unhandled failure paths, races, leaks, broken callers
or contracts), **security** (untrusted input reaching a sink, missing
authn/authz, leaked secrets, weak crypto, over-broad permissions, unpinned
dependencies), **data safety** (destructive or irreversible operations without a
guard, migrations that lose data or can't roll back), **implementation quality**
(duplicating what already exists, wrong level of abstraction, dead code,
structure that fights the surrounding conventions), and **tests and
observability** (is the risky part covered, are failures diagnosable). Match the
codebase's existing style — personal preference is not a finding.

Verify each finding before acting: re-read the code and confirm the failure is
real. "No issues found" is a valid outcome, and a wrong finding costs more than
it saves, so argue against one you can't stand behind instead of "fixing" it.
Apply the fix for every finding you do confirm, minimal and targeted. Refactor
only where the code genuinely needs it — behaviour-preserving, inside the
reviewed change, never style churn — and stop and describe instead when a fix
would be large, risky, or would change intended behaviour.

Report what you **fixed** (file:line, the defect in one sentence, the concrete
failure scenario, what the fix does — most severe first), what you
**refactored** and why it was worth it, and what you **left alone** and why. Then
re-run `infra-llm --verify`. Never commit or push as part of a review; fixes stay
in the working tree.
