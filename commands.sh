# Shell entry point for this infra checkout.
#
#   source /path/to/infra/commands.sh
#
# Loads git.sh (git shortcuts, worktree helpers, the PS1 branch prompt) and
# llm.sh (the infra-llm agent workflow). Sourcing git.sh on its own still works
# - it pulls llm.sh in itself - but this file is what install.sh writes into
# ~/.bashrc, because it also re-sources both when the checkout changes.
#
# Nothing here runs anything: it defines what those two files define, and that
# is all. Safe to source twice.

# Where this file lives, whether the shell is bash or zsh. Resolved on every
# source rather than cached, so a moved checkout can't leave a stale path.
if [ -n "${BASH_SOURCE[0]}" ]; then
  INFRA_COMMANDS_FILE="${BASH_SOURCE[0]}"
elif [ -n "${ZSH_VERSION}" ]; then
  # ${(%):-%x} is zsh's "path of the file being sourced"
  INFRA_COMMANDS_FILE="${(%):-%x}"
else
  INFRA_COMMANDS_FILE="$0"
fi
INFRA_DIR="$(cd "$(dirname "$INFRA_COMMANDS_FILE")" 2>/dev/null && pwd)"

# The files this entry point owns, in load order
INFRA_COMMANDS_FILES="git.sh llm.sh"

# $1 = file under the checkout. Missing is not an error: a partial checkout
# should still give the user whatever it does have.
_infra_load() {
  [ -f "$INFRA_DIR/$1" ] && . "$INFRA_DIR/$1"
  return 0
}

# git.sh sources llm.sh at its own bottom; loading llm.sh again afterwards is
# harmless - both files only define things - and keeps this entry point honest
# about what it provides even if that ever changes.
_infra_load git.sh
_infra_load llm.sh

# ------------------------------------------------------------------ auto-reload
#
# Editing the checkout leaves every already-open shell running the functions it
# sourced at startup - the stale copy --doctor reports. Comparing modification
# times before each prompt costs one stat per file and fixes that: change a
# file, press enter, and the shell you are standing in is current.

# One line per file: "<path> <mtime>". stat's flags differ between GNU and BSD,
# so try both and fall back to ls, which every platform has.
_infra_stamp() {
  local f out
  for f in $INFRA_COMMANDS_FILES; do
    [ -f "$INFRA_DIR/$f" ] || continue
    out="$(stat -c %Y "$INFRA_DIR/$f" 2>/dev/null \
        || stat -f %m "$INFRA_DIR/$f" 2>/dev/null \
        || ls -l "$INFRA_DIR/$f" 2>/dev/null)"
    printf '%s %s\n' "$f" "$out"
  done
}

INFRA_COMMANDS_STAMP="$(_infra_stamp)"

# Re-source when the stamp moved. Quiet by default - a shell that reloads on
# every edit should not narrate it - but say so when asked directly.
_infra_reload_if_changed() {
  local now
  now="$(_infra_stamp)"
  [ "$now" = "$INFRA_COMMANDS_STAMP" ] && return 0
  INFRA_COMMANDS_STAMP="$now"
  _infra_load git.sh
  _infra_load llm.sh
  [ -n "$1" ] && printf 'infra: reloaded %s\n' "$INFRA_COMMANDS_FILES"
  return 0
}

# Reload now, whether or not anything changed - for a shell that was open
# before commands.sh existed, or when the prompt hook isn't running (a script,
# a non-interactive shell). Says what it loaded, because it was asked to.
infra-reload() {
  local f
  for f in $INFRA_COMMANDS_FILES; do
    if [ -f "$INFRA_DIR/$f" ]; then
      . "$INFRA_DIR/$f"
      printf '  reloaded %s\n' "$INFRA_DIR/$f"
    else
      printf '  missing  %s\n' "$INFRA_DIR/$f" >&2
    fi
  done
  INFRA_COMMANDS_STAMP="$(_infra_stamp)"
  printf 'infra-llm %s\n' "${LLM_VERSION:-(llm.sh not loaded)}"
}
alias infrareload='infra-reload'

# Hook it into the prompt, without trampling anything already there.
if [ -n "$ZSH_VERSION" ]; then
  autoload -Uz add-zsh-hook 2>/dev/null && add-zsh-hook precmd _infra_reload_if_changed
elif [ -n "$BASH_VERSION" ]; then
  case ";${PROMPT_COMMAND};" in
    *";_infra_reload_if_changed;"*) ;;   # already wired, don't stack it
    *) PROMPT_COMMAND="_infra_reload_if_changed${PROMPT_COMMAND:+;$PROMPT_COMMAND}" ;;
  esac
fi
