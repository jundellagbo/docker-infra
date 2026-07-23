<!-- infra-llm:start -->

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
| `infra-llm --pull-request` | PR brief + this branch's commits, status and existing PR          |
| `infra-llm --create-release` | release brief + tags, published releases and commits since       |
| `infra-llm --sessions`     | past session records in `.claude/sessions/`                       |
| `infra-llm --status`       | wiring, active plan, git-guard mode, session count                |
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

### Don't edit what infra-llm generates

This block (everything between the `infra-llm` markers) and any skill or hook
infra-llm installed are generated copies. Editing them here is lost on the next
refresh and never reaches the other repos on the same workflow. Change the
source in the infra checkout and re-run `infra-llm --docs`; if that isn't
yours to change, say what needs changing instead of patching the copy.

### Writing plans, instructions and skills

Anything written for an agent to follow later — a plan file, an instruction
block, a skill, a command brief — is short, specific and imperative. Say what to
do and why it matters, then stop: padding is re-read on every future run and
buries the line that mattered. A plan step is one line naming a concrete
outcome, detail underneath only where it isn't obvious. Explain the reason
rather than stacking MUSTs; the next agent reads better than it obeys.

Use the `skill-creator` plugin skill when the user asks you to add or rework a
**skill, instruction file or command** — its frontmatter description is what
decides whether the thing ever triggers, and that is easy to get wrong by hand.

**Not for plans.** A plan is just the checkbox checklist in `plans/`; write it
directly and get on with the work — skill-creator's drafting and eval loop is
pure overhead there.

### Git

**Git state is the user's decision — never run a repository-mutating git
command** (commit, push, merge, rebase, reset, checkout, branch or tag creation,
stash, history rewriting). Leave the work in the working tree and say what you
changed; the user decides when it gets committed. Read-only git (`status`,
`diff`, `log`, `show`, `blame`) is fine and encouraged.

A guard hook enforces this and denies those commands — don't route around it
with aliases or wrappers. A repo that wants it relaxed configures that itself;
destructive commands stay denied regardless.

Never put AI/LLM attribution in a commit message, tag, release note or PR body.

### Pull requests and releases

Asked for a PR or a release, run `infra-llm --pull-request` /
`infra-llm --create-release`: each prints its brief plus the repo's real state.
Follow it — don't duplicate one that already exists, verify first, then
**prepare** the message, body or notes and hand the user the commands to run.

Releases are tagged `vMAJOR.MINOR.PATCH`: `v1.0.1` bug fix, `v1.1.0` feature,
`v2.0.0` breaking. One breaking change makes it a major release however small.

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

<!-- infra-llm:end -->
