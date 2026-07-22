# Code review brief

Review the change described under "Scope" below. Unless the user named other
code, review **only the recent changes** — not the whole repository, and not
pre-existing code the change merely touches.

Read the actual diff and the surrounding code before judging anything. A review
that only restates what the diff says is worthless.

## What to look for, in priority order

1. **Correctness** — does it do what it claims? Wrong logic, off-by-one, bad
   edge/empty/null handling, wrong operator precedence, silently swallowed
   errors, unhandled failure paths, race conditions, resource leaks, changes
   that break an existing caller or contract.
2. **Security** — untrusted input reaching a sink: injection (SQL/command/path/
   template), missing authentication or authorization checks, secrets or tokens
   committed or logged, unsafe deserialization, weak or hand-rolled crypto,
   overly broad permissions, SSRF, unvalidated redirects, missing output
   escaping, dependencies pulled from unpinned or untrusted sources.
3. **Data safety** — destructive or irreversible operations without a guard,
   migrations that lose data or can't be rolled back, writes outside the
   intended scope.
4. **Implementation quality** — duplication of something that already exists in
   the codebase, an abstraction at the wrong level, a special case where the
   general path already works, dead or unreachable code, naming or structure
   that contradicts the surrounding file's conventions.
5. **Tests and observability** — is the risky part of this change actually
   covered? Are failures diagnosable, or do they vanish silently?

Match the codebase's existing style and idioms; do not push a personal
preference as a finding.

## Fix as you go

Verify each finding before acting on it: re-read the code and confirm the
failure is real. A plausible-sounding finding that doesn't actually reproduce
wastes more time than it saves. "No issues found" is a valid outcome.

**Apply the fix for every finding you confirm** — don't just list problems and
wait to be told. Keep each fix minimal and targeted at the defect; do not
rewrite surrounding code, restructure the change, or slip in unrelated
improvements while you are in there. If a fix would be large, risky, or would
change intended behaviour, stop and describe it instead of applying it.

Drop a finding you can't stand behind rather than "fixing" it defensively — a
suggestion that turns out to be wrong should be argued against, not applied.

### Refactoring

Refactor when the code needs it — it is allowed, not required. Do it when the
change is genuinely hard to follow, duplicates logic that already exists, or
when the clean fix is a small restructure rather than a patch on top of a bad
shape. Keep it **behaviour-preserving** and confined to the code under review.

Don't refactor for taste: no renaming that isn't load-bearing, no re-layering
working code, no style-only churn, and nothing outside the reviewed change.
If a worthwhile refactor is bigger than the fix itself, describe it and let the
user decide instead of doing it. Say explicitly in the report which changes were
refactors rather than defect fixes.

## How to report

After fixing, report:

- **Fixed** — for each: **file:line**, one sentence on the defect, the concrete
  failure scenario (inputs/state → wrong result), and what the fix does. Most
  severe first.
- **Refactored** — any behaviour-preserving cleanup you made, and why it was
  worth doing. Omit this section if you didn't refactor anything.
- **Not fixed** — anything you deliberately left alone, with the reason (too
  large, needs a decision, out of scope, or the finding turned out to be wrong).

Re-run the repo's checks (`infra-llm --verify`) after applying fixes.

Never run `git commit`, `git push`, or any other repository-mutating git
command as part of a review — the fixes stay in the working tree.
