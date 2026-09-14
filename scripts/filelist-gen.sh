#!/usr/bin/env bash

ROOT=$1
FILELIST_DEST=$2

# RUN ME IN FAKEROOT!
# Install a bunch of apk packages, then generate a list of files to be used by mkqnximage
function usage() {
  echo "filelist-gen.sh [APKROOT] [MKQNX6FSIMG_DEST]"
  echo "  [APKROOT]           location to write files to"
  echo "  [MKQNX6FSIMG_DEST]  location to write filelist to"
}

function msg() {
  echo "[filelist-gen] $*"
}

function generate_filelist() {
  local root=$1
  local prefix=$2
  local repo_parent=$3
  local target_partition_prefix=$4

  echo "# root=${root}"
  echo "# prefix=${prefix}"
  echo "# repo_parent=${repo_parent}"
  echo "# target_partition_prefix=${target_partition_prefix}"

  # Directory to scan; %P then yields the path relative to it,
  # replacing the old ${file#$root/} + ${file#$prefix/} stripping.
  local start=${root}
  if [[ ${prefix} != "" ]]; then
    start=${root}/${prefix}
  fi

  # Static strings baked into the printf format. Escape them for find:
  # % is special (-> %%) and backslash is an escape char (-> \\).
  local np=
  if [[ ${target_partition_prefix} != "" ]]; then
    np=${target_partition_prefix}/
    np=${np//%/%%}
    np=${np//\\/\\\\}
  fi
  local rp=${repo_parent}/
  if [[ ${prefix} != "" ]]; then
    rp+=${prefix}/
  fi
  rp=${rp//%/%%}
  rp=${rp//\\/\\\\}

  # -P (default): -type d = real dir (excludes symlinks), -type l = symlink,
  # everything else (regular, fifo, socket, device) lands in the last branch,
  # matching the original if/elif/else chain.
  find "${start}" -mindepth 1 \
    \( -type d -printf "[type=dir uid=%U gid=%G dperms=%m] \"${np}%P\"\n" \) -o \
    \( -type l -printf "[type=link uid=%U gid=%G] \"${np}%P\"=\"%l\"\n" \) -o \
    \( -printf "[type=file uid=%U gid=%G perms=%m] \"${np}%P\"=\"${rp}%P\"\n" \)
}

msg "Generating filelist for ${ROOT}"
generate_filelist "${ROOT}" '' "${ROOT}" >>"${FILELIST_DEST}"
