# box installer ISO (experimental)

This turns a stock Ubuntu Server ISO into a USB stick that installs a box
with no questions asked, apart from one safety confirmation.

> ⚠️ **It erases the largest disk in the machine** after you confirm on
> screen. It supports UEFI machines only, which covers roughly anything from
> 2012 onwards. It hasn't been tested on real hardware yet: please report how
> it goes.

```bash
# 1. Get Ubuntu Server: https://ubuntu.com/download/server  (26.04 LTS, amd64)
# 2. Build (needs xorriso + openssl):
iso/build-iso.sh --iso ubuntu-26.04-live-server-amd64.iso --github-keys <your-github-username>
# 3. Write it to a USB stick and boot the target machine from it.
```

What happens when you boot it:

1. **Ubuntu install, about 5 minutes.** It confirms first, then installs
   Ubuntu Server (minimal) on a btrfs root, then reboots.
2. **First boot, about 5 minutes.** `box-firstboot.service` runs the regular
   installer from GitHub with the options you built in, and writes its log to
   `/var/log/box.log`.
3. **Done.** Connect with `ssh <user>@<ip>`. With `--tailscale-authkey`,
   it's also reachable as `<hostname>` on your tailnet.

Because the root filesystem is btrfs, a box installed this way gets
whole-filesystem snapshots (snapper) before and after every `box apply`.

Secrets: the password hash, and the Tailscale key if you give one, are baked
into the ISO, and also stay readable on the installed machine in
`/var/log/installer/`. The first-boot service deletes its own copy of the key
once it's done. Use a one-off, short-lived Tailscale key.
