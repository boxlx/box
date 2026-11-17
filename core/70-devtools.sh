# shellcheck shell=bash
# GitHub CLI and mise (system-wide via apt), then your languages per-user.

apt_repo github-cli https://cli.github.com/packages/githubcli-archive-keyring.gpg \
  "https://cli.github.com/packages stable main"
apt_repo mise https://mise.jdx.dev/gpg-key.pub "https://mise.jdx.dev/deb stable main"
apt_install gh mise
ok "gh $(gh --version | awk 'NR==1 {print $3}'), mise $(mise --version | awk '{print $1}')"

if [[ -n $BOX_LANGS ]]; then
  # shellcheck disable=SC2086 # BOX_LANGS is a word list
  as_user mise use --quiet --global --yes $BOX_LANGS
  ok "languages: $BOX_LANGS"
fi
