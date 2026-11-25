#!/usr/bin/env bash

# RUN ME IN FAKEROOT!
# Install apk packages into a staging root, then write the lock file.

set -Eeuo pipefail

PROG="apk-dump"
# shellcheck source=steps/prelude.sh
source "$(dirname -- "$(realpath -e -- "${BASH_SOURCE[0]}")")/prelude.sh"

usage() {
  echo "apk-dump.sh [OPTIONS] [PACKAGES...]

    -k, --key KEY        signing key to trust (http(s)://, abuild://, file://)
    -r, --repo REPO      repository to install from
    -R, --root APKROOT   location to write files to
    -a, --arch ARCH      target architecture
    -l, --lockfile PATH  write the installed package manifest here
    -h, --help           show this help and exit
"
}

if ! PARSED_OPTIONS=$(getopt -o "k:r:R:a:l:h" --long "key:,repo:,root:,arch:,lockfile:,help" -n "apk-dump.sh" -- "$@"); then
  usage >&2
  die "failed to parse options"
fi

# shellcheck disable=SC2086 # getopt has already quoted each field
eval set -- "${PARSED_OPTIONS}"

: "${ABUILD_USERDIR:=${HOME}/.abuild}"
apk_keys=()
apk_repos=()
apk_root=""
apk_arch=""
lock_file_path=""

while true; do
  case "$1" in
  -k | --key) apk_keys+=("$2"); shift 2 ;;
  -r | --repo) apk_repos+=("$2"); shift 2 ;;
  -R | --root) apk_root="$2"; shift 2 ;;
  -a | --arch) apk_arch="$2"; shift 2 ;;
  -l | --lockfile) lock_file_path="$2"; shift 2 ;;
  -h | --help) usage; exit 0 ;;
  --) shift; break ;;
  *) die "internal parsing error at '$1'" ;;
  esac
done

apk_packages=("$@")

if [[ -z "${apk_root}" ]] || [[ -z "${apk_arch}" ]] || [[ ${#apk_packages[@]} -eq 0 ]]; then
  usage >&2
  die "missing required fields (--root, --arch, or positional PACKAGES)"
fi

apk_root="$(realpath -- "${apk_root}")" || die "invalid path for root (${apk_root})"

APK=(apk --no-cache --root "${apk_root}")

# The essential files before running apk
#TODO: lets not have to do this here but update the packaging
stage_essential_dirs() {
  mkdir -p -- "${apk_root}/tmp"
  install -d -m 755 "${apk_root}/usr/lib" "${apk_root}/usr/bin" "${apk_root}/etc"
  cd -- "${apk_root}"
  ln -sfn usr/lib lib
  ln -sfn usr/bin bin
}
(stage_essential_dirs) || die "unable to stage the directories apk needs under ${apk_root}"

msg "Install apk packages to staging directory..."

mkdir -p -- "${apk_root}/etc/apk/keys" || die "unable to create ${apk_root}/etc/apk/keys"
printf '%s\n' "${apk_arch}" >"${apk_root}/etc/apk/arch" || die "unable to write ${apk_root}/etc/apk/arch"

"${APK[@]}" add --initdb || die "apk add --initdb failed in ${apk_root}"

: >"${apk_root}/etc/apk/repositories" || die "unable to write ${apk_root}/etc/apk/repositories"
for repo in "${apk_repos[@]}"; do
  printf '%s\n' "${repo}" >>"${apk_root}/etc/apk/repositories" ||
    die "unable to add ${repo} to ${apk_root}/etc/apk/repositories"
done

#TODO: add some checking to prevent overwriting
for key_url in "${apk_keys[@]}"; do
  protocol="${key_url%%[:/]*}"
  case "${protocol}" in
  http | https)
    key_name="$(basename -- "${key_url}")"
    curl -sSL -o "${apk_root}/etc/apk/keys/${key_name}" "${key_url}" \
      || die "failed to download signing key ${key_url}"
    ;;
  abuild)
    abuild_key="${key_url#abuild://}"
    if [[ "${abuild_key}" == "default" ]]; then
      abuild_conf="${ABUILD_USERDIR}/abuild.conf"
      [[ -e "${abuild_conf}" ]] || die "abuild key 'default' needs ${abuild_conf} but it does not exist"
      # shellcheck disable=SC1090 # user-owned abuild config, path fixed by HOME
      abuild_key="$( (source "${abuild_conf}" && echo "${PACKAGER_PRIVKEY}") ).pub"
    else
      abuild_key="${ABUILD_USERDIR}/${abuild_key}"
    fi
    [[ -e "${abuild_key}" ]] || die "abuild signing key ${abuild_key} does not exist"
    cp -- "${abuild_key}" "${apk_root}/etc/apk/keys/$(basename -- "${abuild_key}")" \
      || die "failed to copy signing key ${abuild_key}"
    ;;
  file)
    file_path="${key_url#file://}"
    [[ -e "${file_path}" ]] || die "signing key ${file_path} does not exist"
    cp -r -- "${file_path}" "${apk_root}/etc/apk/keys/$(basename -- "${file_path}")" \
      || die "failed to copy signing key ${file_path}"
    ;;
  *)
    die "unsupported signing key protocol '${protocol}' in '${key_url}'; supported: http, https, abuild, file"
    ;;
  esac
done

"${APK[@]}" update || die "apk update failed; check the repositories and signing keys"

#TODO: ensure NOTHING puts files into /var/run right now there are a few so we have to hack this here
"${APK[@]}" add --no-scripts filesystem \
  || die "apk add failed; check that the packages listed in the preset resolve"

printf '%s\n' "${apk_packages[@]}" >"${apk_root}/etc/apk/world" ||
  die "unable to write ${apk_root}/etc/apk/world"
sed -i 's:[[:space:]]*::g' "${apk_root}/etc/apk/world"

"${APK[@]}" add --no-scripts \
  || die "apk add failed; check that the packages listed in the preset resolve"

if [[ -n "${lock_file_path}" ]]; then
  msg "Generating lock file at ${lock_file_path}..."
  mkdir -p -- "$(dirname -- "${lock_file_path}")" \
    || die "unable to create the directory for ${lock_file_path}"
  "${APK[@]}" list -I --manifest | sed 's: :=:g' >"${lock_file_path}" ||
    die "failed to write the package manifest to ${lock_file_path}"
fi
