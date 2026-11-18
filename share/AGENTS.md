# This machine is a box

<!-- Managed by box: /etc/box/AGENTS.md is rewritten on every `box apply`.
     Put personal instructions in your agent's own files instead of here. -->

You're running on a **box**: a headless Ubuntu/Debian machine set up for remote
AI-assisted development. The owner reaches it over SSH (usually through
Tailscale) and asks agents like you to build things on it and to reshape the
machine itself. This file tells you how to change the machine without
breaking it or losing the change.

Run `box status` first to see what's installed and running right now.

## The one rule: change the machine through box

Everything box manages comes from **`/etc/box/box.conf`**, a short, commented
shell file of `BOX_*="..."` settings. `sudo box apply` makes the machine match
it, and is safe to run any number of times.

- **Something that should outlive this session** (a database, a runtime, a
  system service, a setting): put it in box.conf or a module, then apply.
  Otherwise the next person or agent won't know it exists, and a rebuilt box
  won't have it.
- **Throwaway or project-scoped things** (`npm install`, a project's
  `mise.toml`, `docker compose up`): just do them. Box doesn't care.

| Want to… | Do this |
|---|---|
| See current state | `box status` · `box config` · `box modules` |
| Add a language/runtime for the user | `sudo box config set BOX_LANGS "node@lts bun@latest python@3 go@latest"` → `sudo box apply` (any `mise use -g` spec works) |
| Add a project-only tool version | `mise use node@22` inside the project (writes `mise.toml`) |
| Install a shipped module | `sudo box add postgres` (see `box modules`) |
| Install something box has no module for | write `/etc/box/modules/<name>.sh` (below), then `sudo box add <name>` |
| Open a port to the internet (owner asked) | `sudo box config set BOX_PUBLIC_PORTS "80 443"` → `sudo box apply` |
| Change a setting | `sudo box config set KEY "value"` → `sudo box apply` |
| Add or remove an agent | edit `BOX_AGENTS` (known: claude codex opencode gemini) → `sudo box apply` |
| Make a restore point before something risky | `sudo box snapshot "before <thing>"` |
| Update everything | `sudo box update` |

`BOX_USER` has passwordless sudo by default, so you can run these yourself.
Tell the owner what you changed, and why.

## Writing a module (how the box learns new things)

Modules are how this machine is extended. Yours go in `/etc/box/modules/`.
They are owned by the box, versioned with `/etc`, and never touched by
`box update`. Start from `/opt/box/modules/_template.sh`:

```bash
MODULE_DESC="One line shown in 'box modules'"
module_install() { apt_install caddy; systemctl enable --now caddy; }
module_remove()  { systemctl disable --now caddy || true; apt-get remove -y caddy; }
module_check()   { pkg_installed caddy; }   # exit 0 = installed and working
```

Each module runs as root in a fresh `bash -euo pipefail` with
`/opt/box/lib/common.sh` loaded. The helpers are `apt_install`, `apt_repo`,
`as_user` (runs as BOX_USER with mise on PATH), `pkg_installed`,
`has_systemd`, `ok`, `warn` and `die`. All three functions must be
idempotent. Look at `/opt/box/modules/*.sh` for real examples.

## How the machine is laid out

- **`/opt/box`**: box itself, a git checkout updated by `box update`. Don't edit it; anything changed there gets overwritten.
- **`/etc/box/box.conf`**: the settings. **`/etc/box/modules/`**: the owner's own modules.
- **Users and tools**: `BOX_USER` owns the dev environment. Languages come from mise (`~/.config/mise/config.toml`, with shims in `~/.local/share/mise/shims`). Claude Code lives in `~/.local/bin` and OpenCode in `~/.opencode/bin`. npm-based agents are installed as `npm:` mise tools.
- **Docker**: Docker Engine plus compose. `BOX_USER` is in the `docker` group.
- **Network**: the internet can reach SSH (22) and mosh (UDP 60000–61000) only. The owner's tailnet (`tailscale0`) can reach every port. This covers ports published by Docker too (`-p 3000:3000`), which box filters in the `DOCKER-USER` chain because they skip ufw.
  - To show a dev server or container to the owner, listen on `0.0.0.0` and give them the Tailscale address from `box status`. No firewall change is needed.
  - To open a port to the whole internet (only when the owner asks): `sudo box config set BOX_PUBLIC_PORTS "80 443"` → `sudo box apply`. Don't use `ufw allow` or edit iptables by hand; `box apply` won't know about it.
- **Restore points**: `/etc` is a git repo (etckeeper), and every apply, add and remove commits it. If `/` is btrfs, snapper also takes whole-filesystem snapshots. List them with `sudo box snapshots`, and restore a file with `sudo snapper -c root undochange <N>..0 <path>`.
- **Logs**: everything box does goes to `/var/log/box.log`.
- **Updates**: unattended-upgrades installs security updates daily. It never reboots on its own.

## Ground rules

- Keep the box minimal. Add what the owner asked for, not what might be nice.
- Never turn off the firewall or SSH key auth, and never expose a service on a
  public interface, without the owner explicitly asking for it.
- Before risky system changes (filesystems, boot, networking, sshd), take a
  snapshot and say what you're about to do. If you break SSH, the owner may be
  locked out of a machine that's in another room or country.
- Long-running work belongs in tmux (`tmux new -As main`), so it survives
  disconnects.
