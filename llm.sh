#!/bin/bash

# Shared LLM/agent workflow - the companion to git.sh.
#
# The workflow (plan protocol, step stop-hooks, session records, vexp search
# guard) lives HERE in the infra repo under llm/ and is never vendored into a
# project. A project only gets: hook wiring that calls the "infra-llm" command,
# and an instruction block appended to its own CLAUDE.md / AGENTS.md / GEMINI.md
# telling the agent which commands to use.
#
#   infra-llm --init            # detect the repo's LLM setups, pick, wire up
#   infra-llm --docs            # re-append/refresh only the instruction blocks
#   infra-llm --status          # wiring + active plan + session records
#   infra-llm --doctor          # does this machine (Linux/macOS/WSL) support it?
#   infra-llm --plan <slug>     # create plans/<slug>.md and register it
#   infra-llm --steps           # what the stop hook thinks the next step is
#   infra-llm --verify [args]   # run the verification gate
#   infra-llm --sessions [id]   # list/print session records
#   infra-llm --code-review     # review brief + scope of the recent changes
#   infra-llm --pull-request    # PR brief + branch/commit/PR state
#   infra-llm --create-release  # release brief + tag/release state
#   infra-llm --worktrees       # every worktree with its own plan state
#   infra-llm --skill [name]    # print a protocol skill (step-plan, llm-workflow)
#   infra-llm --designer        # add the design-review skill (--remove to drop it)
#   infra-llm --hook <name>     # run a hook (used by the wiring, not by hand)
#   infra-llm --uninstall       # remove wiring + instruction blocks again
#
# --init inspects the repo for every LLM setup it knows (Claude Code, Codex,
# Cursor, Windsurf, Copilot, Gemini, Cline/Roo, Aider) and offers a selection -
# what it finds is pre-selected, and the rest can still be picked to adopt an
# agent the repo does not use yet. Non-interactively pass the agents instead:
#
#   infra-llm --init --claude --cursor     # explicit (one flag per agent)
#   infra-llm --init --all --yes           # everything, no prompt
#   infra-llm --init --force               # rewrite an existing instruction block
#   infra-llm --init --no-git-guard        # skip the git guard (--no-vexp likewise)
#   infra-llm --init --no-commands         # generate no slash command at all
#
# Source it from a shell (git.sh does) for the short aliases:
#   llminit  llmdocs  llmstatus  llmplan  llmsteps  llmverify  llmsessions
#   llmreview  llmpr  llmrelease  llmskill  llmwt  llmdesigner  llmdoctor
#   claude_session   (claude, with session recording wired up first)

# Where this infra checkout lives - resolved whether sourced or executed
if [ -n "${BASH_SOURCE[0]}" ]; then
  LLM_INFRA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
  LLM_INFRA_DIR="$(cd "$(dirname "$0")" && pwd)"
fi
export LLM_INFRA_DIR
LLM_HOOKS_DIR="${LLM_INFRA_DIR}/llm/hooks"
LLM_SKILLS_DIR="${LLM_INFRA_DIR}/llm/skills"
LLM_TEMPLATE="${LLM_INFRA_DIR}/llm/templates/instructions.md"
# Where the infra-llm launcher is installed so hooks can find it on PATH
LLM_BIN_DIR="${LLM_BIN_DIR:-$HOME/.local/bin}"
# Every agent this knows how to wire up. Agents the repo shows no sign of are
# still offered in the selection, so a repo can adopt one it doesn't use yet.
LLM_AGENTS="claude codex cursor windsurf copilot gemini cline aider"
# Only these two expose a hook API; the rest get instructions only
LLM_HOOK_AGENTS="claude codex"
# The one per-repo settings file (VERIFY_CMD, GIT_GUARD, …). Nothing else is
# read - a repo has exactly this file or it has no settings.
LLM_ENV_FILE=".infra-llm.env"
# Bumped whenever a command is added or removed. A shell that sourced an older
# git.sh keeps that older infra-llm function, which shadows the launcher on
# PATH and answers "unknown command" for anything added since - comparing this
# against the value in the file on disk is how --doctor catches that.
LLM_VERSION="2026-07-23.4"
LLM_DOC_START="<!-- infra-llm:start -->"
LLM_DOC_END="<!-- infra-llm:end -->"

_llm_c()  { printf '\033[0;34m→ %s\033[0m\n' "$1"; }
_llm_ok() { printf '\033[0;32m✓ %s\033[0m\n' "$1"; }
_llm_no() { printf '\033[0;31m✗ %s\033[0m\n' "$1" >&2; }
_llm_hm() { printf '\033[1;33m! %s\033[0m\n' "$1"; }

# Repo root of wherever we're standing (plain cwd outside a repo)
_llm_target() {
  local root
  root="$(git rev-parse --show-toplevel 2>/dev/null)"
  [ -n "$root" ] || root="$PWD"
  printf '%s\n' "$root"
}

# BSD mktemp needs a template, GNU is happy with one - so always pass one.
_llm_tmp() {
  mktemp "${TMPDIR:-/tmp}/infra-llm.XXXXXX"
}

# BSD `wc -l` pads its output with spaces; GNU doesn't. Strip either way.
_llm_count() {
  wc -l | tr -d '[:space:]'
}

_llm_assets_ok() {
  if [ ! -d "$LLM_HOOKS_DIR" ]; then
    _llm_no "workflow assets not found at ${LLM_INFRA_DIR}/llm - is LLM_INFRA_DIR right?"
    return 1
  fi
}

# ------------------------------------------------------------- hook execution

# Every wired hook runs through this, so the repo never holds a copy of a hook
# script and the scripts can be updated in one place.
_llm_hook() {
  local name="$1" script
  [ $# -gt 0 ] && shift
  case "$name" in
    prompt|user-prompt)  script="plan-prompt.sh" ;;
    stop|claude-stop)    script="steps-stop.sh" ;;
    codex-stop)          script="codex-stop.sh" ;;
    session|session-end) script="session-record.sh" ;;
    vexp|search-guard)   script="vexp-guard.sh" ;;
    git|git-guard)       script="git-guard.sh" ;;
    steps|steps-status)  script="steps-status.sh" ;;
    guard|steps-guard)   script="steps-guard.sh" ;;
    verify|verify-build) script="verify-build.sh" ;;
    *) _llm_no "unknown hook: $name"; return 1 ;;
  esac
  if [ ! -f "$LLM_HOOKS_DIR/$script" ]; then
    _llm_no "missing hook script: $LLM_HOOKS_DIR/$script"
    return 1
  fi
  # Subshell so a sourced shell never gets its cwd moved
  ( cd "${CLAUDE_PROJECT_DIR:-${CODEX_PROJECT_DIR:-$PWD}}" 2>/dev/null || cd "$PWD"
    bash "$LLM_HOOKS_DIR/$script" "$@" )
}

# --------------------------------------------------------------- cli launcher

# Hooks are invoked by the agent, not by an interactive shell, so a shell alias
# is not enough - a real launcher has to be on PATH.
_llm_install_cli() {
  local force="${1:-0}" target="${LLM_BIN_DIR}/infra-llm" desired
  desired="$(printf '#!/bin/bash\n# infra-llm launcher - generated by %s/llm.sh\nexec bash "%s/llm.sh" "$@"\n' "$LLM_INFRA_DIR" "$LLM_INFRA_DIR")"

  mkdir -p "$LLM_BIN_DIR" || return 1
  if [ ! -e "$target" ]; then
    printf '%s' "$desired" > "$target" && chmod +x "$target"
    _llm_ok "installed $target"
  elif [ "$(cat "$target" 2>/dev/null)" = "$desired" ]; then
    printf '  current  %s\n' "$target"
  elif [ "$force" -eq 1 ]; then
    printf '%s' "$desired" > "$target" && chmod +x "$target"
    _llm_ok "updated  $target"
  else
    _llm_hm "$target exists and points elsewhere - kept (use --force to repoint)"
  fi

  case ":$PATH:" in
    *":$LLM_BIN_DIR:"*) ;;
    *) _llm_hm "$LLM_BIN_DIR is not on PATH - add it, or hooks won't find infra-llm" ;;
  esac
}

# ------------------------------------------------------------------ detection

_llm_agent_label() {
  case "$1" in
    claude)   echo "Claude Code    hooks + session records + CLAUDE.md" ;;
    codex)    echo "Codex          hooks + AGENTS.md" ;;
    cursor)   echo "Cursor         .cursor/rules/ instructions" ;;
    windsurf) echo "Windsurf       .windsurf/rules/ instructions" ;;
    copilot)  echo "GitHub Copilot .github/copilot-instructions.md" ;;
    gemini)   echo "Gemini CLI     GEMINI.md instructions" ;;
    cline)    echo "Cline / Roo    .clinerules/ instructions" ;;
    aider)    echo "Aider          CONVENTIONS.md instructions" ;;
    *)        echo "$1" ;;
  esac
}

