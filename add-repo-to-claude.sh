#!/usr/bin/env bash
# add-repo-to-claude.sh — interactively clone a repo (from any configured git
# provider) into the claude-dev container and pre-accept its workspace-trust
# dialog so the supervisor can spawn a working Remote Control session.
#
# Run this on the Pi host:  ./add-repo-to-claude.sh
#
# Supports:
#   - GitHub:        paste owner/name      (e.g. seancullinan31/skc-intake)
#                    or a full https URL   (https://github.com/owner/repo)
#   - Azure DevOps:  paste the full clone URL, e.g.
#                    https://seancullinan.visualstudio.com/DefaultCollection/FPS/_git/FPS
#                    https://usviking.visualstudio.com/Project/_git/Repo
#                    https://dev.azure.com/Org/Project/_git/Repo
#
# Credentials are matched by host automatically (configured at container boot
# from GH_TOKEN + GIT_CREDENTIALS), so you never type a PAT here.
#
# Optional overrides:
#   CONTAINER=claude-dev   the docker container name (default claude-dev)
#   WORKSPACE=/workspace   the in-container workspace dir (default /workspace)
#   CLAUDE_JSON=/root/.claude/.claude.json   config path for trust (default)

set -euo pipefail

CONTAINER="${CONTAINER:-claude-dev}"
WORKSPACE="${WORKSPACE:-/workspace}"
CLAUDE_JSON="${CLAUDE_JSON:-/root/.claude/.claude.json}"

# --- sanity: container running? ---
if ! docker ps --format '{{.Names}}' | grep -qx "${CONTAINER}"; then
  echo "ERROR: container '${CONTAINER}' is not running."
  echo "Start the stack in Portainer (or 'docker start ${CONTAINER}') and try again."
  exit 1
fi

echo "Add a repo to ${CONTAINER}:${WORKSPACE}"
echo "Paste one of:"
echo "  - GitHub shorthand:  owner/name"
echo "  - Full clone URL:    https://<host>/.../_git/Repo  (Azure DevOps, etc.)"
read -r -p "Repo: " INPUT

if [ -z "${INPUT}" ]; then
  echo "Nothing entered. Aborting."
  exit 1
fi

# --- figure out clone URL, repo folder name, and clone method ---
CLONE_URL=""
REPO_NAME=""
METHOD=""   # gh | git

if printf '%s' "${INPUT}" | grep -qE '^[^/]+/[^/]+$' && ! printf '%s' "${INPUT}" | grep -q '://'; then
  # GitHub shorthand owner/name
  METHOD="gh"
  CLONE_URL="${INPUT}"
  REPO_NAME="$(basename "${INPUT}")"
elif printf '%s' "${INPUT}" | grep -q '://'; then
  # full URL
  HOST="$(printf '%s' "${INPUT}" | sed -E 's#^[a-z]+://([^/]+)/.*#\1#')"
  CLONE_URL="${INPUT}"
  # derive a sensible folder name: last path segment, strip trailing .git
  REPO_NAME="$(basename "${INPUT}")"
  REPO_NAME="${REPO_NAME%.git}"
  if printf '%s' "${HOST}" | grep -qi 'github.com'; then
    METHOD="gh"
    # gh clone can take a full URL too, but owner/name is cleaner; use git for uniformity
    METHOD="git"
  else
    METHOD="git"
  fi
  echo "Detected host: ${HOST}  ->  cloning with: ${METHOD}"
else
  echo "ERROR: couldn't parse '${INPUT}' as owner/name or a URL."
  exit 1
fi

REPO_PATH="${WORKSPACE}/${REPO_NAME}"

# --- already present? ---
if docker exec "${CONTAINER}" test -d "${REPO_PATH}/.git" 2>/dev/null; then
  echo "'${REPO_NAME}' is already cloned at ${REPO_PATH}."
  read -r -p "Re-accept trust and (re)register it anyway? [y/N] " ANS
  case "${ANS}" in
    y|Y) : ;;
    *) echo "Nothing to do."; exit 0 ;;
  esac
else
  echo "Cloning ${REPO_NAME} ..."
  if [ "${METHOD}" = "gh" ]; then
    if ! docker exec "${CONTAINER}" bash -c "cd '${WORKSPACE}' && gh repo clone '${CLONE_URL}'"; then
      echo "ERROR: gh clone failed. Check the name and 'gh auth status'."
      exit 1
    fi
  else
    if ! docker exec "${CONTAINER}" bash -c "cd '${WORKSPACE}' && git clone '${CLONE_URL}' '${REPO_NAME}'"; then
      echo "ERROR: git clone failed."
      echo "  - Is a PAT registered for that host? (GIT_CREDENTIALS env on the stack)"
      echo "  - For Azure DevOps, the PAT needs the 'Code (Read & Write)' scope."
      exit 1
    fi
  fi
fi

# --- pre-accept the workspace trust dialog for this repo path ---
echo "Pre-accepting workspace trust for ${REPO_PATH} ..."
docker exec "${CONTAINER}" bash -c \
  "jq '.projects[\"${REPO_PATH}\"].hasTrustDialogAccepted = true' '${CLAUDE_JSON}' > /tmp/cc-add.json && mv /tmp/cc-add.json '${CLAUDE_JSON}'"

TRUSTED="$(docker exec "${CONTAINER}" jq -r ".projects[\"${REPO_PATH}\"].hasTrustDialogAccepted" "${CLAUDE_JSON}" 2>/dev/null || echo "false")"
if [ "${TRUSTED}" != "true" ]; then
  echo "WARNING: trust flag did not get set. The session may stop at the trust prompt."
else
  echo "Trust accepted."
fi

echo
echo "Done. '${REPO_NAME}' will appear in your Code tab within ~60s."
echo "Watch it:   docker exec ${CONTAINER} tmux list-windows -t cc"
echo "Session:    docker exec ${CONTAINER} tmux capture-pane -t cc:${REPO_NAME} -p -S -20"
