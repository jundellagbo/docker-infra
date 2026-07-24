# Git shortcuts
#
# Companion: llm.sh (agent workflow - infra-llm --init, llmplan, llmsteps, ...)
# is sourced at the bottom of this file.
#
# Sourcing this file directly works and is self-contained. commands.sh is the
# usual entry point (what install.sh wires into ~/.bashrc): it loads this file
# plus llm.sh, and re-sources both when the checkout changes.

# Commit
alias gcom='git commit -m'
alias gamend='git commit --amend'
alias gundo='git reset --soft HEAD~1'

# Status / Diff
alias gst='git status -sb'
alias gdf='git diff'
alias gdfc='git diff --cached'

# Branching
alias gbr='git branch'
alias gch='git fetch && git checkout'
alias gnb='function _gnb(){ git checkout -b "$1" && git push -u origin "$1"; }; _gnb'
alias gdel='git branch -d'

# Worktrees
#
#   gwtadd <branch> [base] [path] [--no-push]
#                            add a worktree (base defaults to origin's default
#                            branch, path defaults to ../<branch>). A branch it
#                            creates is pushed to origin with -u; --no-push
#                            keeps it local.
#   gwtls                    list worktrees
#   gwtcd <branch>           jump into a worktree
#   gwtrm <branch> [opts]    tear a worktree down (docker + dir + local/remote branch)
#   gwtprune                 prune stale worktree metadata
#
# Worktrees live next to the repo in "../<slug>" unless GIT_WORKTREE_DIR is set
# or an explicit path is passed to gwtadd.

_gwt_root() { git rev-parse --show-toplevel 2>/dev/null; }

_gwt_base_dir() {
  local root
  root="$(_gwt_root)"
  if [ -z "$root" ]; then
    echo "not inside a git repository" >&2
    return 1
  fi
  if [ -n "$GIT_WORKTREE_DIR" ]; then
    printf '%s\n' "${GIT_WORKTREE_DIR%/}"
  else
    printf '%s\n' "$(dirname "$root")"
  fi
}

# feature/login -> feature-login (safe as a directory name)
_gwt_slug() { printf '%s\n' "${1//\//-}"; }

# origin's default branch (master, main, ...), falling back to the current one
_gwt_default_branch() {
  local head
  head="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)"
  head="${head#origin/}"
  [ -n "$head" ] || head="$(git branch --show-current 2>/dev/null)"
  printf '%s\n' "$head"
}

# Path of the worktree holding <branch>, if any
_gwt_path_of() {
  git worktree list --porcelain 2>/dev/null | awk -v want="refs/heads/$1" '
    /^worktree /  { path = substr($0, 10) }
    /^branch /    { if (substr($0, 8) == want) { print path; exit } }
  '
}

