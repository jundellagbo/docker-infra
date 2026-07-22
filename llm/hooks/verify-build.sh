#!/bin/bash
# Final verification, run after every plan step is checked.
#
# Deliberately minimal and project-agnostic: it runs whatever VERIFY_CMD the
# repo declares and nothing else. No build tool, framework, container runtime
# or VCS operation is assumed or invoked.
#
# When the checks pass and every active plan file (plans/.active-plan) is fully
# checked, the active-plan marker is cleared so agent stop hooks allow the
# session to end. Fix any failures and re-run until it prints VERIFY OK.
#
# Usage: infra-llm --verify
#
# Per-repo settings live in .llm-verify.env at the repo root (git-ignored,
# optional; .agents/verify.env is still read for older setups):
#   VERIFY_CMD="<lint/type-check/test command>"   # unset = no checks to run

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$ROOT" || exit 1

[ -f .llm-verify.env ] && . ./.llm-verify.env
[ -f .agents/verify.env ] && . ./.agents/verify.env

# --------------------------------------------------------------------- checks

if [ -n "${VERIFY_CMD:-}" ]; then
  echo "== $VERIFY_CMD =="
  if ! eval "$VERIFY_CMD"; then
    echo "VERIFY FAILED: project checks reported errors. Fix them, then re-run infra-llm --verify" >&2
    exit 1
  fi
else
  echo "NOTE: no VERIFY_CMD set - skipping project checks."
  echo "      Add one in .llm-verify.env to run this repo's own checks here,"
  echo '      e.g. VERIFY_CMD="<your lint/type-check/test command>"'
fi

# ----------------------------------------------------------------- plan marker

ACTIVE="plans/.active-plan"
remaining=0
if [ -f "$ACTIVE" ]; then
  while IFS= read -r plan; do
    [ -n "$plan" ] && [ -f "$plan" ] || continue
    grep -qE '^[[:space:]]*[-*] \[ \]' "$plan" && remaining=1
  done < "$ACTIVE"

  if [ "$remaining" -eq 0 ]; then
    rm -f "$ACTIVE" plans/.progress-guard-*
    echo "All active plan steps are checked — cleared plans/.active-plan."
  else
    echo "NOTE: unchecked steps remain in the active plan file(s); the active-plan marker stays." >&2
  fi
fi

echo "VERIFY OK"
exit 0
