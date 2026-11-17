# shellcheck shell=bash
# Shared helpers for box. Sourced by bin/box and by every core step and
# module; never executed directly. Keep this file free of side effects
# other than defining variables and functions.

BOX_VERSION="0.1.0"
BOX_ROOT="${BOX_ROOT:-/opt/box}"
BOX_ETC="${BOX_ETC:-/etc/box}"
BOX_CONF="${BOX_CONF:-$BOX_ETC/box.conf}"
BOX_STATE="${BOX_STATE:-/var/lib/box}"
BOX_LOG="${BOX_LOG:-/var/log/box.log}"
export BOX_ROOT BOX_ETC BOX_CONF BOX_STATE BOX_LOG
export DEBIAN_FRONTEND=noninteractive

# --- output -----------------------------------------------------------------

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  _c_reset=$'\e[0m' _c_bold=$'\e[1m' _c_dim=$'\e[2m'
  _c_red=$'\e[31m' _c_green=$'\e[32m' _c_yellow=$'\e[33m' _c_blue=$'\e[34m'
else
  _c_reset='' _c_bold='' _c_dim='' _c_red='' _c_green='' _c_yellow='' _c_blue=''
fi

log()  { printf '%s==>%s %s\n' "$_c_blue$_c_bold" "$_c_reset" "$*"; }
step() { printf '\n%s## %s%s\n' "$_c_bold" "$*" "$_c_reset"; }
ok()   { printf '  %s✓%s %s\n' "$_c_green" "$_c_reset" "$*"; }
warn() { printf '  %s!%s %s\n' "$_c_yellow" "$_c_reset" "$*" >&2; }
die()  { printf '%serror:%s %s\n' "$_c_red$_c_bold" "$_c_reset" "$*" >&2; exit 1; }

need_root() { [[ $EUID -eq 0 ]] || die "this needs root — try: sudo box $*"; }

# --- OS ---------------------------------------------------------------------

os_load() {
  local id ver code name
  IFS=$'\t' read -r id ver code name < <(
    # shellcheck disable=SC1091
    . /etc/os-release
    printf '%s\t%s\t%s\t%s\n' "${ID:-unknown}" "${VERSION_ID:-0}" "${VERSION_CODENAME:-unknown}" "${PRETTY_NAME:-${ID:-unknown}}"
  )
  BOX_OS_ID=$id BOX_OS_VERSION=$ver BOX_OS_CODENAME=$code BOX_OS_NAME=$name
}

# version_ge A B  →  true when A >= B (dotted versions)
version_ge() { [[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" == "$2" ]]; }

os_check() {
  os_load
  case "$BOX_OS_ID" in
    ubuntu) version_ge "$BOX_OS_VERSION" 24.04 || die "Ubuntu $BOX_OS_VERSION is too old — box needs 24.04+ (26.04 LTS recommended)" ;;
    debian) version_ge "$BOX_OS_VERSION" 12 || die "Debian $BOX_OS_VERSION is too old — box needs 12+ (13 recommended)" ;;
    *) die "unsupported OS '$BOX_OS_ID' — box runs on Ubuntu 24.04+ and Debian 12+" ;;
  esac
}

has_systemd() { [[ -d /run/systemd/system ]]; }
in_container() { [[ -f /.dockerenv || -f /run/.containerenv ]] || systemd-detect-virt --container -q 2>/dev/null; }
svc_active() { has_systemd && systemctl is-active -q "$1" 2>/dev/null; }

# --- apt --------------------------------------------------------------------

