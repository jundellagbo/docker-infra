#!/bin/bash
# git-guard: PreToolUse(Bash) guard - git state is the USER's decision.
#
# The agent edits files; committing, pushing, merging, resetting, tagging and
# friends stay with the user. This denies those subcommands and lets read-only
# git (status/log/diff/show/blame/branch listing/…) fall through untouched, so
# normal permission behaviour is preserved for everything else - the hook never
# auto-approves an arbitrary command.
#
# Per-repo tuning, all optional, in "<repo>/.infra-llm.env" (git-ignored,
# written by infra-llm --init). That file is the only one read:
#
#   GIT_GUARD=deny   # default - deny mutating git from the agent
#   GIT_GUARD=ask    # let the user confirm each mutating git command instead
#   GIT_GUARD=off    # guard disabled (destructive commands still denied)
#   GIT_GUARD_ALLOW="tag stash"   # subcommands to let through in this repo
#
# `infra-llm --pull-request` / `--create-release` open a time-boxed window
# (plans/.git-window) in which commit/push/tag/branch are allowed without any
# config change, because asking for a PR or a release is asking for those.
#
# GIT_GUARD / GIT_GUARD_ALLOW in the environment win over the file, so a repo
# can be relaxed for one session without editing anything.
#
# Destructive, hard-to-undo commands (force push, reset --hard, clean -f,
# history rewriting, branch -D, …) are denied in "deny" and "ask" mode no matter
# what GIT_GUARD_ALLOW says; only GIT_GUARD=off silences them.
set -uo pipefail

proj="${CLAUDE_PROJECT_DIR:-${CODEX_PROJECT_DIR:-$PWD}}"

# ------------------------------------------------------------------ the command

input="$(cat 2>/dev/null)"
if command -v jq >/dev/null 2>&1; then
  cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null)"
else
  # No jq: a crude extraction is better than failing open on every command.
  cmd="$(printf '%s' "$input" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p' | head -1)"
fi
[ -n "$cmd" ] || exit 0

# ----------------------------------------------------------------- config

# Captured before sourcing: a value already in the environment beats the file.
env_mode="${GIT_GUARD:-}"
env_allow="${GIT_GUARD_ALLOW:-}"
mode="deny"
allow=""
if [ -f "$proj/.infra-llm.env" ]; then
  # eval'd through tr, not sourced, so a CRLF settings file can't smuggle a
  # carriage return into the mode and silently turn the guard off.
  eval "$(tr -d '\r' < "$proj/.infra-llm.env")" 2>/dev/null || true
  mode="${GIT_GUARD:-$mode}"
  allow="${GIT_GUARD_ALLOW:-$allow}"
fi
mode="${env_mode:-$mode}"
allow="${env_allow:-$allow}"

case "$mode" in
  off|none|0|false) exit 0 ;;
  ask|deny)         ;;
  *)                mode="deny" ;;
esac

# ------------------------------------------------------- authorization window
#
# Asking for a pull request or a release IS asking for a commit and a push, so
# those two commands open a short window here and the agent just does the work -
# no config to edit, nothing to revert afterwards, and no argument with the
# guard mid-flow. Everyday git writes outside the window stay denied, and the
# destructive set below stays denied even inside it.
window="$proj/plans/.git-window"
window_open=0
window_why=""
if [ -f "$window" ]; then
  # file holds: <expiry-epoch> <what opened it>
  read -r w_exp w_why < "$window" 2>/dev/null || true
  now="$(date +%s 2>/dev/null || echo 0)"
  case "$w_exp" in
    ''|*[!0-9]*) rm -f "$window" ;;
    *) if [ "$now" -lt "$w_exp" ]; then
         window_open=1; window_why="${w_why:-a workflow command}"
       else
         rm -f "$window"   # expired - never leave a stale grant lying around
       fi ;;
  esac
fi

# ----------------------------------------------------------------- matching

# git subcommands that change repository state. Read-only git is absent on
# purpose and never matches.
mutating='commit|push|merge|rebase|reset|revert|cherry-pick|tag|stash|clean|am|apply|checkout|switch|restore|filter-branch|filter-repo|remote|submodule|worktree|gc|prune|reflog|update-ref|notes|replace|fast-import'

