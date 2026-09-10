#!/bin/env bash
# shellcheck disable=SC2034

arch="x86_64"
boot_type="uefi"

#boot_type="custom"
#boot_partition_layout="rpi5" # rpi5.build
#boot_partition_gpt="ms"

boot_partition_size="256M" # parse size via ex G M T

mkdynifs_preset="x86_64-uefi" # mkdynifs/presets/<preset>

image_size="200G"    # parse size via ex G M T
image_format="qcow2" # iso, qcows2
image_inodes="auto"  # auto, <number>

repositories=(
  "https://repo.oss.qnx.com/8.0.3/core"
  "https://repo.oss.qnx.com/8.0.3/extra"
  "https://repo.oss.qnx.com/8.0.5/core"
  "https://repo.oss.qnx.com/8.0.5/extra"
  "https://repo.qa.oss.qnx.com/8.0.5/qnx-core"
  "https://repo.qa.oss.qnx.com/8.0.5/qnx-extra"
)

local_repositories=(
  ["/opt/qsc-apk/qnx-core"]="~/.cache/qsc-apk/8.0.5/qnx-core"
  ["/opt/qsc-apk/qnx-extra"]="~/.cache/qsc-apk/8.0.5/qnx-extra"
)

#TODO: how do deal with keys
keys=(
  "https://repo.oss.qnx.com/keys/qnxosd.rsa.pub"
  "abuild:/default"
)

packages=(
  # Base
  base
  # Graphics
  asdf
)
users="
sshd:x:15:15:sshd:/var/chroot/sshd:/bin/false
qnx:everywhere:1000:1000::/var/home/qnx:/bin/bash
"
groups="
sshd::15:sshd
"

openrc_services=("random" "screen")
openrc_confd["io-sock"]='
# io-sock config for virtio network adapters
io_sock_args="-m phy -m pci -d vtnet_pci"
'
