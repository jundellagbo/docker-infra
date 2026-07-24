#!/bin/bash
# Proof for the session-keyed stall guard.
#
# The bug: .progress-guard-<agent> counted consecutive no-progress stops keyed
# on the plan digest alone, so a repo left at the cap had auto-continue dead on
# arrival in the next session - the first Stop read 4, allowed the stop, and
# stayed quiet until something edited a plan file.
#
# What must hold now:
#   - a session that stalls still gets capped (the guard still guards)
#   - a NEW session on the same unchanged plan starts over and is blocked again
#   - a counter file written before the session field is still read correctly
#   - an absent session id behaves as it did before this change
#
# Usage: bash llm/tests/steps-guard.test.sh

HOOKS="$(cd "$(dirname "$0")/../hooks" && pwd)"
PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
no() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n     expected: %s\n     actual:   %s\n' "$1" "$2" "$3"; }

is() { # is <label> <expected> <actual>
  [ "$2" = "$3" ] && ok "$1" || no "$1" "$2" "$3"
}

has() { # has <label> <needle> <haystack>
  case "$3" in
    *"$2"*) ok "$1" ;;
    *) no "$1" "output containing '$2'" "$3" ;;
  esac
}

hasnt() { # hasnt <label> <needle> <haystack>
  case "$3" in
    *"$2"*) no "$1" "output WITHOUT '$2'" "$3" ;;
    *) ok "$1" ;;
  esac
}

# ------------------------------------------------------------------- fixtures

REPO="$(mktemp -d)"
trap 'rm -rf "$REPO"' EXIT

# A repo with one active plan holding a single unchecked step - the "no
# progress" situation the guard counts.
mkplan() {
  mkdir -p "$REPO/infra-llm/plans"
  printf 'infra-llm/plans/p.md\n' > "$REPO/infra-llm/plans/.active-plan"
  printf '# p\n\n- [ ] %s\n' "${1:-a step nobody is finishing}" \
    > "$REPO/infra-llm/plans/p.md"
  rm -f "$REPO"/infra-llm/plans/.progress-guard-*
}

# The counter, as the stop adapters call it.
guard() { # guard <agent> [session]
  (cd "$REPO" && bash "$HOOKS/steps-guard.sh" "$1" "$2")
}

# The Claude adapter end to end, with a real stdin payload.
stop() { # stop [session]
  local payload='{}'
  [ -n "$1" ] && payload="{\"session_id\":\"$1\"}"
  printf '%s' "$payload" | CLAUDE_PROJECT_DIR="$REPO" bash "$HOOKS/steps-stop.sh"
}

counter() { cat "$REPO"/infra-llm/plans/.progress-guard-claude 2>/dev/null; }
# Fields of the counter file, read without touching it - calling guard() again
# would advance the very number under test.
counter_session() { counter | cut -d' ' -f2; }
counter_count()   { counter | cut -d' ' -f3; }

# --------------------------------------------- 1. the cap still fires in-session

echo "a stalled session still gets capped"
mkplan
is "1st stop counts 1" 1 "$(guard claude sess-A)"
is "2nd stop counts 2" 2 "$(guard claude sess-A)"
is "3rd stop counts 3" 3 "$(guard claude sess-A)"
is "4th stop counts 4" 4 "$(guard claude sess-A)"
has "4th stop is allowed through" "allowing stop" "$(stop sess-A)"

# ------------------------------- 2. the fix: a new session is blocked again

echo
echo "a new session resumes auto-continue on the same unchanged plan"
# The counter is past the cap and the plan has not been touched - this is
# exactly the state that used to silence the next session.
[ "$(counter_count)" -gt 3 ] \
  && ok "counter left past the cap" \
  || no "counter left past the cap" "a count above 3" "$(counter)"
out="$(stop sess-B)"
has "new session is blocked again" '"decision":"block"' "$out"
hasnt "new session is not waved through" "allowing stop" "$out"
is "new session owns the counter" sess-B "$(counter_session)"
is "new session starts its own count" 1 "$(counter_count)"

# ------------------------------------------- 3. a pre-existing counter file

echo
echo "a counter file written before the session field"
mkplan
h="$(guard claude sess-A)"    # seed a valid digest, then rewrite in old format
digest="$(cut -d' ' -f1 < "$REPO/infra-llm/plans/.progress-guard-claude")"
printf '%s 4\n' "$digest" > "$REPO/infra-llm/plans/.progress-guard-claude"
is "old two-field count is not read as a session" 1 "$(guard claude sess-C)"
is "counter is rewritten with the session" "$digest sess-C 1" "$(counter)"

# --------------------------------------------------- 4. progress resets it

echo
echo "editing the plan resets the count"
mkplan
guard claude sess-D >/dev/null
guard claude sess-D >/dev/null
printf '# p\n\n- [x] a step somebody finished\n- [ ] the next one\n' \
  > "$REPO/infra-llm/plans/p.md"
is "changed plan set starts over" 1 "$(guard claude sess-D)"

# ------------------------------------ 5. no session id: unchanged behaviour

echo
echo "an absent session id behaves as it did before"
mkplan
is "1st stop with no session counts 1" 1 "$(guard claude '')"
is "2nd stop with no session counts 2" 2 "$(guard claude '')"
is "3rd stop with no session counts 3" 3 "$(guard claude '')"

# ------------------------------------------------------------------- summary

echo
printf '%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
echo "GUARD OK"
exit 0
