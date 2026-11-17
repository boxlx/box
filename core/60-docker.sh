# shellcheck shell=bash
# Docker Engine + buildx + compose, from Docker's repo when it supports this
# release, else from the distro.

if [[ $BOX_DOCKER != yes ]]; then
  ok "docker disabled (BOX_DOCKER=$BOX_DOCKER)"
  exit 0
fi

if ! command -v docker >/dev/null; then
  base="https://download.docker.com/linux/$BOX_OS_ID"
  if curl -fsIL "$base/dists/$BOX_OS_CODENAME/Release" >/dev/null 2>&1; then
    apt_repo docker "$base/gpg" "$base $BOX_OS_CODENAME stable"
    apt_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    ok "docker (docker.com repo)"
  else
    warn "Docker's repo has no $BOX_OS_CODENAME yet — using the distro packages"
    pkgs=(docker.io)
    # buildx, then compose v2 under whichever name this release uses
    for p in docker-buildx docker-compose-v2 docker-compose; do
      pkg_available "$p" || continue
      pkgs+=("$p")
      if [[ $p == docker-compose-v2 ]]; then break; fi
    done
    apt_install "${pkgs[@]}"
    ok "docker (distro: ${pkgs[*]})"
  fi
fi

usermod -aG docker "$BOX_USER"
if has_systemd; then
  systemctl enable --now docker >/dev/null 2>&1 || warn "docker daemon didn't start (fine inside a container)"
fi
ok "docker: $(docker --version | awk '{print $3}' | tr -d ,) ($BOX_USER is in the docker group)"
