# shellcheck shell=bash
MODULE_DESC="Redis server on localhost:6379"

module_install() {
  apt_install redis-server
  if has_systemd; then systemctl enable --now redis-server >/dev/null 2>&1; fi
  ok "redis on 127.0.0.1:6379"
}

module_remove() {
  if has_systemd; then systemctl disable --now redis-server >/dev/null 2>&1 || true; fi
  apt-get remove -y -qq redis-server >/dev/null
}

module_check() { pkg_installed redis-server; }
