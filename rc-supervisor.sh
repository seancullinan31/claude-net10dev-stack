#!/usr/bin/env bash
# Option B supervisor: discovers every git repo under WORKSPACE and starts a
# named interactive `claude --remote-control "<repo>"` session for each, one per
# tmux window inside a single tmux session ("cc"). Each session shows up as a
# named, tappable entry in the Claude app's Code tab.
#
# Each per-repo loop relaunches its session if it exits (e.g. after the ~10-min
# network-outage timeout).
#
# Driven by these env vars (set in the stack):
#   AUTO_REMOTE_CONTROL=1     enable (handled by entrypoint)
#   WORKSPACE=/workspace      root dir scanned for git repos (default /workspace)
#   RC_RESTART_DELAY=10       seconds between relaunches (default 10)
#   RC_RESCAN_INTERVAL=60     seconds between scans for newly-added repos (default 60)
#   RC_PERMISSION_MODE=auto   permission mode each session starts in. One of:
#                             default | acceptEdits | plan | auto | bypassPermissions
#                             Use 'default' to pass no flag (normal prompting).
#                             NOTE: bypassPermissions is BLOCKED when running as root
#                             (this container runs as root), so 'auto' is the default.

set -u

WORKSPACE="${WORKSPACE:-/workspace}"
RESTART_DELAY="${RC_RESTART_DELAY:-10}"
RESCAN_INTERVAL="${RC_RESCAN_INTERVAL:-60}"
PERMISSION_MODE="${RC_PERMISSION_MODE:-auto}"
TMUX_SESSION="cc"
LOOP_DIR="/tmp/rc-loops"

# Build the permission-mode flag. 'default' (or empty) means pass no flag.
if [ -z "${PERMISSION_MODE}" ] || [ "${PERMISSION_MODE}" = "default" ]; then
  PERM_FLAG=""
else
  PERM_FLAG="--permission-mode ${PERMISSION_MODE}"
fi

log() { echo "[rc-supervisor] $*"; }

mkdir -p "${LOOP_DIR}"

# Write a standalone loop script for one repo, then return its path.
# Args: $1 = repo path, $2 = session name, $3 = sanitized window/file name
write_loop_script() {
  local dir="$1" name="$2" key="$3"
  local script="${LOOP_DIR}/${key}.sh"
  cat > "${script}" <<EOF
#!/usr/bin/env bash
cd "${dir}" || exit 1
while true; do
  if claude auth status 2>/dev/null | grep -qi 'claude.ai'; then
    echo "[rc-supervisor] starting session '${name}' in ${dir}"
    claude --remote-control "${name}" ${PERM_FLAG}
    echo "[rc-supervisor] session '${name}' exited (code \$?). Restarting in ${RESTART_DELAY}s..."
  else
    echo "[rc-supervisor] not logged in to claude.ai. Run 'claude' then '/login' once."
    echo "[rc-supervisor] retrying in ${RESTART_DELAY}s..."
  fi
  sleep ${RESTART_DELAY}
done
EOF
  chmod +x "${script}"
  echo "${script}"
}

# Wait for the workspace to exist (volume may populate after first boot).
while [ ! -d "${WORKSPACE}" ]; do
  log "waiting for ${WORKSPACE} to exist..."
  sleep 5
done

# Ensure the tmux session exists (created with a holding window).
if ! tmux has-session -t "${TMUX_SESSION}" 2>/dev/null; then
  tmux new-session -d -s "${TMUX_SESSION}" -n "supervisor" "bash -lc 'sleep infinity'"
  log "created tmux session '${TMUX_SESSION}'."
fi

# Scan loop: pick up repos at boot and any added later.
while true; do
  for gitdir in "${WORKSPACE}"/*/.git; do
    [ -e "${gitdir}" ] || continue
    repo_path="$(dirname "${gitdir}")"
    repo_name="$(basename "${repo_path}")"
    win_name="$(echo "${repo_name}" | tr '.:' '__')"

    if tmux list-windows -t "${TMUX_SESSION}" -F '#W' 2>/dev/null | grep -qx "${win_name}"; then
      continue
    fi

    log "found repo '${repo_name}' -> starting session window '${win_name}'"
    script_path="$(write_loop_script "${repo_path}" "${repo_name}" "${win_name}")"
    tmux new-window -t "${TMUX_SESSION}" -n "${win_name}" "bash '${script_path}'"
  done
  sleep "${RESCAN_INTERVAL}"
done
