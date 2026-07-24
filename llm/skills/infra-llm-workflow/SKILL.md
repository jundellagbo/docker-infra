---
name: infra-llm-workflow
description: Wire up, refresh, operate and explain the shared agent workflow - plan protocol, step stop-hooks, session records, verification gate, git guard and search guard - in whatever repository is open. Use this when a repo has no infra-llm wiring yet, when the user asks to "set up the agent workflow / hooks / plan protocol here", when a hook or guard is misbehaving, or when asked what the step/plan/session tooling in this repo is and how to drive it.
---

# infra-llm workflow

The hooks live **once** in the infra checkout and are never vendored into a
project. A repo gets two things: hook wiring that shells out to the `infra-llm`
command, and an instruction block in whatever file each LLM tool actually reads.
That is what keeps every repo on the same workflow — improve a hook here and
every wired repo picks it up on its next run.

**Three scopes.** `infra-llm --global` installs the machine-wide layer into
Claude Code's config dir: the hooks, the `/infra-llm` command and the three
skills (`infra-llm-step`, `infra-llm-workflow`, `infra-llm-design`), covering
every project Claude Code opens. `infra-llm --init` prepares one repo — the
git-ignored `infra-llm/` state dirs, `.infra-llm.env`, the ignore entries, and
the instruction block in its `CLAUDE.md`. `infra-llm --agent` (alias `llmagent`)
wires the repo to carry the hooks itself, for when there is no machine-wide
install or when teammates and CI must get the workflow with the clone; it detects
the repo's LLM setups, pre-checks what it finds, installs the launcher on PATH
(hooks run non-interactively, so an alias won't do), merges hook entries without
touching the repo's own, and writes each agent's block. Don't wire both layers:
Claude Code merges user-level and project-level hooks, so a repo with both fires
everything twice. Re-running anything is safe — every piece is compared first and
rewritten only when it differs. `--uninstall` removes wiring and blocks,
`--docs` refreshes just the instructions, and `--no-git-guard` / `--no-vexp` skip
a guard.

**What the hooks do.** `UserPromptSubmit` registers a plan file named in the
prompt and injects the protocol. `Stop` auto-continues one step per turn until
every box is checked, then demands verification, giving up after 3 no-progress
continues. `SessionEnd` records what the session was asked to do.
`PreToolUse(Bash)` is the git guard: agent-run git writes are denied, read-only
git and everything else passes straight through. `PreToolUse(Grep|Glob)` denies
raw text search only while a healthy semantic-index daemon is running. Every
wired command is guarded with `command -v infra-llm`, so a machine without the
infra checkout is never blocked by a hook it can't run.

**Operating it.** `--status` (wiring, docs, active plan, git guard, sessions),
`--doctor` (can this machine run it — Linux/macOS/WSL), `--plan <slug>`,
`--steps`, `--verify`, `--code-review`, `--pull-request`, `--create-release`,
`--sessions`, `--worktrees`, `--skill <name>`. In Claude Code the same words are
one generated slash command: `/infra-llm review|pr|release|plan|steps|verify|
status|sessions|worktrees|doctor`. An `unknown command` in a terminal means the
shell sourced `git.sh` before that command existed — `infra-reload` fixes it.

**Per-repo tuning** lives in one git-ignored file at the repo root,
`.infra-llm.env`, written by `--init` with every line commented out so a fresh
repo behaves as if it weren't there. `VERIFY_CMD` is this repo's own checks —
without it verification runs nothing, because no build tool or framework is
assumed. `GIT_GUARD` (`deny` / `ask` / `off`) and `GIT_GUARD_ALLOW` set the guard
mode and the subcommands this repo lets through; destructive commands stay denied
regardless. `GIT_WINDOW_SECONDS` (default 1800, `0` to prepare only) is how long
`--pull-request` / `--create-release` may commit, push and tag — asking for a PR
is asking for the commit behind it, so those two open that window themselves
rather than making anyone relax the guard by hand.

**Adding to the workflow.** A new hook, brief or skill lands in the infra
checkout, not in a project — that is what keeps every repo on one workflow, and
it is why the generated copies in a repo are never edited in place. Write it
short, direct and paragraph-first; it is re-read on every run. Build skills,
instruction files and commands with the `skill-creator` skill rather than by
hand, since their description decides whether they trigger at all — but never for
a plan file, which you just write. Instruction text is the only thing that needs
redistributing afterwards: `infra-llm --docs` per repo.

**Environments.** Linux, macOS and WSL. Scripts are pinned to `#!/bin/bash` and
stay within a stock BSD userland and bash 3.2 (macOS ships 3.2 at that path, so
bash 4 syntax is off limits); line endings are pinned to LF so a Windows checkout
can't break the hooks. `infra-llm --doctor` reports the OS, the tools the hooks
need and the launcher on PATH, then runs every hook once in a scratch directory —
non-zero exit means something is genuinely broken on this machine.

**Worktrees.** Wiring is tracked, so every worktree of a wired repo is wired;
state is not, so each keeps its own plan and session history. That is what makes
one agent per worktree safe. `gwtadd` prepares a new worktree automatically;
`infra-llm --wt-prep` does it for one created another way.