# Which instruction/config files for this agent already exist in the repo
_llm_agent_markers() {
  local root="$1" agent="$2" found="" m
  case "$agent" in
    claude)   set -- CLAUDE.md .claude/CLAUDE.md .claude/settings.json .claude ;;
    codex)    set -- AGENTS.md .codex/hooks.json .codex ;;
    cursor)   set -- .cursor/rules .cursorrules .cursor ;;
    windsurf) set -- .windsurf/rules .windsurfrules .windsurf ;;
    copilot)  set -- .github/copilot-instructions.md .github/instructions ;;
    gemini)   set -- GEMINI.md .gemini ;;
    cline)    set -- .clinerules .roorules .roo ;;
    aider)    set -- CONVENTIONS.md .aider.conf.yml ;;
    *)        set -- ;;
  esac
  for m in "$@"; do
    [ -e "$root/$m" ] && found="$found $m"
  done
  printf '%s\n' "${found# }"
}

# The file this agent's instructions belong in - following what the repo
# already uses when there is more than one accepted location.
_llm_agent_doc() {
  local root="$1" agent="$2"
  case "$agent" in
    claude)
      if [ -f "$root/CLAUDE.md" ]; then echo "CLAUDE.md"
      elif [ -f "$root/.claude/CLAUDE.md" ]; then echo ".claude/CLAUDE.md"
      else echo "CLAUDE.md"; fi ;;
    codex)    echo "AGENTS.md" ;;
    cursor)
      if [ -f "$root/.cursorrules" ] && [ ! -d "$root/.cursor" ]; then echo ".cursorrules"
      else echo ".cursor/rules/infra-llm.mdc"; fi ;;
    windsurf)
      if [ -f "$root/.windsurfrules" ] && [ ! -d "$root/.windsurf" ]; then echo ".windsurfrules"
      else echo ".windsurf/rules/infra-llm.md"; fi ;;
    copilot)  echo ".github/copilot-instructions.md" ;;
    gemini)   echo "GEMINI.md" ;;
    cline)
      if [ -f "$root/.clinerules" ]; then echo ".clinerules"
      else echo ".clinerules/infra-llm.md"; fi ;;
    aider)    echo "CONVENTIONS.md" ;;
  esac
}

