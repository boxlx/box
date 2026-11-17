# A systemd-enabled base image for smoke-testing box. See test/smoke.sh.
ARG BASE=ubuntu:26.04
FROM ${BASE}
ENV container=docker DEBIAN_FRONTEND=noninteractive
RUN apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends systemd systemd-sysv dbus ca-certificates curl openssh-client >/dev/null \
 && rm -f /etc/systemd/system/*.wants/*getty* /lib/systemd/system/*.wants/*getty* \
          /lib/systemd/system/multi-user.target.wants/systemd-logind.service \
 && rm -rf /var/lib/apt/lists/*
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
