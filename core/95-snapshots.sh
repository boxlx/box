# shellcheck shell=bash
# Restore points. /etc is always versioned (etckeeper); on btrfs we also take
# whole-filesystem snapshots with snapper before and after every apply.

fstype=$(findmnt -no FSTYPE / 2>/dev/null || echo unknown)
if [[ $fstype == btrfs ]]; then
  apt_install snapper
  if ! snapper_ready; then
    snapper --no-dbus -c root create-config /
    snapper --no-dbus -c root set-config NUMBER_LIMIT=20 NUMBER_LIMIT_IMPORTANT=10 TIMELINE_CREATE=no
  fi
  ok "btrfs snapshots (snapper) + /etc history (etckeeper)"
else
  ok "/etc history (etckeeper); whole-disk snapshots need a btrfs root (yours is $fstype)"
fi
