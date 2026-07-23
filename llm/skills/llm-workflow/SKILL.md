---
name: llm-workflow
description: Wire up, refresh, and operate the shared agent workflow (plan protocol, step stop-hooks, session records, git guard, search guard) in whatever repository is currently open. Use when a repo has no infra-llm wiring yet, when the user asks to "set up the agent workflow / hooks / plan protocol here", or when asked what the step/plan/session tooling in this repo does and how to drive it.
---

# LLM workflow setup

The hooks live **once** in the infra checkout and are never vendored into a
project. A repo gets only two things: hook wiring that shells out to the
`infra-llm` command, and an instruction block in whatever file each LLM tool
actually reads. That is what keeps every repo on the same workflow — improve a
hook here and every wired repo picks it up on its next run.

## Wire up the current repo

```bash
infra-llm --init         # alias: llminit
```

It detects the repo's LLM setups, pre-checks what it finds, then installs the
`infra-llm` launcher on PATH (hooks run non-interactively, so an alias won't
do), merges hook entries into the agent's config without touching the repo's own
hooks, appends the instruction block between its markers, and creates the
git-ignored state directories.

Re-running is safe — entries are keyed by command and the block is left alone
unless refreshed. `--uninstall` removes the wiring and the block; `--docs`
refreshes just the instructions. Non-interactive flags exist per agent, plus
`--all` / `--yes`, and `--no-git-guard` / `--no-vexp` to skip a guard.

Claude and Codex are the only agents with a hook API; the rest get instructions
only, written where that tool reads them.

## What gets wired

- **UserPromptSubmit** — a prompt naming a plan file registers it as active and
  injects the protocol.
- **Stop** — auto-continues one step per turn until every box is checked, then
  demands verification; gives up after 3 no-progress continues.
- **SessionEnd** — records what the session was asked to do.
- **PreToolUse(Bash)** — the git guard: denies agent-run git writes, passes
  read-only git and everything else straight through.
- **PreToolUse(Grep|Glob)** — denies raw text search only while a healthy
  semantic-index daemon is running; otherwise always allows.

Every wired command is guarded so a machine without the infra checkout is never
blocked by a hook it can't run.

## Operating it

```bash
infra-llm --status          # wiring, docs, active plan, git guard, sessions
infra-llm --doctor          # can this machine run it? (Linux / macOS / WSL)
infra-llm --plan <slug>     # create and register a plan
infra-llm --steps           # the next step the stop hook will demand
infra-llm --verify          # run the repo's checks and close out the plan
infra-llm --code-review     # review brief + scope of the recent changes
infra-llm --pull-request    # PR brief + branch, commits, existing PR
infra-llm --create-release  # release brief + tags, releases, commits since
infra-llm --sessions        # session records
infra-llm --worktrees       # every worktree with its own plan state
```

In Claude Code the same commands are one generated slash command,
`/infra-llm <what>` — `review`, `pr`, `release`, `plan`, `steps`, `verify`,
`status`, `sessions`, `worktrees`, `doctor`. One file per repo, skippable with
`--init --no-commands`. An `unknown command` in a terminal means the shell
sourced `git.sh` before that command existed; re-source it.

`infra-llm --skill step-plan` is the protocol itself. To strip a repo's own
duplicate workflow, copy the infra checkout's `plans/adopt-infra-llm.md` into
that repo's `plans/` and have its agent work through it.

Releases follow `vMAJOR.MINOR.PATCH`: `v1.0.1` bug fix, `v1.1.0` feature,
`v2.0.0` breaking.

## Adding to the workflow

A new hook, brief or skill lands in the infra checkout, not in a project — that
is what keeps every repo on one workflow, and it is why the generated copies in
a repo (the instruction block, installed skills and hooks) are never edited in
place: a refresh overwrites them and nobody else gets the change. Write it
short, specific and imperative; it is re-read on every run. Build skills,
instruction files and commands with the `skill-creator` plugin skill rather than
by hand, since their description is what decides whether they trigger at all —
but never for a plan file, which you just write. Instruction text is the only
thing that needs redistributing afterwards: `infra-llm --docs` per repo.

## Per-repo tuning

One git-ignored settings file at the repo root, `.infra-llm.env`, written by
`--init` with every line commented out — so a fresh repo behaves as if it
weren't there:

- `VERIFY_CMD` — this repo's own checks. Without it verification runs nothing,
  because no build tool or framework is assumed.
- `GIT_GUARD` / `GIT_GUARD_ALLOW` — guard mode (deny / ask / off) and the
  subcommands this repo lets through. Destructive commands stay denied
  regardless.
- `GIT_WINDOW_SECONDS` — how long `--pull-request` / `--create-release` may
  commit, push and tag without asking (default 1800, `0` to prepare only).
  Asking for a PR is asking for the commit behind it, so those two commands open
  that window themselves rather than making anyone relax the guard by hand.

## Environments

Linux, macOS and WSL. Scripts are pinned to `#!/bin/bash` and stay within a
stock BSD userland and bash 3.2 — macOS ships 3.2 at that path, so bash 4 syntax
is off limits. Line endings are pinned to LF so a Windows checkout can't break
the hooks.
`infra-llm --doctor` reports the OS, the tools the hooks need, the launcher on
PATH, and runs every hook once in a scratch directory — non-zero exit means
something is genuinely broken on this machine.

## Worktrees

Wiring is tracked, so every worktree of a wired repo is wired; state is not, so
each worktree keeps its own plan and session history. That is what makes one
agent per worktree safe. `gwtadd` prepares a new worktree automatically;
`infra-llm --wt-prep` does it for one created another way.
