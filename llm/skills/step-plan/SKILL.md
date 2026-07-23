---
name: step-plan
description: Step-by-step execution protocol for this repository — track any multi-step task with checkboxes directly in a plan file under plans/ (registered in plans/.active-plan), implement exactly one step per turn for token budgeting, and finish with the verification gate. Use at the START of any task with more than one step (a feature, a batch of fixes, a refactor, a migration, a client feedback list) and whenever an unfinished active plan exists (resume it before starting anything new).
---

# Step plan protocol

Multi-step work is tracked with `- [ ]` / `- [x]` checkboxes **inside the plan
file itself** — there is no separate progress file. One step per turn bounds the
work per turn and makes it impossible to silently drop something the user asked
for. Stop hooks enforce it; they live in the infra checkout and run through
`infra-llm`, so editing them changes every wired repo.

Use it for any task that decomposes into more than one completable step. Skip it
for a one-line change or a conversational answer.

## 1 — Plan

- An active plan with unchecked boxes wins: resume it, don't start over.
- Given a plan file, convert **every** discrete item into its own `- [ ]`
  checkbox, in place. Write each line short, specific and concrete — it names an
  outcome, not a topic — because the stop hook reads it back to you as the next
  step and that line is all the context you get. Detail goes underneath.
- For ad-hoc work, `infra-llm --plan <slug>` creates and registers one. Size each
  step to fit one focused turn.

## 2 — Execute

- Implement exactly **one** unchecked step, completely, touching only what it
  needs. Mark it `- [x]` and stop — the stop hook feeds you the next one, so
  starting it early only makes the turn harder to review.
- Never batch steps; never delete one. An unnecessary step is marked
  `- [x] … (skipped: reason)` so the record stays honest.
- Verify what you changed where it matters — a green type-check is not proof a
  feature works. For a step with a real UI surface, exercise it in the browser
  (screenshot, console, the actual flow). Skip that for copy tweaks, constants,
  type-only edits or pure refactors.

## 3 — Finish

Run `infra-llm --verify` when every box is checked. It runs whatever checks this
repo declares and nothing otherwise — no build tool, runtime or framework is
assumed. If the repo clearly has checks worth running and none are configured,
say so and offer to add them rather than inventing a command. Re-run until it
prints `VERIFY OK`; that is what lets the session end.

Review is **not** part of this gate — `infra-llm --code-review` is on request.

## Writing for the next agent

Plans, instruction blocks, skills and briefs are re-read on every future run, so
length is a recurring cost. Keep them short, specific and imperative: say what
to do and why it matters, then stop. Explaining the reason beats stacking MUSTs.

Write plan files yourself, directly — planning is not a skill-authoring task.
`skill-creator` belongs to the other case: when the user asks for a skill, an
instruction file or a command, it gets the description right, and that field
decides whether the thing triggers at all.

## Guardrails

- Git state is the user's: no commit, push, merge, rebase, reset, branch or tag
  from the agent. Finish in the working tree and report what changed. Read-only
  git is encouraged, and the guard hook enforces the rest.
- Never edit the generated infra-llm content in a repo — the instruction block
  between its markers, or a skill or hook it installed. Those are copies: edits
  are lost on the next refresh and never reach the other repos. Fix the source
  in the infra checkout, or say what needs fixing.
- The stop hook gives up after 3 no-progress continues — if you hit that, say
  what is blocking you instead of spinning.
- Plan state is per worktree, so parallel agents don't collide. Stay in the
  worktree you were started in; `infra-llm --worktrees` shows the rest.
- `infra-llm --skill llm-workflow` explains the wiring; session records recover
  what an earlier session was asked to do.
