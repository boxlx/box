# shellcheck shell=bash
# OpenSSH: key-only login once a key exists, no root passwords, keepalives.

home=$(user_home "$BOX_USER")
has_key=no
[[ -s $home/.ssh/authorized_keys ]] && has_key=yes

pw=$BOX_SSH_PASSWORD_AUTH
if [[ $pw == auto ]]; then
  if [[ $has_key == yes ]]; then pw=no; else pw=yes; fi
fi
if [[ $pw == no && $has_key == no ]]; then
  warn "keeping SSH password login on: $BOX_USER has no SSH key yet (turning it off would lock you out)"
  pw=yes
fi

conf=/etc/ssh/sshd_config.d/10-box.conf
install -d -m 755 /etc/ssh/sshd_config.d
cat >"$conf" <<CONF
# Managed by box (core/30-ssh.sh). Change settings in /etc/box/box.conf instead.
PermitRootLogin prohibit-password
PasswordAuthentication $pw
KbdInteractiveAuthentication no
X11Forwarding no
ClientAliveInterval 60
ClientAliveCountMax 3
CONF

install -d -m 755 /run/sshd
if ! /usr/sbin/sshd -t; then
  rm -f "$conf"
  die "sshd rejected the generated config"
fi

if has_systemd; then
  # Ubuntu 24.04+ uses socket activation (ssh.socket); Debian runs ssh.service.
  # Make sure whichever one this system uses is actually listening.
  if systemctl is-enabled -q ssh.socket 2>/dev/null; then
    systemctl start ssh.socket
  else
    systemctl enable --now ssh.service >/dev/null 2>&1
  fi
  systemctl try-reload-or-restart ssh.service >/dev/null 2>&1 || true
  svc_active ssh.socket || svc_active ssh.service || die "sshd isn't running — check: systemctl status ssh"
fi
ok "sshd (password login: $pw)"
