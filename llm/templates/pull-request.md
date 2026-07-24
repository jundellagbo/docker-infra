# Pull request brief

Open a PR for the current branch unless one already exists — the repo's real
state is under "Scope" below, so read it first. If a PR is already open, show its
URL and status and stop; don't create a duplicate.

Otherwise: read the actual diff, because the description says what the change
does, not what the task asked for. Run `infra-llm --verify` and confirm it
passes — a PR on a red tree wastes the reviewer's time. If HEAD is on the base
branch, the work needs its own branch first. Then do it rather than handing
commands back: running this command opened a short window in which commit, push
and branch are allowed, because asking for a PR is asking for those. Branch if
needed, commit with a clear message, open the PR with `gh pr create` (it pushes
the branch), and report the URL. Destructive git stays blocked and always will
be — no force push, no `reset --hard`, no history rewriting; if you think one is
needed, stop and say so. No AI/LLM attribution anywhere in the commit message or
the PR body.

Write the PR body as four short sections readable in under 30 seconds:
**Summary** (what changed and why), **Testing** (what was run and its result),
**Risks** (what a reviewer should watch), **Rollback** (how to undo it).
