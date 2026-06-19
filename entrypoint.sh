#!/usr/bin/env bash
set -e

# --- git identity (idempotent; safe to run every start) ---
if [ -n "${GIT_AUTHOR_NAME}" ]; then
  git config --global user.name "${GIT_AUTHOR_NAME}"
fi
if [ -n "${GIT_AUTHOR_EMAIL}" ]; then
  git config --global user.email "${GIT_AUTHOR_EMAIL}"
fi

# --- wire the PAT into gh + git so push/pull just work ---
# gh reads GH_TOKEN from the environment automatically, so we don't need
# `gh auth login`. We just make git use gh as its credential helper.
if [ -n "${GH_TOKEN}" ]; then
  gh auth setup-git 2>/dev/null || true
fi

# --- optional: auto-start Claude Code Remote Control (supervised) on container start ---
# Requires a one-time interactive `/login` to claude.ai to have been done first
# (persisted on the claude-config volume). Set AUTO_REMOTE_CONTROL=1 to enable.
# The supervisor keeps the session alive in tmux, relaunching it if it exits
# (e.g. after the ~10-minute network-outage timeout). It runs in the background
# so it doesn't block the container's main process.
if [ "${AUTO_REMOTE_CONTROL}" = "1" ]; then
  echo "[entrypoint] AUTO_REMOTE_CONTROL=1 -> starting Remote Control supervisor."
  /usr/local/bin/rc-supervisor.sh &
fi

exec "$@"