_gwtadd() {
  local branch="" base="" path="" root base_dir start want_push=1
  local usage="usage: gwtadd <branch> [base-branch] [path] [--no-push]   e.g. gwtadd feature/login master-upgrade ../login"

  # Positional order is unchanged - the flags just get picked out of the line,
  # so every existing "gwtadd feature/x master ../x" still means what it did.
  while [ $# -gt 0 ]; do
    case "$1" in
      --no-push)  want_push=0 ;;
      --push)     want_push=1 ;;   # the default; accepted so it can be explicit
      -h|--help)  echo "$usage"; return 0 ;;
      -*)         echo "unknown option: $1" >&2; return 1 ;;
      *)
        if   [ -z "$branch" ]; then branch="$1"
        elif [ -z "$base" ];   then base="$1"
        elif [ -z "$path" ];   then path="$1"
        else echo "too many arguments: $1" >&2; return 1
        fi ;;
    esac
    shift
  done

  if [ -z "$branch" ]; then
    echo "$usage" >&2
    return 1
  fi

  root="$(_gwt_root)" || return 1
  if [ -n "$path" ]; then
    # Explicit path: a trailing "/" (or an existing dir) means "put it in here"
    case "$path" in
      */) path="${path%/}/$(_gwt_slug "$branch")" ;;
      *)  if [ -d "$path" ]; then path="${path}/$(_gwt_slug "$branch")"; fi ;;
    esac
    base_dir="$(dirname "$path")"
  else
    base_dir="$(_gwt_base_dir)" || return 1
    path="${base_dir}/$(_gwt_slug "$branch")"
  fi

  if [ -e "$path" ]; then
    echo "path already exists: $path" >&2
    return 1
  fi

  git fetch --prune origin || return 1
  [ -n "$base" ] || base="$(_gwt_default_branch)"
  mkdir -p "$base_dir" || return 1

  local created=0
  if git show-ref --verify --quiet "refs/heads/$branch"; then
    # Branch already exists locally - just check it out somewhere new
    git worktree add "$path" "$branch" || return 1
  elif git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
    git worktree add --track -b "$branch" "$path" "origin/$branch" || return 1
  else
    # New branch: prefer the remote tip of the base so we branch off fresh code
    start="$base"
    git show-ref --verify --quiet "refs/remotes/origin/$base" && start="origin/$base"
    if ! git show-ref --verify --quiet "refs/heads/$base" && [ "$start" = "$base" ]; then
      echo "base branch not found: $base" >&2
      return 1
    fi
    echo "branching $branch off $start"
    git worktree add -b "$branch" "$path" "$start" || return 1
    created=1
  fi

  # Publish a branch this command just invented: without it there is no upstream
  # for the first push, nothing for teammates or CI to see, and nothing for
  # gwtrm to delete on the remote. Only the branch we created - re-checking out
  # something that already exists locally or on origin pushes nothing.
  if [ $want_push -eq 1 ] && [ $created -eq 1 ] && git remote get-url origin >/dev/null 2>&1; then
    if ! git -C "$path" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' >/dev/null 2>&1; then
      echo "pushing $branch to origin"
      # A push can fail for reasons that say nothing about the worktree - no
      # network, no write access, a hook on the server. The checkout is still
      # exactly what was asked for, so keep it and name the retry.
      if ! git -C "$path" push -u origin "$branch"; then
        echo "push failed - worktree is ready, branch is local only" >&2
        echo "  retry with: git -C '$path' push -u origin '$branch'" >&2
      fi
    fi
  fi

  # Untracked env files never come along with the checkout - carry them over
  local f
  for f in .env .env.local .infra-llm.env; do
    [ -f "${root}/${f}" ] && [ ! -e "${path}/${f}" ] && cp "${root}/${f}" "${path}/${f}"
  done

  # Give the worktree its own agent state (plans + session records) so an agent
  # can start here in parallel with whatever is running in the other worktrees
  if declare -F _llm_wt_prep >/dev/null 2>&1; then
    _llm_wt_prep "$path" >/dev/null
  else
    # Fallback for a shell that sourced git.sh without llm.sh - the names have
    # to match LLM_PLANS_DIR / LLM_SESSIONS_DIR over there
    mkdir -p "${path}/infra-llm/plans" "${path}/infra-llm/sessions"
  fi

  echo "worktree ready: $path"
  cd "$path" || return 1
}

# Compose project name docker derives from a directory (lowercase, alnum/_/- only)
_gwt_compose_project() {
  local name
  # tr, not ${name,,}: that expansion is bash 4+, and macOS ships bash 3.2 -
  # a syntax error here would break sourcing this whole file.
  name="$(basename "$1" | tr '[:upper:]' '[:lower:]')"
  printf '%s\n' "${name//[^a-z0-9_-]/}"
}

_gwt_docker_cleanup() {
  local path="$1" proj file ids
  command -v docker >/dev/null 2>&1 || return 0
  proj="$(_gwt_compose_project "$path")"

  for file in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
    if [ -f "${path}/${file}" ]; then
      echo "docker compose down (${proj})"
      ( cd "$path" && docker compose -f "$file" -p "$proj" down --volumes --rmi local --remove-orphans )
      break
    fi
  done

  # Sweep anything compose left behind (orphans from renamed/removed services)
  ids="$(docker ps -aq --filter "label=com.docker.compose.project=${proj}" 2>/dev/null)"
  [ -n "$ids" ] && docker rm -f $ids >/dev/null
  ids="$(docker volume ls -q --filter "label=com.docker.compose.project=${proj}" 2>/dev/null)"
  [ -n "$ids" ] && docker volume rm -f $ids >/dev/null
  ids="$(docker images -q --filter "label=com.docker.compose.project=${proj}" 2>/dev/null)"
  [ -n "$ids" ] && docker rmi -f $ids >/dev/null
  ids="$(docker network ls -q --filter "label=com.docker.compose.project=${proj}" 2>/dev/null)"
  [ -n "$ids" ] && docker network rm $ids >/dev/null 2>&1
  return 0
}

