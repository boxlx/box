# shellcheck shell=bash
# Template for a box module. Copy to /etc/box/modules/<name>.sh (your own
# modules live there and survive `box update`), then: sudo box add <name>
#
# A module is a shell file defining MODULE_DESC and three functions. It is
# sourced in a fresh `bash -euo pipefail` process as root, after
# lib/common.sh and /etc/box/box.conf are loaded, so you can use:
#   apt_install PKG...          apt_repo NAME KEY_URL "URI SUITE COMPONENTS"
#   as_user CMD...              (runs as $BOX_USER with mise on PATH)
#   has_systemd, pkg_installed, ok, warn, die, $BOX_USER, $BOX_OS_ID ...
# All three functions must be safe to run more than once.

MODULE_DESC="One line describing what this adds"

module_install() {
  apt_install some-package
  # as_user mise use --global --yes some-tool@latest
}

module_remove() {
  apt-get remove -y -qq some-package >/dev/null
}

# Exit 0 when the module is installed and working.
module_check() {
  pkg_installed some-package
}
