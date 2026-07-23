# Pull request brief

Open a PR for the current branch — unless one already exists. The repo's real
state is under "Scope" below; read it first.

**Already open?** Show the URL and its status, don't create a duplicate.

**Otherwise:**

1. Read the actual diff — the description must say what the change does, not
   what the task asked for.
2. Run `infra-llm --verify` and confirm it passes. A PR on a red tree wastes the
   reviewer's time.
3. If HEAD is on the base branch, the work needs its own branch first.
4. Do it — don't hand commands back. Running this command opened a short window
   in which commit, push and branch are allowed, because asking for a PR is
   asking for those. Branch if needed, commit the work with a clear message, and
   open the PR with `gh pr create` (it pushes the branch). Report the URL.
5. Destructive git stays blocked and always will be — no force push, no `reset
   --hard`, no history rewriting. If you think one is needed, stop and say so.
6. No AI/LLM attribution anywhere in the commit message or the PR body.

**PR body** — four short sections, readable in under 30 seconds:

- **Summary** — what changed and why
- **Testing** — what was run and its result
- **Risks** — what a reviewer should watch
- **Rollback** — how to undo it
