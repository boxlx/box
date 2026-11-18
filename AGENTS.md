# Working on box

box turns a fresh Ubuntu/Debian machine into a remote AI-coding box. It's an
installer plus a CLI on top of a stock distro, not a distro of its own. Read
`docs/decisions/` for why.

(This file is for people and agents working **on this repo**. The guide that
ships **to boxes** is `share/AGENTS.md`.)

## Principles

1. **Minimal core.** Core is what every remote coding box needs: access,
   Docker, languages, agents and safety. Anything else is a module. When in
   doubt, it's a module.
2. **Idempotent everything.** Every core step and module function must be safe
   to run again on an already-configured machine. `box apply` is how drift
   gets fixed.
3. **Never lock the owner out.** Changes to SSH, the firewall or the network
   must fail safe. Examples: password auth stays on while there's no key, and
   `sshd -t` runs before any reload.
4. **Vendor-first packages.** Use the official apt repo or installer where one
   exists (Docker, gh, mise, Tailscale, Claude Code), with a distro fallback.
5. **Agent-legible.** State lives in `/etc/box/box.conf`, plus modules in
   readable bash. If an agent can't understand a change from the files, it's
   the wrong design.

## Layout

| Path | What |
|---|---|
| `install.sh` | curl entry point: installs to `/opt/box`, writes `/etc/box/box.conf`, runs `box apply` |
| `bin/box` | the CLI (`status`, `apply`, `add`, `remove`, `config`, `snapshot`, `update`) |
| `lib/common.sh` | helpers shared by everything; no side effects when sourced |
| `core/NN-name.sh` | always-on steps, run in numeric order |
| `modules/name.sh` | opt-in modules; `_template.sh` documents the contract |
| `share/box.conf` | the config template, with every setting documented |
| `share/AGENTS.md`, `share/skills/box/` | installed onto boxes for their agents |
| `cloud-init/`, `iso/` | other ways to start an install |
| `test/smoke.sh` | end-to-end test in a systemd container |
| `test/vm.sh` | end-to-end test on a real VM (KVM): firewall from outside, reboot |

## How steps and modules run

`run_script` (in `lib/common.sh`) runs each core step, and each module
function, in a **fresh `bash -euo pipefail` process** as root. `common.sh`,
the config and `os_load` are already loaded in that process. So:

- A step can `exit 0` to skip the rest of itself.
- `set -e` really applies. It isn't silently disabled by a caller's `||`.
- Steps share nothing except files and `box.conf`.

New config keys:

1. Add a default in `config_defaults`.
2. Document the key in `share/box.conf`.
3. Add it to `BOX_CONFIG_KEYS` in `install.sh` if it should be settable from
   the command line.

## Checks

```bash
shellcheck -x bin/box install.sh lib/*.sh core/*.sh modules/*.sh test/*.sh test/vm/*.sh
test/smoke.sh ubuntu:26.04     # also: debian:13, ubuntu:24.04 (needs Docker, ~5 min)
test/vm.sh ubuntu-26.04        # also: debian-13, ubuntu-24.04 (needs Docker + /dev/kvm)
```

CI runs all three on every push. A change isn't done until the smoke test
passes on Ubuntu 26.04 and Debian 13. Changes to SSH, the firewall, the
network or boot also need `test/vm.sh`: containers skip all of those.

## Style

- Bash only. No dependencies beyond what `10-system.sh` installs.
- Quote everything. Use `[[ ]]` and `local`.
- Keep apt and installer output quiet. Report results with `ok` and `warn`,
  and fail with `die`.
- Every generated system file starts with a `Managed by box` comment that
  names its source.
- Keep user-facing text short and concrete. When something's wrong, tell the
  user the exact command to fix it.
