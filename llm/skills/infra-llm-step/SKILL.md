---
name: infra-llm-step
description: The step-by-step execution protocol for this machine - track multi-step work as checkboxes written directly into a plan file under infra-llm/plans/, implement exactly one step per turn, and close out with the verification gate. Use this at the START of any task with more than one step (a feature, a batch of fixes, a refactor, a migration, a list of client feedback, anything the user numbered) and whenever an unfinished active plan already exists, which is resumed before anything new begins - even if the user never says "plan".
---

# Step plan protocol

Multi-step work is tracked as `- [ ]` / `- [x]` checkboxes **inside the plan file
itself**; there is no separate progress file. One step per turn bounds the work
per turn and makes it impossible to silently drop something the user asked for.
Stop hooks enforce it — they live in the infra checkout and run through
`infra-llm`, so editing one changes every wired repo. Use this for any task that
decomposes into more than one completable step; skip it for a one-line change or
a conversational answer.

**Plan.** An active plan with unchecked boxes wins: resume it, don't start over.
Given a plan file, convert **every** discrete item into its own `- [ ]` checkbox,
in place. Each line is short, specific and names an outcome rather than a topic,
because the stop hook reads that line back to you as the next step and it is all
the context you get — detail goes underneath it. `infra-llm --plan <slug>`
creates and registers one for ad-hoc work. Size each step to fit one focused
turn.

**Execute.** Implement exactly **one** unchecked step, completely, touching only
what it needs; mark it `- [x]` and stop. The stop hook feeds you the next one, so
starting it early only makes the turn harder to review. Never batch steps and
never delete one — something unnecessary is marked `- [x] … (skipped: reason)` so
the record stays honest. Verify what you changed where it matters: a green
type-check is not proof a feature works, so exercise a real UI surface in the
browser (screenshot, console, the actual flow) and skip that for copy tweaks,
constants, type-only edits or pure refactors.

**Finish.** Run `infra-llm --verify` when every box is checked. It runs whatever
checks this repo declares and nothing otherwise — no build tool, runtime or
framework is assumed. If the repo clearly has checks worth running and none are
configured, say so and offer to add them rather than inventing a command. Re-run
until it prints `VERIFY OK`; that is what lets the session end. Review is **not**
part of this gate — `infra-llm --code-review` is on request.

**Writing for the next agent.** Plans, instruction blocks, skills and briefs are
re-read on every future run, so length is a recurring cost. Keep them short,
direct and paragraph-first: say what to do and why it matters, then stop.
Explaining the reason beats stacking MUSTs. Write plan files yourself — planning
is not a skill-authoring task; `skill-creator` belongs to the other case, when
the user asks for a skill, an instruction file or a command, where the
description field decides whether the thing triggers at all.

**Guardrails.** Git state is the user's: no commit, push, merge, rebase, reset,
branch or tag from the agent. Finish in the working tree and report what changed;
read-only git is encouraged and the guard hook enforces the rest. Never edit the
generated infra-llm content in a repo — the instruction block between its
markers, or a skill or hook it installed — because those are copies whose edits
are lost on the next refresh and never reach the other repos; fix the source in
the infra checkout or say what needs fixing. The stop hook gives up after 3
no-progress continues, so if you hit that, say what is blocking you instead of
spinning. Plan state is per worktree: stay in the worktree you were started in,
and `infra-llm --worktrees` shows the rest. `infra-llm --skill
infra-llm-workflow` explains the wiring, and session records recover what an
earlier session was asked to do.
