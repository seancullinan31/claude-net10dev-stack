#!/usr/bin/env bash
# Keeps `claude remote-control` alive inside a tmux session, relaunching it
# whenever it exits (e.g. after the ~10-minute network-outage timeout).
#
# Driven by these env vars (set in the stack):
#   AUTO_REMOTE_CONTROL=1     enable
#   RC_PROJECT_DIR=/workspace project dir the session opens in
#   RC_SESSION_NAME=claude-dev session title at claude.ai/code
#   RC_SPAWN_MODE=worktree    same-dir | worktree | session (default worktree)
#   RC_RESTART_DELAY=10       seconds to wait between relaunches (default 10)

set -u

PROJECT_DIR="${RC_PROJECT_DIR:-/workspace}"
RC_NAME="${RC_SESSION_NAME:-claude-dev}"
RESTART_DELAY="${RC_RESTART_DELAY:-10}"
SPAWN_MODE="${RC_SPAWN_MODE:-worktree}"
TMUX_SESSION="cc"

log() { echo "[rc-supervisor] $*"; }

# Build the loop that runs *inside* tmux. It restarts claude on every exit.
# We guard on claude.ai login each iteration so a logged-out container just
# waits and logs instead of spinning on instant failures.
read -r -d '' INNER_LOOP <<EOF || true
cd '${PROJECT_DIR}'
SPAWN='${SPAWN_MODE}'
# worktree mode needs the project dir to be a git repo; fall back to same-dir if not
if [ "\$SPAWN" = "worktree" ] && ! git -C '${PROJECT_DIR}' rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "[rc-supervisor] '${PROJECT_DIR}' is not a git repo; worktree mode needs one."
  echo "[rc-supervisor] falling back to --spawn same-dir. Point RC_PROJECT_DIR at a repo for worktree mode."
  SPAWN='same-dir'
fi
while true; do
  if claude auth status 2>/dev/null | grep -qi 'claude.ai'; then
    echo "[rc-supervisor] starting: claude remote-control --name '${RC_NAME}' --spawn \$SPAWN"
    claude remote-control --name '${RC_NAME}' --spawn "\$SPAWN"
    echo "[rc-supervisor] remote-control exited (code \$?). Restarting in ${RESTART_DELAY}s..."
  else
    echo "[rc-supervisor] not logged in to claude.ai. Run 'claude' then '/login' once."
    echo "[rc-supervisor] retrying in ${RESTART_DELAY}s..."
  fi
  sleep ${RESTART_DELAY}
done
EOF

# Wait until the project dir exists (first run may clone into the volume later).
while [ ! -d "${PROJECT_DIR}" ]; do
  log "waiting for ${PROJECT_DIR} to exist..."
  sleep 5
done

# Create the tmux session running the loop, if not already present.
if tmux has-session -t "${TMUX_SESSION}" 2>/dev/null; then
  log "tmux session '${TMUX_SESSION}' already exists; leaving it alone."
else
  tmux new-session -d -s "${TMUX_SESSION}" "bash -lc \"${INNER_LOOP}\""
  log "launched tmux session '${TMUX_SESSION}' running the supervised loop."
fi
