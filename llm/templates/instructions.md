## Step-by-step execution protocol (infra-llm)

Multi-step work in this repo is tracked with `- [ ]` / `- [x]` checkboxes
**directly in the plan file** under `plans/` (registered in
`plans/.active-plan`, git-ignored). The hooks that enforce this live outside
the repo and are driven through the `infra-llm` command, so nothing is vendored
in here. Run `infra-llm --skill step-plan` for the full protocol.

### Commands

| Command                    | What it does                                                     |
| -------------------------- | ---------------------------------------------------------------- |
| `infra-llm --plan <slug>`  | create `plans/<slug>.md` and register it as the active plan       |
| `infra-llm --steps`        | the next unchecked step the stop hook will demand                 |
| `infra-llm --verify`       | run this repo's checks and close out the plan                     |
| `infra-llm --code-review`  | review brief + the scope of the recent changes                    |
| `infra-llm --sessions`     | past session records in `.claude/sessions/`                       |
| `infra-llm --status`       | wiring, active plan, session count                                |
| `infra-llm --skill <name>` | print a protocol skill (`step-plan`, `llm-workflow`)              |

### How to work

1. When a task has more than one step — or the prompt names a `plans/*.md`
   file — read the plan and convert **EVERY** discrete item into its own
   `- [ ]` checkbox, editing the plan file in place. It is the checklist; there
   is no separate progress file. For ad-hoc work, `infra-llm --plan <slug>`
   creates and registers one.
2. Implement exactly **ONE** unchecked step per turn, mark it `- [x]`, then
   stop. The Stop hook blocks the stop and feeds you the next step, so you
   never need to start the next one in the same turn.
3. Never batch steps and never drop one silently — an unnecessary step is
   marked `- [x] … (skipped: reason)`, not deleted.
4. When every box is checked, run `infra-llm --verify` and fix what it reports
   until it prints `VERIFY OK`.
5. If an active plan still has unchecked steps at the start of a session,
   resume it before starting anything new.

The stop hook gives up after 3 consecutive auto-continues with no progress —
if you hit that, say what is blocking you instead of spinning.

### Git

**Do not run repository-mutating git commands unless the user explicitly asks.**
No `git commit`, `git push`, `git merge`, `git rebase`, `git reset`,
`git checkout -b`, no branch or tag creation, no stashing, no history rewriting.
Leave the work in the working tree and say what you changed; the user decides
when it gets committed. Read-only git (`status`, `diff`, `log`, `show`, `blame`)
is fine and encouraged.

### Code review

Reviewing is a separate, on-request activity — it is not a gate on finishing a
task. When the user asks for a review, run `infra-llm --code-review`: it prints
the review brief (correctness, security, data safety, implementation quality,
tests) together with the scope of the recent changes. Pass paths or a git range
to review something else instead.

**Apply the fixes yourself** for every finding you confirm, keeping each fix
minimal and scoped to the defect. Refactor where the code genuinely needs it —
optional, behaviour-preserving, confined to the reviewed change, never style
churn — then report what you fixed, what you refactored, and what you left
alone and why. Stop and describe instead of applying when a fix would be large,
risky, or would change intended behaviour — and argue against a finding you
believe is wrong rather than "fixing" it.

### Worktrees

`plans/` and `.claude/sessions/` are untracked, so **every git worktree has its
own active plan and its own session history** — agents in different worktrees
run in parallel without colliding. Work only in the worktree you were started
in: never edit another worktree's `plans/`, and never assume a plan you can't
see in this directory. `infra-llm --worktrees` lists every worktree with its
plan state.

Session records for the last 10 sessions are written to
`.claude/sessions/<session-id>.md`; read them to recover what an earlier
session was asked to do.