# Remove a directory for real. Containers write into a bind-mounted worktree as
# root, so a plain `rm -rf` there dies with "Permission denied" and leaves the
# tree half-gone; escalate rather than reporting a cleanup that didn't happen.
_gwt_rm_tree() {
  local path="$1"
  [ -n "$path" ] && [ -e "$path" ] || return 0

  rm -rf "$path" 2>/dev/null
  [ -e "$path" ] || return 0

  # Our own files, just written read-only (node_modules, vendor, .git objects)
  chmod -R u+rwX "$path" 2>/dev/null
  rm -rf "$path" 2>/dev/null
  [ -e "$path" ] || return 0

  if command -v sudo >/dev/null 2>&1; then
    # Passwordless first so scripts and hooks never block on a prompt
    sudo -n rm -rf "$path" 2>/dev/null
    [ -e "$path" ] || return 0
    if [ -t 0 ]; then
      echo "root-owned files left in $path - sudo needed to remove them"
      sudo rm -rf "$path"
      [ -e "$path" ] || return 0
    fi
  fi

  echo "could not remove $path (permission denied) - remove it manually: sudo rm -rf '$path'" >&2
  return 1
}

_gwtrm() {
  local branch="" want_path="" force=0 assume_yes=0 skip_docker=0 keep_branch=0 keep_remote=0
  local usage="usage: gwtrm <branch> [path] [-f] [-y] [--no-docker] [--keep-branch] [--keep-remote]"
  while [ $# -gt 0 ]; do
    case "$1" in
      -f|--force)    force=1 ;;
      -y|--yes)      assume_yes=1 ;;
      --no-docker)   skip_docker=1 ;;
      --keep-branch) keep_branch=1 ;;
      --keep-remote) keep_remote=1 ;;
      -h|--help)
        echo "$usage"
        return 0 ;;
      -*) echo "unknown option: $1" >&2; return 1 ;;
      *)  if [ -z "$branch" ]; then branch="$1"; else want_path="$1"; fi ;;
    esac
    shift
  done

  if [ -z "$branch" ]; then
    echo "$usage" >&2
    return 1
  fi

  local root path has_remote=0 remote_stale=0 remote_offline=0
  root="$(_gwt_root)" || return 1
  if [ -n "$want_path" ]; then
    if [ ! -d "$want_path" ]; then
      echo "worktree path not found: $want_path" >&2
      return 1
    fi
    path="$(cd "$want_path" && pwd)"
  else
    path="$(_gwt_path_of "$branch")"
  fi
  if [ -z "$path" ]; then
    # Fall back to the current directory when we're standing inside the worktree
    path="$PWD"
    [ "$path" != "$root" ] && [ -e "${path}/.git" ] || path=""
  fi
  # Ask origin itself. refs/remotes/origin/<branch> only says what the last
  # fetch saw: missing there (never fetched) is why a delete used to be skipped
  # silently, and present-but-stale is a tracking ref to clean up, not a push.
  git show-ref --verify --quiet "refs/remotes/origin/$branch" && remote_stale=1
  if git remote get-url origin >/dev/null 2>&1; then
    # GIT_TERMINAL_PROMPT=0: on a private remote with no cached credentials this
    # probe would sit on a username prompt. Failing fast is right - it falls
    # through to the tracking ref like any other unreachable origin.
    GIT_TERMINAL_PROMPT=0 git ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1
    case $? in
      0) has_remote=1; remote_stale=0 ;;
      2) has_remote=0 ;;                                  # origin answered: not there
      *) has_remote=$remote_stale; remote_stale=0; remote_offline=1 ;;
    esac
  fi

  echo "about to remove:"
  [ -n "$path" ] && echo "  worktree      $path"
  [ $skip_docker -eq 0 ] && [ -n "$path" ] && echo "  docker        containers/volumes/images/networks for $(_gwt_compose_project "$path")"
  [ $keep_branch -eq 0 ] && echo "  local branch  $branch"
  if [ $keep_remote -eq 0 ] && [ $has_remote -eq 1 ]; then
    if [ $remote_offline -eq 1 ]; then
      echo "  remote branch origin/$branch  (irreversible; origin unreachable - delete may fail)"
    else
      echo "  remote branch origin/$branch  (irreversible)"
    fi
  fi

  if [ $assume_yes -eq 0 ]; then
    local reply
    read -r -p "proceed? [y/N] " reply
    case "$reply" in [yY]|[yY][eE][sS]) ;; *) echo "aborted"; return 1 ;; esac
  fi

  # Don't saw off the branch we're sitting on
  case "$PWD/" in "${path%/}/"*) cd "$root" || return 1 ;; esac

  [ $skip_docker -eq 0 ] && [ -n "$path" ] && _gwt_docker_cleanup "$path"

  if [ -n "$path" ]; then
    if [ $force -eq 1 ]; then
      git worktree remove --force "$path" 2>/dev/null
    else
      # git refuses on a dirty tree, but it also refuses when it can't unlink a
      # root-owned file - only the first case is the user's to resolve.
      if ! git worktree remove "$path" 2>/dev/null && [ -n "$(git -C "$path" status --porcelain 2>/dev/null)" ]; then
        echo "worktree is dirty - re-run with -f to discard it" >&2
        return 1
      fi
    fi
    # git's own remove is best-effort here: whatever it left behind (docker
    # bind-mount leftovers, root-owned build output) still has to go.
    _gwt_rm_tree "$path" || return 1
  fi
  # Drops the now-dangling .git/worktrees/<name> admin directory as well
  git worktree prune

  if [ $keep_branch -eq 0 ] && git show-ref --verify --quiet "refs/heads/$branch"; then
    git branch -D "$branch"
  fi

  local rc=0
  if [ $keep_remote -eq 0 ] && [ $has_remote -eq 1 ]; then
    if git push origin --delete "$branch"; then
      # The push leaves the tracking ref behind when it was created locally
      git update-ref -d "refs/remotes/origin/$branch" 2>/dev/null
    else
      echo "failed to delete origin/$branch - retry with: git push origin --delete '$branch'" >&2
      rc=1
    fi
  elif [ $keep_remote -eq 0 ] && [ $remote_stale -eq 1 ]; then
    # Already gone on origin; drop the tracking ref so it stops showing up
    git update-ref -d "refs/remotes/origin/$branch" 2>/dev/null
    echo "origin/$branch was already gone - dropped the stale tracking ref"
  fi

  [ $rc -eq 0 ] && echo "cleaned up: $branch"
  return $rc
}

