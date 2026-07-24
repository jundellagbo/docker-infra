# Cross-agent step protocol hooks

Shared machinery for the step-by-step execution protocol: every agent that can
run a command hook — Claude Code, Codex, anything else — works one step per turn
through the plan file being implemented, auto-continues to the next step, and
finishes at a verification gate. These scripts stay here and are never copied
into a project; a repo only wires `.claude/settings.json` / `.codex/hooks.json`
to call `infra-llm --hook <name>`, so editing one changes every wired repo
immediately.

**State.** `infra-llm/plans/.active-plan` lists one plan-file path per line,
registered by `plan-prompt.sh` when a prompt references a plan file or by the
agent for ad-hoc tasks, and cleared by `verify-build.sh` once every registered
plan is fully checked and the checks pass. There is no separate progress file —
the plan file IS the checklist, and everything under `infra-llm/` is git-ignored.

| Hook | Script | What it does |
| --- | --- | --- |
| `prompt` | `plan-prompt.sh` | `UserPromptSubmit` (Claude + Codex): registers plan files named in the prompt and injects the protocol |
| `stop` | `steps-stop.sh` | Claude `Stop`: returns `{"decision":"block"}` with the next step, or demands verification |
| `codex-stop` | `codex-stop.sh` | Codex `Stop`: returns `{"continue":false,"stopReason":…}` to auto-continue |
| `session` | `session-record.sh` | `SessionEnd`: writes `infra-llm/sessions/<id>.md` (date, id, every task asked for), keeping the 10 most recent |
| `git-guard` | `git-guard.sh` | `PreToolUse(Bash)`: denies agent-run git writes; read-only git and non-git commands pass through |
| `vexp` | `vexp-guard.sh` | `PreToolUse(Grep\|Glob)`: denies raw text search only while a healthy `vexp` daemon runs |
| `steps` | `steps-status.sh` | Prints `NO_PLAN`, `UNPLANNED\|<file>`, `REMAINING\|<file>\|<n>\|<next>` or `NEEDS_VERIFY\|<file>` |
| `verify` | `verify-build.sh` | Runs `VERIFY_CMD` (nothing if unset — no build tool or runtime is assumed) and clears `.active-plan` |

`steps-guard.sh <agent>` sits behind the stop hooks as the stall guard: it counts
consecutive auto-continues with the active plan set unchanged, and the adapters
give up past 3 so a stuck agent can't loop forever.

**Per-repo tuning** is one git-ignored file at the repo root, written by
`infra-llm --init` with everything commented out — `VERIFY_CMD` (unset = no
checks), `GIT_GUARD` (`deny` / `ask` / `off`) with `GIT_GUARD_ALLOW`, and
`GIT_WINDOW_SECONDS` (how long a PR/release may commit and push; `0` = never).
Destructive git stays denied unless the guard is `off`. Nothing else is read, and
`--init` warns when an older `infra-llm.env` / `.llm-verify.env` / `.llm-git.env`
is still lying around so its settings can be moved over.

**Lifecycle.** A prompt mentions a plan file (or the agent registers one) → it is
listed in `.active-plan` → the agent converts every discrete item into its own
`- [ ]` checkbox in place → it implements ONE step, marks it `- [x]` and stops,
and the stop hook blocks that stop and points at the next unchecked step → with
every box checked the hook demands `infra-llm --verify`, which on success clears
`.active-plan`. With no plan registered the stop hooks are silent and the session
ends normally.

**Wiring.** Claude Code registers `SessionEnd`, `UserPromptSubmit`, `Stop` and
both `PreToolUse` guards in `.claude/settings.json`; Codex registers
`UserPromptSubmit` → `prompt` and `Stop` → `codex-stop` in `.codex/hooks.json`
(its hooks are experimental and disabled on Windows — the `AGENTS.md` protocol
still applies without them). Every entry is guarded by `command -v infra-llm`, so
a machine without the infra checkout is never blocked by a hook it can't run.
