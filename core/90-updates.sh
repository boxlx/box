# shellcheck shell=bash
# Unattended security updates (no automatic reboots).

cat >/etc/apt/apt.conf.d/20auto-upgrades <<'APT'
// Managed by box (core/90-updates.sh)
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT
ok "unattended security updates"
