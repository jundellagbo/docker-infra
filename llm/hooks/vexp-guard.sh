#!/bin/bash
# vexp-guard: block Grep/Glob when the vexp daemon is running AND its index is
# healthy, so agents use the semantic pipeline instead of raw text search.
# Fast path: if the socket or healthy marker is missing, allow immediately.
# PID check: verify the daemon process is alive (handles stale files after kill -9).
# Repos without .vexp are unaffected — the guard always allows.
VEXP_DIR="${CLAUDE_PROJECT_DIR:-.}/.vexp"
SOCK="$VEXP_DIR/daemon.sock"
HEALTHY="$VEXP_DIR/healthy"
PID_FILE="$VEXP_DIR/daemon.pid"
if [ -S "$SOCK" ] && [ -f "$HEALTHY" ] && [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE" 2>/dev/null)" 2>/dev/null; then
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"vexp daemon is running. Use run_pipeline instead of Grep/Glob."}}'
else
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"vexp index not ready, allowing direct search fallback."}}'
fi
exit 0
