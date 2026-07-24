#!/bin/bash
# UserPromptSubmit hook (Claude Code + Codex): when the user's prompt
# references a plan file (infra-llm/plans/feature.md, or one of the older
# layouts in a repo that has not migrated), register it in <plans>/.active-plan
# and inject the step-by-step protocol:
# progress is tracked with checkboxes directly in that plan file. Plain
# stdout is added as context by both Claude Code and Codex; empty output
# injects nothing.
INPUT=$(cat)

refs=$(printf '%s' "$INPUT" \
  | grep -oE '(infra-llm/plans|infra-llm-plans|plans)/[A-Za-z0-9._ -]+\.md' | sort -u)
[ -z "$refs" ] && exit 0

. "$(dirname "$0")/state-dirs.sh"
PLANS="$(llm_plans_dir)"
mkdir -p "$PLANS"
ACTIVE="$PLANS/.active-plan"
touch "$ACTIVE"
while IFS= read -r ref; do
  grep -qxF "$ref" "$ACTIVE" || printf '%s\n' "$ref" >> "$ACTIVE"
done <<< "$refs"

refs_line=$(printf '%s' "$refs" | paste -sd ' ' -)

cat <<EOF
STEP-BY-STEP PROTOCOL (this prompt references plan file(s): $refs_line — now registered in $ACTIVE)

1. Read the plan file(s) and convert EVERY discrete item into its own
   '- [ ]' checkbox, editing the file in place — the plan file itself is the
   working checklist; do not create a separate progress file. Each checkbox is
   one short, specific line naming a concrete outcome; detail goes underneath.
2. Implement exactly ONE unchecked step per turn (token budgeting). Mark it
   '- [x]' in the plan file when finished, then stop — the Stop hook
   auto-continues you into the next step so nothing is missed.
3. When every step is checked, run: infra-llm --verify
   (the repo's own VERIFY_CMD if it has one, container-log check, code-review
   gate) and fix failures until it prints VERIFY OK — on success it clears
   the active-plan marker so the session can end.

Anything you write for a later agent to follow — plan, instructions, skill,
brief — stays short, specific and imperative. Write the plan file directly:
skill-creator is for skills, instruction files and commands when the user asks
for one, never for planning.
EOF
exit 0
