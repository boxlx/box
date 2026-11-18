# qemu + KVM in a container, so test/vm.sh needs nothing on the host but Docker.
FROM debian:13-slim
RUN apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends \
      qemu-system-x86 qemu-utils genisoimage openssh-client curl ca-certificates >/dev/null \
 && rm -rf /var/lib/apt/lists/*
COPY boot.sh /boot.sh
CMD ["/boot.sh"]
