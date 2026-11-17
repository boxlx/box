# shellcheck shell=bash
MODULE_DESC="zellij terminal multiplexer (a friendlier tmux), via mise"

module_install() { as_user mise use --quiet --global --yes zellij; }
module_remove() { as_user mise unuse --quiet --global zellij; }
module_check() { as_user mise which zellij >/dev/null 2>&1; }
