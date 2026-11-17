# shellcheck shell=bash
MODULE_DESC="PostgreSQL server, with a superuser role and database for BOX_USER"

_psql() { (cd /tmp && runuser -u postgres -- psql -tAc "$1"); }

module_install() {
  apt_install postgresql
  if has_systemd; then systemctl enable --now postgresql >/dev/null 2>&1; fi
  # BOX_USER is validated as [a-z_][a-z0-9_-]* so it's safe to interpolate.
  if [[ "$(_psql "SELECT 1 FROM pg_roles WHERE rolname='$BOX_USER'")" != 1 ]]; then
    (cd /tmp && runuser -u postgres -- createuser --superuser "$BOX_USER")
  fi
  if [[ "$(_psql "SELECT 1 FROM pg_database WHERE datname='$BOX_USER'")" != 1 ]]; then
    (cd /tmp && runuser -u postgres -- createdb --owner "$BOX_USER" "$BOX_USER")
  fi
  ok "postgres: connect as $BOX_USER with plain 'psql' (unix socket, no password)"
}

module_remove() {
  if has_systemd; then systemctl disable --now postgresql >/dev/null 2>&1 || true; fi
  apt-get remove -y -qq 'postgresql*' >/dev/null
  warn "databases kept in /var/lib/postgresql (delete with: sudo apt-get purge 'postgresql*')"
}

module_check() { pkg_installed postgresql; }
