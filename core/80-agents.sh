# shellcheck shell=bash
# Coding agents, plus the box guide wired into each agent's global context.

home=$(user_home "$BOX_USER")

# report BIN — confirm an agent actually runs, warn (don't abort) if not
report() {
  local v
  if v=$(as_user timeout 30 "$1" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+[0-9.]*' | head -n1) && [[ -n $v ]]; then
    ok "$1 $v"
  else
    warn "$1 was installed but doesn't run — try: sudo box apply, or install it by hand"
  fi
}

# npm-based agents are mise tools, so `mise upgrade` keeps them current.
mise_npm_agent() { # PACKAGE BIN
  if ! as_user mise which node >/dev/null 2>&1; then
    as_user mise use --quiet --global --yes node@lts
  fi
  as_user mise use --quiet --global --yes "npm:$1"
  report "$2"
}

for agent in $BOX_AGENTS; do
  case $agent in
    claude)
      if [[ ! -x $home/.local/bin/claude ]]; then
        as_user bash -c 'curl -fsSL https://claude.ai/install.sh | bash' >/dev/null
      fi
      report claude
      ;;
    codex) mise_npm_agent @openai/codex codex ;;
    opencode)
      # Its npm package needs a postinstall script, which mise skips — use the official installer.
      if [[ ! -x $home/.opencode/bin/opencode ]]; then
        as_user bash -c 'curl -fsSL https://opencode.ai/install | bash' >/dev/null
      fi
      report opencode
      ;;
    gemini) mise_npm_agent @google/gemini-cli gemini ;;
    *) warn "unknown agent '$agent' (known: claude codex opencode gemini)" ;;
  esac
done

# The box guide every agent reads: what this machine is and how to change it.
install -d -m 755 "$BOX_ETC" "$BOX_ETC/modules"
install -m 644 "$BOX_ROOT/share/AGENTS.md" "$BOX_ETC/AGENTS.md"

link_if_absent() { # TARGET LINK — never clobbers the user's own files
  [[ -e $2 || -L $2 ]] && return 0
  as_user mkdir -p "$(dirname "$2")"
  as_user ln -s "$1" "$2"
}
link_if_absent "$BOX_ETC/AGENTS.md" "$home/.claude/CLAUDE.md"
link_if_absent "$BOX_ETC/AGENTS.md" "$home/.codex/AGENTS.md"
link_if_absent "$BOX_ETC/AGENTS.md" "$home/.config/opencode/AGENTS.md"
link_if_absent "$BOX_ETC/AGENTS.md" "$home/.gemini/GEMINI.md"
link_if_absent "$BOX_ROOT/share/skills/box" "$home/.claude/skills/box"
ok "agent guide: $BOX_ETC/AGENTS.md (linked into each agent's global context)"
