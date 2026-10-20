#!/usr/bin/env bash

# RUN ME IN FAKEROOT!
# Install a bunch of apk packages, then generate a list of files to be used by mkqnximage

set -Eeuo pipefail

function usage() {
  echo "apk-dump.sh [OPTIONS] [PACKAGES...]

    -k, --key KEY        signing key to trust (http(s)://, abuild://, file://)
    -r, --repo REPO      repository to install from
    -R, --root APKROOT   location to write files to
    -a, --arch ARCH      target architecture
    -l, --lockfile PATH  write the installed package manifest here
    -h, --help           show this help and exit
"
}

function msg() {
  echo "[apk-dump] $*"
}

function msg_error() {
  printf '[apk-dump] ERROR: %s\n' "${1}" >&2
  exit 1
}

if ! PARSED_OPTIONS=$(getopt -o "k:r:R:a:l:h" --long "key:,repo:,root:,arch:,lockfile:,help" -n "apk-dump.sh" -- "$@"); then
  usage >&2
  msg_error "failed to parse options"
fi

# shellcheck disable=SC2086 # getopt has already quoted each field
eval set -- "${PARSED_OPTIONS}"

apk_keys=()
apk_repos=()
apk_root=""
apk_arch=""
lock_file_path=""

while true; do
  case "$1" in
  -k | --key)
    apk_keys+=("$2")
    shift 2
    ;;
  -r | --repo)
    apk_repos+=("$2")
    shift 2
    ;;
  -R | --root)
    apk_root="$2"
    shift 2
    ;;
  -a | --arch)
    apk_arch="$2"
    shift 2
    ;;
  -l | --lockfile)
    lock_file_path="$2"
    shift 2
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  --)
    shift
    break
    ;;
  *)
    msg_error "internal parsing error at '$1'"
    ;;
  esac
done

apk_packages=("$@")

if [[ -z "${apk_root}" ]] || [[ -z "${apk_arch}" ]] || [[ ${#apk_packages[@]} -eq 0 ]]; then
  usage >&2
  msg_error "missing required fields (--root, --arch, or positional PACKAGES)"
fi

if ! apk_root=$(realpath -- "${apk_root}"); then
  msg_error "invalid path for root (${apk_root})"
fi

APK=(apk --no-cache --root "${apk_root}")

if [[ ! -d ${apk_root} ]]; then
  if ! mkdir -p -- "${apk_root}"; then
    msg_error "unable to create ${apk_root}"
  fi
fi

#TODO: lets not have to do this here but update the packaging
# The essential files before running apk
stage_essential_dirs() {
  mkdir -p -- "${apk_root}/tmp"
  install -d -m 755 "${apk_root}/usr/lib"
  install -d -m 755 "${apk_root}/usr/bin"
  install -d -m 755 "${apk_root}/etc"
  cd -- "${apk_root}"
  ln -sfn usr/lib lib
  ln -sfn usr/bin bin
}
if ! (stage_essential_dirs); then
  msg_error "unable to stage the directories apk needs under ${apk_root}"
fi

msg "Install apk packages to staging directory..."

if ! mkdir -p -- "${apk_root}/etc/apk/keys"; then
  msg_error "unable to create ${apk_root}/etc/apk/keys"
fi
if ! echo "${apk_arch}" >"${apk_root}/etc/apk/arch"; then
  msg_error "unable to write ${apk_root}/etc/apk/arch"
fi

if ! "${APK[@]}" add --initdb; then
  msg_error "apk add --initdb failed in ${apk_root}"
fi

if ! : >"${apk_root}/etc/apk/repositories"; then
  msg_error "unable to write ${apk_root}/etc/apk/repositories"
fi
for repo in "${apk_repos[@]}"; do
  if ! echo "${repo}" >>"${apk_root}/etc/apk/repositories"; then
    msg_error "unable to add ${repo} to ${apk_root}/etc/apk/repositories"
  fi
done

#TODO: add some checking to prevent overwriting
for key_url in "${apk_keys[@]}"; do
  protocol="${key_url%%[:/]*}"
  case "${protocol}" in
  http | https)
    key_name="$(basename -- "${key_url}")"
    if ! curl -sSL -o "${apk_root}/etc/apk/keys/${key_name}" "${key_url}"; then
      msg_error "failed to download signing key ${key_url}"
    fi
    ;;
  abuild)
    abuild_key="${key_url#abuild://}"
    if [[ "${abuild_key}" == "default" ]]; then
      abuild_conf="${HOME}/.abuild/abuild.conf"
      if [[ ! -e "${abuild_conf}" ]]; then
        msg_error "abuild key 'default' needs ${abuild_conf} but it does not exist"
      fi
      # shellcheck disable=SC1090 # user-owned abuild config, path fixed by HOME
      abuild_key="$( (source "${abuild_conf}" && echo "${PACKAGER_PRIVKEY}") ).pub"
    else
      abuild_key="${HOME}/.abuild/${abuild_key}"
    fi
    if [[ ! -e "${abuild_key}" ]]; then
      msg_error "abuild signing key ${abuild_key} does not exist"
    fi
    if ! cp -- "${abuild_key}" "${apk_root}/etc/apk/keys/$(basename -- "${abuild_key}")"; then
      msg_error "failed to copy signing key ${abuild_key}"
    fi
    ;;
  file)
    file_path="${key_url#file://}"
    if [[ ! -e "${file_path}" ]]; then
      msg_error "signing key ${file_path} does not exist"
    fi
    if ! cp -r -- "${file_path}" "${apk_root}/etc/apk/keys/$(basename -- "${file_path}")"; then
      msg_error "failed to copy signing key ${file_path}"
    fi
    ;;
  *)
    msg_error "unsupported signing key protocol '${protocol}' in '${key_url}'; supported: http, https, abuild, file"
    ;;
  esac
done

if ! "${APK[@]}" update; then
  msg_error "apk update failed; check the repositories and signing keys"
fi

# Translate apk_packages array into valid world file
if ! : >"${apk_root}/etc/apk/world"; then
  msg_error "unable to write ${apk_root}/etc/apk/world"
fi
for pkg in "${apk_packages[@]}"; do
  if ! echo "${pkg}" >>"${apk_root}/etc/apk/world"; then
    msg_error "unable to add ${pkg} to ${apk_root}/etc/apk/world"
  fi
done
sed -i 's:[[:space:]]*::g' "${apk_root}/etc/apk/world"

# TODO: ensure NOTHING puts files into /var/run right now there are a few so we have to hack this here
if ! "${APK[@]}" add --no-scripts filesystem; then
  msg_error "apk add filesystem failed; check that the packages listed in the preset resolve"
fi

# Dump lock file
if [[ -n "${lock_file_path}" ]]; then
  msg "Generating lock file at ${lock_file_path}..."
  if ! mkdir -p -- "$(dirname -- "${lock_file_path}")"; then
    msg_error "unable to create the directory for ${lock_file_path}"
  fi

  if ! "${APK[@]}" list -I --manifest | sed 's: :=:g' >"${lock_file_path}"; then
    msg_error "failed to write the package manifest to ${lock_file_path}"
  fi
fi
