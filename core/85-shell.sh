# shellcheck shell=bash
# PATH for user tools in every kind of shell, a sane tmux, and a login summary.

cat >/etc/profile.d/box.sh <<'SH'
# Managed by box. Puts user-level tools (claude, opencode, mise shims) on PATH.
case ":$PATH:" in *":$HOME/.local/share/mise/shims:"*) ;; *) PATH="$HOME/.local/share/mise/shims:$PATH" ;; esac
case ":$PATH:" in *":$HOME/.opencode/bin:"*) ;; *) PATH="$HOME/.opencode/bin:$PATH" ;; esac
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) PATH="$HOME/.local/bin:$PATH" ;; esac
export PATH
export EDITOR="${EDITOR:-vim}"
SH

# Non-interactive SSH commands (`ssh box claude -p ...`) only read ~/.bashrc,
# and Debian's bashrc returns early for them — so source our PATH at the top.
home=$(user_home "$BOX_USER")
rc="$home/.bashrc"
marker='# box: tool PATH (keep at top)'
if [[ -f $rc ]] && ! grep -qF "$marker" "$rc"; then
  tmp=$(mktemp)
  printf '%s\n[ -r /etc/profile.d/box.sh ] && . /etc/profile.d/box.sh\n\n' "$marker" | cat - "$rc" >"$tmp"
  cat "$tmp" >"$rc"
  rm -f "$tmp"
fi

if [[ ! -f /etc/tmux.conf ]]; then
  cat >/etc/tmux.conf <<'TMUX'
# Written once by box; yours to edit.
set -g mouse on
set -g history-limit 50000
set -g default-terminal "tmux-256color"
set -sg escape-time 10
TMUX
fi

if [[ -d /etc/update-motd.d ]]; then
  cat >/etc/update-motd.d/60-box <<'MOTD'
#!/bin/sh
[ -x /usr/local/bin/box ] && /usr/local/bin/box status --short 2>/dev/null
exit 0
MOTD
  chmod 755 /etc/update-motd.d/60-box
fi
ok "shell: PATH, tmux defaults, login summary"
