#!/usr/bin/env bash

# RUN ME IN FAKEROOT!
# Walk the staged apk root and generate the file list used by mkqnx6fsimg

set -Eeuo pipefail

PROG="filelist-gen"
# shellcheck source=steps/prelude.sh
source "$(dirname -- "$(realpath -e -- "${BASH_SOURCE[0]}")")/prelude.sh"

usage() {
  echo "filelist-gen.sh [APKROOT] [MKQNX6FSIMG_DEST]
    [APKROOT]           location to write files to
    [MKQNX6FSIMG_DEST]  location to write filelist to"
}

generate_filelist() {
  local root=$1
  local prefix=$2
  local repo_parent=${3-${root}}
  local target_partition_prefix=${4-}

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

if (($# != 2)); then
  usage >&2
  die "expected an APKROOT and an MKQNX6FSIMG_DEST, got $#: $*"
fi

root="$1"
dest="$2"

[[ -d "${root}" ]] || die "APKROOT ${root} is not a directory"
touch -- "${dest}" || die "filelist destination ${dest} is not writable"

msg "Generating filelist for ${root}"
generate_filelist "${root}" '' "${root}" >>"${dest}" ||
  die "failed to generate the filelist for ${root}"
