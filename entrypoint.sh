#!/usr/bin/env bash
set -e

# --- git identity (idempotent; safe to run every start) ---
if [ -n "${GIT_AUTHOR_NAME}" ]; then
  git config --global user.name "${GIT_AUTHOR_NAME}"
fi
if [ -n "${GIT_AUTHOR_EMAIL}" ]; then
  git config --global user.email "${GIT_AUTHOR_EMAIL}"
fi

# --- GitHub auth: make gh the credential helper for github.com only ---
# gh reads GH_TOKEN from the environment automatically. setup-git configures
# gh as a credential helper scoped to github.com / gist.github.com, so it does
# NOT interfere with the other providers handled by the store helper below.
if [ -n "${GH_TOKEN}" ]; then
  gh auth setup-git 2>/dev/null || true
fi

# --- Other providers: write PATs into git's credential store, keyed by host ---
# GIT_CREDENTIALS holds one or more entries of the form:
#     host|username|PAT
# separated by ';' or newlines. Example:
#     seancullinan.visualstudio.com|seancullinan|abc123;usviking.visualstudio.com|seancullinan|def456
#
# How this coexists with gh: `gh auth setup-git` installs a helper SCOPED to
# https://github.com, so gh only answers for GitHub. The global `store` helper
# below answers for everything else. Git matches on host only (default), and
# .git-credentials contains no github.com line, so there's no conflict.
CRED_FILE="/root/.git-credentials"
if [ -n "${GIT_CREDENTIALS:-}" ]; then
  # rewrite fresh each boot so removed providers don't linger
  : > "${CRED_FILE}"
  chmod 600 "${CRED_FILE}"

  # enable the store helper globally (gh's github-scoped helper takes precedence
  # for github.com because a host-scoped match wins over the general one)
  git config --global credential.helper store 2>/dev/null || true

  # parse entries: split on ';' and newlines, then on '|'
  printf '%s' "${GIT_CREDENTIALS}" | tr ';' '\n' | while IFS='|' read -r host user pat; do
    host="$(echo "${host}" | xargs)"   # trim
    user="$(echo "${user}" | xargs)"
    pat="$(echo "${pat}" | xargs)"
    [ -z "${host}" ] && continue
    if [ -z "${pat}" ]; then
      echo "[entrypoint] WARNING: no PAT for host '${host}', skipping."
      continue
    fi
    # Azure DevOps requires a non-empty username (any value); default to 'git'
    [ -z "${user}" ] && user="git"
    echo "https://${user}:${pat}@${host}" >> "${CRED_FILE}"
    echo "[entrypoint] registered git credentials for host: ${host}"
  done
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
