# shellcheck shell=bash
# The account you SSH into and agents run as.

if ! id "$BOX_USER" >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash "$BOX_USER"
  ok "created user $BOX_USER"
fi
usermod -aG sudo "$BOX_USER"
home=$(user_home "$BOX_USER")
ssh_dir="$home/.ssh" auth="$home/.ssh/authorized_keys"

install -d -m 700 -o "$BOX_USER" -g "$BOX_USER" "$ssh_dir"
[[ -f $auth ]] || install -m 600 -o "$BOX_USER" -g "$BOX_USER" /dev/null "$auth"

# A fresh VPS usually only has keys for root — reuse them.
if [[ ! -s $auth && -s /root/.ssh/authorized_keys ]]; then
  cat /root/.ssh/authorized_keys >>"$auth"
  ok "copied root's SSH keys to $BOX_USER"
fi

if [[ -n $BOX_SSH_GITHUB_USER ]]; then
  keys=$(curl -fsSL "https://github.com/$BOX_SSH_GITHUB_USER.keys") || die "couldn't fetch keys for github user '$BOX_SSH_GITHUB_USER'"
  added=0
  while IFS= read -r key; do
    [[ -n $key ]] || continue
    grep -qxF "$key" "$auth" || { printf '%s\n' "$key" >>"$auth"; added=$((added + 1)); }
  done <<<"$keys"
  ok "SSH keys from github.com/$BOX_SSH_GITHUB_USER ($added new)"
fi

sudoers=/etc/sudoers.d/90-box
if [[ $BOX_SUDO_NOPASSWD == yes ]]; then
  printf '# Managed by box (BOX_SUDO_NOPASSWD in /etc/box/box.conf)\n%s ALL=(ALL) NOPASSWD:ALL\n' "$BOX_USER" >"$sudoers"
  chmod 440 "$sudoers"
  visudo -cqf "$sudoers" || { rm -f "$sudoers"; die "generated sudoers file is invalid"; }
  ok "$BOX_USER can sudo without a password"
else
  rm -f "$sudoers"
  ok "$BOX_USER sudo requires a password"
fi
