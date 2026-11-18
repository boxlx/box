# shellcheck shell=bash
# Tailscale: reach the box from anywhere without opening ports.

if ! command -v tailscale >/dev/null; then
  # The upstream script traces every command (set -x); only show it on failure.
  quietly sh -c 'curl -fsSL https://tailscale.com/install.sh | sh' || die "tailscale install failed"
  ok "tailscale installed"
fi

if ! has_systemd || [[ ! -c /dev/net/tun ]]; then
  warn "tailscaled can't run here (no systemd or /dev/net/tun) — skipping login"
  exit 0
fi
systemctl enable --now tailscaled >/dev/null 2>&1 || true

state=$(tailscale status --json 2>/dev/null | jq -r '.BackendState // empty' || true)
if [[ $state == Running ]]; then
  ok "tailscale connected: $(tailscale ip -4 2>/dev/null | head -n1)"
elif [[ -n ${BOX_TAILSCALE_AUTHKEY:-} ]]; then
  args=(--authkey="$BOX_TAILSCALE_AUTHKEY")
  [[ -n $BOX_HOSTNAME ]] && args+=(--hostname="$BOX_HOSTNAME")
  if tailscale up "${args[@]}"; then
    ok "tailscale connected: $(tailscale ip -4 2>/dev/null | head -n1)"
  else
    warn "tailscale login with the auth key failed — run: sudo tailscale up"
  fi
else
  warn "tailscale isn't logged in yet — run: sudo tailscale up"
fi