pkg_installed() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q '^install ok installed$'; }
pkg_available() { apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/ {print $2}' | grep -qv '(none)'; }

# apt_install PKG...  — installs only what's missing, quietly.
apt_install() {
  local missing=() p
  for p in "$@"; do pkg_installed "$p" || missing+=("$p"); done
  ((${#missing[@]})) || return 0
  apt-get install -y -qq --no-install-recommends "${missing[@]}" >/dev/null
}

# apt_repo NAME KEY_URL "URI SUITE COMPONENTS"
# Adds a signed third-party apt repo (idempotent) and refreshes the index
# when the source line changed.
apt_repo() {
  local name=$1 key_url=$2 spec=$3 ext=asc
  [[ $key_url == *.gpg ]] && ext=gpg
  local keyring="/etc/apt/keyrings/$name.$ext" list="/etc/apt/sources.list.d/$name.list"
  install -d -m 0755 /etc/apt/keyrings
  if [[ ! -s $keyring ]]; then
    curl -fsSL "$key_url" -o "$keyring"
    chmod a+r "$keyring"
  fi
  local line
  line="deb [arch=$(dpkg --print-architecture) signed-by=$keyring] $spec"
  if [[ ! -f $list || "$(cat "$list")" != "$line" ]]; then
    printf '%s\n' "$line" >"$list"
    apt-get update -qq
  fi
}

# --- the box user -----------------------------------------------------------

user_home() { getent passwd "$1" | cut -d: -f6; }

# as_user CMD...  — run CMD as $BOX_USER with a clean login-like environment
# (mise shims and ~/.local/bin on PATH). Works when called as root or as
# $BOX_USER; fails otherwise.
as_user() {
  local home
  home=$(user_home "$BOX_USER")
  local -a envv=(
    HOME="$home" USER="$BOX_USER" LOGNAME="$BOX_USER" SHELL=/bin/bash LANG="${LANG:-C.UTF-8}"
    PATH="$home/.local/bin:$home/.opencode/bin:$home/.local/share/mise/shims:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
  )
  # Let a token through so mise isn't rate-limited by the GitHub API.
  [[ -n "${GITHUB_TOKEN:-}" ]] && envv+=(GITHUB_TOKEN="$GITHUB_TOKEN")
  [[ -n "${MISE_GITHUB_TOKEN:-}" ]] && envv+=(MISE_GITHUB_TOKEN="$MISE_GITHUB_TOKEN")
  if [[ "$(id -un)" == "$BOX_USER" ]]; then
    (cd "$home" && env -i "${envv[@]}" "$@")
  elif [[ $EUID -eq 0 ]]; then
    (cd "$home" && runuser -u "$BOX_USER" -- env -i "${envv[@]}" "$@")
  else
    return 1
  fi
}

# --- config -----------------------------------------------------------------
# /etc/box/box.conf is a plain shell file of BOX_* assignments. It's the
# single source of truth for a box: edit it (by hand or with an agent), then
# run `sudo box apply`.

config_defaults() {
  BOX_USER="${BOX_USER:-dev}"
  BOX_HOSTNAME="${BOX_HOSTNAME:-}"
  BOX_TIMEZONE="${BOX_TIMEZONE:-}"
  BOX_LANGS="${BOX_LANGS-node@lts bun@latest python@3}"
  BOX_AGENTS="${BOX_AGENTS-claude codex opencode}"
  BOX_MODULES="${BOX_MODULES-}"
  BOX_DOCKER="${BOX_DOCKER:-yes}"
  BOX_FIREWALL="${BOX_FIREWALL:-yes}"
  BOX_SUDO_NOPASSWD="${BOX_SUDO_NOPASSWD:-yes}"
  BOX_SSH_PASSWORD_AUTH="${BOX_SSH_PASSWORD_AUTH:-auto}"
  BOX_SSH_GITHUB_USER="${BOX_SSH_GITHUB_USER:-}"
}

config_load() {
  if [[ -r $BOX_CONF ]]; then
    # shellcheck source=/dev/null
    . "$BOX_CONF"
  fi
  config_defaults
  [[ $BOX_USER =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || die "BOX_USER '$BOX_USER' is not a valid username"
  [[ $BOX_USER != root ]] || die "BOX_USER can't be root — box sets up a normal user with sudo"
}

config_require() { [[ -f $BOX_CONF ]] || die "$BOX_CONF not found — run the installer first"; }

# config_set KEY VALUE — set a BOX_* key in box.conf (append if missing).
config_set() {
  local key=$1 val=$2
  [[ $key =~ ^BOX_[A-Z_]+$ ]] || die "invalid config key '$key' (keys look like BOX_SOMETHING)"
  [[ $val != *[\"\$\`\\]* ]] || die "config values can't contain quotes, \$, backticks or backslashes"
  local line="$key=\"$val\"" tmp
  tmp=$(mktemp)
  awk -v k="$key" -v l="$line" '
    index($0, k "=") == 1 { if (!done) print l; done = 1; next }
    { print }
    END { if (!done) print l }
  ' "$BOX_CONF" >"$tmp"
  cat "$tmp" >"$BOX_CONF"
  rm -f "$tmp"
}

# --- word lists (space separated) ---------------------------------------------

list_has() { [[ " $2 " == *" $1 "* ]]; }
list_add() { if list_has "$1" "$2"; then printf '%s' "$2"; else printf '%s' "${2:+$2 }$1"; fi; }
list_remove() {
  local out="" w
  for w in $2; do [[ $w == "$1" ]] || out="${out:+$out }$w"; done
  printf '%s' "$out"
}

# --- modules ----------------------------------------------------------------
# Modules live in $BOX_ROOT/modules (shipped) and $BOX_ETC/modules (yours —
# survives `box update`, wins on name clashes). See AGENTS.md for the contract.

module_path() {
  local m=$1
  [[ $m =~ ^[a-z0-9][a-z0-9-]*$ ]] || return 1
  if [[ -f $BOX_ETC/modules/$m.sh ]]; then
    printf '%s' "$BOX_ETC/modules/$m.sh"
  elif [[ -f $BOX_ROOT/modules/$m.sh ]]; then
    printf '%s' "$BOX_ROOT/modules/$m.sh"
  else
    return 1
  fi
}

module_names() {
  local f
  for f in "$BOX_ROOT"/modules/*.sh "$BOX_ETC"/modules/*.sh; do
    [[ -f $f ]] || continue
    f=${f##*/}
    [[ $f == _* ]] || printf '%s\n' "${f%.sh}"
  done | sort -u
}

module_desc() { (
  # shellcheck source=/dev/null
  . "$(module_path "$1")" && printf '%s' "${MODULE_DESC:-}"
); }

# run_script FILE [FUNCTION] — run a core step or module in a fresh, strict
# bash process (so `set -e` really applies, and `exit 0` skips cleanly).
run_script() {
  BOX_SCRIPT="$1" BOX_FN="${2:-}" bash -euo pipefail -c '
    . "$BOX_ROOT/lib/common.sh"
    config_load
    os_load
    . "$BOX_SCRIPT"
    if [[ -n $BOX_FN ]]; then "$BOX_FN"; fi
  '
}

# --- snapshots --------------------------------------------------------------

snapper_ready() { command -v snapper >/dev/null && [[ -f /etc/snapper/configs/root ]]; }

# snapshot_create DESCRIPTION — record a restore point: an etckeeper commit
# of /etc always, plus a btrfs snapshot when the root filesystem supports it.
snapshot_create() {
  local desc="box: $1" made=()
  if command -v etckeeper >/dev/null && [[ -d /etc/.git ]]; then
    if etckeeper unclean 2>/dev/null; then
      etckeeper commit "$desc" >/dev/null 2>&1 || true
      made+=("/etc committed")
    else
      made+=("/etc unchanged")
    fi
  fi
  if snapper_ready && snapper --no-dbus -c root create --cleanup-algorithm number --description "$desc" 2>/dev/null; then
    made+=("btrfs snapshot")
  fi
  ((${#made[@]})) && ok "restore point '$1': ${made[*]}"
  return 0
}
