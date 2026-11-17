# shellcheck shell=bash
# ufw: deny inbound except SSH, mosh and anything from your tailnet.
# Note: ports published by Docker (-p) bypass ufw — bind them to 127.0.0.1
# or your Tailscale IP instead of 0.0.0.0.

if [[ $BOX_FIREWALL != yes ]]; then
  ok "firewall disabled (BOX_FIREWALL=$BOX_FIREWALL)"
  exit 0
fi
if in_container; then
  warn "skipping firewall inside a container"
  exit 0
fi

ufw default deny incoming >/dev/null
ufw default allow outgoing >/dev/null
ufw allow OpenSSH >/dev/null
ufw allow 60000:61000/udp comment mosh >/dev/null
ufw allow in on tailscale0 comment tailscale >/dev/null
ufw --force enable >/dev/null
ok "ufw: ssh, mosh and tailnet allowed; everything else inbound denied"