# Written only when the instruction file is created from scratch, and only for
# tools that need frontmatter for a rule file to be picked up at all. Everything
# else starts empty - the block carries its own heading.
_llm_doc_header() {
  local root="$1" agent="$2" file="$3"
  case "$file" in
    *.mdc)
      printf -- '---\ndescription: Step-by-step execution protocol (infra-llm)\nalwaysApply: true\n---\n' ;;
    .windsurf/rules/*)
      printf -- '---\ntrigger: always_on\n---\n' ;;
  esac
}

# Print the detected/undetected table and let the user choose. Echoes the
# chosen agent names on stdout (everything else goes to stderr).
_llm_choose_agents() {
  local root="$1" preselected="$2" i=0 agent markers detected="" reply
  local names=()

  {
    printf '\n'
    printf 'LLM setups in %s\n' "$root"
    for agent in $LLM_AGENTS; do
      markers="$(_llm_agent_markers "$root" "$agent")"
      i=$((i + 1))
      names+=("$agent")
      if [ -n "$markers" ]; then
        detected="$detected $agent"
        printf '  %d) [x] %-9s found: %s\n' "$i" "$agent" "$markers"
      else
        printf '  %d) [ ] %-9s %s\n' "$i" "$agent" "$(_llm_agent_label "$agent")"
      fi
    done
    printf '\n'
  } >&2

  detected="${detected# }"
  [ -n "$preselected" ] && detected="$preselected"
  [ -n "$detected" ] || detected="claude"

  printf 'apply to which? [numbers, names, "all", Enter = %s]: ' "$detected" >&2
  # stdin is untouched by the command substitution around this function; if it
  # is closed (cron, a pipe that ended) fall back to what was detected.
  read -r reply || reply=""

  case "$reply" in
    "")         printf '%s\n' "$detected" ;;
    all|a|ALL)  printf '%s\n' "$LLM_AGENTS" ;;
    none|n)     printf '\n' ;;
    *)
      local out="" tok
      for tok in $(printf '%s' "$reply" | tr ',' ' '); do
        case "$tok" in
          [0-9]*) [ "$tok" -ge 1 ] && [ "$tok" -le "${#names[@]}" ] && out="$out ${names[$((tok - 1))]}" ;;
          *)      case " $LLM_AGENTS " in *" $tok "*) out="$out $tok" ;; esac ;;
        esac
      done
      printf '%s\n' "${out# }" ;;
  esac
}

# ----------------------------------------------------------- instruction docs

# Append (or refresh) the protocol block inside the repo's own instruction file.
# Everything between the markers is ours; the rest of the file is never touched.
_llm_doc_block() {
  local root="$1" file="$2" force="$3" agent="$4" tmp
  local path="$root/$file"
  [ -f "$LLM_TEMPLATE" ] || { _llm_no "missing template: $LLM_TEMPLATE"; return 1; }

  if [ -f "$path" ] && grep -qF "$LLM_DOC_START" "$path"; then
    if [ "$force" -eq 0 ]; then
      printf '  current  %s (block present; --force to refresh)\n' "$file"
      return 0
    fi
    tmp="$(_llm_tmp)"
    awk -v s="$LLM_DOC_START" -v e="$LLM_DOC_END" '
      index($0, s) { skip = 1 }
      !skip { print }
      index($0, e) { skip = 0 }
    ' "$path" > "$tmp"
    # Drop trailing blank lines left behind by the removed block. A file that
    # held nothing but the block becomes empty again, so repeated refreshes
    # don't accumulate blank lines at the top.
    if [ -n "$(tr -d '[:space:]' < "$tmp")" ]; then
      printf '%s\n' "$(cat "$tmp")" > "$path"
    else
      : > "$path"
    fi
    rm -f "$tmp"
  fi

  mkdir -p "$(dirname "$path")"
  [ -f "$path" ] || _llm_doc_header "$root" "$agent" "$file" > "$path"

  {
    # No leading blank line when we just created the file
    [ -s "$path" ] && printf '\n'
    printf '%s\n\n' "$LLM_DOC_START"
    cat "$LLM_TEMPLATE"
    printf '\n%s\n' "$LLM_DOC_END"
  } >> "$path"
  _llm_ok "instructions in $file"
}

_llm_doc_strip() {
  local root="$1" file="$2" tmp
  local path="$root/$file"
  [ -f "$path" ] || return 0
  grep -qF "$LLM_DOC_START" "$path" || return 0
  tmp="$(_llm_tmp)"
  awk -v s="$LLM_DOC_START" -v e="$LLM_DOC_END" '
    index($0, s) { skip = 1 }
    !skip { print }
    index($0, e) { skip = 0 }
  ' "$path" > "$tmp"
  printf '%s\n' "$(cat "$tmp")" > "$path"
  rm -f "$tmp"
  _llm_ok "removed instructions from $file"
}

# ------------------------------------------------------------- hook settings

# Wiring calls the launcher on PATH and fails open, so a checkout without infra
# (a teammate, CI) is never blocked by a hook it cannot run.
_llm_hook_cmd() {
  printf 'command -v infra-llm >/dev/null 2>&1 && infra-llm --hook %s || exit 0' "$1"
}

_llm_claude_settings_json() {
  local prompt stop session vexp git
  prompt="$(_llm_hook_cmd prompt)"; stop="$(_llm_hook_cmd stop)"
  session="$(_llm_hook_cmd session)"; vexp="$(_llm_hook_cmd vexp)"
  git="$(_llm_hook_cmd git-guard)"
  cat <<JSON
{
  "hooks": {
    "SessionEnd": [
      { "hooks": [ { "type": "command", "command": "$session", "timeout": 10 } ] }
    ],
    "UserPromptSubmit": [
      { "hooks": [ { "type": "command", "command": "$prompt", "timeout": 10 } ] }
    ],
    "Stop": [
      { "hooks": [ { "type": "command", "command": "$stop", "timeout": 30 } ] }
    ],
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [ { "type": "command", "command": "$git", "timeout": 10 } ] },
      { "matcher": "Grep|Glob", "hooks": [ { "type": "command", "command": "$vexp", "timeout": 10 } ] }
    ]
  }
}
JSON
}

_llm_codex_hooks_json() {
  local prompt stop
  prompt="$(_llm_hook_cmd prompt)"; stop="$(_llm_hook_cmd codex-stop)"
  cat <<JSON
{
  "hooks": {
    "UserPromptSubmit": [
      { "hooks": [ { "type": "command", "command": "$prompt", "timeout": 10 } ] }
    ],
    "Stop": [
      { "hooks": [ { "type": "command", "command": "$stop", "timeout": 30 } ] }
    ]
  }
}
JSON
}

# Merge hook entries into an existing settings file, keyed by command string so
# re-running never duplicates an entry and never drops the repo's own hooks.
_llm_merge_hooks() {
  local file="$1" desired="$2" rel="$3" merged

  if [ ! -f "$file" ]; then
    mkdir -p "$(dirname "$file")"
    printf '%s\n' "$desired" > "$file"
    _llm_ok "wired    $rel"
    return 0
  fi

  if ! command -v jq >/dev/null 2>&1; then
    _llm_hm "jq not installed - merge these hooks into $rel by hand:"
    printf '%s\n' "$desired"
    return 0
  fi

  merged="$(jq -s '
    (.[0] | if has("hooks") then . else .hooks = {} end) as $cur
    | .[1] as $new
    | reduce ($new.hooks | to_entries[]) as $e ($cur;
        .hooks[$e.key] = ((.hooks[$e.key] // [])
          + [ $e.value[]
              | select(
                  .hooks[0].command as $c
                  | [ $cur.hooks[$e.key][]? | .hooks[]?.command ] | index($c) | not
                ) ]))
  ' "$file" <(printf '%s' "$desired") 2>/dev/null)"

  if [ -z "$merged" ]; then
    _llm_no "could not parse $rel - left untouched; merge the hooks manually"
    return 1
  fi
  if [ "$(printf '%s' "$merged" | jq -S .)" = "$(jq -S . "$file" 2>/dev/null)" ]; then
    printf '  current  %s\n' "$rel"
    return 0
  fi
  printf '%s\n' "$merged" > "$file"
  _llm_ok "wired    $rel"
}

# Drop every hook entry that calls infra-llm, leaving the repo's own hooks alone
_llm_unmerge_hooks() {
  local file="$1" rel="$2" cleaned
  [ -f "$file" ] || return 0
  command -v jq >/dev/null 2>&1 || { _llm_hm "jq missing - remove the infra-llm hooks from $rel by hand"; return 0; }
  cleaned="$(jq '
    if has("hooks") then
      .hooks |= with_entries(
        .value |= map(select([.hooks[]?.command] | map(test("infra-llm")) | any | not))
      )
      | .hooks |= with_entries(select(.value | length > 0))
    else . end
  ' "$file" 2>/dev/null)"
  [ -n "$cleaned" ] || return 0
  printf '%s\n' "$cleaned" > "$file"
  _llm_ok "unwired  $rel"
}

# The one per-repo settings file. Written with everything commented out, so a
# fresh repo behaves exactly as if it weren't there - it exists to be found and
# edited, not to change defaults. Never overwritten: whatever the repo set wins.
_llm_env_file() {
  local root="$1" file="$root/$LLM_ENV_FILE"
  if [ -f "$file" ]; then
    printf '  current  %s\n' "$LLM_ENV_FILE"
    return 0
  fi
  cat > "$file" <<'ENV'
# infra-llm settings for this repo (git-ignored). Everything is optional -
# uncomment what this repo needs.

# The checks `infra-llm --verify` runs. Unset means no checks at all: no build
# tool, framework or test runner is assumed.
#VERIFY_CMD="<this repo's lint/type-check/test command>"

# Git guard (PreToolUse): deny = block agent git writes, ask = the user
# confirms each one, off = no guard. Destructive commands (force push, hard
# reset, clean, history rewriting) stay denied unless the guard is off.
#GIT_GUARD=deny

# Git subcommands this repo lets the agent run anyway, space separated.
#GIT_GUARD_ALLOW="tag stash"

# How long (seconds) `infra-llm --pull-request` / `--create-release` may commit,
# push and tag without asking. 0 turns that off and they prepare only.
#GIT_WINDOW_SECONDS=1800
ENV
  _llm_ok "wrote    $LLM_ENV_FILE"
}

# Workflow state is per-machine scratch, never committed. Creates .gitignore
# when the repo has none - otherwise these entries would silently never land.
_llm_gitignore() {
  local root="$1" file="$root/.gitignore" line bare
  git -C "$root" rev-parse --git-dir >/dev/null 2>&1 || return 0

  if [ ! -e "$file" ]; then
    : > "$file" || return 0
    _llm_ok "created  .gitignore"
  elif [ -s "$file" ] && [ -n "$(tail -c 1 "$file")" ]; then
    # No trailing newline - don't glue our first entry onto the last line
    printf '\n' >> "$file"
  fi

  for line in "plans/" "$LLM_ENV_FILE" ".claude/sessions/"; do
    bare="${line%/}"
    # Accept the entry however it is already written (with or without the
    # trailing slash or a leading /), so re-running never duplicates it
    if grep -qxE "/?${bare//./\\.}/?" "$file" 2>/dev/null; then
      printf '  current  .gitignore: %s\n' "$line"
      continue
    fi
    printf '%s\n' "$line" >> "$file"
    _llm_ok "ignored  $line"
  done

  # An already-tracked file keeps being tracked no matter what .gitignore says
  local tracked
  tracked="$(git -C "$root" ls-files -- '.claude/sessions' 'plans' 2>/dev/null | head -3)"
  if [ -n "$tracked" ]; then
    _llm_hm "already tracked by git despite .gitignore:"
    printf '%s\n' "$tracked" | sed 's/^/    /'
    _llm_hm "untrack them yourself when ready: git rm -r --cached .claude/sessions plans"
  fi
}

# ------------------------------------------------------------ slash commands

# Claude Code only exposes a project command if a file for it exists under
# .claude/commands/. The brief itself stays in the infra checkout - these are
# three-line wrappers that shell out to it, so there is still one source of
# truth and nothing to keep in sync.
LLM_CMD_MARK="<!-- infra-llm:generated -->"

# A repo gets ONE generated command - "/infra-llm <what>" - so the footprint in
# somebody else's project is a single file, and every workflow command is still
# reachable. The brief and the routing stay in the infra checkout; this file
# only points at them. --init --no-commands skips even this.
LLM_COMMANDS="infra-llm"
# Generated under earlier schemes - removed on sight so a repo keeps only one
LLM_COMMANDS_OLD="pull-request create-release infra-llm-review infra-llm-pr \
infra-llm-release infra-llm-plan infra-llm-steps infra-llm-verify \
infra-llm-status infra-llm-sessions infra-llm-worktrees infra-llm-doctor"

_llm_command_md() {
  cat <<'CMD'
---
description: Run an infra-llm workflow command - review, pr, release, plan, steps, verify, status, sessions, worktrees, doctor.
---

<!-- infra-llm:generated -->
Generated by `infra-llm --init`. Don't edit this file - a re-run overwrites it;
change it in the infra checkout instead.

Run `infra-llm $ARGUMENTS` and act on what it prints:

| Argument             | What you get                                          |
| -------------------- | ----------------------------------------------------- |
| `review`             | review brief + the scope of the recent changes - verify each finding, then fix it |
| `pr`                 | pull-request brief + branch, commits and any existing PR - follow it |
| `release [version]`  | release brief + tags, releases and commits since - follow it |
| `plan <slug>`        | creates and registers a plan - then fill it with one checkbox per step |
| `steps`              | the next unchecked step of the active plan            |
| `verify`             | this repo's checks - fix what it reports until it prints VERIFY OK |
| `status`             | wiring, active plan, git guard, sessions              |
| `sessions [id]`      | recorded session histories                            |
| `worktrees`          | every worktree with its own plan state                |
| `doctor`             | whether this machine can run the workflow             |

With no argument it prints the status. For anything that prints a brief, follow
that brief rather than improvising - it carries the repo's real state.
CMD
}

_llm_install_commands() {
  local root="$1" dir="$root/.claude/commands" name file
  mkdir -p "$dir" || return 0

  # Drop the previous generation's names, ours only
  for name in $LLM_COMMANDS_OLD; do
    file="$dir/$name.md"
    [ -f "$file" ] && grep -qF "$LLM_CMD_MARK" "$file" 2>/dev/null && {
      rm -f "$file"; _llm_ok "replaced /$name with the single /infra-llm command"
    }
  done

  for name in $LLM_COMMANDS; do
    file="$dir/$name.md"
    # Never clobber a command the repo wrote itself
    if [ -f "$file" ] && ! grep -qF "$LLM_CMD_MARK" "$file" 2>/dev/null; then
      _llm_hm "kept     .claude/commands/$name.md (not generated by infra-llm)"
      continue
    fi
    if [ -f "$file" ] && [ "$(cat "$file")" = "$(_llm_command_md)" ]; then
      printf '  current  .claude/commands/%s.md\n' "$name"
      continue
    fi
    _llm_command_md > "$file"
    _llm_ok "command  /$name"
  done
}

_llm_remove_commands() {
  local root="$1" dir="$root/.claude/commands" name file
  [ -d "$dir" ] || return 0
  for name in $LLM_COMMANDS $LLM_COMMANDS_OLD; do
    file="$dir/$name.md"
    [ -f "$file" ] || continue
    if grep -qF "$LLM_CMD_MARK" "$file" 2>/dev/null; then
      rm -f "$file"
      _llm_ok "removed  .claude/commands/$name.md"
    fi
  done
  rmdir "$dir" 2>/dev/null || true
}

# ----------------------------------------------------------------- installers

_llm_install_claude() {
  local root="$1" force="$2" want_vexp="$3" want_git="${4:-1}" want_cmds="${5:-1}" desired
  desired="$(_llm_claude_settings_json)"
  # Drop the opted-out PreToolUse guards by matcher, keeping the other one, and
  # drop PreToolUse entirely when neither is wanted.
  if { [ "$want_vexp" -eq 0 ] || [ "$want_git" -eq 0 ]; } && command -v jq >/dev/null 2>&1; then
    desired="$(printf '%s' "$desired" | jq \
      --argjson vexp "$want_vexp" --argjson git "$want_git" '
      .hooks.PreToolUse |= map(select(
        (.matcher == "Grep|Glob" and $vexp == 1) or (.matcher == "Bash" and $git == 1)
      ))
      | if (.hooks.PreToolUse | length) == 0 then del(.hooks.PreToolUse) else . end')"
  fi
  _llm_merge_hooks "$root/.claude/settings.json" "$desired" ".claude/settings.json"
  mkdir -p "$root/.claude/sessions"
  [ "$want_cmds" -eq 1 ] && _llm_install_commands "$root"
  _llm_doc_block "$root" "$(_llm_agent_doc "$root" claude)" "$force" claude
}

_llm_install_codex() {
  local root="$1" force="$2"
  _llm_merge_hooks "$root/.codex/hooks.json" "$(_llm_codex_hooks_json)" ".codex/hooks.json"
  _llm_doc_block "$root" "AGENTS.md" "$force" codex
}

# Everything else takes instructions only - no hook API to wire
_llm_install_docs_agent() {
  local root="$1" force="$2" agent="$3"
  _llm_doc_block "$root" "$(_llm_agent_doc "$root" "$agent")" "$force" "$agent"
}

_llm_init() {
  local force=0 docs_only=0 want_vexp=1 want_git=1 want_cmds=1 assume_yes=0 root="" chosen="" agent
  while [ $# -gt 0 ]; do
    case "$1" in
      -f|--force)  force=1 ;;
      --docs)      docs_only=1 ;;
      --no-vexp)   want_vexp=0 ;;
      --no-git-guard|--no-git) want_git=0 ;;
      --no-commands|--no-command) want_cmds=0 ;;
      -y|--yes)    assume_yes=1 ;;
      --all)       chosen="$LLM_AGENTS" ;;
      --claude|--codex|--cursor|--windsurf|--copilot|--gemini|--cline|--aider)
                   chosen="$chosen ${1#--}" ;;
      -*)          _llm_no "unknown option: $1"; return 1 ;;
      *)           root="$1" ;;
    esac
    shift
  done

  _llm_assets_ok || return 1
  [ -n "$root" ] || root="$(_llm_target)"
  [ -d "$root" ] || { _llm_no "no such directory: $root"; return 1; }
  chosen="${chosen# }"

  if [ -z "$chosen" ]; then
    if [ "$assume_yes" -eq 1 ]; then
      for agent in $LLM_AGENTS; do
        [ -n "$(_llm_agent_markers "$root" "$agent")" ] && chosen="$chosen $agent"
      done
      chosen="${chosen# }"
      [ -n "$chosen" ] || chosen="claude"
    else
      chosen="$(_llm_choose_agents "$root" "")"
    fi
  fi

  if [ -z "$(printf '%s' "$chosen" | tr -d ' ')" ]; then
    _llm_hm "nothing selected - no changes made"
    return 0
  fi

  if [ "$docs_only" -eq 1 ]; then
    _llm_c "refreshing instruction blocks in $root  [$chosen]"
    for agent in $chosen; do
      _llm_doc_block "$root" "$(_llm_agent_doc "$root" "$agent")" 1 "$agent"
    done
    return 0
  fi

  _llm_c "wiring agent workflow into $root  [$chosen]"
  _llm_install_cli "$force"
  mkdir -p "$root/plans"
  _llm_env_file "$root"
  _llm_wt_prep "$root"

  for agent in $chosen; do
    case " $LLM_AGENTS " in
      *" $agent "*) ;;
      *) _llm_hm "unknown agent, skipped: $agent"; continue ;;
    esac
    case "$agent" in
      claude) _llm_install_claude "$root" "$force" "$want_vexp" "$want_git" "$want_cmds" ;;
      codex)  _llm_install_codex  "$root" "$force" ;;
      *)      _llm_install_docs_agent "$root" "$force" "$agent" ;;
    esac
  done

  _llm_gitignore "$root"

  # Renamed from these - say so rather than silently ignoring a repo's settings
  local old
  for old in infra-llm.env .llm-verify.env .llm-git.env .agents/verify.env; do
    [ -f "$root/$old" ] || continue
    _llm_hm "$old is no longer read - move its settings into $LLM_ENV_FILE"
  done

  echo ""
  _llm_ok "workflow ready for: $chosen"
  echo "  hooks:    ${LLM_HOOKS_DIR}  (run via 'infra-llm --hook …', not copied here)"
  echo "  plans:    plans/            (plan files + .active-plan, git-ignored)"
  case " $chosen " in *" claude "*)
  echo "  sessions: .claude/sessions/ (one file per session, last 10)" ;;
  esac
  echo "  tune:     $LLM_ENV_FILE     (VERIFY_CMD, git guard - all optional)"
  case " $chosen " in *" claude "*)
    [ "$want_cmds" -eq 1 ] && echo "  command:  /infra-llm <what>   (one file; --no-commands to skip)" ;;
  esac
  case " $chosen " in *" claude "*)
    if [ "$want_git" -eq 1 ]; then
  echo "  git:      guarded          (agent can't commit/push; tune in $LLM_ENV_FILE)"
    fi ;;
  esac
}

# A fresh worktree starts with no untracked state: give it its own plans/ and
# sessions dir, and carry over the main checkout's verify config.
_llm_wt_prep() {
  local root="${1:-$(_llm_target)}" main
  mkdir -p "$root/plans" "$root/.claude/sessions"
  main="$(_llm_main_root "$root")"
  [ "$main" = "$root" ] && return 0
  if [ -f "$main/$LLM_ENV_FILE" ] && [ ! -e "$root/$LLM_ENV_FILE" ]; then
    cp "$main/$LLM_ENV_FILE" "$root/$LLM_ENV_FILE"
    _llm_ok "carried over $LLM_ENV_FILE from the main checkout"
  fi
  return 0
}

_llm_uninstall() {
  local root; root="$(_llm_target)"
  _llm_c "removing agent workflow wiring from $root"
  _llm_unmerge_hooks "$root/.claude/settings.json" ".claude/settings.json"
  _llm_unmerge_hooks "$root/.codex/hooks.json" ".codex/hooks.json"
  _llm_remove_commands "$root"
  local agent
  for agent in $LLM_AGENTS; do
    _llm_doc_strip "$root" "$(_llm_agent_doc "$root" "$agent")"
  done
  _llm_doc_strip "$root" ".claude/CLAUDE.md"
  _llm_hm "plans/ and .claude/sessions/ were left alone"
}

# -------------------------------------------------------------------- designer

# The "design-review" project skill this drops into a repo. It tells the agent
# to validate UI/design work with the impeccable + emilkowalski design skills
# and the chrome-devtools MCP instead of eyeballing the result. Kept as a
# heredoc (like the settings JSON) so there is nothing extra to vendor.
_llm_designer_skill_md() {
  cat <<'SKILL'
---
name: design-review
description: >-
  Use when building, changing, polishing, or reviewing any UI / visual /
  front-end work - a page, component, layout, styling, animation, or "make this
  look better / less like AI slop". Drives testing and validation of the design
  through the impeccable and emilkowalski design skills and the chrome-devtools
  MCP, instead of eyeballing the result.
---

# Design review & validation

<!-- Generated by `infra-llm --designer`. Don't edit this file: a re-run
     overwrites it. Change it in the infra checkout instead. -->

"It renders" is not done. When a change touches UI, styling, layout or motion,
validate it instead of eyeballing it.

## 1. Audit the design - impeccable

Run the `impeccable` skill (or its no-LLM scanner, `npx impeccable detect
<path>`) over the changed UI to catch typography, colour, spacing, layout and
motion anti-patterns. The scanner covers the common web markup/CSS formats; for
server-rendered template languages it has to be told which extensions to scan,
and it judges the markup and CSS, not the backend logic. Fix what it flags and
say what you deliberately left alone.

## 2. Review the motion - emilkowalski/skills

For anything animated or interactive, review easing, duration, physicality,
interruptibility, performance and accessibility with the emilkowalski
design-engineering skills rather than inventing curves.

## 3. Validate live - chrome-devtools MCP

Load the running UI in a real browser: screenshot the result, inspect computed
styles, spacing and contrast on the actual elements, check the console and
network for new errors, and run a performance/accessibility pass when those
matter. Iterate until the rendered page matches what the audit asked for.

Done means: no unaddressed anti-patterns, motion reviewed, and the change seen
working in the browser with no new console or network errors.
SKILL
}

# Generate the design-review skill into the current repo's .claude/skills so
# Claude Code auto-loads it. --remove / -r tears it down again.
_llm_designer() {
  local root name dir file remove=0
  name="design-review"
  while [ $# -gt 0 ]; do
    case "$1" in
      -r|--remove|remove|--uninstall) remove=1 ;;
      -*) _llm_no "unknown option: $1"; return 1 ;;
    esac
    shift
  done

  root="$(_llm_target)"
  dir="$root/.claude/skills/$name"
  file="$dir/SKILL.md"

  if [ "$remove" -eq 1 ]; then
    if [ ! -e "$file" ] && [ ! -d "$dir" ]; then
      _llm_hm "no design-review skill here - nothing to remove"
      return 0
    fi
    rm -f "$file"
    # Drop the skill directory too, but only if it's now empty (never clobber
    # anything the user added alongside it).
    rmdir "$dir" 2>/dev/null || true
    _llm_ok "removed .claude/skills/$name/"
    return 0
  fi

  _llm_c "installing the design-review skill into $root"
  mkdir -p "$dir"
  _llm_designer_skill_md > "$file"
  _llm_ok "wrote .claude/skills/$name/SKILL.md"
  echo "  uses:   impeccable · emilkowalski/skills · chrome-devtools MCP"
  echo "  remove: infra-llm --designer --remove"
}

# ------------------------------------------------------------------ worktrees

# The main checkout behind a linked worktree (the worktree itself if it is the
# main one). .git/worktrees/<name> lives under the common dir.
_llm_main_root() {
  local root="$1" common
  common="$(git -C "$root" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
  # git < 2.31 has no --path-format; its --git-common-dir may be relative to the
  # worktree, so resolve it there.
  if [ -z "$common" ]; then
    common="$(git -C "$root" rev-parse --git-common-dir 2>/dev/null)"
    case "$common" in
      ""|--*) printf '%s\n' "$root"; return 0 ;;
      /*) ;;
      *)  common="$( cd "$root" && cd "$(dirname "$common")" 2>/dev/null && pwd )/$(basename "$common")" ;;
    esac
  fi
  printf '%s\n' "$(dirname "$common")"
}

_llm_is_worktree() {
  local root="$1"
  [ "$(_llm_main_root "$root")" != "$root" ]
}

# One-line plan state for a directory, for the worktree table
_llm_plan_line() {
  local dir="$1" status
  status="$( cd "$dir" 2>/dev/null && bash "$LLM_HOOKS_DIR/steps-status.sh" 2>/dev/null )"
  case "$status" in
    REMAINING*)    printf '%s left: %s' "$(echo "$status" | cut -d'|' -f3)" "$(echo "$status" | cut -d'|' -f4- | cut -c1-48)" ;;
    NEEDS_VERIFY*) printf 'verify pending' ;;
    UNPLANNED*)    printf 'plan has no checkboxes' ;;
    *)             printf '-' ;;
  esac
}

# Every worktree of this repo with its own plan state - each one carries its
# own plans/ and .claude/sessions/, so agents can run in parallel without
# stepping on each other.
_llm_worktrees() {
  local root here path="" branch="" rows=0 line
  root="$(_llm_target)"
  if ! git -C "$root" rev-parse --git-dir >/dev/null 2>&1; then
    _llm_no "not a git repository"
    return 1
  fi
  here="$root"

  printf '%-24s %-22s %-34s %s\n' "WORKTREE" "BRANCH" "PLAN" "SESSIONS"
  emit() {
    [ -n "$path" ] || return 0
    local mark=" "
    [ "$path" = "$here" ] && mark="*"
    printf '%s%-23s %-22s %-34s %s\n' \
      "$mark" "$(basename "$path")" "${branch:-(detached)}" \
      "$(_llm_plan_line "$path")" \
      "$(ls -1 "$path/.claude/sessions"/*.md 2>/dev/null | _llm_count)"
    rows=$((rows + 1))
    path=""; branch=""
  }
  while IFS= read -r line; do
    case "$line" in
      "worktree "*) emit; path="${line#worktree }" ;;
      "branch "*)   branch="${line#branch refs/heads/}" ;;
      "detached")   branch="(detached)" ;;
    esac
  done < <(git -C "$root" worktree list --porcelain 2>/dev/null)
  emit
  unset -f emit

  echo ""
  echo "plans/ and .claude/sessions/ are untracked, so each worktree keeps its own"
  echo "active plan and its own session history - parallel agents don't collide."
  [ "$rows" -gt 1 ] || echo "add one with: gwtadd <branch>"
}

# --------------------------------------------------------------------- doctor

# Can this machine run the workflow? Reports the environment and the tools the
# hooks shell out to, then runs each hook for real - a syntax check proves
# nothing about a BSD userland or a CRLF checkout.
_llm_doctor() {
  local fails=0 warns=0 os="unknown" tmp t path out

  case "$(uname -s 2>/dev/null)" in
    Linux)  os="Linux"; grep -qi microsoft /proc/version 2>/dev/null && os="WSL (Linux on Windows)" ;;
    Darwin) os="macOS" ;;
    CYGWIN*|MINGW*|MSYS*) os="Windows (git-bash/msys)" ;;
  esac

  echo "environment"
  printf '  os:       %s\n' "$os"
  printf '  version:  %s\n' "$LLM_VERSION"
  printf '  bash:     %s\n' "${BASH_VERSION:-unknown}"
  printf '  infra:    %s\n' "$LLM_INFRA_DIR"

  # The scripts hard-code #!/bin/bash, so that interpreter is what runs them -
  # not whichever bash is first on PATH. macOS ships 3.2 there, which is why
  # nothing in these scripts may use bash 4 syntax.
  local sv
  if [ -x /bin/bash ]; then
    sv="$(/bin/bash -c 'echo "$BASH_VERSION"' 2>/dev/null)"
    printf '  shebang:  /bin/bash %s\n' "${sv:-(version unknown)}"
    case "$sv" in
      [12].*|3.0*|3.1*)
        _llm_no "/bin/bash is $sv - too old; the scripts need 3.2 or newer"
        fails=$((fails + 1)) ;;
      3.2*)
        _llm_hm "/bin/bash is 3.2 (stock macOS) - supported, and nothing here uses bash 4 syntax"
        warns=$((warns + 1)) ;;
    esac
  else
    _llm_no "no /bin/bash - every script's shebang points at it"
    fails=$((fails + 1))
  fi

  echo ""
  echo "required tools"
  for t in bash git grep sed awk tr cut sort head tail wc mktemp; do
    path="$(command -v "$t" 2>/dev/null)"
    if [ -n "$path" ]; then
      printf '  ok       %-8s %s\n' "$t" "$path"
    else
      _llm_no "missing  $t - the hooks need it"
      fails=$((fails + 1))
    fi
  done
  # Any one of these covers the stall guard's digest
  if ! command -v md5sum >/dev/null 2>&1 && ! command -v md5 >/dev/null 2>&1 \
     && ! command -v shasum >/dev/null 2>&1 && ! command -v cksum >/dev/null 2>&1; then
    _llm_no "missing  md5sum/md5/shasum/cksum - the stall guard can't hash the plan"
    fails=$((fails + 1))
  fi

  echo ""
  echo "optional tools"
  for t in jq gh; do
    path="$(command -v "$t" 2>/dev/null)"
    if [ -n "$path" ]; then
      printf '  ok       %-8s %s\n' "$t" "$path"
    else
      case "$t" in
        jq) _llm_hm "missing  jq - no session records, and the guards fall back to plain text matching" ;;
        gh) _llm_hm "missing  gh - --pull-request / --create-release can't see existing PRs or releases" ;;
      esac
      warns=$((warns + 1))
    fi
  done

  echo ""
  echo "sourced copy"
  local on_disk
  on_disk="$(sed -n 's/^LLM_VERSION="\(.*\)"$/\1/p' "$LLM_INFRA_DIR/llm.sh" 2>/dev/null | head -1)"
  if [ -z "$on_disk" ]; then
    _llm_hm "could not read LLM_VERSION from $LLM_INFRA_DIR/llm.sh"
    warns=$((warns + 1))
  elif [ "$on_disk" = "$LLM_VERSION" ]; then
    printf '  ok       running %s, same as %s/llm.sh\n' "$LLM_VERSION" "$LLM_INFRA_DIR"
  else
    _llm_no "this shell has an OLD copy sourced ($LLM_VERSION) - the file on disk is $on_disk"
    _llm_hm "the stale infra-llm function shadows the launcher, so newer commands report 'unknown command'"
    _llm_hm "fix with:  source $LLM_INFRA_DIR/git.sh    (or open a new shell)"
    fails=$((fails + 1))
  fi

  echo ""
  echo "launcher"
  if [ -x "${LLM_BIN_DIR}/infra-llm" ]; then
    case ":$PATH:" in
      *":${LLM_BIN_DIR}:"*) printf '  ok       %s\n' "${LLM_BIN_DIR}/infra-llm" ;;
      *) _llm_no "${LLM_BIN_DIR} is not on PATH - hooks run non-interactively and won't find infra-llm"
         fails=$((fails + 1)) ;;
    esac
  else
    _llm_hm "not installed yet - run: infra-llm --init"
    warns=$((warns + 1))
  fi

  echo ""
  echo "hook scripts"
  local f name crlf=0
  for f in "$LLM_HOOKS_DIR"/*.sh; do
    [ -f "$f" ] || continue
    name="$(basename "$f")"
    if LC_ALL=C grep -q "$(printf '\r')" "$f" 2>/dev/null; then
      _llm_no "CRLF     $name - a carriage return in the shebang makes the kernel refuse to run it"
      crlf=1; fails=$((fails + 1))
    elif ! bash -n "$f" 2>/dev/null; then
      _llm_no "syntax   $name"
      fails=$((fails + 1))
    else
      printf '  ok       %s\n' "$name"
    fi
  done
  [ "$crlf" -eq 0 ] || _llm_hm "fix with: git -C \"$LLM_INFRA_DIR\" config core.autocrlf false && git -C \"$LLM_INFRA_DIR\" checkout -- ."

  echo ""
  echo "hook smoke test"
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/infra-llm-doctor.XXXXXX")" || return 1
  mkdir -p "$tmp/plans"
  printf 'plans/t.md\n' > "$tmp/plans/.active-plan"
  printf -- '- [ ] a test step\n' > "$tmp/plans/t.md"

  out="$( cd "$tmp" && bash "$LLM_HOOKS_DIR/steps-status.sh" 2>/dev/null )"
  case "$out" in
    REMAINING*plans/t.md*) printf '  ok       steps-status\n' ;;
    *) _llm_no "steps-status returned: ${out:-<nothing>}"; fails=$((fails + 1)) ;;
  esac

  out="$( cd "$tmp" && bash "$LLM_HOOKS_DIR/steps-guard.sh" doctor 2>/dev/null )"
  case "$out" in
    [0-9]*) printf '  ok       steps-guard (counter: %s)\n' "$out" ;;
    *) _llm_no "steps-guard returned: ${out:-<nothing>}"; fails=$((fails + 1)) ;;
  esac

  out="$( cd "$tmp" && printf '{"prompt":"work on plans/t.md"}' | bash "$LLM_HOOKS_DIR/plan-prompt.sh" 2>/dev/null | head -1 )"
  case "$out" in
    STEP-BY-STEP*) printf '  ok       plan-prompt\n' ;;
    *) _llm_no "plan-prompt returned: ${out:-<nothing>}"; fails=$((fails + 1)) ;;
  esac

  out="$( printf '{"tool_input":{"command":"git commit -m x"}}' | CLAUDE_PROJECT_DIR="$tmp" bash "$LLM_HOOKS_DIR/git-guard.sh" 2>/dev/null )"
  case "$out" in
    *deny*) printf '  ok       git-guard (denies git commit)\n' ;;
    *) _llm_no "git-guard did not deny a commit: ${out:-<nothing>}"; fails=$((fails + 1)) ;;
  esac
  out="$( printf '{"tool_input":{"command":"git status"}}' | CLAUDE_PROJECT_DIR="$tmp" bash "$LLM_HOOKS_DIR/git-guard.sh" 2>/dev/null )"
  if [ -z "$out" ]; then
    printf '  ok       git-guard (passes read-only git)\n'
  else
    _llm_no "git-guard interfered with 'git status': $out"
    fails=$((fails + 1))
  fi

  printf 'VERIFY_CMD="echo doctor-ok"\n' > "$tmp/$LLM_ENV_FILE"
  out="$( cd "$tmp" && bash "$LLM_HOOKS_DIR/verify-build.sh" 2>/dev/null | sed -n '2p' )"
  case "$out" in
    doctor-ok) printf '  ok       verify-build (ran VERIFY_CMD)\n' ;;
    *) _llm_no "verify-build did not run VERIFY_CMD: ${out:-<nothing>}"; fails=$((fails + 1)) ;;
  esac

  out="$( printf '{}' | CLAUDE_PROJECT_DIR="$tmp" bash "$LLM_HOOKS_DIR/vexp-guard.sh" 2>/dev/null )"
  case "$out" in
    *allow*) printf '  ok       vexp-guard (allows search with no daemon)\n' ;;
    *) _llm_no "vexp-guard returned: ${out:-<nothing>}"; fails=$((fails + 1)) ;;
  esac

  rm -rf "$tmp"

  echo ""
  if [ "$fails" -gt 0 ]; then
    _llm_no "$fails problem(s) - the workflow will not behave correctly here"
    return 1
  fi
  if [ "$warns" -gt 0 ]; then
    _llm_hm "$warns optional thing(s) missing - everything essential works"
  else
    _llm_ok "all good - Linux, macOS and WSL are all supported"
  fi
  return 0
}

# --------------------------------------------------------------------- status

_llm_status() {
  local root; root="$(_llm_target)"
  echo "repo:     $root"
  if _llm_is_worktree "$root"; then
    echo "worktree: $(basename "$root") on $(git -C "$root" branch --show-current 2>/dev/null) (main: $(_llm_main_root "$root"))"
  fi
  echo "infra:    $LLM_INFRA_DIR"

  # Hooks run in a non-interactive shell, so what matters is the launcher on
  # PATH - not the shell function this file defines.
  local launcher; launcher="$(PATH="$PATH" command -v infra-llm 2>/dev/null)"
  if [ -x "${LLM_BIN_DIR}/infra-llm" ]; then
    case ":$PATH:" in
      *":${LLM_BIN_DIR}:"*) echo "cli:      ${LLM_BIN_DIR}/infra-llm" ;;
      *)                    echo "cli:      ${LLM_BIN_DIR}/infra-llm (NOT on PATH - hooks can't run it)" ;;
    esac
  elif [ -n "$launcher" ] && [ -f "$launcher" ]; then
    echo "cli:      $launcher"
  else
    echo "cli:      not installed (hooks need it - run: infra-llm --init)"
  fi

  local agent markers line=""
  for agent in $LLM_AGENTS; do
    markers="$(_llm_agent_markers "$root" "$agent")"
    [ -n "$markers" ] && line="$line $agent"
  done
  echo "detected:${line:- none}"

  local wired="" f
  for f in .claude/settings.json .codex/hooks.json; do
    [ -f "$root/$f" ] && grep -q "infra-llm --hook" "$root/$f" 2>/dev/null && wired="$wired $f"
  done
  echo "wiring:  ${wired:- none}"

  local docs="" agent2
  for agent2 in $LLM_AGENTS; do
    f="$(_llm_agent_doc "$root" "$agent2")"
    [ -f "$root/$f" ] && grep -qF "$LLM_DOC_START" "$root/$f" 2>/dev/null && docs="$docs $f"
  done
  f=".claude/CLAUDE.md"
  [ -f "$root/$f" ] && grep -qF "$LLM_DOC_START" "$root/$f" 2>/dev/null && docs="$docs $f"
  echo "docs:    ${docs:- none}"

  local status
  status="$( cd "$root" && bash "$LLM_HOOKS_DIR/steps-status.sh" 2>/dev/null )"
  case "$status" in
    UNPLANNED*)    echo "plan:     $(echo "$status" | cut -d'|' -f2) (no checkboxes yet)" ;;
    REMAINING*)    echo "plan:     $(echo "$status" | cut -d'|' -f2) - $(echo "$status" | cut -d'|' -f3) step(s) left"
                   echo "next:     $(echo "$status" | cut -d'|' -f4-)" ;;
    NEEDS_VERIFY*) echo "plan:     $(echo "$status" | cut -d'|' -f2) - all steps checked, verification pending" ;;
    *)             echo "plan:     none active" ;;
  esac

  echo "sessions: $(ls -1 "$root/.claude/sessions"/*.md 2>/dev/null | _llm_count) recorded"
  if [ -f "$root/.claude/commands/infra-llm.md" ]; then
    echo "command:  /infra-llm (generated; --init --no-commands to skip)"
  else
    echo "command:  none generated - use the infra-llm CLI directly"
  fi

  local gmode="deny (default)"
  if [ -f "$root/$LLM_ENV_FILE" ]; then
    gmode="$( . "$root/$LLM_ENV_FILE" 2>/dev/null; printf '%s' "${GIT_GUARD:-deny} ($LLM_ENV_FILE)" )"
  fi
  if grep -q 'infra-llm --hook git-guard' "$root/.claude/settings.json" 2>/dev/null; then
    echo "git:      guard wired - $gmode"
  else
    echo "git:      guard not wired (agent git writes rely on instructions only)"
  fi

  [ -z "$wired$docs" ] && _llm_hm "not wired up here yet - run: infra-llm --init"
  return 0
}

# ---------------------------------------------------------------- plan / steps

_llm_plan() {
  local slug="$1" root file
  if [ -z "$slug" ]; then
    _llm_no "usage: infra-llm --plan <slug>"
    return 1
  fi
  root="$(_llm_target)"
  slug="${slug%.md}"
  file="plans/${slug}.md"
  mkdir -p "$root/plans"
  if [ ! -f "$root/$file" ]; then
    cat > "$root/$file" <<EOF
# ${slug}

Every discrete item below is one step. The agent implements ONE per turn and
marks it - [x] here; the stop hook advances to the next.

Keep each step one short, specific line naming a concrete outcome — the stop
hook reads that line back as the next instruction. Detail goes underneath it.

- [ ] first step
EOF
    _llm_ok "created  $file"
  fi
  touch "$root/plans/.active-plan"
  grep -qxF "$file" "$root/plans/.active-plan" || printf '%s\n' "$file" >> "$root/plans/.active-plan"
  _llm_ok "registered $file in plans/.active-plan"
}

# Print the review brief plus the scope of the change to review. Read-only:
# it never runs a repository-mutating git command.
_llm_code_review() {
  local root brief base range="" stat=""
  root="$(_llm_target)"
  brief="${LLM_INFRA_DIR}/llm/templates/code-review.md"
  if [ ! -f "$brief" ]; then
    _llm_no "missing template: $brief"
    return 1
  fi
  cat "$brief"

  printf '\n## Scope\n\n'
  if [ $# -gt 0 ]; then
    printf 'Explicitly requested: %s\n\n' "$*"
    ( cd "$root" && git diff --stat "$@" 2>/dev/null ) || true
    return 0
  fi

  if ! git -C "$root" rev-parse --git-dir >/dev/null 2>&1; then
    printf 'Not a git repository - review the files the user just changed.\n'
    return 0
  fi

  # Uncommitted work first, then anything committed on top of the base branch
  stat="$( cd "$root" && git status --short 2>/dev/null )"
  if [ -n "$stat" ]; then
    printf 'Uncommitted changes:\n\n```\n%s\n```\n\n' "$stat"
    printf 'Diff stat (working tree vs HEAD):\n\n```\n%s\n```\n\n' \
      "$( cd "$root" && git diff --stat HEAD 2>/dev/null )"
  fi

  base="$( cd "$root" && git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null )"
  for b in $base origin/master origin/main; do
    range="$( cd "$root" && git log --oneline "$b..HEAD" 2>/dev/null )"
    if [ -n "$range" ]; then
      printf 'Commits ahead of %s:\n\n```\n%s\n```\n\n' "$b" "$range"
      printf 'Diff stat (%s..HEAD):\n\n```\n%s\n```\n' "$b" \
        "$( cd "$root" && git diff --stat "$b..HEAD" 2>/dev/null )"
      break
    fi
  done

  if [ -z "$stat" ] && [ -z "$range" ]; then
    printf 'No uncommitted changes and nothing ahead of the base branch.\n'
    printf 'Review the last commit (`git show HEAD`) or ask what to review.\n'
  fi
}

# ------------------------------------------------------------------ git briefs

# The base branch to compare/target: origin's default branch, else whatever of
# master/main exists, else the current branch.
_llm_base_branch() {
  local root="$1" b
  b="$( cd "$root" && git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null )"
  b="${b#origin/}"
  if [ -z "$b" ]; then
    for b in master main trunk develop; do
      git -C "$root" show-ref --verify --quiet "refs/heads/$b" && break
      b=""
    done
  fi
  [ -n "$b" ] || b="$( cd "$root" && git branch --show-current 2>/dev/null )"
  printf '%s\n' "$b"
}

_llm_git_repo_ok() {
  local root="$1"
  if ! git -C "$root" rev-parse --git-dir >/dev/null 2>&1; then
    printf '\nNot a git repository - nothing to open a pull request or release from.\n'
    return 1
  fi
}

# Print a brief from llm/templates plus the repo's real state. Read-only: like
# --code-review, it never runs a repository-mutating git command.
# Asking for a PR or a release is asking for the commit and the push that make
# one, so both commands open a short window the git guard honours - no config
# edit, nothing for the user to revert. Destructive git stays denied throughout.
_llm_git_window() {
  local root="$1" why="$2" secs
  secs="$( [ -f "$root/$LLM_ENV_FILE" ] && ( . "$root/$LLM_ENV_FILE" 2>/dev/null; printf '%s' "${GIT_WINDOW_SECONDS:-}" ) )"
  case "$secs" in ''|*[!0-9]*) secs=1800 ;; esac
  [ "$secs" -eq 0 ] && return 0          # GIT_WINDOW_SECONDS=0 opts out
  mkdir -p "$root/plans" 2>/dev/null || return 0
  printf '%s %s\n' "$(( $(date +%s) + secs ))" "$why" > "$root/plans/.git-window"
  printf '\nGit: commit/push/tag are allowed for the next %s minutes (opened by this command).\n' "$((secs / 60))"
  printf 'Do the work - commit, push, and create it - instead of handing commands back.\n'
}

_llm_pull_request() {
  local root brief branch base ahead stat
  root="$(_llm_target)"
  brief="${LLM_INFRA_DIR}/llm/templates/pull-request.md"
  [ -f "$brief" ] || { _llm_no "missing template: $brief"; return 1; }
  cat "$brief"

  printf '\n## Scope\n\n'
  _llm_git_repo_ok "$root" || return 0

  branch="$( cd "$root" && git branch --show-current 2>/dev/null )"
  base="$(_llm_base_branch "$root")"
  printf 'Branch: %s   Base: %s\n' "${branch:-(detached)}" "${base:-?}"
  if [ -n "$branch" ] && [ "$branch" = "$base" ]; then
    printf '\n**On the base branch** - the work needs its own branch before a PR.\n'
  fi

  stat="$( cd "$root" && git status --short 2>/dev/null )"
  if [ -n "$stat" ]; then
    printf '\nUncommitted changes (must be committed by the user before the PR):\n\n```\n%s\n```\n' "$stat"
  else
    printf '\nWorking tree is clean.\n'
  fi

  ahead="$( cd "$root" && git log --oneline "origin/${base}..HEAD" 2>/dev/null )"
  [ -n "$ahead" ] || ahead="$( cd "$root" && git log --oneline "${base}..HEAD" 2>/dev/null )"
  if [ -n "$ahead" ]; then
    printf '\nCommits not in %s:\n\n```\n%s\n```\n' "$base" "$ahead"
    printf '\nDiff stat:\n\n```\n%s\n```\n' \
      "$( cd "$root" && { git diff --stat "origin/${base}...HEAD" 2>/dev/null || git diff --stat "${base}...HEAD" 2>/dev/null; } )"
  else
    printf '\nNo commits ahead of %s yet.\n' "$base"
  fi

  printf '\nExisting pull request: '
  if command -v gh >/dev/null 2>&1; then
    local pr
    pr="$( cd "$root" && gh pr view --json url,state,title,isDraft 2>/dev/null )"
    if [ -n "$pr" ]; then
      printf '\n\n```json\n%s\n```\n\n**A PR already exists - do not create a duplicate.**\n' "$pr"
    else
      printf 'none for this branch (gh found no open PR).\n'
    fi
  else
    printf 'unknown - `gh` is not installed, so ask the user or check the forge manually.\n'
  fi

  printf '\nVerify gate: `infra-llm --verify`%s\n' \
    "$( grep -qsE '^[[:space:]]*VERIFY_CMD=' "$root/$LLM_ENV_FILE" && printf ' (VERIFY_CMD set in %s)' "$LLM_ENV_FILE" || printf ' (no VERIFY_CMD configured - say so instead of claiming it passed)' )"
  _llm_git_window "$root" "pull-request"
}

_llm_create_release() {
  local root brief want="$1" tags last range
  root="$(_llm_target)"
  brief="${LLM_INFRA_DIR}/llm/templates/create-release.md"
  [ -f "$brief" ] || { _llm_no "missing template: $brief"; return 1; }
  cat "$brief"

  printf '\n## Scope\n\n'
  [ -n "$want" ] && printf 'Requested version: %s\n\n' "$want"
  _llm_git_repo_ok "$root" || return 0

  printf 'Branch: %s\n' "$( cd "$root" && git branch --show-current 2>/dev/null )"

  tags="$( cd "$root" && git tag --sort=-v:refname 2>/dev/null | head -10 )"
  if [ -n "$tags" ]; then
    printf '\nMost recent tags:\n\n```\n%s\n```\n' "$tags"
    last="$(printf '%s\n' "$tags" | head -1)"
  else
    printf '\nNo tags yet - this would be the first release.\n'
  fi

  if [ -n "$want" ] && printf '%s\n' "$tags" | grep -qxF "$want"; then
    printf '\n**Tag %s already exists - do not create a duplicate.**\n' "$want"
  fi

  # Candidate next versions, so the agent picks a bump rather than inventing a
  # number. Only for a vX.Y.Z-shaped previous tag; anything else is the user's.
  if [ -n "$last" ] && printf '%s' "$last" | grep -qE '^v?[0-9]+\.[0-9]+\.[0-9]+$'; then
    local core maj min pat pre
    core="${last#v}"; pre=""
    case "$last" in v*) pre="v" ;; esac
    maj="${core%%.*}"; pat="${core##*.}"; min="${core#*.}"; min="${min%.*}"
    printf '\nNext from %s:  %s%s.%s.%s bug fix  ·  %s%s.%s.0 feature  ·  %s%s.0.0 breaking\n' \
      "$last" "$pre" "$maj" "$min" "$((pat + 1))" \
      "$pre" "$maj" "$((min + 1))" "$pre" "$((maj + 1))"
  fi

  if [ -n "$last" ]; then
    range="$( cd "$root" && git log --oneline "${last}..HEAD" 2>/dev/null )"
    if [ -n "$range" ]; then
      printf '\nCommits since %s:\n\n```\n%s\n```\n' "$last" "$range"
      printf '\nDiff stat (%s..HEAD):\n\n```\n%s\n```\n' "$last" \
        "$( cd "$root" && git diff --stat "${last}..HEAD" 2>/dev/null )"
    else
      printf '\nNothing new since %s - there may be nothing to release.\n' "$last"
    fi
  else
    printf '\nRecent commits:\n\n```\n%s\n```\n' "$( cd "$root" && git log --oneline -20 2>/dev/null )"
  fi

  printf '\nPublished releases: '
  if command -v gh >/dev/null 2>&1; then
    local rel
    rel="$( cd "$root" && gh release list --limit 5 2>/dev/null )"
    if [ -n "$rel" ]; then printf '\n\n```\n%s\n```\n' "$rel"; else printf 'none found by gh.\n'; fi
  else
    printf 'unknown - `gh` is not installed; tag-only releases then, or ask the user.\n'
  fi

  # Dependency/lock churn in the range - the concrete input for the security
  # pass. Matched by name so no ecosystem is assumed; the agent reads the diff.
  if [ -n "$last" ]; then
    local deps
    deps="$( cd "$root" && git diff --name-only "${last}..HEAD" 2>/dev/null | grep -iE \
      '(^|/)(package(-lock)?\.json|yarn\.lock|pnpm-lock\.yaml|composer\.(json|lock)|Gemfile(\.lock)?|(requirements[^/]*\.txt)|poetry\.lock|Pipfile(\.lock)?|pyproject\.toml|go\.(mod|sum)|Cargo\.(toml|lock)|.*\.csproj|pom\.xml|build\.gradle.*|mix\.exs|pubspec\.(yaml|lock))$' )"
    if [ -n "$deps" ]; then
      printf '\nDependency manifests changed since %s - check these for security updates:\n\n```\n%s\n```\n' "$last" "$deps"
    else
      printf '\nNo dependency manifest changed since %s.\n' "$last"
    fi
  fi

  # Where this repo declares its version, so the agent bumps the right files
  local vf found=""
  for vf in package.json composer.json pyproject.toml Cargo.toml VERSION version.txt \
            style.css CHANGELOG.md galaxy.yml build.gradle setup.py; do
    [ -f "$root/$vf" ] && found="$found $vf"
  done
  printf '\nVersion declared in (check and keep in sync):%s\n' "${found:- nothing obvious - ask the user}"

  printf '\nVerify gate: `infra-llm --verify`%s\n' \
    "$( grep -qsE '^[[:space:]]*VERIFY_CMD=' "$root/$LLM_ENV_FILE" && printf ' (VERIFY_CMD set in %s)' "$LLM_ENV_FILE" || printf ' (no VERIFY_CMD configured - say so instead of claiming it passed)' )"
  _llm_git_window "$root" "create-release"
}

_llm_skill() {
  local name="$1" f
  if [ -z "$name" ]; then
    echo "available skills:"
    for f in "$LLM_SKILLS_DIR"/*/SKILL.md; do
      [ -f "$f" ] || continue
      printf '  %s\n' "$(basename "$(dirname "$f")")"
    done
    return 0
  fi
  f="$LLM_SKILLS_DIR/$name/SKILL.md"
  # Briefs that aren't full skills (the review brief) live under templates/
  [ -f "$f" ] || f="${LLM_INFRA_DIR}/llm/templates/${name}.md"
  if [ ! -f "$f" ]; then
    _llm_no "no such skill: $name"
    return 1
  fi
  cat "$f"
}

