# claude-dev-stack

A Portainer-deployable Docker stack for a Raspberry Pi 5 that gives you an on-demand
development container with .NET 10, Node.js, full Linux/dev tooling, GitHub access via
a PAT, and Claude Code running in Remote Control mode so you can drive it from your
phone or any browser.

## What's inside the image

- .NET 10 SDK (ARM64 — runs natively on the Pi 5)
- Node.js LTS (Claude Code runtime + your HTML5/CSS/JS frontend tooling)
- Claude Code (`@anthropic-ai/claude-code`)
- GitHub CLI (`gh`) + git, pre-wired to your PAT for push/pull
- `dotnet-ef`, `dotnet-outdated`, plus build-essential, jq, tmux, vim, etc.

## Files

| File                 | Purpose                                                        |
|----------------------|----------------------------------------------------------------|
| `Dockerfile`         | Builds the dev image                                           |
| `entrypoint.sh`      | Wires git/gh from env, optional auto-start of Remote Control   |
| `rc-supervisor.sh`   | Keeps `claude remote-control` alive in tmux, relaunches on exit |
| `docker-compose.yml` | The Portainer stack (build-only, with persistence volumes)     |
| `.env.example`       | Documents the env vars you must set                            |

## Deploy in Portainer

1. Push this folder to a GitHub repo (or paste the compose into a Portainer stack).
2. Portainer → **Stacks** → **Add stack** → point at the repo, or use the web editor.
3. Under **Environment variables**, set at least:
   - `GH_TOKEN` — your GitHub PAT (repo scope)
   - `GIT_AUTHOR_NAME`, `GIT_AUTHOR_EMAIL`
4. Deploy.

> The stack uses `pull_policy: build` because this is a build-only image with no
> registry. Portainer 2.39.3 runs `compose pull` before redeploy regardless of the UI
> toggle, which breaks build-only services — `pull_policy: build` is the fix.

## One-time setup (exec into the container)

Portainer → Containers → `claude-dev` → **Console** → `/bin/bash`:

```bash
cd /workspace
gh repo clone seancullinan31/your-repo
cd your-repo

# REQUIRED for Remote Control: authenticate to claude.ai (NOT an API key / setup-token)
claude
#   inside claude:  /login   (complete the OAuth flow)  then  /exit
```

git and gh already work via the PAT (the entrypoint ran `gh auth setup-git`), so
`git push` / `git pull` / `gh pr create` need no extra steps.

### Why `/login` and not an API key?

Remote Control requires a full-scope **claude.ai OAuth** login (Pro/Max/Team/Enterprise).
It rejects `ANTHROPIC_API_KEY` and the long-lived `claude setup-token` /
`CLAUDE_CODE_OAUTH_TOKEN` (those are inference-only). The login is persisted on the
`claude-config` volume, so you only do it once.

## Start Remote Control

Server mode needs a live TTY and should outlive your console session, so run it in tmux:

```bash
tmux new -s cc
cd /workspace/your-repo
claude remote-control --name "your-repo"
#   press SPACEBAR to show a QR code -> scan with the Claude mobile app
#   detach without stopping it:  Ctrl-b  then  d
```

Then from anywhere: Claude mobile app → **Code** tab (session shows a green dot), or
open the session URL / claude.ai/code in any browser. No inbound ports are opened —
the connection is outbound HTTPS only.

Server mode can host multiple project sessions from one process (default capacity 32).
Use `--spawn worktree` to give each session its own git worktree.

## Optional: supervised auto-start on container boot

After the one-time `/login`, set these env vars and redeploy:

```
AUTO_REMOTE_CONTROL=1
RC_PROJECT_DIR=/workspace/your-repo
RC_SESSION_NAME=your-repo
RC_RESTART_DELAY=10
```

On boot the entrypoint launches `rc-supervisor.sh`, which runs `claude remote-control`
inside a tmux session named `cc` and **relaunches it automatically whenever it exits**
— including after the ~10-minute network-outage timeout. It waits for `RC_PROJECT_DIR`
to exist before starting, and if you're not logged in to claude.ai it logs a reminder
and retries instead of crash-looping.

To watch it live, exec into the container and attach:

```bash
tmux attach -t cc      # detach again with Ctrl-b then d
```

## Operational notes

- If the container loses network for ~10 minutes, the Remote Control session times out
  and the process exits. With `AUTO_REMOTE_CONTROL=1` the supervisor relaunches it
  automatically; otherwise re-run `claude remote-control` yourself.
- `restart: unless-stopped` keeps the container alive across Pi reboots.
- Your code lives on the `claude-workspace` volume, so it survives image rebuilds.
