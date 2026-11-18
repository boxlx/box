#!/usr/bin/env bash
# Test box on a real VM: boots a cloud image under KVM, installs box from
# this checkout, and checks what the container smoke test can't — the
# firewall seen from outside (host and Docker ports), BOX_PUBLIC_PORTS,
# BOX_FIREWALL=no, and a reboot.
#
#   test/vm.sh [ubuntu-26.04|ubuntu-24.04|debian-13]    (default ubuntu-26.04)
#   KEEP=1 test/vm.sh ...     leave the VM running; then:
#                             docker exec -it box-vm-<image> ssh -i /work/id -p 2222 tester@127.0.0.1
#
# Needs Docker and /dev/kvm. Cloud images are cached in ~/.cache/box-vm.
# Set GITHUB_TOKEN to avoid GitHub API rate limits when mise downloads tools.
set -euo pipefail

image=${1:-ubuntu-26.04}
case $image in
  ubuntu-26.04) url=https://cloud-images.ubuntu.com/releases/26.04/release/ubuntu-26.04-server-cloudimg-amd64.img ;;
  ubuntu-24.04) url=https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img ;;
  debian-13) url=https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2 ;;
  *) echo "unknown image '$image' (ubuntu-26.04, ubuntu-24.04, debian-13)" >&2; exit 2 ;;
esac
here=$(cd "$(dirname "$0")/.." && pwd)
name="box-vm-$image"
cache=${XDG_CACHE_HOME:-$HOME/.cache}/box-vm
base="$cache/${url##*/}"

pass() { printf '\033[32mPASS\033[0m %s\n' "$*"; }
fail() {
  printf '\033[31mFAIL\033[0m %s\n' "$*" >&2
  echo "--- last lines of the VM console:" >&2
  docker exec "$name" tail -n 20 /work/console.log >&2 2>/dev/null || true
  exit 1
}
# vm CMD — run CMD in the VM as tester (over SSH from inside the container).
vm() {
  docker exec -i "$name" ssh -q -i /work/id -p 2222 -o BatchMode=yes -o ConnectTimeout=5 \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null tester@127.0.0.1 "$@"
}
# outside PORT — fetch http://VM:PORT/ from outside the VM, as the internet would.
outside() { docker exec "$name" curl -s -m 4 "http://127.0.0.1:$1/" 2>/dev/null || true; }
# inside PORT — the same, from the VM itself.
inside() { vm "curl -s -m 4 http://127.0.0.1:$1/" 2>/dev/null || true; }
# reachable WHERE PORT MARKER — retry a few times; services start asynchronously.
reachable() {
  local i
  for i in 1 2 3 4 5; do
    [[ "$("$1" "$2")" == *"$3"* ]] && return 0
    sleep 2
  done
  return 1
}
blocked() { [[ "$(outside "$1")" != *"$2"* ]]; }
wait_ssh() {
  local i
  for i in $(seq 1 90); do
    vm true 2>/dev/null && return 0
    sleep 2
  done
  fail "VM didn't come up on SSH"
}
apply() { vm 'sudo box apply' >/dev/null || fail "box apply ($*)"; }

cleanup() { [[ -n ${KEEP:-} ]] || docker rm -f "$name" >/dev/null 2>&1 || true; }
trap cleanup EXIT

[[ -w /dev/kvm ]] || { echo "needs /dev/kvm (KVM) to be writable" >&2; exit 2; }
if [[ ! -s $base ]]; then
  echo "--- downloading ${url##*/}"
  mkdir -p "$cache"
  progress=-sS
  [[ -t 2 ]] && progress=--progress-bar
  curl -fL "$progress" -o "$base.part" "$url"
  mv "$base.part" "$base"
fi

echo "--- booting $image"
docker build -q -t box-vm "$here/test/vm" >/dev/null
docker rm -f "$name" >/dev/null 2>&1 || true
docker run -d --name "$name" --device /dev/kvm -v "$base:/base.img:ro" -v "$here:/src:ro" box-vm >/dev/null
wait_ssh
vm 'cloud-init status --wait' >/dev/null 2>&1 || true
pass "VM boots and takes SSH"

