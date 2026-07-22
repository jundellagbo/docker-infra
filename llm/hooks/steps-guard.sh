#!/bin/bash
# Stall guard for stop-hook auto-continue. Prints how many consecutive times
# the given agent has been auto-continued while the active plan set
# (plans/.active-plan and every plan file it lists) stayed unchanged.
# Adapters stop auto-continuing past 3 so a stuck agent can't loop forever.
# The counter file lives in plans/ (git-ignored).
AGENT="${1:-agent}"
ACTIVE="plans/.active-plan"
GUARD="plans/.progress-guard-$AGENT"

hash=""
if [ -f "$ACTIVE" ]; then
  hash=$(
    {
      cat "$ACTIVE"
      while IFS= read -r plan; do
        [ -n "$plan" ] && [ -f "$plan" ] && cat "$plan"
      done < "$ACTIVE"
    } | md5sum | cut -d' ' -f1
  )
fi

prev_hash=""
prev_count=0
if [ -f "$GUARD" ]; then
  read -r prev_hash prev_count < "$GUARD"
fi

if [ -n "$hash" ] && [ "$hash" = "$prev_hash" ]; then
  count=$((prev_count + 1))
else
  count=1
fi

echo "$hash $count" > "$GUARD"
echo "$count"
exit 0
