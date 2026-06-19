# claude-net10dev-stack — Operations Cheat Sheet

A Raspberry Pi 5 (DietPi) running Portainer hosts a Docker container that runs
.NET 10 + Node + Claude Code. The container auto-discovers every git repo under
`/workspace` and registers each as a named Claude Code **Remote Control** session
you can drive from the Claude mobile app or claude.ai/code.

Container name: `claude-dev`  ·  Stack/repo: `claude-net10dev-stack`
GitHub owner: `seancullinan31`

---

## How it works (mental model)

- An **entrypoint** wires git/gh from your PAT and, if `AUTO_REMOTE_CONTROL=1`,
  launches the **supervisor** (`rc-supervisor.sh`).
- The supervisor scans `/workspace` every 60s. For each git repo it finds, it
  writes a small loop script to `/tmp/rc-loops/<repo>.sh` and runs it in its own
  **tmux window** inside the `cc` session.
- Each loop runs `claude --remote-control "<repo>" --permission-mode <mode>` and
  relaunches it if it exits (network drop, etc.).
- All Claude state (login, theme, onboarding, per-repo trust, `.claude.json`)
  lives under `/root/.claude` via `CLAUDE_CONFIG_DIR`, on the `claude-config`
  volume, so it survives rebuilds.

---

## Access the Pi and container

```bash
# SSH to the Pi (use an Android SSH app like Termux/JuiceSSH), then:
docker exec -it claude-dev /bin/bash      # shell inside the container
```

Use SSH + `docker exec`, NOT the Portainer web console (its copy/paste mangles
long URLs — this bit us during first-time login).

---

## Connect from your tablet/phone

- Open the **Claude app -> Code tab**; sessions show by name with a green dot.
- Or open a session's URL directly in a browser (bypasses the list).
- If a session vanishes from the app list but is healthy on the container side,
  it's the preview's list flakiness: **force-close and reopen the app**. The
  session is fine; the list is stale.

Get a session's current URL:
```bash
docker exec claude-dev tmux capture-pane -t cc:REPO-NAME -p -S -200 | grep "claude.ai/code/session"
```

---

## Add a repo (the easy way)

A helper script on the Pi prompts for the repo and handles clone + trust:

```bash
~/add-repo-to-claude.sh
```

It asks for `owner/name`, clones into `/workspace`, and pre-accepts the workspace
trust dialog so the supervisor can spawn a working session (no theme/trust stall).
The repo appears in the Code tab within ~60s.

### Add a repo manually (if not using the script)
```bash
# 1. clone
docker exec claude-dev bash -c 'cd /workspace && gh repo clone seancullinan31/NEW-REPO'
# 2. pre-accept trust for that exact path
docker exec claude-dev bash -c 'jq ".projects[\"/workspace/NEW-REPO\"].hasTrustDialogAccepted = true" /root/.claude/.claude.json > /tmp/c.json && mv /tmp/c.json /root/.claude/.claude.json'
```

---

## Permission modes (RC_PERMISSION_MODE)

Set on the stack in Portainer, or relies on the built-in default `auto`.

| Mode               | Behavior                                              |
|--------------------|-------------------------------------------------------|
| `auto`             | Classifier auto-approves routine cmds, asks on risky. **Default.** |
| `acceptEdits`      | Auto-approves file edits, still asks for shell cmds.  |
| `default`          | Normal per-action prompting (no flag passed).         |
| `bypassPermissions`| No prompts — **BLOCKED under root, will crash-loop.** Don't use here. |

**Gotcha:** this container runs as root, and Claude Code refuses
`bypassPermissions`/`--dangerously-skip-permissions` as root. `auto` is the
practical "fewer prompts" choice. The remote app UI also doesn't cleanly expose
the "don't ask again" (option 2) picker, which is why mode matters more than
clicking through prompts.

---

## Deploy / redeploy

1. Commit changed files to GitHub.
2. Portainer -> Stacks -> `claude-net10dev-stack` -> set env vars as needed:
   - `AUTO_REMOTE_CONTROL=1`
   - `GH_TOKEN`, `GIT_AUTHOR_NAME`, `GIT_AUTHOR_EMAIL`
   - `RC_PERMISSION_MODE=auto` (optional; auto is the default)
