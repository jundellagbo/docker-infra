---
name: step-plan
description: Step-by-step execution protocol for this repository — track any multi-step task with checkboxes directly in a plan file under plans/ (registered in plans/.active-plan), implement exactly one step per turn for token budgeting, and finish with the verification gate (project checks, container logs, code review). Use at the START of any task with more than one step (a feature, a batch of fixes, a refactor, a migration, a client feedback list) and whenever an unfinished active plan exists (resume it before starting anything new).
---

# Step plan protocol

Multi-step work is tracked with `- [ ]` / `- [x]` checkboxes **directly in the
plan file being implemented** — there is no separate progress file. Stop hooks
for Claude and Codex enforce it via `plans/.active-plan` (one plan-file path
per line, git-ignored). Working one step per turn bounds token usage per turn
and guarantees no requested item is silently dropped.

The hooks that enforce this are not vendored into the repo — they live in the
infra checkout and run through the `infra-llm` command, wired into
`.claude/settings.json` / `.codex/hooks.json` by `infra-llm --init`. Editing
them changes the workflow for every repo, so don't, unless that is the intent.

## When to use

- The user hands you a plan/feedback file (`plans/*.md`) to implement.
- Any task that decomposes into more than one independently-completable step.
- Resuming: if `plans/.active-plan` lists a plan with unchecked boxes, finish
  it before starting new work.

Skip it for a single conversational answer or a one-line change.

## 1 — Plan (turn one)

1. If `plans/.active-plan` already lists a plan with unchecked boxes, **resume
   that** — don't start over.
2. When the task is "implement this plan file" (any `plans/*.md`), read it and
   convert **EVERY** discrete item into its own `- [ ]` checkbox, editing the
   file in place — it becomes the working checklist. Leave prose/detail under
   each checkbox; the checkbox line itself should be a clear one-line summary
   (the Stop hook reads it to tell you the next step). The `UserPromptSubmit`
   hook auto-registers the file in `plans/.active-plan` whenever a prompt
   mentions a `plans/*.md` file.
3. For an ad-hoc multi-step task with no plan file, create one and register it:

   ```bash
   infra-llm --plan <task-slug>
   ```

   Every discrete thing the user asked for gets its own checkbox. Size each
   step to fit comfortably in one focused turn.

## 2 — Execute (one step per turn)

- Implement exactly **ONE** unchecked step, completely. Keep the change scoped
  to that step; touch only what it needs.
- Mark it `- [x]` in the plan file, then **stop**. The Stop hook
  (`infra-llm --hook stop`) blocks the stop and feeds you the next step,
  so you don't need to start it in the same turn.
- Never batch several steps into one turn, and never skip one silently — an
  unnecessary step is marked `- [x] … (skipped: reason)`, not deleted.
- Verify behaviour as you go where it matters — a green type-check is not proof
  the change works. For a step that changes a **feature or the UI**, exercise it
  in the browser (Chrome DevTools MCP or the `claude-in-chrome` tools): load the
  affected page, run the flow, screenshot, check the console. If the page is
  login-gated, open the login page and ask the user to enter their credentials
  themselves, then ask whether they're done before continuing. **Skip the
  browser** for steps with no runtime surface (copy tweaks, a single
  style/constant, type-only edits, pure refactors).

## 3 — Finish (verification)

When every box is checked, the Stop hook demands verification. Run:

```bash
infra-llm --verify
```

It runs this repo's own checks — whatever `VERIFY_CMD` in `.llm-verify.env`
says, and nothing at all if that isn't set. No build tool, container runtime or
framework is assumed, so this works the same in a Laravel app, a static site or
a shell-script repo. If the repo has checks worth running and no `VERIFY_CMD`
yet, say so and offer to add one — don't invent a command and run it yourself.

When the checks pass and no unchecked steps remain it clears
`plans/.active-plan`, which is what lets the session end. Re-run until it prints
`VERIFY OK`.

Reviewing is **not** part of this gate. If the user wants the change reviewed,
run `infra-llm --code-review` (see below).

## Git

Do **not** run repository-mutating git commands — `commit`, `push`, `merge`,
`rebase`, `reset`, branch/tag creation, stashing — unless the user explicitly
asks for it. Finish the work in the working tree and report what changed; the
user decides when it gets committed. Read-only git is fine.

## Code review

`infra-llm --code-review` prints the review brief (correctness, security, data
safety, implementation quality, tests) plus the scope of the recent changes —
uncommitted work and anything ahead of the base branch. Pass paths or a git
range to review something else.

Verify each finding, then **fix it yourself** — minimal, targeted changes only,
plus a behaviour-preserving refactor where the code genuinely needs one (never
style churn, never outside the reviewed change). Report what you fixed
(file:line + failure scenario), what you refactored, and what you left alone
with the reason; stop and describe rather than apply when a fix is large or
would change intended behaviour. Re-run `infra-llm --verify` afterwards.

## Guardrails

- The Stop hook gives up after **3** consecutive auto-continues with no change
  to the plan, so a stuck agent can't loop forever — if you hit that, say what
  is blocking you instead of spinning.
- Everything under `plans/` is git-ignored (the active-plan marker, the guard
  counters, and the plan files themselves).
- `infra-llm --skill llm-workflow` explains the wiring itself.
- Plan state is **per worktree** (`plans/` is untracked), so parallel agents in
  different worktrees never share an active plan. Stay inside the worktree you
  were started in; `infra-llm --worktrees` shows what each one is working on.
- Session records land in `.claude/sessions/<session-id>.md` (last 10 sessions,
  written by the `SessionEnd` hook) — read them to recover what a previous
  session was asked to do.
