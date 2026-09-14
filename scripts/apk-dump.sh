#!/usr/bin/env bash

# RUN ME IN FAKEROOT!
# Install a bunch of apk packages, then generate a list of files to be used by mkqnximage
# Generate a lock file listing all package installed during build time into $APKROOT/tmp/world.lock
function usage() {
  echo "apk-dump.sh [APKROOT]

    [APKROOT] location to write files to
"
}

function msg() {
  echo "[apk-dump] $*"
}

# 1. Parse options using the enhanced `getopt` utility
# The colon (:) after letters/words means that option requires an argument
PARSED_OPTIONS=$(getopt -o "k:r:R:a:l:h" --long "key:,repo:,root:,arch:,lockfile:,help" -n "apk-dump.sh" -- "$@")

# If getopt fails (e.g. unknown flag used), exit immediately
if [[ $? -ne 0 ]]; then
  usage
fi

# Re-evaluate the arguments to normalize them for the loop below
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
  -h | --help) usage ;;
  --)
    shift
    break
    ;;
  *)
    msg "Internal parsing error!"
    exit 1
    ;;
  esac
done

apk_packages=("$@")

if [[ -z "${apk_root}" ]] || [[ -z "${apk_arch}" ]] || [[ ${#apk_packages[@]} -eq 0 ]]; then
  msg "Error: Missing required fields (--root, --arch, or positional APK_PACKAGES)"
  usage
fi

APK="apk --no-cache --root ${apk_root}"

if ! apk_root=$(realpath "${apk_root}"); then
  msg "Invalid path for root (${apk_root})!"
  exit 1
elif ! [[ -d ${apk_root} ]]; then
  mkdir "${apk_root}"
fi

#TODO: lets not have to do this here but update the packaging
# The essential files before running apk
mkdir -p "${apk_root}"/tmp
install -d -m 755 "${apk_root}/usr/lib"
install -d -m 755 "${apk_root}/usr/bin"
install -d -m 755 "${apk_root}/etc"
cd "${apk_root}"
ln -s usr/lib lib
ln -s usr/bin bin
cd -

# Install packages
msg "Install apk packages to staging directory..."

mkdir -p "${apk_root}"/etc/apk/keys
echo "${apk_arch}" >>"${apk_root}"/etc/apk/arch

${APK} add --initdb

mkdir -p "${apk_root}"/etc/apk
: >"${apk_root}"/etc/apk/repositories
for repo in "${apk_repos[@]}"; do
  echo "${repo}" >>"${apk_root}"/etc/apk/repositories
done

#TODO: add some checking to prevent overwriting
for key_url in "${apk_keys[@]}"; do
  protocol=$(echo "${key_url}" | grep -o '^[^:]*')
  case "${protocol}" in
  "http" | https)
    curl -sSL -o "${apk_root}"/etc/apk/keys/"$(basename "${key_url}")" "${key_url}"
    ;;
  "abuild")
    abuild_key="${key_url#abuild://}"
    if [[ "${abuild_key}" == "default" ]]; then
      abuild_key="$( (source "${HOME}/.abuild/abuild.conf" && echo "${PACKAGER_PRIVKEY}") ).pub"
    else
      abuild_key="${HOME}/.abuild/${abuild_key}"
    fi
    cp "${abuild_key}" "${apk_root}"/etc/apk/keys/"$(basename "${abuild_key}")"
    ;;
  "file")
    file_path="${key_url#file://}"
    cp -r "${file_path}" "${apk_root}"/etc/apk/keys/"$(basename "${file_path}")"
    ;;
  esac
done

${APK} update

# Translate apk_packages array into valid world file
: >"${apk_root}"/etc/apk/world
for pkg in "${apk_packages[@]}"; do
  echo "${pkg}" >>"${apk_root}"/etc/apk/world
done
sed -i 's:[[:space:]]*::g' "${apk_root}"/etc/apk/world

# TODO: ensure NOTHING puts files into /var/run right now there are a few so we have to hack this here
${APK} add --no-scripts filesystem

# Dump lock file
if [[ -n "${lock_file_path}" ]]; then
  msg "Generating lock file at ${lock_file_path}..."
  mkdir -p "$(dirname "${lock_file_path}")"

  ${APK} list -I --manifest | sed 's: :=:g' >"${lock_file_path}"
fi
