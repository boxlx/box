#!/usr/bin/env bash
# Build an unattended box installer from an Ubuntu Server ISO (24.04+, amd64).
#
#   iso/build-iso.sh --iso ubuntu-26.04-live-server-amd64.iso --github-keys <you>
#
# Booting the result installs Ubuntu on btrfs (UEFI), asking you to confirm
# first because it ERASES THE LARGEST DISK. On first boot it sets up box
# (~5 min, progress in /var/log/box.log).
#
# Options:
#   --iso PATH            Ubuntu Server ISO to start from (required)
#   -o, --out PATH        output ISO (default: box-<ubuntu iso name>)
#   --user NAME           account to create (default: dev)
#   --hostname NAME       hostname / Tailscale name (default: box)
#   --github-keys USER    import SSH keys from github.com/USER.keys (recommended)
#   --timezone ZONE       e.g. Europe/Berlin (default: Etc/UTC)
#   --tailscale-authkey K join your tailnet on first boot. The key is baked into
#                         the ISO: use a one-off, short-lived key.
#   --ref REF             box branch/tag to install (default: main)
# The login password is read from $BOX_PASSWORD, or prompted for.
#
# Needs: xorriso, openssl.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

iso="" out="" user=dev hostname=box gh_keys="" tz=Etc/UTC ts_key="" ref=main
while (($#)); do
  case $1 in
    --iso) iso=$2; shift 2 ;;
    -o | --out) out=$2; shift 2 ;;
    --user) user=$2; shift 2 ;;
    --hostname) hostname=$2; shift 2 ;;
    --github-keys) gh_keys=$2; shift 2 ;;
    --timezone) tz=$2; shift 2 ;;
    --tailscale-authkey) ts_key=$2; shift 2 ;;
    --ref) ref=$2; shift 2 ;;
    -h | --help) sed -n '2,25p' "$0"; exit 0 ;;
    *) die "unknown option: $1 (see --help)" ;;
  esac
done

[[ -f $iso ]] || die "--iso must point to an Ubuntu Server ISO"
command -v xorriso >/dev/null || die "xorriso is required (apt install xorriso / pacman -S libisoburn)"
command -v openssl >/dev/null || die "openssl is required"
[[ $user =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || die "invalid --user"
[[ $hostname =~ ^[a-zA-Z0-9-]{1,63}$ ]] || die "invalid --hostname"
for v in "$gh_keys" "$tz" "$ts_key" "$ref"; do
  [[ $v =~ ^[A-Za-z0-9_./+-]*$ ]] || die "option value '$v' has unexpected characters"
done
out=${out:-box-$(basename "$iso")}
[[ -n $gh_keys ]] || printf 'note: no --github-keys; you will log in with the password over SSH at first\n' >&2

password=${BOX_PASSWORD:-}
if [[ -z $password ]]; then
  read -rsp "Password for $user: " password && echo
  read -rsp "Again: " again && echo
  [[ $password == "$again" ]] || die "passwords don't match"
fi
[[ -n $password ]] || die "empty password"
hash=$(openssl passwd -6 -stdin <<<"$password")

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/box"

# Environment for box-firstboot.service, indented to sit inside the YAML block.
env_lines="      Environment=BOX_REF=$ref BOX_USER=$user BOX_HOSTNAME=$hostname BOX_TIMEZONE=$tz"
[[ -n $gh_keys ]] && env_lines+=" BOX_SSH_GITHUB_USER=$gh_keys"
[[ -n $ts_key ]] && env_lines+=$'\n'"      Environment=BOX_TAILSCALE_AUTHKEY=$ts_key"

awk -v env="$env_lines" '/^ *@@BOX_ENV@@$/ { print env; next } { print }' "$here/autoinstall.yaml" |
  sed -e "s|@@USER@@|$user|g" -e "s|@@HOSTNAME@@|$hostname|g" \
    -e "s|@@TIMEZONE@@|$tz|g" -e "s|@@PASSWORD_HASH@@|$hash|g" >"$work/box/user-data"
: >"$work/box/meta-data"

# Point the installer's boot entries at our config. Without the `autoinstall`
# kernel flag, Ubuntu asks for confirmation before touching the disk.
xorriso -osirrox on -indev "$iso" -extract /boot/grub/grub.cfg "$work/grub.cfg" 2>/dev/null
chmod u+w "$work/grub.cfg"
grep -q '/casper/vmlinuz' "$work/grub.cfg" || die "this doesn't look like an Ubuntu Server ISO (no /casper/vmlinuz in grub.cfg)"
sed -i \
  -e 's|^\([[:space:]]*linux[[:space:]]\+/casper/vmlinuz\)|\1 "ds=nocloud;s=/cdrom/box/"|' \
  -e 's|menuentry "Try or Install Ubuntu Server"|menuentry "Install box (erases the largest disk)"|' \
  -e 's|^set timeout=.*|set timeout=10|' \
  "$work/grub.cfg"

rm -f "$out"
xorriso -indev "$iso" -outdev "$out" \
  -map "$work/box" /box \
  -map "$work/grub.cfg" /boot/grub/grub.cfg \
  -boot_image any replay 2>/dev/null

printf 'built %s\n  write it to a USB stick:  sudo dd if=%s of=/dev/sdX bs=4M status=progress oflag=sync\n' "$out" "$out"
