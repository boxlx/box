#!/bin/sh
# Boots /base.img (a cloud image, mounted read-only) as a throwaway VM.
# The user "tester" gets /work/id as its SSH key; port 2222 is the VM's SSH,
# and 8080, 8081 and 9000 are forwarded for firewall checks. Disk writes go
# to an overlay inside this container, so removing it removes everything.
set -eu
mkdir -p /work/seed
ssh-keygen -q -t ed25519 -N '' -f /work/id
cat >/work/seed/user-data <<CFG
#cloud-config
users:
  - name: tester
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys: ["$(cat /work/id.pub)"]
CFG
printf 'instance-id: box-vm\nlocal-hostname: box-vm\n' >/work/seed/meta-data
genisoimage -quiet -output /work/seed.iso -volid cidata -joliet -rock /work/seed/user-data /work/seed/meta-data
qemu-img create -q -f qcow2 -F qcow2 -b /base.img /work/disk.qcow2 "${DISK:-20G}"
fwd=hostfwd=tcp::2222-:22,hostfwd=tcp::8080-:8080,hostfwd=tcp::8081-:8081,hostfwd=tcp::9000-:9000
exec qemu-system-x86_64 -enable-kvm -cpu host -smp "${CPUS:-4}" -m "${MEM:-4096}" \
  -drive file=/work/disk.qcow2,if=virtio \
  -drive file=/work/seed.iso,if=virtio,format=raw,readonly=on \
  -netdev "user,id=n0,$fwd" -device virtio-net-pci,netdev=n0 \
  -display none -serial file:/work/console.log
