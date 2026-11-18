#!/usr/bin/env bash
# box installer — turns a fresh Ubuntu 24.04+/Debian 12+ machine into a
# remote AI-coding box. Safe to re-run; it converges instead of reinstalling.
#
#   curl -fsSL https://raw.githubusercontent.com/boxlx/box/main/install.sh | sudo bash
#
# Options (environment variables; any BOX_* setting from box.conf works too):
#   BOX_USER=dev                    account to set up (default: the sudo user, else "dev")
#   BOX_HOSTNAME=box                hostname and Tailscale machine name
#   BOX_TAILSCALE_AUTHKEY=tskey-…   join your tailnet unattended (used once, never saved)
#   BOX_SSH_GITHUB_USER=you         import SSH keys from github.com/<you>.keys
#   BOX_AGENTS="claude codex"       BOX_LANGS="node@lts go@latest"   BOX_MODULES="postgres"
#   BOX_REPO=… BOX_REF=main         install from a fork or another branch
#
# Pass options to the root shell, e.g.:  … | sudo BOX_HOSTNAME=box bash
set -euo pipefail

BOX_CONFIG_KEYS=(
  BOX_USER BOX_HOSTNAME BOX_TIMEZONE BOX_LANGS BOX_AGENTS BOX_MODULES BOX_DOCKER
  BOX_FIREWALL BOX_PUBLIC_PORTS BOX_SUDO_NOPASSWD BOX_SSH_PASSWORD_AUTH BOX_SSH_GITHUB_USER
)

say() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

main() {
  [[ $EUID -eq 0 ]] || fail "run as root:  curl -fsSL https://raw.githubusercontent.com/boxlx/box/main/install.sh | sudo bash"
  [[ -r /etc/os-release ]] || fail "can't identify this OS (/etc/os-release missing)"
  local os
  os=$(. /etc/os-release && printf '%s' "${ID:-unknown}")
  case $os in
    ubuntu | debian) ;;
    *) fail "unsupported OS '$os' — box runs on Ubuntu 24.04+ and Debian 12+" ;;
  esac

  export DEBIAN_FRONTEND=noninteractive NEEDRESTART_SUSPEND=1
  say "preparing"
  # A fresh server is often still running unattended-upgrades: wait for it
  # instead of failing on the dpkg lock, and retry flaky downloads.
  # (core/10-system.sh keeps this file.)
  printf '%s\n' '// Managed by box (core/10-system.sh).' 'DPkg::Lock::Timeout "600";' 'Acquire::Retries "5";' \
    >/etc/apt/apt.conf.d/50box
  apt-get update -qq
  apt-get install -y -qq --no-install-recommends git ca-certificates curl >/dev/null

  local root=/opt/box repo=${BOX_REPO:-https://github.com/boxlx/box.git} ref=${BOX_REF:-main}
  if [[ -n ${BOX_LOCAL_SRC:-} ]]; then
    say "installing box from $BOX_LOCAL_SRC"
    rm -rf "$root"
    cp -a "$BOX_LOCAL_SRC" "$root"
  elif [[ -d $root/.git ]]; then
    say "updating box in $root"
    git -C "$root" fetch -q origin "$ref"
    git -C "$root" reset -q --hard FETCH_HEAD
  else
    say "downloading box ($ref)"
    git clone -q --depth 1 --branch "$ref" "$repo" "$root"
  fi
  ln -sf "$root/bin/box" /usr/local/bin/box

  install -d -m 755 /etc/box /etc/box/modules
  if [[ ! -f /etc/box/box.conf ]]; then
    install -m 644 "$root/share/box.conf" /etc/box/box.conf
    # Default the user to whoever ran sudo — that's who'll SSH in.
    if [[ -z ${BOX_USER:-} && -n ${SUDO_USER:-} && $SUDO_USER != root ]]; then
      BOX_USER=$SUDO_USER
    fi
  fi
  # Persist any BOX_* options given on the command line (never secrets).
  local key
  for key in "${BOX_CONFIG_KEYS[@]}"; do
    if [[ -n ${!key+x} ]]; then
      /usr/local/bin/box config set "$key" "${!key}" >/dev/null
    fi
  done
  unset "${BOX_CONFIG_KEYS[@]}"

  exec /usr/local/bin/box apply
}

# Everything runs from main, so a partial download can't half-execute.
main "$@"
