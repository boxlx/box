---
name: box
description: Change, extend or inspect this box machine — install software, add languages/runtimes/databases/services, change system settings, write box modules, take snapshots or update the system. Use whenever a change should persist on the machine itself rather than inside one project.
---

# Changing this box

This machine is managed by **box**. Durable system changes go through
`/etc/box/box.conf` and modules, so they're recorded, repeatable and can be
undone.

1. Look before changing anything: `box status`, `box config`, `box modules`.
2. Pick the smallest mechanism that fits:
   - **A setting, runtime or agent**: `sudo box config set KEY "value"`, then `sudo box apply`.
   - **A shipped module**: `sudo box add <name>`.
   - **Anything else that should persist**: write `/etc/box/modules/<name>.sh` from `/opt/box/modules/_template.sh`, then run `sudo box add <name>`.
   - **Project-only**: do it in the project (`mise use`, `npm i`, `docker compose`) and leave box out of it.
3. For risky changes, run `sudo box snapshot "before <what>"` first.
4. Verify with `box status`. Tell the owner what changed and how to undo it.

Full guide, including the module contract, file layout and network rules: `/etc/box/AGENTS.md`.