# "git", optionally with its own -c/-C/--flags, then the subcommand.
git_re="(^|[^[:alnum:]_./-])git([[:space:]]+(-c[[:space:]]+[^[:space:]]+|-C[[:space:]]+[^[:space:]]+|--[^[:space:]]+|-[^[:space:]]+))*[[:space:]]+"

matched=""
for sub in $(printf '%s' "$mutating" | tr '|' ' '); do
  if printf '%s' "$cmd" | grep -qE "${git_re}${sub}([[:space:]]|$)"; then
    matched="$sub"
    break
  fi
done

# Subcommands that only mutate with a flag - listing them is read-only.
if [ -n "$matched" ]; then
  case "$matched" in
    remote|submodule|worktree|notes|reflog)
      printf '%s' "$cmd" | grep -qE "${git_re}${matched}[[:space:]]+(add|rm|remove|set-url|set-head|rename|prune|move|expire|delete|deinit|update|sync|init|absorb)([[:space:]]|$)" || matched="" ;;
    prune)
      # "git prune" only; "git remote prune" was handled above
      ;;
  esac
fi

if [ -z "$matched" ]; then
  # Not a mutating git command (or read-only usage) - no decision, normal flow.
  exit 0
fi

# Destructive/irreversible - denied even in "ask" mode and even if allow-listed.
destructive=0
if printf '%s' "$cmd" | grep -qE "${git_re}push([[:space:]]+[^[:space:]]+)*[[:space:]]+(-f|--force|--force-with-lease|--delete|--mirror)" \
  || printf '%s' "$cmd" | grep -qE "${git_re}reset([[:space:]]+[^[:space:]]+)*[[:space:]]+--hard" \
  || printf '%s' "$cmd" | grep -qE "${git_re}clean([[:space:]]+-[^[:space:]]*[fdx][^[:space:]]*)" \
  || printf '%s' "$cmd" | grep -qE "${git_re}(filter-branch|filter-repo|fast-import)" \
  || printf '%s' "$cmd" | grep -qE "${git_re}branch([[:space:]]+[^[:space:]]+)*[[:space:]]+-D" \
  || printf '%s' "$cmd" | grep -qE "${git_re}checkout([[:space:]]+[^[:space:]]+)*[[:space:]]+(-f|--force|--|\.)" \
  || printf '%s' "$cmd" | grep -qE "${git_re}restore([[:space:]]|$)" \
  || printf '%s' "$cmd" | grep -qE "${git_re}(reflog[[:space:]]+expire|gc[[:space:]]+--prune|update-ref[[:space:]]+-d)" ; then
  destructive=1
fi

# Allow-listed for this repo, or inside the window a PR/release opened. Neither
# covers the destructive set.
if [ "$destructive" -eq 0 ]; then
  for ok in $allow; do
    [ "$ok" = "$matched" ] && exit 0
  done
  if [ "$window_open" -eq 1 ]; then
    case "$matched" in
      commit|push|tag|checkout|switch|merge) exit 0 ;;
    esac
  fi
fi

# ------------------------------------------------------------------- decision

decide() {
  # $1 = allow|deny|ask, $2 = reason
  local reason
  if command -v jq >/dev/null 2>&1; then
    reason="$(printf '%s' "$2" | jq -Rs .)"
  else
    reason="\"$(printf '%s' "$2" | tr '\n' ' ' | sed 's/["\\]/ /g')\""
  fi
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":%s}}' "$1" "$reason"
  exit 0
}

hint="Make the file changes only and say what changed; the user reviews and runs git themselves (in Claude Code they can type '! git add -A && git commit'). To open a PR or cut a release, run 'infra-llm --pull-request' / 'infra-llm --create-release' and follow the brief."

if [ "$destructive" -eq 1 ]; then
  decide deny "Blocked: '${matched}' here is destructive/irreversible (force push, hard reset, clean, history rewrite, branch delete, discarding working-tree changes). The agent must never run it. $hint"
fi

if [ "$mode" = "ask" ]; then
  decide ask "'git ${matched}' changes repository state, which is the user's decision. Approve only if the user asked for it."
fi

decide deny "Git state is the user's decision - the agent must not run 'git ${matched}' (or commit/push/merge/rebase/reset/tag/stash/checkout). Read-only git (status/log/diff/show/blame) is allowed. $hint"