echo "--- installing"
docker exec "$name" tar -C /src --exclude=.git -cf - . | vm 'rm -rf ~/box-src && mkdir ~/box-src && tar -xf - -C ~/box-src'
start=$(date +%s)
vm "sudo env BOX_LOCAL_SRC=\$HOME/box-src GITHUB_TOKEN='${GITHUB_TOKEN:-}' bash \$HOME/box-src/install.sh" ||
  fail "install.sh"
pass "install ($(($(date +%s) - start))s)"

vm true || fail "SSH after the firewall went up"
vm 'sudo sshd -T | grep -qx "passwordauthentication no"' || fail "SSH password login should be off"
pass "SSH still works with the firewall on; password login is off"

# A host service and two Docker containers, each answering with a marker.
vm 'mkdir -p ~/www && echo host-ok >~/www/index.html && (cd ~/www && setsid nohup python3 -m http.server 9000 </dev/null >/dev/null 2>&1 &)'
for port in 8080 8081; do
  vm "docker run -d -q --restart always --name web$port -p $port:$port busybox \
    sh -c 'mkdir /w && echo docker-$port-ok >/w/index.html && exec httpd -f -p $port -h /w'" >/dev/null ||
    fail "docker run on $port"
done
reachable inside 9000 host-ok || fail "host service answers locally"
reachable inside 8080 docker-8080-ok || fail "container answers locally"
blocked 9000 host-ok || fail "a host port is reachable from outside"
blocked 8080 docker-8080-ok || fail "a Docker-published port is reachable from outside"
pass "from outside: host and Docker ports are blocked (locally they answer)"

vm 'sudo box config set BOX_PUBLIC_PORTS "8081 9000/tcp"' >/dev/null
apply "public ports"
reachable outside 8081 docker-8081-ok || fail "BOX_PUBLIC_PORTS opens a Docker port"
reachable outside 9000 host-ok || fail "BOX_PUBLIC_PORTS opens a host port"
blocked 8080 docker-8080-ok || fail "ports not in BOX_PUBLIC_PORTS stay closed"
pass "BOX_PUBLIC_PORTS opens exactly the listed ports"

vm 'sudo box config set BOX_PUBLIC_PORTS ""' >/dev/null
apply "no public ports"
blocked 8081 docker-8081-ok || fail "a Docker port stays open after leaving BOX_PUBLIC_PORTS"
blocked 9000 host-ok || fail "a host port stays open after leaving BOX_PUBLIC_PORTS"
pass "removing a port from BOX_PUBLIC_PORTS closes it again"

vm 'sudo box config set BOX_FIREWALL no' >/dev/null
apply "firewall off"
reachable outside 8080 docker-8080-ok || fail "BOX_FIREWALL=no leaves Docker ports blocked"
vm 'sudo box config set BOX_FIREWALL yes' >/dev/null
apply "firewall back on"
blocked 8080 docker-8080-ok || fail "turning the firewall back on doesn't cover Docker"
pass "BOX_FIREWALL=no turns it all off, and yes turns it back on"

echo "--- rebooting"
vm 'sudo systemctl reboot' >/dev/null 2>&1 || true
sleep 5
wait_ssh
vm 'systemctl is-active -q ufw box-docker-firewall docker ssh.socket 2>/dev/null || systemctl is-active -q ufw box-docker-firewall docker ssh' ||
  fail "services after reboot"
reachable inside 8080 docker-8080-ok || fail "container restarted after reboot"
blocked 8080 docker-8080-ok || fail "a Docker port is reachable from outside after reboot"
vm 'sudo box status' >/dev/null || fail "box status reports a problem after reboot"
pass "after a reboot: services up, Docker ports still blocked, box status clean"

echo
vm 'sudo box status' || true
echo
pass "all VM checks on $image"
