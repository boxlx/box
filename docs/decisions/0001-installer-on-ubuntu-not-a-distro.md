# 0001: An installer on Ubuntu LTS, not a distro

**Status:** accepted, 2026-11-17

## Context

Coding agents are moving off laptops and onto always-on machines: home
servers, old PCs and VPSes. People reach these machines over SSH or
Tailscale. Developers report that Linux handles heavy agent workloads far
better than macOS. Filesystem-heavy work such as git worktrees and installs
is especially slow on APFS.

The options in this space so far:

- **Cloud sandboxes** (boat.dev, Fly Sprites, E2B, Daytona). These are paid
  and hosted, and every serious one runs Ubuntu.
- **Scripts and guides** (devbox, lfg, many blog posts). The usual stack is
  Linux + Tailscale + SSH/mosh + tmux, with agents running as a normal user.
- **Opinionated desktop distros** (Omarchy). These are Arch + Hyprland,
  increasingly agent-integrated, and built around a desktop.

What nobody offers yet is a minimal, self-hosted, "flash or curl it and it's
a coding box" option.

## Decision

box is an **installer plus a CLI layered on Ubuntu LTS**, with Debian
supported through the same apt code path. It is **headless-first**, and it
is shipped three ways from the same code:

- `curl | sudo bash`
- cloud-init
- an autoinstall ISO

## Why not…

- **…our own distro?** We'd be maintaining a kernel, packages and security
  updates, which is a full-time team's job, and users would get nothing they
  could notice in return.
- **…a fork of Omarchy?** It's built around a desktop (Hyprland) and is
  deliberately opinionated. We want the opposite on both counts.
- **…Arch underneath?** A rolling release on an unattended machine you reach
  remotely is the wrong trade: a bad update can cost you the box until you're
  physically next to it. Docker and NVIDIA CUDA don't officially support Arch,
  and vendors ship `.deb` packages first. Arch's main draw, fresh packages,
  mostly doesn't matter here: languages and agents come from mise and the
  vendors' own installers, so they're current on any base.
- **…Debian as the primary target?** Debian is cleaner, but Ubuntu is what
  vendors, CI runners, cloud images and CUDA target first. We still test
  Debian 13, because supporting it costs almost nothing.

## Consequences

- Fresh tools come from mise and vendor repos; the base OS stays stable and
  patches itself.
- "Malleable with AI" is a design constraint:
  - all state lives in `/etc/box/box.conf` and readable modules
  - an agent guide ships on every box
  - every change records a restore point (etckeeper always; snapper on btrfs)
- Fully atomic, image-based updates (bootc) are a possible v2, once the
  script version has users.