3. **If a script/Dockerfile changed:** redeploy with **re-pull / rebuild ON**.
   **If only env vars changed:** plain redeploy is fine.

Volumes (`claude-workspace`, `claude-config`, `claude-config-json`) persist
across redeploys, so repos + login + settings are kept.

---

## Verify it's healthy

```bash
# auto-start enabled?
docker exec claude-dev env | grep AUTO_REMOTE          # want =1

# config persisting (reads from CLAUDE_CONFIG_DIR location)
docker exec claude-dev jq '{hasCompletedOnboarding, theme}' /root/.claude/.claude.json
                                                       # want true / "dark"

# which windows/sessions exist
docker exec claude-dev tmux list-windows -t cc

# what a session is doing (want "/rc active" + a session URL)
docker exec claude-dev tmux capture-pane -t cc:REPO-NAME -p -S -20

# what mode a session launched with
docker exec claude-dev cat /tmp/rc-loops/REPO-NAME.sh | grep permission-mode
```

Watch a session live:
```bash
docker exec -it claude-dev tmux attach -t cc
#   Ctrl-b w  = list/switch windows
#   Ctrl-b n / p = next / prev window
#   Ctrl-b d  = detach (leaves everything running)
```

---

## Troubleshooting quick map

| Symptom | Likely cause | Fix |
|---|---|---|
| Session not in app list, but window exists & shows `/rc active` | App list flakiness | Force-close & reopen the Claude app |
| Session stuck on theme screen | onboarding/theme not in config | re-write keys (see below) |
| Session stuck on "trust this folder?" | repo path not pre-accepted | add `hasTrustDialogAccepted` for that path |
| Session crash-loops: "cannot be used with root/sudo" | bypassPermissions under root | set `RC_PERMISSION_MODE=auto` |
| Theme/login lost after rebuild | config not persisted | ensure `CLAUDE_CONFIG_DIR=/root/.claude` is set |
| `jq: command not found` | ran on Pi host, not container | wrap in `docker exec claude-dev ...` |
| Stale `bypassPermissions` in loop script after change | old `/tmp/rc-loops/*.sh` reused | clear & restart (see below) |

Re-write theme/onboarding keys:
```bash
docker exec claude-dev bash -c 'jq ".hasCompletedOnboarding = true | .theme = \"dark\"" /root/.claude/.claude.json > /tmp/c.json && mv /tmp/c.json /root/.claude/.claude.json'
```

Force a fully clean supervisor restart (clears stale loop scripts):
```bash
docker exec claude-dev bash -c 'pkill -f rc-supervisor.sh; tmux kill-server 2>/dev/null; rm -f /tmp/rc-loops/*.sh; sleep 2'
docker restart claude-dev      # entrypoint relaunches the supervisor cleanly
```

Restart a single stuck session (supervisor respawns it in ~60s):
```bash
docker exec claude-dev tmux kill-window -t cc:REPO-NAME
```

---

## Key files in the repo

| File | Role |
|---|---|
| `Dockerfile` | Builds the .NET 10 + Node + Claude Code image |
| `entrypoint.sh` | Wires git/gh, starts supervisor if AUTO_REMOTE_CONTROL=1 |
| `rc-supervisor.sh` | Discovers repos, runs one named session per repo in tmux |
| `add-repo-to-claude.sh` | Interactive clone + trust helper (runs on the Pi host) |
| `docker-compose.yml` | The Portainer stack (volumes, env, CLAUDE_CONFIG_DIR) |
| `.env.example` | Documents every env var |

---

## One-time setup (only if rebuilding from scratch / new volume)

1. Deploy stack with `AUTO_REMOTE_CONTROL=0` first.
2. `docker exec -it claude-dev /bin/bash`
3. `claude` -> `/login` (claude.ai OAuth — NOT an API key/setup-token; those are
   rejected by Remote Control). Copy the URL to your tablet browser, approve.
4. Click through onboarding once (theme etc.) so the keys get written.
5. Set `AUTO_REMOTE_CONTROL=1` and redeploy.
