# shellcheck shell=bash
# Base packages, hostname and timezone.

# Wait for other apt runs (unattended-upgrades on a fresh server) instead of
# failing on the dpkg lock, and retry flaky downloads. install.sh writes the
# same file before box exists.
cat >/etc/apt/apt.conf.d/50box <<'APT'
// Managed by box (core/10-system.sh).
DPkg::Lock::Timeout "600";
Acquire::Retries "5";
APT

apt-get update -qq
apt_install \
  ca-certificates curl wget gnupg git sudo openssh-server \
  build-essential pkg-config unzip zip xz-utils \
  jq ripgrep fd-find fzf bat tree rsync less vim \
  htop btop tmux mosh lsof bind9-dnsutils iproute2 iputils-ping \
  etckeeper unattended-upgrades ufw
ok "base packages"

# Debian/Ubuntu ship these under other names; give them their usual ones.
[[ -x /usr/bin/fdfind && ! -e /usr/local/bin/fd ]] && ln -s /usr/bin/fdfind /usr/local/bin/fd
[[ -x /usr/bin/batcat && ! -e /usr/local/bin/bat ]] && ln -s /usr/bin/batcat /usr/local/bin/bat

if [[ -n $BOX_HOSTNAME && "$(hostname)" != "$BOX_HOSTNAME" ]]; then
  if has_systemd && ! in_container; then
    hostnamectl set-hostname "$BOX_HOSTNAME"
    if grep -q '^127\.0\.1\.1' /etc/hosts; then
      sed -i "s/^127\.0\.1\.1.*/127.0.1.1\t$BOX_HOSTNAME/" /etc/hosts
    else
      printf '127.0.1.1\t%s\n' "$BOX_HOSTNAME" >>/etc/hosts
    fi
    ok "hostname: $BOX_HOSTNAME"
  else
    warn "can't set the hostname here (no systemd or inside a container)"
  fi
fi

if [[ -n $BOX_TIMEZONE ]]; then
  [[ -f /usr/share/zoneinfo/$BOX_TIMEZONE ]] || die "unknown timezone '$BOX_TIMEZONE'"
  if [[ "$(readlink -f /etc/localtime)" != "/usr/share/zoneinfo/$BOX_TIMEZONE" ]]; then
    ln -sf "/usr/share/zoneinfo/$BOX_TIMEZONE" /etc/localtime
    printf '%s\n' "$BOX_TIMEZONE" >/etc/timezone
    ok "timezone: $BOX_TIMEZONE"
  fi
fi
