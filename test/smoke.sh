#!/usr/bin/env bash
# Smoke-test the installer end to end inside a systemd container.
#
#   test/smoke.sh [image]        e.g. ubuntu:26.04 (default), ubuntu:24.04, debian:13
#   KEEP=1 test/smoke.sh ...     leave the container running afterwards
#
# Needs Docker with --privileged. Set GITHUB_TOKEN to avoid GitHub API rate
# limits when mise downloads tools.
set -euo pipefail

base=${1:-ubuntu:26.04}
here=$(cd "$(dirname "$0")/.." && pwd)
slug=${base//[:\/.]/-}
tag="box-test:$slug" name="box-smoke-$slug"

pass() { printf '\033[32mPASS\033[0m %s\n' "$*"; }
fail() { printf '\033[31mFAIL\033[0m %s\n' "$*" >&2; exit 1; }
in_box() { docker exec "$name" "$@"; }
as_dev() { docker exec "$name" runuser -u dev -- bash -lc "$1"; }

cleanup() { [[ -n ${KEEP:-} ]] || docker rm -f "$name" >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo "--- building test image for $base"
docker build -q -t "$tag" --build-arg BASE="$base" "$here/test" >/dev/null
docker rm -f "$name" >/dev/null 2>&1 || true
docker run -d --name "$name" --hostname box-smoke --privileged --cgroupns=host \
  -v /sys/fs/cgroup:/sys/fs/cgroup:rw --tmpfs /run --tmpfs /run/lock \
  -v "$here:/src:ro" "$tag" >/dev/null
in_box systemctl is-system-running --wait >/dev/null 2>&1 || true

# Root gets an SSH key, like a fresh VPS; the installer should hand it to dev.
in_box bash -c 'mkdir -p /root/.ssh && ssh-keygen -q -t ed25519 -N "" -f /root/.ssh/id_ed25519 && cp /root/.ssh/id_ed25519.pub /root/.ssh/authorized_keys'

echo "--- installing"
start=$(date +%s)
docker exec -e BOX_LOCAL_SRC=/src -e BOX_USER=dev -e BOX_HOSTNAME=box-smoke -e GITHUB_TOKEN="${GITHUB_TOKEN:-}" \
  "$name" bash /src/install.sh || fail "install.sh"
pass "install ($(($(date +%s) - start))s)"

as_dev 'node --version && bun --version && python --version && gh --version >/dev/null && mise --version >/dev/null' >/dev/null || fail "languages/tools on PATH"
pass "languages and tools on dev's PATH"
as_dev 'claude --version && codex --version && opencode --version' >/dev/null || fail "agents"
pass "agents: claude, codex, opencode"
as_dev 'docker --version' >/dev/null || fail "docker"
pass "docker"
in_box test -L /home/dev/.claude/CLAUDE.md || fail "agent guide linked"
pass "agent guide linked into ~/.claude"

in_box grep -q '^PasswordAuthentication no' /etc/ssh/sshd_config.d/10-box.conf || fail "ssh password auth should be off once a key exists"
in_box ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes dev@localhost 'command -v claude codex node' >/dev/null ||
  fail "non-interactive ssh sees agents on PATH"
pass "ssh with root's key as dev; non-interactive PATH has agents"

in_box box add postgres redis >/dev/null || fail "box add"
as_dev 'psql -tAc "select 1"' | grep -qx 1 || fail "postgres as dev"
in_box grep -q '^BOX_MODULES="postgres redis"' /etc/box/box.conf || fail "modules recorded in box.conf"
pass "box add postgres redis"
in_box box remove redis >/dev/null || fail "box remove"
in_box grep -q '^BOX_MODULES="postgres"' /etc/box/box.conf || fail "box remove updates box.conf"
pass "box remove redis"

start=$(date +%s)
in_box box apply >/dev/null || fail "re-apply"
pass "re-apply is idempotent ($(($(date +%s) - start))s)"
# box commits /etc around every change (skipped when /etc is unchanged).
commits=$(in_box bash -c "git -C /etc log --format=%s | grep -c '^box: '" || true)
((commits > 0)) || fail "etckeeper restore points"
[[ -z "$(in_box git -C /etc status --porcelain)" ]] || fail "/etc has uncommitted changes after apply"
pass "restore points in /etc history"

echo
in_box box status || true
echo
pass "all checks on $base"
