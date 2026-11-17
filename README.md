# box

**Turn any Linux machine into a remote AI-coding box in one command.**

You bring an old PC, a VM or a $5 VPS. box installs everything needed to code
on it remotely with AI agents, so you can just SSH in from anywhere and start
working:

- **Remote access:** Tailscale, SSH and mosh
- **Dev stack:** Docker, mise-managed languages and the GitHub CLI
- **Agents:** Claude Code, Codex and OpenCode

Then it gets out of the way, and you reshape it by asking your agent.

```bash
curl -fsSL https://raw.githubusercontent.com/boxlx/box/main/install.sh | sudo bash
```

> **Status: early (v0.1).** Installer smoke-tested end-to-end on Ubuntu 26.04 and Debian 13 (systemd containers, in CI). Not yet battle-tested on real hardware.

## Why

Coding agents run best on Linux, and they're better off on a machine that
stays on than on a laptop that sleeps. Today you either rent a cloud sandbox
or spend an evening turning a stock Ubuntu install into a usable dev box,
and then you do it all again on the next machine.

box is that evening, written down once:

- **Minimal, not opinionated.** No desktop, no theme, no dotfiles war. It
  installs a small, boring core, and everything else is opt-in.
- **Built on what tools ship to first.** It sits on Ubuntu LTS (Debian works
  too), so vendor packages, Docker, CUDA and cloud images just work. It is not
  a new distro, and there's nothing exotic to maintain.
- **Made to be changed by AI.** The whole machine is described by one short
  config file, plus modules an agent can write. Every change creates a
  restore point first. Agents get a guide to the box
  ([`share/AGENTS.md`](share/AGENTS.md)), so "set up Postgres and a Rails
  env" is a single prompt.

## What you get

| | |
|---|---|
| Access | OpenSSH (key-only once you have a key), mosh, tmux, Tailscale |
| Dev | Docker Engine + compose, git, gh, build-essential, ripgrep, fd, fzf, jq, bat, btop |
| Languages | [mise](https://mise.jdx.dev), default `node@lts bun@latest python@3` (anything mise supports) |
| Agents | Claude Code, Codex, OpenCode (Gemini CLI optional), each pre-wired to read the box guide |
| Safety | ufw (SSH, mosh and tailnet only), unattended security updates, etckeeper history of `/etc`, btrfs snapshots via snapper when `/` is btrfs |

## Install

**Any fresh Ubuntu 24.04+ / Debian 12+ machine** (VPS, VM, old PC):

```bash
curl -fsSL https://raw.githubusercontent.com/boxlx/box/main/install.sh \
  | sudo BOX_HOSTNAME=box BOX_TAILSCALE_AUTHKEY=tskey-auth-… bash
```

Every option is optional:

- `BOX_USER`: the account to set up. It defaults to the user who ran `sudo`, or `dev`.
- `BOX_SSH_GITHUB_USER`: imports SSH keys from `github.com/<you>.keys`.
- `BOX_TAILSCALE_AUTHKEY`: used once to join your tailnet, and never written to disk.
- Any setting from [`box.conf`](share/box.conf), such as `BOX_LANGS` or `BOX_MODULES`.

**A new VPS:** paste [`cloud-init/user-data.yaml`](cloud-init/user-data.yaml)
as "user data" when you create the server (Hetzner, DigitalOcean, AWS, …).

**A bare PC from a USB stick (experimental):**
[`iso/build-iso.sh`](iso/build-iso.sh) turns an Ubuntu Server ISO into an
unattended box installer. It wipes the disk, uses btrfs for snapshots, and
finishes setting up on first boot. See [`iso/README.md`](iso/README.md).

## Use

```
box status                  what's installed and running
sudo box add postgres       opt-in modules (box modules lists them)
sudo box config set BOX_LANGS "node@lts go@latest rust@stable"
sudo box apply              make the machine match /etc/box/box.conf
sudo box snapshot "note"    restore point (sudo box snapshots to list)
sudo box update             update box, the OS, languages and agents
```

Or just ask your agent: *"add Redis and Go 1.24 to this box"*. It reads
`/etc/box/AGENTS.md` and does this through box, so the change is recorded
and can be undone.

## How it works

```
install.sh        clone to /opt/box, write /etc/box/box.conf, run `box apply`
bin/box           the CLI
lib/common.sh     shared helpers (apt, users, config, modules, snapshots)
core/NN-*.sh      the always-on setup, run in order, each idempotent
modules/*.sh      opt-in extras; your own go in /etc/box/modules/
share/            box.conf template and the on-box agent guide and skill
```

`box apply` is idempotent. It records a restore point, runs every core step,
installs the modules listed in `box.conf`, then records another restore
point. Re-running it is how you fix drift.

## Roadmap

- [ ] ISO tested on real hardware, with BIOS (non-UEFI) support
- [ ] `gpu` module (NVIDIA driver + CUDA + container toolkit)
- [ ] Web terminal on the tailnet, for coding from a phone
- [ ] Optional desktop module (remote GUI for browser-based testing)
- [ ] One-step rollback (`box rollback`) on btrfs
- [ ] Image-based variant (bootc) for fully atomic updates

## Contributing

See [AGENTS.md](AGENTS.md). It's written for humans and coding agents alike.
The design rationale is in [docs/decisions](docs/decisions).

## License

[MIT](LICENSE)
