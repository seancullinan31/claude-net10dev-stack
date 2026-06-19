#!/usr/bin/env bash
# add-repo-to-claude.sh — interactively clone a repo into the claude-dev container and
# pre-accept its workspace-trust dialog so the supervisor can spawn a working
# Remote Control session for it (no theme/trust prompts).
#
# Run this on the Pi host:  ./add-repo-to-claude.sh
#
# Optional overrides:
#   CONTAINER=claude-dev   the docker container name (default claude-dev)
#   WORKSPACE=/workspace   the in-container workspace dir (default /workspace)

set -euo pipefail

CONTAINER="${CONTAINER:-claude-dev}"
WORKSPACE="${WORKSPACE:-/workspace}"

# --- sanity: container running? ---
if ! docker ps --format '{{.Names}}' | grep -qx "${CONTAINER}"; then
  echo "ERROR: container '${CONTAINER}' is not running."
  echo "Start the stack in Portainer (or 'docker start ${CONTAINER}') and try again."
  exit 1
fi

# --- prompt for the repo ---
echo "Add a repo to ${CONTAINER}:${WORKSPACE}"
echo "Enter the GitHub repo as owner/name (e.g. seancullinan31/IntelliBrite-Kasa-Commander)"
read -r -p "Repo: " REPO

if [ -z "${REPO}" ]; then
  echo "No repo entered. Aborting."
  exit 1
fi

# derive the local folder name (the part after the slash)
REPO_NAME="$(basename "${REPO}")"
REPO_PATH="${WORKSPACE}/${REPO_NAME}"

# --- already present? ---
if docker exec "${CONTAINER}" test -d "${REPO_PATH}/.git"; then
  echo "'${REPO_NAME}' is already cloned at ${REPO_PATH}."
  read -r -p "Re-accept trust and (re)register it anyway? [y/N] " ANS
  case "${ANS}" in
    y|Y) : ;;
    *) echo "Nothing to do."; exit 0 ;;
  esac
else
  # --- clone ---
  echo "Cloning ${REPO} ..."
  if ! docker exec "${CONTAINER}" bash -c "cd '${WORKSPACE}' && gh repo clone '${REPO}'"; then
    echo "ERROR: clone failed. Check the repo name and that gh is authenticated"
    echo "(run: docker exec ${CONTAINER} gh auth status)."
    exit 1
  fi
fi

# --- pre-accept the workspace trust dialog for this repo path ---
echo "Pre-accepting workspace trust for ${REPO_PATH} ..."
docker exec "${CONTAINER}" bash -c \
  "jq '.projects[\"${REPO_PATH}\"].hasTrustDialogAccepted = true' /root/.claude.json > /tmp/cc-add.json && mv /tmp/cc-add.json /root/.claude.json"

# --- verify ---
TRUSTED="$(docker exec "${CONTAINER}" jq -r ".projects[\"${REPO_PATH}\"].hasTrustDialogAccepted" /root/.claude.json 2>/dev/null || echo "false")"
if [ "${TRUSTED}" != "true" ]; then
  echo "WARNING: trust flag did not get set. The session may stop at the trust prompt."
else
  echo "Trust accepted."
fi

echo
echo "Done. '${REPO_NAME}' will appear in your Code tab within ~60s"
echo "(the supervisor rescans ${WORKSPACE} on a timer)."
echo
echo "To watch it spawn:   docker exec ${CONTAINER} tmux list-windows -t cc"
echo "To see its session:  docker exec ${CONTAINER} tmux capture-pane -t cc:${REPO_NAME} -p -S -20"