alias gwtadd='_gwtadd'
alias gwtrm='_gwtrm'
alias gwtls='git worktree list'
alias gwtprune='git worktree prune -v'
alias gwtcd='function _gwtcd(){ cd "$(_gwt_base_dir)/$(_gwt_slug "$1")"; }; _gwtcd'

# Pull / Push
alias gpull='git pull origin'
alias gpush='git push -u origin'
alias gpf='git push --force-with-lease'

# Merge / Rebase
alias gmg='git merge'
alias grb='git rebase'
alias grbi='git rebase -i'

# Logs
alias glg='git log --oneline --graph --decorate --all'
alias glast='git log -1 HEAD'
alias gtree='git log --graph --pretty=format:"%C(auto)%h%d %s %Cgreen(%cr) %C(bold blue)<%an>" --abbrev-commit --date=relative'

# Cleanup
alias gwipe='git reset --hard && git clean -fd'

# Who wrote what
alias gwho='git shortlog -s --'

# Project tooling
alias sail='./vendor/bin/sail'

# Git branch in PS1
git_branch() {
  local branch status=""

  branch=$(git branch --show-current 2>/dev/null) || return

  # Staged changes
  git diff --cached --quiet 2>/dev/null || status+="+"

  # Unstaged changes
  git diff --quiet 2>/dev/null || status+="*"

  # Untracked files
  [ -n "$(git ls-files --others --exclude-standard 2>/dev/null)" ] && status+="?"

  # Merge conflicts
  [ -n "$(git diff --name-only --diff-filter=U 2>/dev/null)" ] && status+="x"

  # Clean repo
  [ -z "$status" ] && status="✓"

  echo " ($branch:$status)"
}

PS1='\[\e[32m\]\u@\h\[\e[0m\]:\[\e[34m\]\w\[\e[33m\]$(git_branch)\[\e[0m\]\$ '

bind '"\e[A": history-search-backward'
bind '"\e[B": history-search-forward'

# Agent/LLM workflow helpers (infra-llm --init, llmplan, llmsteps, claude_session, ...)
_git_sh_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$_git_sh_dir/llm.sh" ] && . "$_git_sh_dir/llm.sh"
unset _git_sh_dir
