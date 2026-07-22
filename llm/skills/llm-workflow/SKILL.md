---
name: llm-workflow
description: Wire up, refresh, and operate the shared agent workflow (plan protocol, step stop-hooks, session records, vexp search guard) in whatever repository is currently open. Use when a repo has no infra-llm wiring yet, when the user asks to "set up the agent workflow / hooks / plan protocol here", or when asked what the step/plan/session tooling in this repo does and how to drive it.
---

# LLM workflow setup

The hooks live **once** in the infra repo (`llm/hooks`) and are never vendored
into a project. A repo only gets two things: hook wiring that shells out to the
`infra-llm` command, and an instruction block appended to the instruction file
each LLM tool actually reads.

## Wire up the current repository

```bash
infra-llm --init         # or the alias: llminit
```

It detects the repo's LLM setups, shows a selection (what it finds is
pre-checked), then:

| What                                    | Where                                                     |
| --------------------------------------- | ---------------------------------------------------------- |
| `infra-llm` launcher                     | `~/.local/bin/infra-llm` — hooks run in a non-interactive shell, so a real executable on PATH is required, not a shell alias |
| Claude hook wiring                       | `.claude/settings.json` (merged; existing hooks are kept)   |
| Codex hook wiring                        | `.codex/hooks.json`                                         |
| Protocol instructions                    | appended between `<!-- infra-llm:start -->` / `<!-- infra-llm:end -->` markers in each selected agent's file — `CLAUDE.md`, `AGENTS.md`, `.cursor/rules/infra-llm.mdc`, `.windsurf/rules/infra-llm.md`, `.github/copilot-instructions.md`, `GEMINI.md`, `.clinerules/infra-llm.md`, `CONVENTIONS.md` (legacy `.cursorrules` / `.windsurfrules` / `.clinerules` honoured when already used) |
| `plans/`, `.claude/sessions/`            | created empty, and added to `.gitignore`                     |

Nothing else is written. Re-running is safe: the block is left alone unless
`--force`/`--docs` is passed, and hook entries are keyed by command so they
never duplicate. `infra-llm --uninstall` removes the wiring and the block,
leaving `plans/` and session records in place.

Agents the repo shows no sign of are still listed unchecked, so you can adopt
one it doesn't use yet. Only Claude and Codex have a hook API; the others get
instructions only.

Non-interactive: `--claude --codex --cursor --windsurf --copilot --gemini
--cline --aider`, `--all`, `--yes`.

## What gets wired

- **UserPromptSubmit** → `infra-llm --hook prompt` — a prompt mentioning
  `plans/*.md` registers that file as the active plan and injects the protocol.
- **Stop** → `infra-llm --hook stop` — auto-continues one step per turn until
  every checkbox is `- [x]`, then demands verification. Gives up after 3
  no-progress continues.
- **SessionEnd** → `infra-llm --hook session` — writes
  `.claude/sessions/<session-id>.md` (date, id, every task the user asked for).
- **PreToolUse(Grep|Glob)** → `infra-llm --hook vexp` — denies raw text search
  only while a healthy `vexp` daemon is running; otherwise always allows, so
  repos without `.vexp` are unaffected.

Every wired command is written as
`command -v infra-llm >/dev/null 2>&1 && infra-llm --hook … || exit 0`, so a
checkout on a machine without the infra repo is never blocked by a hook it
cannot run.

## Operating it

Read `infra-llm --skill step-plan` for the protocol itself. Day-to-day:

```bash
infra-llm --status       # cli, wiring, instruction blocks, active plan, sessions
infra-llm --plan <slug>  # create plans/<slug>.md and register it
infra-llm --steps        # what the stop hook currently thinks the next step is
infra-llm --verify       # run the repo's checks and close out the plan
infra-llm --code-review  # review brief + scope of the recent changes
infra-llm --sessions     # list session records; --sessions <id> prints one
infra-llm --docs         # refresh the instruction block after infra changes
```

## Per-repo tuning

`.llm-verify.env` at the repo root (git-ignored, optional) is where a repo
declares its own checks. The workflow is project-agnostic — it never guesses a
build tool:

```bash
VERIFY_CMD="<this repo's lint/type-check/test command>"
```

Without `VERIFY_CMD` verification runs no checks at all — it just closes out
the plan. Nothing about the project is assumed: no build tool, no container
runtime, no framework, and no git operations.

## Changing the workflow

Edit the hooks in the infra repo (`llm/hooks/*`) — every wired repo picks the
change up on its next hook run, with no per-repo update step. Only the
instruction text needs redistributing: `infra-llm --docs` in each repo after
editing `llm/templates/instructions.md`.
