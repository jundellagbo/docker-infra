# Cross-agent step protocol hooks

Shared machinery for the step-by-step execution protocol. It makes every agent
— Claude Code, Codex, and anything else that can run a command hook — work one
step per turn through the plan file being implemented (checkboxes tracked in
that file itself), auto-continue to the next step, and finish with a
verification gate.

These scripts stay here in the infra repo — they are never copied into a
project. `infra-llm --init` only wires a repo's `.claude/settings.json` /
`.codex/hooks.json` to call `infra-llm --hook <name>`, which dispatches to the
script below. Editing one changes the behaviour for every wired repo
immediately.

## State

`plans/.active-plan` — one plan-file path per line (e.g. `plans/feature.md`).
Registered automatically by `plan-prompt.sh` when a prompt references a
`plans/*.md` file, or manually by the agent for ad-hoc tasks. Cleared by
`verify-build.sh` when every registered plan is fully checked and the checks
pass. No separate progress file exists — the plan file IS the checklist.
Everything under `plans/` is git-ignored.

## Shared scripts (`llm/hooks/`, via `infra-llm --hook`)

| Script                   | Purpose                                                                                                                                    |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `plan-prompt.sh`         | `UserPromptSubmit` adapter (Claude + Codex): detects `plans/*.md` references in the prompt, registers them in `plans/.active-plan`, and injects the protocol. |
| `steps-status.sh`        | Reads `plans/.active-plan`; prints `NO_PLAN`, `UNPLANNED\|<file>`, `REMAINING\|<file>\|<n>\|<next step>`, or `NEEDS_VERIFY\|<file>`.        |
| `steps-guard.sh <agent>` | Stall guard: counts consecutive auto-continues with the active plan set unchanged. Adapters give up past 3 so a stuck agent can't loop forever. |
| `verify-build.sh`        | Runs the repo's own checks (`VERIFY_CMD` from `.infra-llm.env`; nothing at all if unset — no build tool, container runtime or git operation is assumed) and clears `plans/.active-plan` when every step is checked. |
| `codex-stop.sh`          | Codex Stop-hook adapter — returns `{"continue": false, "stopReason": …}` to auto-continue.                                                  |

| Hook name (`infra-llm --hook …`) | Script            |
| -------------------------------- | ------------------ |
| `prompt`                         | `plan-prompt.sh`   |
| `stop`                           | `steps-stop.sh`    |
| `codex-stop`                     | `codex-stop.sh`    |
| `session`                        | `session-record.sh`|
| `vexp`                           | `vexp-guard.sh`    |
| `git-guard`                      | `git-guard.sh`     |
| `steps` / `verify`               | `steps-status.sh` / `verify-build.sh` |

## Claude adapters

| Script              | Purpose                                                                                              |
| ------------------- | ------------------------------------------------------------------------------------------------------ |
| `steps-stop.sh`     | `Stop` hook — returns `{"decision": "block", …}` with the next step, or demands verification.          |
| `session-record.sh` | `SessionEnd` hook — writes `.claude/sessions/<session-id>.md` (date, id, every task asked for); keeps the 10 most recent. |
| `vexp-guard.sh`     | `PreToolUse(Grep\|Glob)` — denies raw text search only while a healthy `vexp` daemon runs; otherwise allows. |
| `git-guard.sh`      | `PreToolUse(Bash)` — denies agent-run git writes (commit/push/merge/reset/tag/…); read-only git and non-git commands pass through. Mode per repo via `.infra-llm.env` (`GIT_GUARD=deny\|ask\|off`, `GIT_GUARD_ALLOW`); destructive commands stay denied unless `off`. |

## Per-agent wiring

- **Claude Code** — `.claude/settings.json` registers `SessionEnd`,
  `UserPromptSubmit`, `Stop` and `PreToolUse` (`Bash` git guard, `Grep|Glob`
  search guard) hooks, each calling
  `infra-llm --hook …` guarded by `command -v infra-llm` so a machine without
  the infra repo is never blocked. Instructions: the block appended to the
  repo's `CLAUDE.md`, plus `infra-llm --skill step-plan`.
- **Codex** — `.codex/hooks.json` registers `UserPromptSubmit` →
  `infra-llm --hook prompt` and `Stop` → `infra-llm --hook codex-stop`.
  Instructions live in the block appended to `AGENTS.md`. Codex hooks are experimental and disabled on Windows; the
  `AGENTS.md` protocol still applies without them.

## Per-repo tuning

One file at the repo root, git-ignored, written by `infra-llm --init` with
everything commented out — every setting is optional:

```bash
# .infra-llm.env
VERIFY_CMD="<this repo's lint/type-check/test command>"  # unset = no checks
GIT_GUARD=deny                # ask = confirm each one, off = guard disabled
GIT_GUARD_ALLOW="tag stash"   # subcommands this repo lets the agent run
```

Nothing else is read — a repo has this file or it has no settings. `--init`
warns when an older `infra-llm.env` / `.llm-verify.env` / `.llm-git.env` is
still lying around so its settings can be moved over.

## Lifecycle of a task

1. A prompt mentions `plans/feature.md` (or the agent registers a plan itself)
   → the file is listed in `plans/.active-plan`.
2. The agent converts every discrete item in the plan file into its own `- [ ]`
   checkbox, in place.
3. The agent implements ONE step, marks it `- [x]`, stops; the stop hook blocks
   the stop and points at the next unchecked step.
4. When all steps are checked, the stop hook demands
   `infra-llm --verify`; on success the script clears
   `plans/.active-plan`.
5. With no active plan registered, the step stop hooks are silent and the
   session ends normally.
