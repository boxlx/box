# shellcheck shell=bash
# Firewall: the internet reaches SSH, mosh and BOX_PUBLIC_PORTS; your tailnet
# reaches everything. ufw covers services on the host. Ports published by
# Docker skip ufw, so a DOCKER-USER chain applies the same rule to them.

unit=/etc/systemd/system/box-docker-firewall.service
rules=$BOX_ETC/docker-firewall.rules
state=$BOX_STATE/public-ports

# Check BOX_PUBLIC_PORTS everywhere (containers too), so typos fail early.
ports=()
for p in $BOX_PUBLIC_PORTS; do
  [[ $p =~ ^[0-9]{1,5}(:[0-9]{1,5})?(/(tcp|udp))?$ ]] ||
    die "BOX_PUBLIC_PORTS: '$p' isn't a port. Use e.g. \"80 443 8000:8100/tcp 51820/udp\""
  [[ $p != *:* || $p == */* ]] ||
    die "BOX_PUBLIC_PORTS: the range '$p' needs a protocol, e.g. $p/tcp"
  ports+=("$p")
done

docker_firewall_off() {
  [[ -f $unit || -f $rules ]] || return 0
  systemctl disable --now box-docker-firewall >/dev/null 2>&1 || true
  rm -f "$unit" "$rules"
  systemctl daemon-reload
  iptables -F DOCKER-USER 2>/dev/null || true
  ip6tables -F DOCKER-USER 2>/dev/null || true
}

if in_container; then
  warn "skipping the firewall inside a container"
  exit 0
fi

if [[ $BOX_FIREWALL != yes ]]; then
  docker_firewall_off
  ufw status 2>/dev/null | grep -q '^Status: active' && ufw --force disable >/dev/null
  rm -f "$state"
  ok "firewall off (BOX_FIREWALL=$BOX_FIREWALL)"
  exit 0
fi

# --- host services (ufw) ----------------------------------------------------

ufw default deny incoming >/dev/null
ufw default allow outgoing >/dev/null
ufw allow OpenSSH >/dev/null
ufw allow 60000:61000/udp comment mosh >/dev/null
ufw allow in on tailscale0 comment tailscale >/dev/null
for p in "${ports[@]}"; do
  ufw allow "$p" comment 'box: BOX_PUBLIC_PORTS' >/dev/null
done
# Close ports that were public after the last apply but aren't listed now.
if [[ -f $state ]]; then
  was=()
  read -ra was <"$state" || true
  for p in "${was[@]}"; do
    list_has "$p" "${ports[*]}" || ufw delete allow "$p" >/dev/null 2>&1 || true
  done
fi
install -d -m 755 "$BOX_STATE"
printf '%s\n' "${ports[*]}" >"$state"
ufw --force enable >/dev/null

public="ssh, mosh"
((${#ports[@]})) && public+=", ${ports[*]}"

# --- Docker-published ports (DOCKER-USER) ------------------------------------

if [[ $BOX_DOCKER != yes ]]; then
  docker_firewall_off
  ok "firewall on: the internet reaches $public; your tailnet reaches everything"
  exit 0
fi

# The same file works for iptables and ip6tables: it only names interfaces.
tmp=$(mktemp)
{
  printf '# Managed by box (core/40-firewall.sh). Set BOX_PUBLIC_PORTS in %s instead.\n' "$BOX_CONF"
  printf '# Who may open connections to Docker containers: this machine, other\n'
  printf '# containers and the tailnet. The internet only on BOX_PUBLIC_PORTS.\n'
  printf '*filter\n:DOCKER-USER - [0:0]\n'
  printf -- '-A DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j RETURN\n'
  printf -- '-A DOCKER-USER -i tailscale0 -j RETURN\n'
  printf -- '-A DOCKER-USER -i docker0 -j RETURN\n'
  printf -- '-A DOCKER-USER -i br-+ -j RETURN\n'
  for p in "${ports[@]}"; do
    port=${p%/*} protos="tcp udp"
    [[ $p == */* ]] && protos=${p#*/}
    for proto in $protos; do
      printf -- '-A DOCKER-USER -p %s -m conntrack --ctorigdstport %s -j RETURN\n' "$proto" "$port"
    done
  done
  printf -- '-A DOCKER-USER -o docker0 -j DROP\n'
  printf -- '-A DOCKER-USER -o br-+ -j DROP\n'
  printf 'COMMIT\n'
} >"$tmp"
iptables-restore --test --noflush "$tmp" || { rm -f "$tmp"; die "generated Docker firewall rules are invalid"; }
install -d -m 755 "$BOX_ETC"
install -m 644 "$tmp" "$rules"
rm -f "$tmp"

# Runs before Docker on every boot, so containers are never reachable from
# the internet, not even briefly. Docker won't start without it.
cat >"$unit.tmp" <<UNIT
# Managed by box (core/40-firewall.sh).
[Unit]
Description=box: keep Docker-published ports off the public internet
After=ufw.service
Before=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/iptables-restore --noflush $rules
ExecStart=-/usr/sbin/ip6tables-restore --noflush $rules

[Install]
RequiredBy=docker.service
UNIT
if ! cmp -s "$unit.tmp" "$unit"; then
  mv "$unit.tmp" "$unit"
  systemctl daemon-reload
else
  rm -f "$unit.tmp"
fi
systemctl enable -q box-docker-firewall
# Apply now as well. Restoring replaces the chain in one step, with no gap.
iptables-restore --noflush "$rules"
ip6tables-restore --noflush "$rules" 2>/dev/null || true
systemctl start box-docker-firewall

ok "firewall on: the internet reaches $public; your tailnet reaches everything (Docker ports too)"