# -------------------------------------------------------------------- sessions

_llm_sessions() {
  local root dir; root="$(_llm_target)"; dir="$root/.claude/sessions"
  if [ ! -d "$dir" ]; then
    _llm_hm "no session records here yet - run: infra-llm --init"
    return 0
  fi
  if [ -n "$1" ]; then
    local match
    match="$(ls -1 "$dir"/*"$1"*.md 2>/dev/null | head -1)"
    if [ -z "$match" ]; then
      _llm_no "no session record matching: $1"
      return 1
    fi
    cat "$match"
    return 0
  fi
  local f
  ls -1t "$dir"/*.md >/dev/null 2>&1 || { echo "no session records yet"; return 0; }
  for f in $(ls -1t "$dir"/*.md 2>/dev/null); do
    printf '%s  %s\n' "$(head -1 "$f" | tr -d '# ')" "$(basename "$f" .md)"
    sed -n '5,7p' "$f" | sed 's/^/    /'
  done
}

# claude, with session recording guaranteed to be wired in this directory first
claude_session() {
  local root; root="$(_llm_target)"
  mkdir -p "$root/.claude/sessions"
  if ! grep -q "infra-llm --hook session" "$root/.claude/settings.json" 2>/dev/null; then
    _llm_c "wiring session records into $root"
    _llm_install_cli 0
    _llm_merge_hooks "$root/.claude/settings.json" "$(_llm_claude_settings_json)" ".claude/settings.json"
  fi
  command claude "$@"
}

# ------------------------------------------------------------------ entrypoint

infra-llm() {
  local cmd="${1:---status}"
  [ $# -gt 0 ] && shift
  case "$cmd" in
    --init|init)           _llm_init "$@" ;;
    --docs|docs)           _llm_init --docs "$@" ;;
    --status|status)       _llm_status ;;
    --doctor|doctor|--check|check) _llm_doctor ;;
    --plan|plan)           _llm_plan "$@" ;;
    --steps|steps)         _llm_hook steps ;;
    --verify|verify)       _llm_hook verify "$@" ;;
    --sessions|sessions)   _llm_sessions "$@" ;;
    --code-review|code-review|--review|review) _llm_code_review "$@" ;;
    --pull-request|pull-request|--pr|pr) _llm_pull_request "$@" ;;
    --create-release|create-release|--release|release) _llm_create_release "$@" ;;
    --worktrees|--worktree|--wt|worktrees|wt) _llm_worktrees ;;
    --wt-prep)             _llm_wt_prep "$@" ;;
    --skill|skill)         _llm_skill "$@" ;;
    --designer|designer)   _llm_designer "$@" ;;
    --hook|hook)           _llm_hook "$@" ;;
    --cli)                 _llm_install_cli 1 ;;
    --uninstall|uninstall) _llm_uninstall ;;
    -h|--help|help)
      sed -n '3,37p' "${LLM_INFRA_DIR}/llm.sh" | sed 's/^# \{0,1\}//' ;;
    *) _llm_no "unknown command: $cmd"; return 1 ;;
  esac
}

alias llminit='infra-llm --init'
alias llmdocs='infra-llm --docs'
alias llmstatus='infra-llm --status'
alias llmdoctor='infra-llm --doctor'
alias llmplan='infra-llm --plan'
alias llmsteps='infra-llm --steps'
alias llmverify='infra-llm --verify'
alias llmsessions='infra-llm --sessions'
alias llmreview='infra-llm --code-review'
alias llmpr='infra-llm --pull-request'
alias llmrelease='infra-llm --create-release'
alias llmwt='infra-llm --worktrees'
alias llmskill='infra-llm --skill'
alias llmdesigner='infra-llm --designer'

# Executed rather than sourced: run the command line and exit
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  infra-llm "$@"
fi
